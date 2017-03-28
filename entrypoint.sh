#!/bin/sh

sed -i "s/allowed_hosts=127.0.0.1/allowed_hosts=127.0.0.1, ${NAGIOS_SERVER}/g" /etc/nrpe.cfg

/usr/bin/nrpe -c /etc/nrpe.cfg -d

# Wait for NRPE Daemon to exit
PID=$(ps -ef | grep -v grep | grep  "/usr/bin/nrpe" | awk '{print $1}')
if [ ! "$PID" ]; then
  echo "Error: Unable to start nrpe daemon..."
  # exit 1
fi
while [ -d /proc/$PID ] && [ -z `grep zombie /proc/$PID/status` ]; do
    echo "NRPE: $PID (running)..."
    sleep 60s
done
echo "NRPE daemon exited. Quitting.."
