FROM ubuntu:latest

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get upgrade -y \
   && apt-get install -y nagios-nrpe-server nagios-plugins libmonitoring-plugin-perl sudo python3 ruby ruby-json \
   && rm -rf /var/lib/apt/lists/* \
   && echo 'nagios ALL=(ALL) NOPASSWD: /usr/lib/nagios/plugins/*' >> /etc/sudoers \
   && echo 'Defaults: nagios        !requiretty' >> /etc/sudoers \
   && ln -sf /dev/stdout /var/log/nrpe.log

ADD check_memory check_time_skew check_oxidized.rb check_docker check_swarm check_cpu_stats.sh check_file_count check_ro_mounts /usr/lib/nagios/plugins/
ADD nrpe.cfg /etc/nagios/nrpe.cfg
ADD entrypoint.sh /entrypoint.sh

EXPOSE 5666

CMD /entrypoint.sh
