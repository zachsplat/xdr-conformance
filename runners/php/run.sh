#!/bin/sh
# Run the PHP adapter in docker: runners/php/run.sh < req.jsonl > out.jsonl
# Builds xdrconf-php:8.3 (php:8.3-cli + gmp, bcmath, composer) and installs
# soneso/stellar-php-sdk (pinned in composer.json) under $XDRCONF_PHP_CACHE.
# If PHP dies on one request (fatal error, out of memory), the driver records
# that request as a crash and restarts PHP on the next one.
set -e
HERE=$(dirname "$(realpath "$0")")
CACHE=${XDRCONF_PHP_CACHE:-$HOME/.cache/xdrconf/php-cache}
IMG=xdrconf-php:8.3
docker image inspect $IMG >/dev/null 2>&1 || docker build -q -t $IMG "$HERE" >&2
mkdir -p "$CACHE/proj" "$CACHE/composer"
if [ ! -f "$CACHE/proj/vendor/autoload.php" ] || ! cmp -s "$HERE/composer.json" "$CACHE/proj/composer.json"; then
  cp "$HERE/composer.json" "$CACHE/proj/composer.json"
  docker run --rm -u "$(id -u):$(id -g)" -e COMPOSER_HOME=/cache/composer -v "$CACHE:/cache" -w /cache/proj $IMG \
    composer update --no-interaction --no-progress -q >&2
fi
exec python3 -I "$HERE/driver.py" docker run --rm -i --network none -u "$(id -u):$(id -g)" \
  -e XDRCONF_PHP_VENDOR=/cache/proj/vendor -v "$CACHE:/cache:ro" -v "$HERE:/adapter:ro" $IMG \
  php -d memory_limit=4G -d display_errors=stderr -d log_errors=0 /adapter/facts.php
