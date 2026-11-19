#!/bin/sh
# Run every reproduction against a java-stellar-sdk classpath, in docker (eclipse-temurin:21,
# Java single-file source launch). Default: the published 6.0.0 jars from Maven Central as
# resolved by ../../../runners/java/build.sh. LIB=<dir of jars> to point elsewhere.
HERE=$(cd "$(dirname "$0")" && pwd)
LIB=${LIB:-${XDG_CACHE_HOME:-$HOME/.cache}/xdrconf/java-cache/target/lib}
run() { docker run --rm -u "$(id -u):$(id -g)" -v "$LIB:/sdk:ro" -v "$HERE:/r:ro" -w /r eclipse-temurin:21 \
  java -cp '/sdk/*' "$@" 2>&1 | grep -v '^Picked up'; }
echo "== J1 LpOrder";       run LpOrder.java
echo "== J2 ResultJson";    run ResultJson.java
echo "== J3 DepthLimit";    run DepthLimit.java scval-vec-95.b64 scval-vec-96.b64 auth-tree-185.b64 auth-tree-186.b64 auth-tree-490.b64
echo "== J4 TrailingBytes"; run TrailingBytes.java
