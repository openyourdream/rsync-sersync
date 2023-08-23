# 基于rsync和sersync制作高效数据同步docker镜像
参考资料：https://github.com/wsgzao/sersync

基于rsync和sersync构建docker镜像，用于实现高效的数据实时同步架构。

## 1，前言

一般简单的服务器数据传输会使用`ftp/sftp`等方式，但是这样的方式效率不高，不支持差异化增量同步也不支持实时传输。针对数据实时同步需求大多数人会选择`rsync+inotify-tools`的解决方案，但是这样的方案也存在弊端，`sersync`是国人基于前两者开发的工具，不仅保留了优点同时还强化了实时监控，文件过滤，简化配置等功能，帮助用户提高运行效率，节省时间和网络资源。



## 2，原理

sersync主要用于服务器同步，web镜像等功能。基于boost1.43.0，inotify api，rsync command开发。目前使用的比较多的同步解决方案是inotify-tools+rsync ，另外一个是google开源项目Openduckbill（依赖于inotify- tools），这两个都是基于脚本语言编写的。相比较上面两个项目，本项目优点是：

- sersync是使用c++编写，而且对linux系统文件系统产生的临时文件和重复的文件操作进行过滤（详细见附录，这个过滤脚本程序没有实现），所以在结合rsync同步的时候，节省了运行时耗和网络资源。因此更快。
- 相比较上面两个项目，sersync配置起来很简单，其中bin目录下已经有基本上静态编译的2进制文件，配合bin目录下的xml配置文件直接使用即可。
- 另外本项目相比较其他脚本开源项目，使用多线程进行同步，尤其在同步较大文件时，能够保证多个服务器实时保持同步状态。
- 本项目有出错处理机制，通过失败队列对出错的文件重新同步，如果仍旧失败，则按设定时长对同步失败的文件重新同步。
- 本项目自带crontab功能，只需在xml配置文件中开启，即可按您的要求，隔一段时间整体同步一次。无需再额外配置crontab功能。
- 本项目socket与http插件扩展，满足您二次开发的需要。



## 3，制作镜像

Dockerfile文件

```shell
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
```

rsyncd.conf配置文件

```shell
uid=root
gid=root
#最大连接数
max connections=36000
#默认为true，修改为no，增加对目录文件软连接的备份 
use chroot=no
#定义日志存放位置
log file=/var/log/rsyncd.log
#忽略无关错误
ignore errors = yes
#设置rsync服务端文件为读写权限
read only = no
#认证的用户名与系统帐户无关在认证文件做配置，如果没有这行则表明是匿名
auth users = rsync
#密码认证文件，格式(虚拟用户名:密码）
secrets file = /etc/rsync.pass
#这里是认证的模块名，在client端需要指定，可以设置多个模块和路径
[rsync]
#自定义注释
comment  = rsync
#同步到B服务器的文件存放的路径
path=/syncdir
hosts allow = *
#hosts deny = *
```

confxml.xml配置文件

