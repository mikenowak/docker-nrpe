#!/usr/bin/env perl
#
# Copyright 2015, Opsview Ltd.
#   Joshua Griffiths <josh.griffiths@opsview.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License at <http://www.gnu.org/licenses/> for
# more details.
#
#
# Checks and reports CPU utilisation for overall utilisation or for
# specific metrics.
#
# Metrics read from /proc/stat and calculated using:
#   ( cpu_utilization_change / uptime_change / user_hz ) * 100
#
# Any metrics added to Linux kernel should be appended to the array
# in the `headers` subroutine.
#
# Only compatible with Linux kernels.
#

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use Getopt::Long qw(:config posix_default bundling no_ignore_case no_auto_abbrev);
use POSIX;
use Storable;

sub usage {
    print "\n$0 [OPTIONS]\n"
    . "\t[-h|--help] display this message\n"
    . "\t[-w|--warning] warning value\n"
    . "\t[-c|--critical] critical value\n"
    . "\t[-s|--sample] seconds to sample CPU utilization instead of storing\n"
    . "\t[-m|--metric] metric to alert on (default: 'utilization')\n"
    . "\t[-e|--expression] comma delimited list of expressions. See below\n"
    . "\t[-t|--tmpdir] directory in which to store state information\n"
    . "\nStandard Expression - List of available metrics\n"
    . "\t--expression=utilization,nice,system,iowait\n"
    . "\nAdditional Expressions:\n"
    . "\tall: (default) displays all available metrics\n"
    . "\tirix: don't divide metrics by number of CPUs - see man top(1)\n"
    . "\tnoguest: Don't display metrics for virtual CPUs\n"
    . "\tnostat: Only display overall utilization or metric specified with [--metric]\n"
    . "\nExamples:\n"
    . "Steal time for virtualised servers\n"
    . "\t$0 --metric=steal --warning=60 --critical=90\n"
    . "General utilization with no extra output\n"
    . "\t$0 --expression=nostat -w 60 -c 90\n"
    . "Ommitting guest metrics for hosts with no guests\n"
    . "\t$0 --expression=noguest -w60 -c90\n"
    . "\nAvailable metrics vary between kernels\n"
    . "\nFor metrics available on your platform see man proc(5) - /stat/proc\n";
    exit 3;
}

sub headers {
    return qw(user nice system idle iowait irq softirq steal guest guest_nice);
}

sub main {
    # We'll need this for a hash after GetOptions reduces ARGV to 0
    my @args = @ARGV;

    my $opts = {
        'm' => 'utilization',
        'e' => 'all'
    };

    GetOptions($opts,
        'h|help',
        'w|warning=f',
        'c|critical=f',
        's|sample=i',
        'm|metric=s',
        'e|expression=s',
        't|tmpdir=s',
        'irix'
    );

    if ($opts->{h}) {
        &usage;
    }

    # Don't continue if warning exceeds critical
    if ($opts->{w} && $opts->{c} && $opts->{w} > $opts->{c}) {
        nexit(3, "Warning value cannot exceed critical");
    }

    # Split the expression by commas
    # Hash is faster than array for key ref
    my @expression = split(/,+/, $opts->{e});
    foreach my $field (@expression) {
        $opts->{expr}->{$field} = 1;
    }

    # Work out which tmp directory to use unless sampling
    # or tmp directory given
    if (!$opts->{s} && !$opts->{t}) {
        if ($ENV{OPSVIEW_BASE} && -d "$ENV{OPSVIEW_BASE}/tmp") {
            $opts->{t} = "$ENV{OPSVIEW_BASE}/tmp";
        } elsif (-d "/opt/opsview/monitoringscripts/tmp") {
            $opts->{t} = "/opt/opsview/monitoringscripts/tmp";
	} elsif (-d "/opt/opsview/tmp") {
	    $opts->{t} = "/opt/opsview/tmp";
        } else {
            $opts->{t} = "/tmp";
        }
    }

    my $filename;
    if (!$opts->{s}) {
        $filename = filepath($opts->{t}, \@args);

        # If file doesn't exist, then assume first run
        # write CPU stats to file and exit
        if (! -e $filename) {
            write_file($filename);
            nexit(0, "Cannot get CPU time on first run. Waiting for next run.");
        }
    }

    my $cpu_info;
    if ($opts->{s}) {
        # Get CPU utilisation metrics over n seconds
        $cpu_info = get_cpu_info_over_nseconds($opts->{s});
    } else {
        # Get CPU utilization metrics since last check ran
        $cpu_info = get_cpu_info_over_check_period($filename);
    }

    # Combine the data for each CPU
    my $cpu_summary = summarise_values($cpu_info);

    # Check that the specified metric (-m) exists in the data
    unless (exists $cpu_summary->{$opts->{m}}) {
        nexit(3, "Cannot locate CPU metric: '$opts->{m}'");
    }

    # Divide metrics by the number of CPUs
    # unless irix is specified
    my $num_cpus = keys %$cpu_info;
    unless ($opts->{expr}->{irix}) {
        $cpu_summary = to_solaris_time($cpu_summary, $num_cpus);
    }

    # Get the metric for the summary (specified as -m or 'utilization' by default)
    my $alert_metric_value = $cpu_summary->{$opts->{m}};

    # Work out the exit code from the warning and critical values
    my $exit_code = get_nagios_exit($alert_metric_value, $opts);

    # Get the output string (message and performance data) from metrics
    my ($output, $perfdata) = get_nagios_output($cpu_summary, $opts, $num_cpus);

    # Exit the script with the code, message and performance data
    nexit($exit_code, $output, $perfdata);
}

