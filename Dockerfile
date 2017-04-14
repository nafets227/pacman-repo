FROM pritunl/archlinux

MAINTAINER Stefan Schallenberg aka nafets227 <infos@nafets.de>
LABEL Description="Pacman repository (private and caching) in a container"

RUN printf '\n\
[options]\n\
IgnorePkg=cryptsetup\n\
IgnorePkg=device-mapper\n\
IgnorePkg=cryptsetup\n\ 
IgnorePkg=device-mapper\n\
IgnorePkg=dhcpcd\n\
IgnorePkg=iproute2\n\
IgnorePkg=jfsutils\n\
IgnorePkg=linux\n\
IgnorePkg=lvm2\n\
IgnorePkg=man-db\n\
IgnorePkg=man-pages\n\ 
IgnorePkg=mdadm\n\
IgnorePkg=nano\n\
IgnorePkg=netctl\n\
IgnorePkg=openresolv\n\
IgnorePkg=pciutils\n\
IgnorePkg=pcmciautils, \
IgnorePkg=reiserfsprogs\n\
IgnorePkg=s-nail\n\
IgnorePkg=systemd-sysvcompat\n\
IgnorePkg=usbutils\n\
IgnorePkg=vi\n\
IgnorePkg=xfsprogs\n\
' \
>> /etc/pacman.conf && pacman -Sy

RUN \
    pacman -S --needed --noconfirm \
        nginx \
        perl \
        perl-fcgi && \
    paccache -r -k0 && \
	rm -rf /usr/share/man/* && \
	rm -rf /tmp/* && \
	rm -rf /var/tmp/*

RUN \
    sed -e 's:bsdtar -xf :bsdtar --no-xattrs --no-fflags -xf :' \
        </usr/bin/repo-add \
        >/usr/local/bin/repo-add && 
    chmod 755 /usr/local/bin/repo-add

EXPOSE 80 443
CMD /usr/local/bin/start.sh
VOLUME /srv/pacman-repo /srv/pacman-cache

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

RUN \
    rm -rf /etc/nginx/*

COPY nginx.conf /etc/nginx/

COPY upload.pl start.sh /usr/local/bin/