```xml-dtd
<?xml version="1.0" encoding="ISO-8859-1"?>
<head version="2.5">
    <host hostip="localhost" port="8008"></host>
    <debug start="true"/>
    <fileSystem xfs="true"/>
    <filter start="false">
        <exclude expression="(.*)\.php"></exclude>
        <exclude expression="^data/*"></exclude>
    </filter>
    <inotify>
        <delete start="false"/>
        <createFolder start="true"/>
        <createFile start="true"/>
        <closeWrite start="true"/>
        <moveFrom start="true"/>
        <moveTo start="true"/>
        <attrib start="false"/>
        <modify start="false"/>
    </inotify>
    <sersync>
        <localpath watch="/syncdir">
            <!-- 这里填写要同步的文件夹路径-->
            <remote ip="{target_host}" name="rsync"/>
            <!-- 这里填写目标服务器的IP地址和模块名-->
        </localpath>
        <rsync>
            <commonParams params="-artuz"/>
            <auth start="true" users="rsync" passwordfile="/app/local/sersync/user.pass"/>
            <!-- rsync+密码文件 这里填写服务器B的认证信息-->
            <userDefinedPort start="false" port="874"/>
            <!-- port=874 -->
            <timeout start="false" time="100"/>
            <!-- timeout=100 -->
            <ssh start="false"/>
        </rsync>
        <failLog path="/tmp/rsync_fail_log.sh" timeToExecute="60"/>
        <!--default every 60mins execute once-->
        <!-- 修改失败日志记录（可选）-->
        <crontab start="false" schedule="600">
            <!--600mins-->
            <crontabfilter start="false">
                <exclude expression="*.php"></exclude>
                <exclude expression="info/*"></exclude>
            </crontabfilter>
        </crontab>
        <plugin start="false" name="command"/>
    </sersync>
    <!-- 下面这些有关于插件你可以忽略了 -->
    <plugin name="command">
        <param prefix="/bin/sh" suffix="" ignoreError="true"/>
        <!--prefix /opt/tongbu/mmm.sh suffix-->
        <filter start="false">
            <include expression="(.*)\.php"/>
            <include expression="(.*)\.sh"/>
        </filter>
    </plugin>
    <plugin name="socket">
        <localpath watch="/home/demo">
            <deshost ip="210.36.158.xxx" port="8009"/>
        </localpath>
    </plugin>
    <plugin name="refreshCDN">
        <localpath watch="/data0/htdocs/cdn.markdream.com/site/">
            <cdninfo domainname="cdn.chinacache.com" port="80" username="xxxx" passwd="xxxx"/>
            <sendurl base="http://cdn.markdream.com/cms"/>
            <regexurl regex="false" match="cdn.markdream.com/site([/a-zA-Z0-9]*).cdn.markdream.com/images"/>
        </localpath>
    </plugin>
</head>
```

start.sh

```shell
#!/bin/sh
#author:openyourdream

sed -i 's|{target_host}|'$target_host'|g' /app/local/sersync/confxml.xml
/usr/local/bin/rsync --daemon
/app/local/sersync/sersync2 -r -d -o /app/local/sersync/confxml.xml >/app/local/sersync/rsync.log 2>&1
tail -f /app/local/sersync/rsync.log
```

构建命令

```shell
# 构建镜像命令
docker build -f Dockerfile -t "openyourdream/rsync-sersync:1.0" . --no-cache

# 删除镜像命令
docker rmi openyourdream/rsync-sersync:1.0

# 保存镜像命令
docker save -o rsync-sersync.tar openyourdream/rsync-sersync:1.0
```



## 4，部署服务

tips：rsync默认TCP端口为873，防火墙必须开启该端口。

假设：

- 服务器A（主服务器）
- 服务器B（从服务器/备份服务器）

分别在两台服务器部署该服务，使用docker-compose方式来运行服务，docker-compose.yml文件

```yaml
version: '2.4'
services:
  rsync-sersync:
    image: 'openyourdream/rsync-sersync:1.0'
    restart: always
    privileged: true
    tty: true
    volumes:
      - '/etc/localtime:/etc/localtime:ro'
      - './rsyncd.conf:/etc/rsyncd.conf'
      - './confxml.xml:/app/local/sersync/confxml.xml'
      - '/data/volumes/rsync:/syncdir'
    ports:
      - '873:873'
    environment:
      target_host: 192.168.8.110   # 例如在A服务器部署就填写B服务器iP,在B服务器部署就填写A服务器ip地址（由此才可以实现双向传输数据）
    network_mode: host
    container_name: rsync-sersync
```

运行命令

```shell
# 运行服务
docker-compose up -d

# 停止服务
docker-compose down -v

# 查看服务日志
docker logs -fn 300 rsync-sersync
```



## 附录1：常见问题

常见错误1：name lookup failed for 192.168.8.110: Name or service not known

```shell
# 在服务端很客户端互相添加对方的IP解析到host文件中
echo "${ip地址} $(hostname)" >>/etc/hosts
```

