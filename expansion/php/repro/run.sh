#!/bin/sh
# Run one reproduction against the published package or SDK main.
#   ./run.sh r1_inner_tx_hash_json.php           # soneso/stellar-php-sdk 1.18.0 from Packagist
#   SDK=main ./run.sh r1_inner_tx_hash_json.php  # a clone of main (for "still on main?")
# Needs the xdrconf-php:8.3 image and the composer installs that runners/php/run.sh makes.
set -e
HERE=$(dirname "$(realpath "$0")")
CACHE=${XDRCONF_PHP_CACHE:-$HOME/.cache/xdrconf/php-cache}
case "${SDK:-release}" in
  main) VENDOR=/cache/sdk-main/vendor ;;
  *)    VENDOR=/cache/proj/vendor ;;
esac
exec docker run --rm -i --network none -u "$(id -u):$(id -g)" -e SDK_VENDOR=$VENDOR \
  -v "$CACHE:/cache:ro" -v "$HERE:/repro:ro" -w /repro xdrconf-php:8.3 php /repro/"$1"
