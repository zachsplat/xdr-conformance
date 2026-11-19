#!/bin/sh
# Run one reproduction against the published package, in docker.
#   expansion/dart/repro/run.sh bin/r01_price_hash.dart
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
DCACHE=${DCACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/xdrconf/dart-cache}
IMG=${IMG:-ghcr.io/cirruslabs/flutter:stable}
U=$(id -u):$(id -g)
if [ ! -f "$HERE/pubspec.lock" ]; then
  docker run --rm -e PUB_CACHE=/c/pub-cache -e FLUTTER_SUPPRESS_ANALYTICS=true -v "$DCACHE:/c" -v "$HERE:/src" -w /src "$IMG" \
    sh -c "flutter --no-version-check pub get >/dev/null; chown -R $U /src /c"
fi
# Runs as root because `dart run` on a package that depends on the Flutter SDK
# consults the image's root-owned Flutter checkout; ownership is restored after.
exec docker run --rm -i -e PUB_CACHE=/c/pub-cache -v "$DCACHE:/c" -v "$HERE:/src" -w /src "$IMG" \
  sh -c "dart --disable-analytics run $*; s=\$?; chown -R $U /src /c; exit \$s"
