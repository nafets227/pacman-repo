#!/bin/bash
#
# Start container fcgiwrap and nginx
#
# (C) 2017 Stefan Schallenberg
#

# Environment variables recognized:
test -z "$NGINX_LOGLVL" && NGINX_LOGLVL="warn"
test -z "$RESOLVER" && RESOLVER="127.0.0.1" 

printf "starting pacman-repo container.\n"
printf "\tNGINX_LOGLVL=%s\n" "$NGINX_LOGLVL"
printf "\tRESOLVER=%s\n" "$RESOLVER"

# Prepare directories and their access rights
test -d /srv/pacman-cache || mkdir -p /srv/pacman-cache
test -d /srv/pacman-repo  || mkdir -p /srv/pacman-repo
chown http:http /srv/pacman-cache /srv/pacman-repo

# Start our Perl Backlend for uploads (Fast CGI)
/usr/local/bin/upload.pl &

sed \
	-e "s/\${NGINX_LOGLVL}/$NGINX_LOGLVL/" \
	-e "s/\${RESOLVER}/$RESOLVER/" \
	</etc/nginx/nginx.conf.template \
	>/etc/nginx/nginx.conf 

#Now run Nginx (not forking!)
nginx -g "daemon off;"
