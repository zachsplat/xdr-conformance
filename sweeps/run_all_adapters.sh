#!/bin/sh
# Run every adapter on one request file. Usage: run_all_adapters.sh REQ.jsonl OUTDIR
# Needs: docker (rust:1.93-slim, stellar/stellar-core), the built Rust and Go
# adapters in $BIN, node with the JS packages in $JSDIR, and a Python venv in $PY.
set -e
REQ=$(realpath "$1"); OUT=$(realpath "$2"); mkdir -p "$OUT"
HERE=$(dirname "$(realpath "$0")"); ROOT=$(dirname "$HERE")
: "${BIN:?set BIN to the dir holding facts (rust) and xdrconf-go}"
: "${PY:?set PY to a python with stellar-sdk and stellar-xdr}"
: "${JSDIR:?set JSDIR to a dir with node_modules for @stellar/stellar-sdk}"
python3 -I "$ROOT/runners/core/core_oracle.py" stellar/stellar-core:latest < "$REQ" > "$OUT/core.jsonl"
for m in 1 0; do
  "$BIN/facts-wrapper" "$m" < "$REQ" > "$OUT/rust_$m.jsonl"
  XDRCONF_DEFAULTS=$m "$PY" -I "$ROOT/runners/python/facts.py" pyxdr < "$REQ" > "$OUT/pyxdr_$m.jsonl"
  XDRCONF_DEFAULTS=$m "$PY" -I "$ROOT/runners/python/facts.py" sdk < "$REQ" > "$OUT/pysdk_$m.jsonl" 2>/dev/null
done
"$BIN/xdrconf-go" < "$REQ" > "$OUT/go.jsonl"
(cd "$JSDIR" && node "$ROOT/runners/js/facts.mjs" "${JSPKG:-@stellar/stellar-sdk}" < "$REQ" > "$OUT/js.jsonl")
