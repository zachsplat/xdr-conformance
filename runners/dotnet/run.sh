#!/bin/sh
# JSONL in, JSONL out. Offline (--network none). Pass XDRCONF_DEPTH=N to decode
# with maxDepth N instead of the SDK default.
WORK=${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/xdrconf}
DOTNET_CACHE=${DOTNET_CACHE:-$WORK/dotnet-cache}
exec docker run --rm -i --network none -u "$(id -u):$(id -g)" \
  -e DOTNET_CLI_TELEMETRY_OPTOUT=1 -e XDRCONF_DEPTH -e XDRCONF_TIMEOUT_MS \
  -v "$DOTNET_CACHE/out:/app:ro" mcr.microsoft.com/dotnet/sdk:9.0 dotnet /app/xdrconf-dotnet.dll
