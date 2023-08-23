#!/bin/sh
#author:openyourdream

sed -i 's|{target_host}|'$target_host'|g' /app/local/sersync/confxml.xml
/usr/local/bin/rsync --daemon
/app/local/sersync/sersync2 -r -d -o /app/local/sersync/confxml.xml >/app/local/sersync/rsync.log 2>&1
tail -f /app/local/sersync/rsync.log
