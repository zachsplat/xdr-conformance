#!/bin/sh
# Rebuild the whole proof from public data. Needs docker, node 24, python 3.12+.
# Scratch goes to $WORK (default ~/.cache/xdrconf); nothing outside it is written
# except reports/ and corpus/ in this repo.
#   ./run.sh fetch     download the ledger sample from the Galexie public data lake
#   ./run.sh build     build the Rust and Go adapters, install JS and Python libraries
#   ./run.sh scan      round-trip every ledger in Rust and tag rare shapes
#   ./run.sh replay    run all adapters on every envelope and meta, diff against Rust
#   ./run.sh hostile   derive the mutation set and run it through stellar-core and all adapters
#   ./run.sh depth     nesting-depth sweep
#   ./run.sh corpus    pick one entry per rare shape and write corpus/
#   ./run.sh sightings reproduce js-stellar-sdk#1766, #1785, #1789 on pre-fix and fixed tags
#   ./run.sh quick     five-minute check, no docker: sightings, runner (Python columns), F1, F2 before/after the fix
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/xdrconf}
mkdir -p "$WORK/bin" "$WORK/cargo" "$WORK/target" "$WORK/gopath" "$WORK/js"
PASS="Public Global Stellar Network ; September 2015"
RUST="docker run --rm -i -u $(id -u):$(id -g) -v $WORK:/w rust:1.93-slim"
export BIN=$WORK/bin PY=$WORK/venv/bin/python JSDIR=$WORK/js

case "$1" in
fetch)
  python3 -I "$ROOT/tools/fetch_galexie.py" "$WORK/lake" 65486000 65486299 59000000 59000019 50460000 50460019 40000000 40000019 28000000 28000019
  ;;
build)
  docker run --rm -u "$(id -u):$(id -g)" -e CARGO_HOME=/c -e CARGO_TARGET_DIR=/t -v "$WORK/cargo:/c" -v "$WORK/target:/t" -v "$ROOT/runners/rust:/src" -w /src rust:1.93-slim cargo build --release
  cp "$WORK/target/release/scan" "$WORK/target/release/facts" "$WORK/bin/"
  docker run --rm -u "$(id -u):$(id -g)" -e GOPATH=/g -e GOCACHE=/g/cache -e GOFLAGS=-mod=mod -v "$WORK/gopath:/g" -v "$ROOT/runners/go:/src" -v "$WORK/bin:/out" -w /src golang:1.25-alpine go build -o /out/xdrconf-go .
  printf '#!/bin/sh\nexec docker run --rm -i -e XDRCONF_DEFAULTS=$1 -e XDRCONF_DEPTH=${2:-500} -u %s -v %s:/w rust:1.93-slim /w/bin/facts\n' "$(id -u):$(id -g)" "$WORK" > "$WORK/bin/facts-wrapper"
  chmod +x "$WORK/bin/facts-wrapper"
  python3 -m venv "$WORK/venv" && "$WORK/venv/bin/pip" install -q stellar-sdk==17.0.1 stellar-xdr==0.2.0
  cp "$ROOT/sightings/package.json" "$WORK/js/" && (cd "$WORK/js" && npm install --silent)
  docker pull -q stellar/stellar-core:latest
  ;;
scan)
  $RUST /w/bin/scan /w/lake /w/scan "$PASS"
  ;;
replay)
  python3 -I - "$WORK" "$PASS" <<'PY'
import json, sys, random, os, base64
work, pas = sys.argv[1], sys.argv[2]
random.seed(7)
os.makedirs(f"{work}/replay", exist_ok=True)
with open(f"{work}/replay/req_env.jsonl", "w") as env, open(f"{work}/replay/req_meta.jsonl", "w") as meta:
    for l in open(f"{work}/scan/txs.jsonl"):
        r = json.loads(l); tid = f"{r['ledger']}:{r['index_in_set']}"
        env.write(json.dumps({"id": tid, "op": "decode", "type": "TransactionEnvelope", "b64": r["envelope_b64"], "network": pas}) + "\n")
        if r["meta_b64"] and (r["tags"] or random.random() < 0.05):
            meta.write(json.dumps({"id": tid, "op": "decode", "type": r["meta_type"], "b64": r["meta_b64"]}) + "\n")
