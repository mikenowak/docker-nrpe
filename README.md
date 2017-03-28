# docker-nrpe

Run as follows:

```
docker run -d --restart unless-stopped -v /:/rootfs:ro -v /var/run:/var/run:rw -v /sys:/sys:ro -v /var/lib/docker/:/var/lib/docker:ro --privileged --net=host --ipc=host --pid=host -e NAGIOS_SERVER="1.2.3.4" mikenowak/nrpe
```

`NAGIOS_SERVER` is the IP address of your monitoring server.
