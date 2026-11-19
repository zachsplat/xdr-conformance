#!/bin/sh
# Run the reproductions against the published gems (stellar-base 0.32.0,
# xdr 3.0.3) in a clean ruby:3.3 container. Gems and libsodium are cached
# under ${WORK:-~/.cache/xdrconf}/ruby-cache (runners/ruby/run.sh creates them).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/xdrconf}
for f in "$HERE"/c*.rb; do
  echo "== $(basename "$f")"
  docker run --rm --network none -u "$(id -u):$(id -g)" -e HOME=/tmp -e GEM_HOME=/gems \
    -v "$WORK/ruby-cache/gems:/gems:ro" -v "$WORK/ruby-cache/lib:/sodium:ro" -e LD_LIBRARY_PATH=/sodium \
    -v "$HERE:/r:ro" ruby:3.3 ruby "/r/$(basename "$f")"
done