with open(f"{work}/replay/req_lcm.jsonl", "w") as f:
    for fn in sorted(os.listdir(f"{work}/scan/lcm")):
        f.write(json.dumps({"id": fn, "op": "decode", "type": "LedgerCloseMetaBatch", "b64": base64.b64encode(open(f"{work}/scan/lcm/{fn}", "rb").read()).decode()}) + "\n")
PY
  cd "$WORK/replay"
  for k in env meta; do
    "$BIN/facts-wrapper" 0 < req_$k.jsonl > rust_$k.jsonl
    "$PY" -I "$ROOT/runners/python/facts.py" pyxdr < req_$k.jsonl > pyxdr_$k.jsonl
    "$PY" -I "$ROOT/runners/python/facts.py" sdk < req_$k.jsonl > sdk_$k.jsonl 2>/dev/null
    "$BIN/xdrconf-go" < req_$k.jsonl > go_$k.jsonl
    (cd "$JSDIR" && node "$ROOT/runners/js/facts.mjs" sdk1740 < "$WORK/replay/req_$k.jsonl" > "$WORK/replay/js_$k.jsonl")
    python3 -I "$ROOT/tools/diff_results.py" "$ROOT/reports/raw/replay-$k.json" rust=rust_$k.jsonl pyxdr=pyxdr_$k.jsonl js=js_$k.jsonl go=go_$k.jsonl sdk=sdk_$k.jsonl
  done
  python3 -I "$ROOT/tools/lockstep.py" req_lcm.jsonl "$ROOT/reports/raw/replay-lcm.json" rust="$BIN/facts-wrapper 0" pyxdr="$PY -I $ROOT/runners/python/facts.py pyxdr" js="cd $JSDIR && node --max-old-space-size=8192 $ROOT/runners/js/facts.mjs sdk1740" go="$BIN/xdrconf-go"
  ;;
hostile)
  mkdir -p "$WORK/hostile"
  "$PY" -I "$ROOT/tools/pick_bases.py" "$WORK/scan/txs.jsonl" "$WORK/bases.json"
  "$PY" -I "$ROOT/tools/mutate.py" "$WORK/bases.json" "$WORK/hostile/req.jsonl" "$WORK/hostile/manifest.json"
  "$ROOT/sweeps/run_all_adapters.sh" "$WORK/hostile/req.jsonl" "$WORK/hostile/out"
  python3 -I "$ROOT/tools/write_hostile.py" "$WORK/hostile/req.jsonl" "$WORK/hostile/manifest.json" "$WORK/hostile/out/core.jsonl" "$ROOT/corpus"
  python3 -I "$ROOT/sweeps/table.py" "$WORK/hostile/req.jsonl" stellar-core=$WORK/hostile/out/core.jsonl rs-stellar-xdr=$WORK/hostile/out/rust_0.jsonl go-stellar-sdk=$WORK/hostile/out/go.jsonl js-stellar-sdk=$WORK/hostile/out/js.jsonl py-stellar-base=$WORK/hostile/out/pysdk_0.jsonl py-stellar-xdr=$WORK/hostile/out/pyxdr_0.jsonl > "$ROOT/reports/hostile-matrix.md"
  ;;
depth)
  [ -f "$WORK/bases.json" ] || "$PY" -I "$ROOT/tools/pick_bases.py" "$WORK/scan/txs.jsonl" "$WORK/bases.json"
  "$PY" -I "$ROOT/sweeps/depth_sweep.py" "$WORK/bases.json" "$WORK/depth_req.jsonl"
  "$ROOT/sweeps/run_all_adapters.sh" "$WORK/depth_req.jsonl" "$WORK/depth"
  python3 -I "$ROOT/sweeps/table.py" "$WORK/depth_req.jsonl" stellar-core_admission=$WORK/depth/rust_admit.jsonl stellar-core_print-xdr=$WORK/depth/core.jsonl rs-stellar-xdr_none=$WORK/depth/rust_1.jsonl rs-stellar-xdr_depth500=$WORK/depth/rust_0.jsonl go-stellar-sdk=$WORK/depth/go.jsonl js-stellar-sdk=$WORK/depth/js.jsonl py-stellar-base=$WORK/depth/pysdk_1.jsonl py-stellar-xdr_default=$WORK/depth/pyxdr_1.jsonl > "$ROOT/reports/depth-sweep.md"
  ;;
