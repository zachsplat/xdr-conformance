#!/usr/bin/env bash
# Replay corpus entries and whole ledgers through wallet-backend at the commits in commits.txt.
#
#   adapters/wallet-backend/run.sh fetch               clone wallet-backend, add a worktree per commit, download Go
#                                                      modules, fetch the Galexie ledgers named in ledgers.txt (network on)
#   adapters/wallet-backend/run.sh replay              run the adapter at every commit with docker --network none,
#                                                      write results/, check them against expected.tsv
#   adapters/wallet-backend/run.sh one COMMIT ARGS...  run the adapter at one commit with your own -entry/-lcm args
#   adapters/wallet-backend/run.sh gen                 regenerate the local-network entries (stellar/quickstart --local,
#                                                      docker --network none); writes to $WORK/gen-out. GEN_CASES picks
#                                                      cases (default trust,muxed,native-transfer)
#
# WORK (default /dev/shm/xdrc-wb) holds the clone, worktrees, module cache and ledgers. Delete it when done
# with chmod -R u+w "$WORK" && rm -rf "$WORK" (Go makes the module cache read-only).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="${WORK:-/dev/shm/xdrc-wb}"
IMG="${GO_IMAGE:-golang:1.25-alpine}"
QS="${QUICKSTART_IMAGE:-stellar/quickstart:latest}"
LAKE="https://aws-public-blockchain.s3.us-east-2.amazonaws.com/v1.1/stellar/ledgers"

commits() { grep -v '^#' "$HERE/commits.txt" | awk 'NF {print $1}'; }
short() { echo "${1:0:8}"; }

godocker() { # godocker NETWORK DIR CMD...
  local net="$1" dir="$2"; shift 2
  local extra=()
  [ "$net" = none ] && extra=(-e GOPROXY=off)
  docker run --rm --network "$net" --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -e GOMODCACHE=/gomod -e GOCACHE=/gocache -e GOFLAGS=-mod=mod -e GOTOOLCHAIN=local "${extra[@]}" \
    -v "$WORK/gomod:/gomod" -v "$WORK/gocache:/gocache" -v "$dir:/src" -v "$ROOT:/kit:ro" -v "$WORK/lake:/lake:ro" \
    -w /src "$IMG" "$@"
}

lake_key() { # lake_key SEQ -> object key below the network prefix
  local seq="$1" start end
  start=$(( seq / 64000 * 64000 )); end=$(( start + 63999 ))
  printf "%08X--%d-%d/%08X--%d.xdr.zst" $(( 0xFFFFFFFF - start )) "$start" "$end" $(( 0xFFFFFFFF - seq )) "$seq"
}

ledger_lines() { grep -v '^#' "$HERE/ledgers.txt" | awk 'NF >= 3'; }

install() { # install COMMIT TOOL: copy a tool into the worktree as cmd/xdrc-TOOL
  local wt="$WORK/wt-$(short "$1")"
  rm -rf "$wt/cmd/xdrc-$2"; mkdir -p "$wt/cmd/xdrc-$2"
  cp "$HERE/$2/main.go" "$wt/cmd/xdrc-$2/main.go"
}

case "${1:-}" in
fetch)
  mkdir -p "$WORK/gomod" "$WORK/gocache" "$WORK/lake"
  [ -d "$WORK/src" ] || git clone -q https://github.com/stellar/wallet-backend.git "$WORK/src"
  git -C "$WORK/src" fetch -q origin
  for c in $(commits); do
    [ -d "$WORK/wt-$(short "$c")" ] || git -C "$WORK/src" worktree add -q --detach "$WORK/wt-$(short "$c")" "$c"
  done
  for c in $(commits); do godocker bridge "$WORK/wt-$(short "$c")" go mod download; done
  ledger_lines | while read -r net src seq _; do
    case "$src" in lake:*) ;; *) continue ;; esac
    mkdir -p "$WORK/lake/$net"
    dest="$WORK/lake/$net/$seq.xdr.zst"
    [ -f "$dest" ] || curl -sSf -m 60 -o "$dest" "$LAKE/${src#lake:}/$(lake_key "$seq")"
  done
  echo "fetched into $WORK"
  ;;
one)
  c="$2"; shift 2
  install "$c" replay
  godocker none "$WORK/wt-$(short "$c")" go run ./cmd/xdrc-replay -commit "$(short "$c")" "$@"
  ;;
replay)
  mkdir -p "$HERE/results"
  # The four indexer entries, then every entry of the SDK corpus that carries a result meta (controls).
  entries=(-manifest /kit/corpus/indexer/manifest.json -manifest /kit/corpus/manifest.json)
  for m in corpus/indexer corpus; do
    for id in $(python3 -I -c 'import json,sys; print(" ".join(e["id"] for e in json.load(open(sys.argv[1]))["entries"] if "meta" in e["files"]))' "$ROOT/$m/manifest.json"); do
      entries+=(-entry "/kit/$m/entries/$id")
    done
  done
  for c in $(commits); do
    s="$(short "$c")"; out="$HERE/results/$s.jsonl"
    "$0" one "$c" "${entries[@]}" > "$out"
    for net in $(ledger_lines | awk '{print $1}' | sort -u); do
      lcms=()
      while read -r n src where tx; do
        [ "$n" = "$net" ] || continue
        case "$src" in lake:*) path="/lake/$net/$where.xdr.zst" ;; *) path="/kit/$where" ;; esac
        if [ "$tx" != - ]; then path="$path#$tx"; fi
        lcms+=(-lcm "$path")
      done < <(ledger_lines)
      "$0" one "$c" -network "$net" "${lcms[@]}" >> "$out"
    done
    echo "$s: $(wc -l < "$out") reports"
  done
  python3 -I "$HERE/summarize.py" "$HERE"
  ;;
gen)
  # Local network only: the quickstart container has no network, the generator joins its namespace.
  name="xdrc-wb-quickstart-$$"
  c="$(commits | tail -1)"
  install "$c" gen
  godocker none "$WORK/wt-$(short "$c")" go build -o /src/xdrc-gen.bin ./cmd/xdrc-gen
  docker run -d --name "$name" --network none "$QS" --local --enable core,horizon,rpc >/dev/null
  trap 'docker rm -f "$name" >/dev/null' EXIT
  for _ in $(seq 1 100); do
    sleep 3
    logs="$(docker logs "$name" 2>&1)"
    grep -q "stellar-rpc: up and ready" <<< "$logs" && grep -q "horizon: ingestion caught up" <<< "$logs" && break
  done
  sleep 5
  rm -rf "$WORK/gen-out"; mkdir -p "$WORK/gen-out"
  docker run --rm --network "container:$name" --user "$(id -u):$(id -g)" \
    -v "$WORK/wt-$(short "$c")/xdrc-gen.bin:/xdrc-gen:ro" -v "$WORK/gen-out:/out" alpine:3 /xdrc-gen -out /out -cases "${GEN_CASES:-trust,muxed,native-transfer}"
  ;;
*)
  sed -n '2,12p' "$0"; exit 1 ;;
esac
