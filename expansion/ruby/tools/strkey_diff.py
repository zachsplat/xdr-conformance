#!/usr/bin/env python3
"""Compare the Ruby adapter's "strkeys" field with the strkeys in the
reference SEP-51 JSON (rs-stellar-xdr), as sorted multisets.

Usage: strkey_diff.py REF.jsonl RUBY.jsonl OUT.json
Reference strings counted: G (account, 56 chars), M (muxed, 69 chars),
T and X (signer keys, 56 chars) and P (signed payload) strkeys.
"""
import collections
import json
import re
import sys

PAT = re.compile(r"^(G[A-Z2-7]{55}|M[A-Z2-7]{68}|T[A-Z2-7]{55}|X[A-Z2-7]{55}|P[A-Z2-7]{55,})$")


def walk(v, out):
    if isinstance(v, dict):
        for x in v.values():
            walk(x, out)
    elif isinstance(v, list):
        for x in v:
            walk(x, out)
    elif isinstance(v, str) and PAT.match(v):
        out.append(v)


def main():
    ref_path, ruby_path, out_path = sys.argv[1:4]
    ruby = {}
    with open(ruby_path) as f:
        for line in f:
            r = json.loads(line)
            if r.get("ok") and "strkeys" in r:
                ruby[r["id"]] = r["strkeys"]
    counts = collections.Counter()
    diffs = []
    with open(ref_path) as f:
        for line in f:
            r = json.loads(line)
            if r["id"] not in ruby or "json" not in r:
                continue
            counts["compared"] += 1
            ref = []
            walk(r["json"], ref)
            ref.sort()
            got = ruby[r["id"]]
            if ref == got:
                counts["equal"] += 1
                continue
            counts["differ"] += 1
            a, b = collections.Counter(ref), collections.Counter(got)
            diffs.append({"id": r["id"], "only_ref": sorted((a - b).elements()), "only_ruby": sorted((b - a).elements())})
    json.dump({"counts": counts, "diffs": diffs}, open(out_path, "w"), indent=1)
    print(dict(counts))
    for d in diffs[:10]:
        print(d)


if __name__ == "__main__":
    main()
