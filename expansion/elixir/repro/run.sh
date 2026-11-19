#!/bin/sh
# Run every repro against the published Hex package in elixir:1.18 (docker).
# Mix.install's cache lives in $WORK/elixir-cache/mix-install.
WORK=${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/xdrconf}
HERE=$(cd "$(dirname "$0")" && pwd)
C=$WORK/elixir-cache
mkdir -p "$C/mix-install" "$C/repro-home"
for f in "$HERE"/r*.exs; do
  n=$(basename "$f" .exs)
  docker run --rm -u "$(id -u):$(id -g)" -e HOME=/c/repro-home -e MIX_HOME=/c/repro-home/mix -e HEX_HOME=/c/repro-home/hex \
    -e MIX_INSTALL_DIR=/c/mix-install -v "$HERE:/r:ro" -v "$C:/c" -w /r elixir:1.18 \
    sh -c 'mix local.hex --force >/dev/null 2>&1; mix local.rebar --force >/dev/null 2>&1; elixir /r/'"$n"'.exs' > "$HERE/$n.out.txt" 2>&1
  echo "== $n"; cat "$HERE/$n.out.txt"
done
