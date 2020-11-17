FROM wordpress:4.9


RUN apt-get update && \
    apt-get install -y \
        git \
        jq \
        curl \
	wget \
	initscripts

WORKDIR /var/www/html/

COPY --chown=www-data:www-data ./src/publish-bash/update-json.sh /var/www/html/publish/update-json.sh

RUN chown -R www-data:www-data /var/www/

RUN touch /usr/local/etc/php/conf.d/uploads.ini
RUN echo "upload_max_filesize = 40M;" >> /usr/local/etc/php/conf.d/uploads.ini
RUN echo "post_max_size = 40M;" >> /usr/local/etc/php/conf.d/uploads.ini

ADD https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar /usr/local/bin/wp
RUN chmod +x /usr/local/bin/wp

RUN a2enmod ssl
RUN a2enmod headers
