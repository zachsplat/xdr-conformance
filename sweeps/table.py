#!/usr/bin/env python3
"""Print an accept/reject table from adapter result files.

Usage: table.py requests.jsonl NAME=results.jsonl ... > table.md
Cell values: ok (decoded, bytes round-trip), ok* (decoded, re-encodes to
different bytes), REJ (refused), - (no result).
"""
import json
import sys


def main():
    ids = [json.loads(l)["id"] for l in open(sys.argv[1]) if l.strip()]
    cols = []
    for arg in sys.argv[2:]:
        name, path = arg.split("=", 1)
        try:
            res = {json.loads(l)["id"]: json.loads(l) for l in open(path) if l.strip()}
        except FileNotFoundError:
            res = {}
        cols.append((name, res))
    print("| input | " + " | ".join(n for n, _ in cols) + " |")
    print("|---|" + "---|" * len(cols))
    for i in ids:
        cells = []
        for _, res in cols:
            r = res.get(i)
            if r is None:
                cells.append("-")
            elif not r.get("ok"):
                cells.append("REJ")
            else:
                cells.append("ok" if r.get("roundtrip_equal", True) else "ok*")
        ref = cells[0]
        mark = " **diverges**" if any((c.startswith("ok")) != ref.startswith("ok") for c in cells[1:] if c != "-") else ""
        print(f"| `{i}`{mark} | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()