corpus)
  "$PY" -I "$ROOT/tools/pick_corpus.py" "$WORK/scan/txs.jsonl" "$WORK/scan/lcm" "$WORK/replay/rust_env.jsonl" "$ROOT/corpus" "$ROOT/corpus/extra/lp-issuers-strkey-vs-bytes-order.json"
  ;;
sightings)
  cp "$ROOT/sightings/"*.mjs "$JSDIR/"
  (cd "$JSDIR" && node repro1766.mjs "$ROOT/sightings/testnet-ledger-5521445-tx-b79f02ec.json" && node repro_sightings.mjs)
  ;;
quick)
  # Each step compares a fresh run with what this repo documents. Same pins as CI.
  Q=$WORK/quick; mkdir -p "$Q/js"
  cp "$ROOT/sightings/package.json" "$ROOT/sightings/package-lock.json" "$ROOT/sightings/"*.mjs "$Q/js/"
  (cd "$Q/js" && npm ci --silent --no-audit --no-fund)
  echo "1. RFP sightings on pre-fix and fixed js-stellar-sdk tags"
  (cd "$Q/js" && node repro1766.mjs "$ROOT/sightings/testnet-ledger-5521445-tx-b79f02ec.json") > "$Q/1766.txt"
  (cd "$Q/js" && node repro_sightings.mjs) > "$Q/178x.txt"
  cat "$Q/1766.txt" "$Q/178x.txt"
  diff "$Q/1766.txt" "$ROOT/sightings/js-1766-output.txt" && diff "$Q/178x.txt" "$ROOT/sightings/js-1785-1789-output.txt" && echo "   same as sightings/*-output.txt" || echo "   DIFFERS from sightings/*-output.txt"
  [ -x "$Q/new/bin/python" ] || { python3 -m venv "$Q/new" && "$Q/new/bin/pip" install -q -r "$ROOT/ci/requirements.txt"; }
  [ -x "$Q/old/bin/python" ] || { python3 -m venv "$Q/old" && "$Q/old/bin/pip" install -q -r "$ROOT/ci/requirements-pyxdr-0.2.0.txt"; }
  echo "2. Conformance runner, all 44 corpus entries, Python adapters, against ci/known-findings.json"
  python3 -I "$ROOT/tools/check_corpus.py" --known "$ROOT/ci/known-findings.json" "$ROOT/corpus" "$Q/matrix.md" py-stellar-base="$Q/new/bin/python -I $ROOT/runners/python/facts.py sdk" py-stellar-xdr="$Q/new/bin/python -I $ROOT/runners/python/facts.py pyxdr" && echo "   every failing cell is a documented finding (exit 0)" || echo "   UNDOCUMENTED failure or stale finding (exit 1)"
  echo "3. F1: py-stellar-base SEP-51 JSON (StellarCN/py-stellar-base#1269)"
  (cd "$ROOT/findings/F1-py-stellar-base-sep51-json" && "$Q/new/bin/python" -I repro.py ../../corpus) > "$Q/f1.txt"
  diff "$Q/f1.txt" "$ROOT/findings/F1-py-stellar-base-sep51-json/output.txt" && echo "   same as findings/F1-*/output.txt" || echo "   DIFFERS from findings/F1-*/output.txt"
  echo "4. F2: py-stellar-xdr default depth (lightsail-network/py-stellar-xdr#17, fixed by #19 in 0.2.1)"
  for v in old new; do
    "$Q/$v/bin/python" -c 'import importlib.metadata as m; print("   stellar-xdr", m.version("stellar-xdr"))'
    (cd "$ROOT/findings/F2-py-stellar-xdr-default-depth" && "$Q/$v/bin/python" -I repro.py) | grep levels | sed 's/^/   /'
  done
  ;;
*)
  sed -n '2,16p' "$0"; exit 1
  ;;
esac
