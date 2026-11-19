#!/bin/sh
# Rerun everything in expansion/dart/REPORT.md. Needs docker and the inputs that
# ./run.sh replay / hostile / depth leave in $WORK (default ~/.cache/xdrconf).
# Raw outputs go to $WORK/dart-cache/out; small ones are copied to expansion/dart/out.
set -e
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd)
WORK=${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/xdrconf}
O=$WORK/dart-cache/out; mkdir -p "$O" "$HERE/out"
IMG=${IMG:-ghcr.io/cirruslabs/flutter:stable}
DART="$ROOT/runners/dart/run.sh"
"$DART" build
# model-diff diagnostic (same package, same image)
docker run --rm -e PUB_CACHE=/c/pub-cache -v "$WORK/dart-cache:/c" -v "$ROOT/runners/dart:/src" -w /src "$IMG" \
  sh -c "dart compile exe tool/model_diff.dart -o /c/bin/model-diff; chown -R $(id -u):$(id -g) /src /c"
python3 -I "$ROOT/tools/check_corpus.py" "$ROOT/corpus" "$HERE/out/corpus-matrix.md" dart="$DART" || true
python3 -I "$ROOT/tools/check_corpus.py" "$ROOT/corpus/indexer" "$HERE/out/indexer-matrix.md" dart="$DART" || true
"$DART" < "$WORK/replay/req_env.jsonl" > "$O/dart_env.jsonl"
"$DART" < "$WORK/replay/req_meta.jsonl" > "$O/dart_meta.jsonl"
"$DART" < "$WORK/hostile/req.jsonl" > "$O/dart_hostile.jsonl"
"$DART" < "$WORK/depth_req.jsonl" > "$O/dart_depth.jsonl"
docker run --rm -i -u "$(id -u):$(id -g)" -v "$WORK/dart-cache/bin:/b:ro" "$IMG" /b/model-diff < "$WORK/replay/req_env.jsonl" > "$O/model_diff_env.jsonl"
python3 -I "$ROOT/tools/diff_results.py" "$HERE/out/replay-env.json" rust="$WORK/replay/rust_env.jsonl" dart="$O/dart_env.jsonl"
python3 -I "$ROOT/tools/diff_results.py" "$HERE/out/replay-meta.json" rust="$WORK/replay/rust_meta.jsonl" dart="$O/dart_meta.jsonl"
python3 -I "$ROOT/tools/diff_results.py" "$HERE/out/hostile.json" rust="$WORK/hostile/rust_ref.jsonl" dart="$O/dart_hostile.jsonl"
# extra probes: stellar-core print-xdr, rs-stellar-xdr and the Dart adapter
"$WORK/venv/bin/python" -I "$HERE/probes/make_probes.py" "$WORK/hostile/req.jsonl" "$HERE/probes/probes_req.jsonl"
python3 -I "$ROOT/runners/core/core_oracle.py" stellar/stellar-core:latest < "$HERE/probes/probes_req.jsonl" > "$HERE/out/probes_core.jsonl"
"$WORK/bin/facts-wrapper" 0 < "$HERE/probes/probes_req.jsonl" > "$HERE/out/probes_rust.jsonl"
"$DART" < "$HERE/probes/probes_req.jsonl" > "$HERE/out/probes_dart.jsonl"
cp "$O/dart_hostile.jsonl" "$HERE/out/"
# reproductions against the published package
for f in "$HERE"/repro/bin/r*.dart; do echo "== $(basename "$f")"; "$HERE/repro/run.sh" "bin/$(basename "$f")"; done > "$HERE/repro/outputs.txt" 2>&1
