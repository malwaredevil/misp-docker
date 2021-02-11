
FROM ubuntu:bionic

# Install core components
ENV DEBIAN_FRONTEND noninteractive
ENV LANG en_US.UTF-8
ENV BUILD_DEPS="build-essential" \
    APP_DEPS="postfix mysql-client curl gcc git \
    gnupg-agent make python openssl redis-server \
    sudo vim zip locales wget libgpgme-dev \
    apache2 apache2-doc apache2-utils \
    python3-dev python3-pip python3-setuptools \
    python3-lxml libjpeg-dev \
    libxml2-dev libxslt1-dev zlib1g-dev libfuzzy-dev \
    cron logrotate supervisor syslog-ng-core \
    libapache2-mod-php7.4 php7.4 php7.4-cli php7.4-dev \
    php7.4-json php7.4-xml php7.4-mysql php7.4-opcache \
    php7.4-readline php7.4-mbstring php-pear php7.4-zip \
    php7.4-redis php7.4-gnupg pkg-config libbson-1.0 libmongoc-1.0-0 \
    php7.4-gd libpoppler73 libpoppler-dev libpoppler-cpp-dev"

RUN apt-get update -y && \
    apt-get install software-properties-common -y && \
    add-apt-repository ppa:ondrej/php -y && \
    apt-get update -y && \
    apt-get dist-upgrade -y && apt-get autoremove -y && apt-get clean && \
    apt-get install -y ${BUILD_DEPS} ${APP_DEPS} && \
    locale-gen en_US.UTF-8 && \
     a2dismod status && \
    a2dissite 000-default && \
    sed -i \
        -e "s/max_execution_time = 30/max_execution_time = 300/" \
        -e "s/memory_limit = 128M/memory_limit = 2048M/" \
        -e "s/upload_max_filesize = 2M/upload_max_filesize = 50M/" \
        -e "s/post_max_size = 8M/post_max_size = 50M/" \
        /etc/php/7.4/apache2/php.ini && \
    apt-get clean

WORKDIR /var/www
RUN chown www-data:www-data /var/www
USER www-data
RUN git clone https://github.com/MISP/MISP.git
WORKDIR /var/www/MISP
RUN git config core.filemode false && \
    git submodule update --init --recursive && \
    git submodule foreach --recursive git config core.filemode false

USER root
RUN python3 -m pip install git+https://github.com/STIXProject/python-stix.git \
                 git+https://github.com/CybOXProject/python-cybox.git \
                 git+https://github.com/CybOXProject/mixbox.git \
                 git+https://github.com/MAECProject/python-maec.git \
                 /var/www/MISP/cti-python-stix2 \
                 plyara  \
                 pydeep

USER www-data
WORKDIR /var/www/MISP
RUN git submodule init && git submodule update
WORKDIR /var/www/MISP/app

RUN curl --fail --location -o composer-setup.php https://getcomposer.org/installer && \
    EXPECTED_SIGNATURE="$(curl https://composer.github.io/installer.sig)"; php -r "if (hash_file('sha384', 'composer-setup.php') == '$(echo $EXPECTED_SIGNATURE)' ) { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" && \
    php composer-setup.php && \
    php -r "unlink('composer-setup.php');" && \
    php composer.phar update && \
    php composer.phar config vendor-dir Vendor && \
    php composer.phar install --ignore-platform-reqs
USER root
RUN phpenmod redis
USER www-data
RUN cp -fa /var/www/MISP/INSTALL/setup/config.php /var/www/MISP/app/Plugin/CakeResque/Config/config.php

USER root
RUN chown -R www-data:www-data /var/www/MISP && \
    chmod -R 750 /var/www/MISP && \
    chmod -R g+ws /var/www/MISP/app/tmp && \
    chmod -R g+ws /var/www/MISP/app/files && \
    chmod -R g+ws /var/www/MISP/app/files/scripts/tmp && \
    chmod +x /var/www/MISP/app/Console/cake && \
     cp /var/www/MISP/INSTALL/misp.logrotate /etc/logrotate.d/misp && \
    RUN echo "postfix postfix/main_mailer_type string Local only" \
  | debconf-set-selections && \
    echo "postfix postfix/mailname string localhost.localdomain" | \
    debconf-set-selections && \
    sed -i 's/^\(daemonize\s*\)yes\s*$/\1no/g' /etc/redis/redis.conf && \
    sed -i 's/^\(bind\s*\)127.0.0.1 ::1\s*$/\1127.0.0.1/g' /etc/redis/redis.conf

