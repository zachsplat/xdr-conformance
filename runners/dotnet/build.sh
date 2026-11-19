#!/bin/sh
# Build the .NET adapter in mcr.microsoft.com/dotnet/sdk:9.0. Nothing is installed
# on the host; the NuGet cache, build tree and output live under $DOTNET_CACHE.
#   ./build.sh            restore (from the lock file once it exists) and publish
# Run it with ./run.sh < requests.jsonl > results.jsonl
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/xdrconf}
DOTNET_CACHE=${DOTNET_CACHE:-$WORK/dotnet-cache}
mkdir -p "$DOTNET_CACHE/nuget" "$DOTNET_CACHE/home" "$DOTNET_CACHE/build" "$DOTNET_CACHE/out"
cp "$HERE/XdrConf.csproj" "$HERE/Program.cs" "$DOTNET_CACHE/build/"
[ -f "$HERE/packages.lock.json" ] && cp "$HERE/packages.lock.json" "$DOTNET_CACHE/build/"
docker run --rm -u "$(id -u):$(id -g)" \
  -e HOME=/c/home -e NUGET_PACKAGES=/c/nuget -e DOTNET_CLI_TELEMETRY_OPTOUT=1 -e DOTNET_NOLOGO=1 \
  -v "$DOTNET_CACHE:/c" -w /c/build mcr.microsoft.com/dotnet/sdk:9.0 \
  dotnet publish -c Release -o /c/out
cp "$DOTNET_CACHE/build/packages.lock.json" "$HERE/packages.lock.json"
