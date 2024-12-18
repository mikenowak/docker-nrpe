FROM alpine:3.20

RUN apk add --no-cache \
    nagios-plugins \
    nrpe \
    perl \
    sudo \
    python3 \
    ruby \
    ruby-json \
    bash \
    && adduser -D -u 5666 nagios \
    && echo 'nagios ALL=(ALL) NOPASSWD: /usr/lib/monitoring-plugins/*' >> /etc/sudoers \
    && echo 'Defaults: nagios !requiretty' >> /etc/sudoers

COPY check_* /usr/lib/monitoring-plugins/
RUN chmod +x /usr/lib/monitoring-plugins/check_*

COPY nrpe.cfg /etc/nrpe.cfg
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5666

ENTRYPOINT ["/entrypoint.sh"]
