#!/bin/sh
# Debug helper: show where stellar_base's decoder fails for each request on stdin.
WORK=${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/xdrconf}
HERE=$(cd "$(dirname "$0")" && pwd)
C=$WORK/elixir-cache
exec docker run --rm -i -u "$(id -u):$(id -g)" -e HOME=/c/home -e MIX_HOME=/c/mix -e HEX_HOME=/c/hex \
  -e MIX_DEPS_PATH=/c/deps -e MIX_BUILD_PATH=/c/build -e MIX_ENV=prod \
  -v "$HERE:/src" -v "$C:/c" -w /src elixir:1.18 \
  sh -c 'mix compile >&2 && exec mix run --no-compile -e "Locate.main()"'
