#!/bin/sh

HTTPD_CONF="/mnt/lg/user/lgmod/httpd.conf"
PASSWD=`awk -F: '/cgi-bin/ {print $3}' $HTTPD_CONF`
while [ "$pass" != "$PASSWD" ]; do
echo -n "Password:"; read pass
done
/bin/sh