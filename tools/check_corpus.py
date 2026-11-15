#!/usr/bin/env python3
"""Conformance runner: check every corpus entry against every adapter.

For each entry and adapter: the file decodes, re-encoding gives the same bytes,
the transaction hash matches the manifest, and (for adapters that write SEP-51
JSON) the JSON equals the expected JSON. Hostile and depth entries are checked
against stellar-core's recorded verdict instead. Every XDR file and expected
JSON file is checked against its sha256 in the manifest first.

Usage: check_corpus.py [--known KNOWN.json] CORPUS_DIR OUT.md NAME='command' [...]

CORPUS_DIR holds manifest.json and/or hostile-manifest.json. With --known, a
failing cell that matches a documented known finding (same entry, same adapter
name, same verdict) is reported but does not fail the run. A known finding that
no longer reproduces does fail the run, so the list stays true.

Exit status 1 on any undocumented failing cell, stale known finding, or file
whose hash differs from the manifest. If GITHUB_STEP_SUMMARY is set, the matrix
is also appended there.
"""
import base64
import hashlib
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
from diff_results import first_diff  # noqa: E402


def requests(corpus):
    reqs, expect, bad_files = [], {}, []
    for mf in ("manifest.json", "hostile-manifest.json"):
        p = os.path.join(corpus, mf)
        if not os.path.exists(p):
            continue
        for e in json.load(open(p))["entries"]:
            for part in e["files"].values():
                data = open(os.path.join(corpus, part["path"]), "rb").read()
                if part.get("sha256") and hashlib.sha256(data).hexdigest() != part["sha256"]:
                    bad_files.append(part["path"])
            f = e["files"]["envelope"]
            raw = open(os.path.join(corpus, f["path"]), "rb").read()
            reqs.append({"id": e["id"], "op": "decode", "type": f["xdr_type"],
                         "b64": base64.b64encode(raw).decode(), "network": e["network_passphrase"]})
            ex = dict(e["expected"])
            if "envelope_sep51_json" in ex:
                data = open(os.path.join(corpus, ex["envelope_sep51_json"]), "rb").read()
                want = ex.get("envelope_sep51_json_sha256")
                if want and hashlib.sha256(data).hexdigest() != want:
                    bad_files.append(ex["envelope_sep51_json"])
                ex["json"] = json.loads(data)
            expect[e["id"]] = ex
    return reqs, expect, bad_files


def verdict(ex, r):
    if r is None:
        return "no result"
    if "stellar_core_decode" in ex:
        want = ex["stellar_core_decode"] == "accept"
        if bool(r.get("ok")) != want:
            return "accepts (core refuses)" if r.get("ok") else "refuses (core accepts)"
        if r.get("ok") and r.get("roundtrip_equal") is False:
            return "accepts, re-encodes to other bytes"
        return "pass"
    if not r.get("ok"):
        return "decode error"
    if r.get("roundtrip_equal") is False:
        return "bytes change"
    if ex.get("tx_hash") and r.get("hash") and r["hash"] != ex["tx_hash"]:
        return "hash differs"
    if "json" in r and "json" in ex:
        d = first_diff(ex["json"], r["json"])
        if d:
            return f"JSON differs at {d[0].split('.')[-1]}"
    return "pass"


def load_known(path):
    known = {}
    if not path:
        return known
    for k in json.load(open(path))["known"]:
        for entry in k["entries"]:
            known[(entry, k["adapter"])] = k
    return known


def main():
    args = sys.argv[1:]
    known_path = None
    if args and args[0] == "--known":
        known_path, args = args[1], args[2:]
    corpus, out = args[0], args[1]
    known = load_known(known_path)
    reqs, expect, bad_files = requests(corpus)
    payload = "".join(json.dumps(r) + "\n" for r in reqs)
    cols = []
    for arg in args[2:]:
        name, cmd = arg.split("=", 1)
        proc = subprocess.run(cmd, shell=True, input=payload, capture_output=True, text=True)
        got = {json.loads(l)["id"]: json.loads(l) for l in proc.stdout.splitlines() if l.strip()}
        if not got:
            print(f"{name}: adapter produced no results (exit {proc.returncode}): {proc.stderr[-500:]}")
        cols.append((name, got))
    unknown, stale, known_hits = [], [], []
    lines = ["| entry | " + " | ".join(n for n, _ in cols) + " |", "|---|" + "---|" * len(cols)]
    for r in reqs:
        cells = []
        for name, got in cols:
            v = verdict(expect[r["id"]], got.get(r["id"]))
            k = known.get((r["id"], name))
            if k and v == k["verdict"]:
                known_hits.append((r["id"], name, k["id"]))
                cells.append(f"known: {v} ({k['id']})")
            elif k:
                stale.append(f"{r['id']} / {name}: known {k['id']} expects \"{k['verdict']}\", got \"{v}\"")
                cells.append(f"**{v}** (was known {k['id']})")
            elif v != "pass":
                unknown.append(f"{r['id']} / {name}: {v}")
                cells.append(f"**{v}**")
            else:
                cells.append("pass")
        lines.append(f"| `{r['id']}` | " + " | ".join(cells) + " |")
    summary = (f"{len(reqs)} entries x {len(cols)} adapters: {len(known_hits)} known findings reproduced, "
               f"{len(unknown)} undocumented failures, {len(stale)} known findings changed, "
               f"{len(bad_files)} files with a wrong hash")
    report = "\n".join(lines) + "\n"
    open(out, "w").write(report)
    print(summary)
    for f in bad_files:
        print(f"HASH MISMATCH: {f}")
    for u in unknown:
        print(f"UNDOCUMENTED: {u}")
    for s in stale:
        print(f"KNOWN FINDING CHANGED (update {known_path}): {s}")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(f"### `{corpus}`\n\n{summary}\n\n{report}\n")
    sys.exit(1 if unknown or stale or bad_files else 0)


if __name__ == "__main__":
    main()
