#!/bin/sh
# Run the Ruby adapter in docker (ruby:3.3) on JSONL requests from stdin.
# Gems live in $WORK/ruby-cache/gems (default ~/.cache/xdrconf); nothing is
# installed outside it. First use installs the pinned versions below, and
# libsodium (needed by rbnacl, a stellar-base dependency) from the image's own
# Debian archive into $WORK/ruby-cache/lib.
#   runners/ruby/run.sh < requests.jsonl > results.jsonl
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/xdrconf}
GEMS=$WORK/ruby-cache/gems
LIB=$WORK/ruby-cache/lib
mkdir -p "$GEMS" "$LIB"
IMG=ruby:3.3
D="docker run --rm -u $(id -u):$(id -g) -e HOME=/tmp -e GEM_HOME=/gems -v $GEMS:/gems -v $LIB:/sodium:ro -e LD_LIBRARY_PATH=/sodium -v $HERE:/a:ro"
if [ ! -d "$GEMS/gems/stellar-base-0.32.0" ]; then
  $D $IMG gem install --no-document stellar-base -v 0.32.0 >&2
fi
if [ ! -e "$LIB/libsodium.so.23" ]; then
  docker run --rm -v "$LIB:/out" $IMG sh -c 'apt-get update -qq >/dev/null && cd /tmp && apt-get download -q libsodium23 && dpkg-deb -x libsodium23_*.deb x && cp -a x/usr/lib/x86_64-linux-gnu/libsodium.so* /out/ && chown -R '"$(id -u):$(id -g)"' /out' >&2
fi
exec $D -i --network none $IMG ruby /a/facts.rb
