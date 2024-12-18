#!/bin/sh
set -e

# Update allowed hosts only if needed
if [ -n "${NAGIOS_SERVER}" ]; then
    CURRENT_HOSTS=$(grep "^allowed_hosts" /etc/nrpe.cfg | cut -d= -f2)
    EXPECTED_HOSTS="127.0.0.1,${NAGIOS_SERVER}"
    
    if [ "$CURRENT_HOSTS" != "$EXPECTED_HOSTS" ]; then
        echo "Updating allowed_hosts configuration..."
        sed -i "s/^allowed_hosts=.*$/allowed_hosts=${EXPECTED_HOSTS}/g" /etc/nrpe.cfg
    fi
fi

# Start NRPE in foreground mode
exec /usr/bin/nrpe -c /etc/nrpe.cfg -f
