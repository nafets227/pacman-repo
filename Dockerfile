FROM pritunl/archlinux:2017-12-23

MAINTAINER Stefan Schallenberg aka nafets227 <infos@nafets.de>
LABEL Description="Pacman repository (private and caching) in a container"

RUN \
	pacman -S --needed --noconfirm \
		systemd \	
		nginx \
		perl-fcgi && \
	paccache -r -k0 && \
	rm -rf /usr/share/man/* && \
	rm -rf /tmp/* && \
	rm -rf /var/tmp/*

RUN \
	sed -e 's:bsdtar -xf :bsdtar --no-xattrs --no-fflags -xf :' \
		</usr/bin/repo-add \
		>/usr/local/bin/repo-add && \ 
	chmod 755 /usr/local/bin/repo-add

EXPOSE 80 443
CMD /usr/local/bin/start.sh
VOLUME /srv/pacman-repo /srv/pacman-cache

# forward request and error logs to docker log collector
RUN \
	ln -sf /dev/stdout /var/log/nginx/access.log && \
	ln -sf /dev/stderr /var/log/nginx/error.log

RUN \
	rm -rf /etc/nginx/*

COPY nginx.conf /etc/nginx/

COPY upload.pl start.sh /usr/local/bin/

