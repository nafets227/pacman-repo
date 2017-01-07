#!/bin/bash
#
# Start container fcgiwrap and nginx
#
# (C) 2017 Stefan Schallenberg
#

# Prepare directories and their access rights
test -d /srv/pacman-cache || mkdir -p /srv/pacman-cache
test -d /srv/pacman-repo  || mkdir -p /srv/pacman-repo
chown http:http /srv/pacman-cache /srv/pacman-repo

# Start our Perl Backlend for uploads (Fast CGI)
/usr/local/bin/upload.pl &

#Now run Nginx (not forking!)
nginx -g "daemon off;"
