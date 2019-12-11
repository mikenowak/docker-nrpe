FROM alpine:edge

RUN apk add --no-cache perl ruby ruby-json nrpe nagios-plugins-procs nagios-plugins-time nagios-plugins-load nagios-plugins-swap nagios-plugins-disk python3 sudo \
   && echo 'nagios ALL=(ALL) NOPASSWD: /usr/lib/nagios/plugins/*' >> /etc/sudoers \
   && echo 'Defaults: nagios        !requiretty' >> /etc/sudoers

ADD check_memory check_time_skew check_oxidized.rb check_docker check_swarm /usr/lib/nagios/plugins/
ADD nrpe.cfg /etc/nrpe.cfg
ADD entrypoint.sh /entrypoint.sh

EXPOSE 5666

CMD /entrypoint.sh
