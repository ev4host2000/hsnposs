#!/bin/sh
set -e
mkdir -p /var/www/html/storage/media /var/www/html/storage/logs /var/www/html/storage/rate_limit
chown -R www-data:www-data /var/www/html/storage 2>/dev/null || true
exec docker-php-entrypoint "$@"
