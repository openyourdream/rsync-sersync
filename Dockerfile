FROM centos:centos7.6.1810
MAINTAINER openyourdream
USER root
RUN mkdir -p /app/local
RUN yum -y install gcc gcc-c++ make perl perl-devel util-linux

ADD rsync-3.1.1.tar.gz /app/local/
RUN cd /app/local/rsync-3.1.1 && ./configure && make && make install
COPY rsyncd.conf /etc/rsyncd.conf
RUN echo "rsync:rsync" > /etc/rsync.pass
RUN chmod 600 /etc/rsyncd.conf && chmod 600 /etc/rsync.pass
RUN echo "/usr/local/bin/rsync --daemon" >> /etc/rc.local

ADD inotify-tools-3.14.tar.gz /app/local/
RUN cd /app/local/inotify-tools-3.14&& ./configure --prefix=/app/local/inotify && make && make install

ADD sersync2.5.4_64bit_binary_stable_final.tar.gz /app/local/
RUN mv /app/local/GNU-Linux-x86/ /app/local/sersync
RUN echo "rsync" > /app/local/sersync/user.pass && chmod 600 /app/local/sersync/user.pass
COPY confxml.xml  /app/local/sersync/confxml.xml

VOLUME /syncdir
EXPOSE 873

COPY start.sh /start.sh
RUN chmod +x /start.sh
CMD ["/start.sh"]
