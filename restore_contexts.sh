#!/bin/bash

restorecon -RvF /etc/systemd/system \
            /etc/pihole \
            /etc/.pihole \
            /opt/pihole \
            /usr/bin/pihole-FTL \
            /usr/local/bin/pihole \
            /usr/local/bin/php-cgi-pihole \
            /dev/shm \
            /var/run \
            /var/www \
            /etc/cron.d \
            /var/log \
            /tmp
