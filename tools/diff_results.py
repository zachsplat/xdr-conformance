#!/usr/bin/env python3
"""Compare adapter results request by request.

Usage: diff_results.py OUT.json NAME=results.jsonl [NAME=results.jsonl ...]
The first NAME is the reference. For every id the script compares: decode
ok/error, byte round-trip, transaction hash, and the SEP-51 JSON (only between
adapters that emit JSON). It writes a summary plus up to 20 example ids per
divergence kind, with the first differing JSON path.
"""
import collections
import json
import sys


def load(path):
    out = {}
    with open(path) as f:
        for line in f:
            r = json.loads(line)
            out[r["id"]] = r
    return out


def first_diff(a, b, path="$"):
    if type(a) is not type(b):
        return path, a, b
    if isinstance(a, dict):
        for k in list(a.keys()) + [k for k in b.keys() if k not in a]:
            if k not in a or k not in b:
                return f"{path}.{k}", a.get(k, "<missing>"), b.get(k, "<missing>")
            d = first_diff(a[k], b[k], f"{path}.{k}")
            if d:
                return d
        return None
    if isinstance(a, list):
        if len(a) != len(b):
            return f"{path}[len]", len(a), len(b)
        for i, (x, y) in enumerate(zip(a, b)):
            d = first_diff(x, y, f"{path}[{i}]")
            if d:
                return d
        return None
    return None if a == b else (path, a, b)


def short(v):
    s = json.dumps(v)
    return s if len(s) < 160 else s[:157] + "..."


def main():
    out_path = sys.argv[1]
    sets = []
    for arg in sys.argv[2:]:
        name, path = arg.split("=", 1)
        sets.append((name, load(path)))
    ref_name, ref = sets[0]
    kinds = collections.defaultdict(list)
    counts = collections.Counter()
    for rid, r in ref.items():
        counts["total"] += 1
        for name, other in sets[1:]:
            o = other.get(rid)
            if o is None:
                kinds[(name, "missing")].append({"id": rid})
                continue
            if r.get("ok") != o.get("ok"):
                kinds[(name, "decode_ok_differs")].append({"id": rid, ref_name: r.get("error", "ok"), name: o.get("error", "ok")})
                continue
            if not r.get("ok"):
                continue
            if r.get("roundtrip_equal") != o.get("roundtrip_equal"):
                kinds[(name, "roundtrip_differs")].append({"id": rid, ref_name: r.get("roundtrip_equal"), name: o.get("roundtrip_equal")})
            if "hash" in r and "hash" in o and r["hash"] != o["hash"]:
                kinds[(name, "hash_differs")].append({"id": rid, ref_name: r["hash"], name: o["hash"]})
            if "json" in r and "json" in o:
                d = first_diff(r["json"], o["json"])
                if d:
                    kinds[(name, "sep51_json_differs")].append({"id": rid, "path": d[0], ref_name: short(d[1]), name: short(d[2])})
    summary = {
        "reference": ref_name,
        "compared": [n for n, _ in sets[1:]],
        "total_requests": counts["total"],
        "divergences": [
            {"adapter": n, "kind": k, "count": len(v), "examples": v[:20]}
            for (n, k), v in sorted(kinds.items())
        ],
    }
    with open(out_path, "w") as f:
        json.dump(summary, f, indent=1)
    for d in summary["divergences"]:
        print(f'{d["adapter"]:>8} {d["kind"]:<22} {d["count"]}')
        for ex in d["examples"][:3]:
            print("          ", short(ex))
    if not summary["divergences"]:
        print("no divergences")


if __name__ == "__main__":
    main()