# Returns the USER_HZ attribute - should be 100 on most architectures
sub user_hz {
    return POSIX::sysconf(&POSIX::_SC_CLK_TCK);
}

# Returns the seconds attribute from /proc/uptime
sub uptime {
    open(my $fh, '<', '/proc/uptime')
        or nexit(3, "Cannot open /proc/uptime: $!");

    my $row = <$fh>;
    close($fh);
    chomp $row;
    my ($uptime) = split(/\s+/, $row, 2);
    return $uptime;
}

# Reads the CPU-specific fields from /proc/stat
# Returns a hashref of the information, with the proper field headers, per CPU
sub procstat {
    open(my $fh, '<', '/proc/stat')
        or die "$!";

    my $cpu_info = {};
    while (my $row = <$fh>) {
        chomp $fh;
        next unless $row =~ /cpu[0-9]+\s+/;
        my ($cpu, $metrics) = split(/\s+/, $row, 2);
        my %zipped_stats;
        my @val_arr = split(/\s+/, $metrics);
        my @headers = &headers;
        @headers = @headers[0..$#val_arr];
        @zipped_stats{@headers} = @val_arr;
        $cpu_info->{$cpu} = \%zipped_stats;
    }
    close($fh);

    return $cpu_info;
}

# Returns a hashref with the CPU information and the uptime
sub uptime_and_stat {
    my $data = {};
    $data->{uptime} = &uptime;
    $data->{cpus} = &procstat;
    return $data;
}

# Returns the difference between two CPU hashrefs, based on uptime
sub get_change {
    my $init = shift;
    my $fin = shift;
    my $change = {};
    $change->{uptime} = $fin->{uptime} - $init->{uptime};

    foreach my $cpu (keys %{$fin->{cpus}}) {
        foreach my $metric (keys %{$fin->{cpus}->{$cpu}}) {
            my $diff = $fin->{cpus}->{$cpu}->{$metric} - $init->{cpus}->{$cpu}->{$metric};
            $change->{cpus}->{$cpu}->{$metric} = $diff;
        }
    }
    return $change;
}

# Calculates percentage utilization, per metric, based on hz and uptime.
sub calculate_percentages {
    my $change = shift;
    my $percentages = {};
    # For each CPU and each metric, calculate the percentage
    foreach my $cpu (keys %{$change->{cpus}}) {
        foreach my $metric (keys %{$change->{cpus}->{$cpu}}) {
            my $value = $change->{cpus}->{$cpu}->{$metric};
            # ( Seconds utilization change / Uptime change / user_hz ) * 100
            $percentages->{$cpu}->{$metric} =
                ($value / $change->{uptime} / &user_hz) * 100;
        }
        # Get overall utilization
        $percentages->{$cpu}->{utilization} =
            get_cpu_utilisation($percentages->{$cpu});
    }
    return $percentages;
}

# Exits plugin with $code, $message, $perfdata
sub nexit {
    my $code = shift;
    my $message = shift;
    my $perfdata = shift;

    if ($perfdata) {
        $message .= "|$perfdata";
    }

    if ($code == 2) {
        $message = "CRITICAL: $message"
    } elsif ($code == 1) {
        $message = "WARNING: $message"
    } elsif ($code == 0) {
        $message = "OK: $message"
    } else {
        $message = "UNKNOWN: $message"
    }

    printf "%s\n", $message;
    exit $code;
}

# Calculate the total CPU utilization (Sum of all metrics - idle time)
sub get_cpu_utilisation {
    my $vals = shift;
    my $idle = $vals->{idle};
    my $sum = 0;
    foreach my $k (keys %$vals) {
        unless ($k eq "idle") {
            $sum += $vals->{$k};
        }
    }
    return $sum;
}

# Gets uptime and CPU metrics
# Sleeps for $1
# Gets uptime and CPU metrics again
# Calculates the change in utilisation
# Calculates the overall utilization, per CPU
# Returns hashref
sub get_cpu_info_over_nseconds {
    my $initial = &uptime_and_stat;
    sleep shift;
    my $final = &uptime_and_stat;
    my $change = get_change($initial, $final);
    my $percentages = calculate_percentages($change);
    return $percentages;
}

# Writes also.
sub get_cpu_info_over_check_period {
    my $filename = shift;
    my $initial = read_file($filename);
    my $final = uptime_and_stat($filename);
    write_file($filename, $final);

    # If a reboot of the host occurrs, will need two runs.
    if ($initial->{uptime} > $final->{uptime}) {
        nexit(3, "Reboot since last run. Waiting for next run")
    }

    my $change = get_change($initial, $final);
    my $percentages = calculate_percentages($change);
    return $percentages;
}

# Accumulates the percentage utilisation of all CPUs into one field
sub summarise_values {
    my $vals = shift;
    my $cpu_summary = {};
    foreach my $cpu (keys %$vals) {
        foreach my $metric (keys %{$vals->{$cpu}}) {
            if ($cpu_summary->{$metric}) {
                $cpu_summary->{$metric} =
                    $cpu_summary->{$metric} + $vals->{$cpu}->{$metric};
            } else {
                $cpu_summary->{$metric} = $vals->{$cpu}->{$metric};
            }
        }
    }
    return $cpu_summary;
}

# Returns solaris time (as opposed to irix time)
# (CPU time divided by number of cores)
sub to_solaris_time {
    my $cpu_info = shift;
    my $num_cpus = shift;
    my $solaris_time = {};
    foreach my $metric (keys %$cpu_info) {
        $solaris_time->{$metric} = $cpu_info->{$metric} / $num_cpus;
    }
    return $solaris_time;
}

# Work out the exit code from the warning, critical and utilisation metric
sub get_nagios_exit {
    my $value = shift;
    my $opts = shift;
    unless ($opts->{w} || $opts->{c}) {
        return 0;
    }
    if ($opts->{c} && $value > $opts->{c}) {
        return 2;
    }
    if ($opts->{w} && $value > $opts->{w}) {
        return 1;
    }
    return 0;
}

# Get an output string of metrics with perfdata
# Uses expression to calculate which fields to output
sub get_nagios_output {
    my $summary = shift;
    my $opts = shift;
    my $cpu_num = shift;

    # For perfdata max values
    my $max_usage;
    if ($opts->{expr}->{irix}) {
        $max_usage = $cpu_num * 100;
    } else {
        $max_usage = 100;
    }

    # Ignore warn and crit for perfdata if not specified
    my $warn = $opts->{w} ? $opts->{w} : '';
    my $critical = $opts->{c} ? $opts->{c} : '';

    my $message = "";
    my $perfdata = "";
    foreach my $metric (sort(keys %$summary)) {
        # Don't include idle time in output unless specified
        if (!$opts->{expr}->{idle} && $metric eq "idle") {
            next;
        }
        # Only use opts->{m} metric for output
        if ($opts->{expr}->{nostat} && $metric ne $opts->{m}) {
            next;
        }
        # No guest metrics if specified
        if ($opts->{expr}->{noguest} && $metric =~ /^guest/ && $metric ne $opts->{m}) {
            next;
        }
        # Honor standard expression
        if (!$opts->{expr}->{all} && !$opts->{expr}->{$metric} && $metric ne $opts->{m}) {
            next;
        }
        # Put the metric used at the start
        if ($metric eq $opts->{m}) {
            $message = sprintf "%s:%.1f%%,%s",
                $metric, $summary->{$metric}, $message;
        } else {
            $message .= sprintf "%s:%.1f%%,",
                $metric, $summary->{$metric};
        }

        $perfdata .= sprintf "'%s'=%.2f%%;%s;%s;0;%u ",
            $metric, $summary->{$metric}, $warn, $critical, $max_usage;
    }
    # Remove leading delimiters
    chop $message;
    chop $perfdata;
    return ($message, $perfdata);
}

# Gets a tmp filename from the servicecheck & args
# Uses directory $1
sub filepath {
    my $dir = shift;
    my $args = shift;
    $dir =~ s/^(.*)\/$/$1/;
    if ( ! -d "$dir" ) {
        nexit(3, "Temp directory $dir not found");
    }
    $args = join(" ", @$args);
    my $hash = md5_hex("$0 $args");
    my $script = $0;
    $script =~ s/^\/?(?:[^\/]+\/)+([^\/]+)/$1/;
    cleanup($dir, $script);
    return sprintf "%s/%s_%s", $dir, $script, $hash;
}

# Stores the uptime and CPU stats in $1
# If $2 isn't a hash, get one
sub write_file {
    my $file = shift;
    my $cpu_info = shift;
    unless ($cpu_info) {
        $cpu_info = &uptime_and_stat;
    }
    store($cpu_info, $file) or nexit(3, "Cannot store file: $file");
}

# Reads file $1 and returns it as a hash
sub read_file {
    my $file = shift;
    my $cpu_info = retrieve($file) or nexit(3, "Cannot read file: $file");
    return $cpu_info;
}

# Silently remove any old files in the given dir
# Removes anything older than a week.
# Runs in BG
sub cleanup {
    my $pid = fork;
    return if $pid;
    my $dir = shift;
    my $prefix = shift;
    opendir (my $od, $dir) or return 0;
    while (my $file = readdir($od)) {
        if ($file =~ /^$prefix/) {
            my @st = stat("$dir/$file");
            my $mtime = $st[9];
            my $time = time;
            if (($time - $mtime) > 604800) {
                unlink "$dir/$file";
            }
        }
    }
    closedir($od);
    exit;
}

# Better call main
main();
