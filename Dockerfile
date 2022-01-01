FROM buildpack-deps:jessie

RUN apt-get update && apt-get install -y --no-install-recommends curl wget build-essential checkinstall zlib1g-dev \
	apache2-bin apache2-dev apache2.2-common && \
	rm -rf /var/lib/apt/lists/*

RUN rm -rf /var/www/html && \
	rm /etc/apache2/conf-enabled/*.conf && \
	mkdir -p /var/lock/apache2 /var/run/apache2 /var/log/apache2 /var/www/html && \
	chown -R www-data:www-data /var/lock/apache2 /var/run/apache2 /var/log/apache2 /var/www/html

# Apache + PHP requires preforking Apache for best results
# Enable sls and rewrite modules as we always use these
RUN a2dismod mpm_event && a2enmod mpm_prefork && \
	a2enmod ssl rewrite deflate

RUN mv /etc/apache2/apache2.conf /etc/apache2/apache2.conf.dist
COPY apache2.conf /etc/apache2/apache2.conf
COPY apache2-foreground /usr/local/bin/

# compile openssl, otherwise --with-openssl won't work
RUN wget --no-check-certificate https://www.openssl.org/source/openssl-1.0.2o.tar.gz -O openssl.tar.gz \
	&& wget --no-check-certificate https://www.openssl.org/source/openssl-1.0.2o.tar.gz.asc -O openssl.tar.gz.asc \
	&& gpg --verify openssl.tar.gz.asc \
	&& tar -zxvf openssl.tar.gz \
	&& cd openssl-1.0.2o \
	&& ./config --prefix=/usr/local/ssl --openssldir=/usr/local/ssl shared zlib && make && make install

ENV PHP_VERSION=5.2.6 \
	PHP_INI_DIR=/usr/local/lib

# php 5.3 needs older autoconf
RUN set -x \
	&& apt-get update && apt-get install -y autoconf2.13 && rm -r /var/lib/apt/lists/* \
	&& wget --no-check-certificate http://launchpadlibrarian.net/140087283/libbison-dev_2.7.1.dfsg-1_amd64.deb \
	&& wget --no-check-certificate http://launchpadlibrarian.net/140087282/bison_2.7.1.dfsg-1_amd64.deb \
	&& dpkg -i libbison-dev_2.7.1.dfsg-1_amd64.deb \
	&& dpkg -i bison_2.7.1.dfsg-1_amd64.deb \
	&& rm *.deb \
	&& wget --no-check-certificate https://museum.php.net/php5/php-$PHP_VERSION.tar.bz2 -O php.tar.bz2 \
	&& wget --no-check-certificate https://museum.php.net/php5/php-$PHP_VERSION.tar.bz2.asc -O php.tar.bz2.asc \
	&& gpg --verify php.tar.bz2.asc \
	&& mkdir -p /usr/src/php $PHP_INI_DIR/conf.d \
	&& tar -xf php.tar.bz2 -C /usr/src/php --strip-components=1 \
	&& rm php.tar.bz2* \
	&& cd /usr/src/php \
	&& wget --no-check-certificate "https://mail.gnome.org/archives/xml/2012-August/txtbgxGXAvz4N.txt" -O patch.txt \
	&& patch -p0 -b < patch.txt \
	&& ./buildconf --force \
	&& ./configure --disable-cgi \
	$(command -v apxs2 > /dev/null 2>&1 && echo '--with-apxs2' || true) \
	--with-config-file-path="$PHP_INI_DIR" \
	--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
	--with-openssl=/usr/local/ssl \
	&& make -j"$(nproc)" \
	&& make install \
	&& dpkg -r bison libbison-dev \
	&& apt-get purge -y --auto-remove autoconf2.13 \
	&& make clean

COPY docker-php-* /usr/local/bin/

# Install curl php extension as we use it often
RUN docker-php-ext-install curl

WORKDIR /var/www/html

EXPOSE 80
CMD ["apache2-foreground"]
