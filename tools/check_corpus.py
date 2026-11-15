#!/usr/bin/env python3
"""Conformance runner: check every corpus entry against every adapter.

For each entry and adapter: the file decodes, re-encoding gives the same bytes,
the transaction hash matches the manifest, and (for adapters that write SEP-51
JSON) the JSON equals the expected JSON. Hostile entries are checked against
stellar-core's recorded verdict instead.

Usage: check_corpus.py CORPUS_DIR OUT.md NAME='command' [NAME='command' ...]
Exit status 1 if any cell fails, so it can gate CI.
"""
import base64
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
from diff_results import first_diff  # noqa: E402


def requests(corpus):
    reqs, expect = [], {}
    for mf in ("manifest.json", "hostile-manifest.json"):
        p = os.path.join(corpus, mf)
        if not os.path.exists(p):
            continue
        for e in json.load(open(p))["entries"]:
            f = e["files"]["envelope"]
            raw = open(os.path.join(corpus, f["path"]), "rb").read()
            reqs.append({"id": e["id"], "op": "decode", "type": f["xdr_type"],
                         "b64": base64.b64encode(raw).decode(), "network": e["network_passphrase"]})
            ex = dict(e["expected"])
            if "envelope_sep51_json" in ex:
                ex["json"] = json.load(open(os.path.join(corpus, ex["envelope_sep51_json"])))
            expect[e["id"]] = ex
    return reqs, expect


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


def main():
    corpus, out = sys.argv[1], sys.argv[2]
    reqs, expect = requests(corpus)
    payload = "".join(json.dumps(r) + "\n" for r in reqs)
    cols = []
    for arg in sys.argv[3:]:
        name, cmd = arg.split("=", 1)
        res = subprocess.run(cmd, shell=True, input=payload, capture_output=True, text=True).stdout
        cols.append((name, {json.loads(l)["id"]: json.loads(l) for l in res.splitlines() if l.strip()}))
    fails = 0
    lines = ["| entry | " + " | ".join(n for n, _ in cols) + " |", "|---|" + "---|" * len(cols)]
    for r in reqs:
        cells = [verdict(expect[r["id"]], c.get(r["id"])) for _, c in cols]
        fails += sum(1 for c in cells if not c.startswith("pass"))
        lines.append(f"| `{r['id']}` | " + " | ".join(cells) + " |")
    open(out, "w").write("\n".join(lines) + "\n")
    print(f"{len(reqs)} entries x {len(cols)} adapters, {fails} failing cells")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