COPY healthcheck.patch healthcheck.patch
RUN patch /var/www/MISP/INSTALL/apache.misp.ubuntu < healthcheck.patch && \
    cp /var/www/MISP/INSTALL/apache.misp.ubuntu /etc/apache2/sites-available/misp.conf && \
    a2dissite 000-default && \
    a2ensite misp && \
    a2enmod rewrite && \
    a2enmod headers && \
    sudo -u www-data cp -a /var/www/MISP/app/Config/bootstrap.default.php /var/www/MISP/app/Config/bootstrap.php && \
    sudo -u www-data cp -a /var/www/MISP/app/Config/database.default.php /var/www/MISP/app/Config/database.php && \
    sudo -u www-data cp -a /var/www/MISP/app/Config/core.default.php /var/www/MISP/app/Config/core.php && \
    sudo -u www-data cp -a /var/www/MISP/app/Config/config.default.php /var/www/MISP/app/Config/config.php && \
    chown -R www-data:www-data /var/www/MISP/app/Config && \
    chmod -R 750 /var/www/MISP/app/Config && \
    sed -i -E "s/'salt'\s=>\s'(\S+)'/'salt' => '`openssl rand -base64 32|tr "/" "-"`'/" /var/www/MISP/app/Config/config.php && \
    chmod a+x /var/www/MISP/app/Console/worker/start.sh && \
    echo "sudo -u www-data bash /var/www/MISP/app/Console/worker/start.sh" >>/etc/rc.local

# Install templates & stuff
WORKDIR /var/www/MISP/app/files
RUN rm -rf misp-objects && git clone https://github.com/MISP/misp-objects.git && \
    rm -rf misp-galaxy && git clone https://github.com/MISP/misp-galaxy.git && \
    rm -rf warninglists && git clone https://github.com/MISP/misp-warninglists.git ./warninglists && \
    rm -rf taxonomies && git clone https://github.com/MISP/misp-taxonomies.git ./taxonomies && \
    chown -R www-data:www-data misp-objects misp-galaxy warninglists taxonomies

# Install MISP Modules
WORKDIR /opt
# RUN git clone --branch v2.4.134 https://github.com/MISP/misp-modules.git
RUN git clone https://github.com/MISP/misp-modules.git && \
    cd misp-modules && \
    python3 -m pip install --upgrade pip setuptools wheel && \
    python3 -m pip install scikit-build && \    
    python3 -m pip install opencv-python && \ 
    python3 -m pip install -I -r REQUIREMENTS && \
    python3 -m pip install -I . && \
    echo "sudo -u www-data misp-modules -s -l 127.0.0.1 &" >>/etc/rc.local && \
    ( \
    echo '[supervisord]'; \
    echo 'nodaemon = true'; \
    echo ''; \
    echo '[program:cron]'; \
    echo 'command=/usr/sbin/cron -f'; \
    echo '[program:postfix]'; \
    echo 'process_name = master'; \
    echo 'directory = /etc/postfix'; \
    echo 'command = /usr/sbin/postfix -c /etc/postfix start'; \
    echo 'startsecs = 0'; \
    echo ''; \
    echo '[program:redis-server]'; \
    echo 'command=redis-server /etc/redis/redis.conf'; \
    echo ''; \
    echo '[program:apache2]'; \
    echo 'command=/bin/bash -c "source /etc/apache2/envvars && exec /usr/sbin/apache2 -D FOREGROUND"'; \
    echo ''; \
    echo '[program:resque]'; \
    echo 'command=/bin/bash /var/www/MISP/app/Console/worker/start.sh'; \
    echo 'user = www-data'; \
    echo 'startsecs = 0'; \
    echo ''; \
    echo '[program:misp-modules]'; \
    echo 'command=/bin/bash -c "misp-modules -l 127.0.0.1"'; \
    echo 'user = www-data'; \
    echo 'startsecs = 0'; \
    ) >> /etc/supervisor/conf.d/supervisord.conf

#INSTALL SSDEEP
WORKDIR /usr/local/src

RUN wget https://github.com/ssdeep-project/ssdeep/releases/download/release-2.14.1/ssdeep-2.14.1.tar.gz && \
    tar zxvf ssdeep-2.14.1.tar.gz
WORKDIR /usr/local/src/ssdeep-2.14.1
RUN ./configure --datadir=/usr --prefix=/usr --localstatedir=/var --sysconfdir=/etc && \
    make && \
    make install && \
    apt-get install -y ssdeep && \
    pecl channel-update pecl.php.net && \
    pecl install ssdeep && \
    pecl install gnupg && \
    echo 'extension=gnupg.so' >  /etc/php/7.4/mods-available/gnupg.ini && \
    echo 'extension=ssdeep.so' >  /etc/php/7.4/mods-available/ssdeep.ini

USER root
RUN phpenmod ssdeep && \
    phpenmod zip && \
    a2enmod php7.4 && \
    update-alternatives --set php /usr/bin/php7.4 && \
    sed -i -E 's/^(\s*)system\(\);/\1unix-stream("\/dev\/log");/' /etc/syslog-ng/syslog-ng.conf

# Add run script
# Trigger to perform first boot operations
ADD run.sh /run.sh
RUN chmod 0755 /run.sh && touch /.firstboot.tmp

# # Make a backup of /var/www/MISP to restore it to the local moint point at first boot
# WORKDIR /var/www/MISP
# RUN tar czpf /root/MISP.tgz .

COPY run.sh /bin/run.sh
RUN chmod +x /bin/run.sh
ENTRYPOINT [ "/bin/run.sh" ]



