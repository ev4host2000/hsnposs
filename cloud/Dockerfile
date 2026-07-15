FROM php:8.2-fpm-alpine

RUN apk add --no-cache \
        postgresql-dev \
        icu-dev \
        libzip-dev \
    && docker-php-ext-install -j"$(nproc)" \
        pdo \
        pdo_pgsql \
        opcache \
    && rm -rf /var/cache/apk/*

WORKDIR /var/www/html

COPY api/ /var/www/html/

COPY deploy/docker-init/docker-entrypoint.sh /usr/local/bin/miza-entrypoint.sh
RUN chmod +x /usr/local/bin/miza-entrypoint.sh \
    && mkdir -p storage/logs storage/rate_limit storage/media \
    && chown -R www-data:www-data storage

ENTRYPOINT ["/usr/local/bin/miza-entrypoint.sh"]
CMD ["php-fpm"]
