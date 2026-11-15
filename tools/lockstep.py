#!/usr/bin/env python3
"""Run several adapters on one request file and compare results line by line,
keeping only a summary (whole LedgerCloseMetaBatch JSON is too big to store).

Usage: lockstep.py REQ.jsonl OUT.json NAME='command' [NAME='command' ...]
The first adapter is the reference. Each command reads requests on stdin.
"""
import json
import subprocess
import sys
import threading

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from diff_results import first_diff, short  # noqa: E402


def feed(path, proc):
    with open(path, "rb") as f:
        for line in f:
            proc.stdin.write(line)
    proc.stdin.close()


def main():
    req, out = sys.argv[1], sys.argv[2]
    procs = []
    for arg in sys.argv[3:]:
        name, cmd = arg.split("=", 1)
        p = subprocess.Popen(cmd, shell=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        threading.Thread(target=feed, args=(req, p), daemon=True).start()
        procs.append((name, p))
    summary = {"reference": procs[0][0], "total": 0, "divergences": []}
    while True:
        lines = [p.stdout.readline() for _, p in procs]
        if not lines[0]:
            break
        res = [json.loads(l) if l else None for l in lines]
        ref = res[0]
        summary["total"] += 1
        for (name, _), r in zip(procs[1:], res[1:]):
            if r is None or r["id"] != ref["id"]:
                summary["divergences"].append({"id": ref["id"], "adapter": name, "kind": "missing_or_misaligned"})
                continue
            if r.get("ok") != ref.get("ok"):
                summary["divergences"].append({"id": ref["id"], "adapter": name, "kind": "decode_ok_differs", "ref": ref.get("error", "ok"), "got": r.get("error", "ok")})
            elif ref.get("ok"):
                if r.get("roundtrip_equal") != ref.get("roundtrip_equal"):
                    summary["divergences"].append({"id": ref["id"], "adapter": name, "kind": "roundtrip_differs"})
                if "json" in r and "json" in ref:
                    d = first_diff(ref["json"], r["json"])
                    if d:
                        summary["divergences"].append({"id": ref["id"], "adapter": name, "kind": "sep51_json_differs", "path": d[0], "ref": short(d[1]), "got": short(d[2])})
    json.dump(summary, open(out, "w"), indent=1)
    print(f'{summary["total"]} requests, {len(summary["divergences"])} divergences')
    for d in summary["divergences"][:10]:
        print(" ", d)


if __name__ == "__main__":
    main()
