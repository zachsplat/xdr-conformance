#!/bin/sh
# Build or run the Dart adapter. Everything runs in docker; caches stay in $DCACHE.
#   runners/dart/run.sh build         flutter pub get + dart compile exe
#   runners/dart/run.sh < REQ.jsonl   run the compiled adapter (JSONL in, JSONL out)
#   runners/dart/run.sh jit < REQ     same, through `dart run` (JIT VM) instead of the AOT binary
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
DCACHE=${DCACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/xdrconf/dart-cache}
IMG=${IMG:-ghcr.io/cirruslabs/flutter:stable}
U=$(id -u):$(id -g)
mkdir -p "$DCACHE/bin" "$DCACHE/pub-cache"
case "$1" in
build)
  docker run --rm -e PUB_CACHE=/c/pub-cache -e FLUTTER_SUPPRESS_ANALYTICS=true -v "$DCACHE:/c" -v "$HERE:/src" -w /src "$IMG" \
    sh -c "flutter --no-version-check pub get && dart compile exe bin/facts.dart -o /c/bin/xdrconf-dart; chown -R $U /src /c"
  ;;
jit)
  exec docker run --rm -i -u "$U" -e PUB_CACHE=/c/pub-cache -e HOME=/tmp -v "$DCACHE:/c" -v "$HERE:/src" -w /src "$IMG" dart --disable-analytics run bin/facts.dart
  ;;
*)
  exec docker run --rm -i -u "$U" -v "$DCACHE/bin:/b:ro" "$IMG" /b/xdrconf-dart
  ;;
esac
