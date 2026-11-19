#!/bin/sh
# Runs Program.cs on inputs/ against the published NuGet package stellar-dotnet-sdk
# 17.0.0 in mcr.microsoft.com/dotnet/sdk:9.0; caches stay under $DOTNET_CACHE.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
DOTNET_CACHE=${DOTNET_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/xdrconf/dotnet-cache}
B="$DOTNET_CACHE/repro/$(basename "$HERE")"
mkdir -p "$B" "$DOTNET_CACHE/nuget" "$DOTNET_CACHE/home"
rm -rf "$B/inputs" && cp -r "$HERE/Repro.csproj" "$HERE/Program.cs" "$HERE/inputs" "$B/"
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/c/home -e NUGET_PACKAGES=/c/nuget \
  -e DOTNET_CLI_TELEMETRY_OPTOUT=1 -e DOTNET_NOLOGO=1 -v "$DOTNET_CACHE:/c" -v "$B:/r" -w /r \
  mcr.microsoft.com/dotnet/sdk:9.0 sh -c 'dotnet build -c Release -v q -nologo -clp:NoSummary >/dev/null && dotnet bin/Release/net9.0/Repro.dll'
