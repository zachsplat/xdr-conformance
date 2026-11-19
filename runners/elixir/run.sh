#!/bin/sh
# Run the stellar_base adapter: JSONL requests on stdin, results on stdout.
# Toolchain and caches only in docker (elixir:1.18) and $WORK/elixir-cache.
WORK=${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/xdrconf}
HERE=$(cd "$(dirname "$0")" && pwd)
C=$WORK/elixir-cache
mkdir -p "$C/home"
exec docker run --rm -i -u "$(id -u):$(id -g)" -e HOME=/c/home -e MIX_HOME=/c/mix -e HEX_HOME=/c/hex \
  -e MIX_DEPS_PATH=/c/deps -e MIX_BUILD_PATH=/c/build -e MIX_ENV=prod \
  -e XDRCONF_TIMEOUT_MS -e XDRCONF_MAX_HEAP_WORDS -e XDRCONF_CONCURRENCY \
  -v "$HERE:/src" -v "$C:/c" -w /src elixir:1.18 \
  sh -c '[ -d /c/deps/stellar_base ] || { mix local.hex --force >&2 && mix local.rebar --force >&2 && mix deps.get >&2; }; mix compile >&2 && exec mix run --no-compile -e "Facts.main()"'
