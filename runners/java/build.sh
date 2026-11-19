#!/bin/sh
# Build the java-stellar-sdk adapter in docker (Maven on Temurin 21). Nothing is
# installed on the host; the Maven repository and the build output live under
# $JCACHE (default ~/.cache/xdrconf/java-cache).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
JCACHE=${JCACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/xdrconf/java-cache}
mkdir -p "$JCACHE/m2" "$JCACHE/home" "$JCACHE/target"
docker run --rm -u "$(id -u):$(id -g)" -v "$JCACHE:/cache" -v "$HERE:/src:ro" -w /cache -e HOME=/cache/home -e MAVEN_CONFIG=/cache/home/.m2 \
  maven:3.9.11-eclipse-temurin-21 sh -c '
    rm -rf /cache/build && mkdir -p /cache/build && cp -r /src/pom.xml /src/src /cache/build/ && cd /cache/build &&
    mvn -q -B -Duser.home=/cache/home -Dmaven.repo.local=/cache/m2 package &&
    rm -rf /cache/target/* && cp target/java-runner-0.jar /cache/target/ && cp -r target/lib /cache/target/'
# Wrapper: JSONL on stdin, results on stdout. Runs on the plain eclipse-temurin:21 image.
cat > "$JCACHE/facts-java" <<WRAP
#!/bin/sh
exec docker run --rm -i -u $(id -u):$(id -g) -v "$JCACHE/target:/app:ro" eclipse-temurin:21 \\
  java \${JAVA_OPTS:--Xmx8g} -cp '/app/java-runner-0.jar:/app/lib/*' Facts
WRAP
chmod +x "$JCACHE/facts-java"
echo "built: $JCACHE/facts-java"
