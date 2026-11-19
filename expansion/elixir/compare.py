#!/usr/bin/env python3
"""Compare the stellar_base adapter's results with the kit's references.

Usage: compare.py WORK OUTDIR
  WORK   the xdrconf cache (replay/, hostile/, depth_req.jsonl)
  OUTDIR expansion/elixir/out (holds replay_env.jsonl, replay_meta.jsonl,
         hostile.jsonl, depth.jsonl written by runners/elixir/run.sh)

Checks:
  replay env/meta: decode ok, byte round trip and transaction hash against
    rs-stellar-xdr 30.0.0 (rust_*.jsonl), plus every strkey the adapter wrote
    against the same path in rs-stellar-xdr's SEP-51 JSON.
  hostile: decode verdict against stellar-core print-xdr (corpus/hostile-manifest.json).
  depth: decode verdict against stellar-core admission and print-xdr (reports/depth-sweep.md).
Writes OUTDIR/compare.json and prints a summary.
"""
import base64
import collections
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load(path):
    return {r["id"]: r for r in map(json.loads, open(path))}


def crc16_xmodem(data):
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else crc << 1
            crc &= 0xFFFF
    return crc


def g_strkey(hexkey):
    # rs-stellar-xdr writes TransactionV0.sourceAccountEd25519 (a uint256) as hex.
    payload = bytes([6 << 3]) + bytes.fromhex(hexkey)
    return base64.b32encode(payload + crc16_xmodem(payload).to_bytes(2, "little")).decode().rstrip("=")


def get_path(j, path):
    for part in path.split("."):
        if isinstance(j, list):
            j = j[int(part)]
        else:
            j = j[part]
    return j


def replay(work, out, kind):
    ref = load(f"{work}/replay/rust_{kind}.jsonl")
    got = load(f"{out}/replay_{kind}.jsonl")
    c = collections.Counter()
    ex = collections.defaultdict(list)
    for rid, r in ref.items():
        g = got.get(rid)
        c["total"] += 1
        if g is None:
            c["missing"] += 1
            continue
        if r["ok"] and not g["ok"]:
            c["refused_rust_ok"] += 1
            ex["refused_rust_ok"].append((rid, g["error"][:100]))
            continue
        if g["ok"] and not r["ok"]:
            c["accepted_rust_refused"] += 1
            ex["accepted_rust_refused"].append(rid)
            continue
        if not g["ok"]:
            c["both_refuse"] += 1
            continue
        c["both_ok"] += 1
        if g.get("roundtrip_equal") is not True:
            c["roundtrip_differs"] += 1
            ex["roundtrip_differs"].append(rid)
        if "hash" in r:
            c["hash_checked"] += 1
            if g.get("hash") != r["hash"]:
                c["hash_differs"] += 1
                ex["hash_differs"].append((rid, r["hash"], g.get("hash")))
        for path, sk in (g.get("strkeys") or {}).items():
            c["strkeys_checked"] += 1
            try:
                want = get_path(r["json"], path)
            except (KeyError, IndexError, TypeError):
                c["strkey_path_missing_in_rust_json"] += 1
                ex["strkey_path_missing_in_rust_json"].append((rid, path))
                continue
            if path.endswith("source_account_ed25519") and len(want) == 64:
                want = g_strkey(want)
            if want != sk:
                c["strkey_differs"] += 1
                ex["strkey_differs"].append((rid, path, want, sk))
            elif sk.startswith("M"):
                c["muxed_strkeys_equal"] += 1
    return {"counts": dict(c), "examples": {k: v[:20] for k, v in ex.items()}}


def hostile(work, out):
    core = {e["id"]: e["expected"] for e in json.load(open(f"{ROOT}/corpus/hostile-manifest.json"))["entries"]}
    rust = load(f"{work}/hostile/rust_ref.jsonl")
    rows = []
    for rid, g in load(f"{out}/hostile.jsonl").items():
        e = core[rid.replace("/", "-")]
        core_ok = e["stellar_core_decode"] == "accept"
        rows.append({
            "id": rid,
            "stellar_core": "ok" if core_ok else "REJ",
            "core_error": e.get("stellar_core_error"),
            "rs_stellar_xdr": "ok" if rust[rid]["ok"] else "REJ",
            "stellar_base": ("ok" if g.get("roundtrip_equal") else "ok*") if g["ok"] else "REJ",
            "stellar_base_error": g.get("error"),
            "agrees_with_core": bool(g["ok"]) == core_ok and (not g["ok"] or g.get("roundtrip_equal")),
        })
    return rows


def depth(out):
    table = {}
    lines = open(f"{ROOT}/reports/depth-sweep.md").read().splitlines()
    head = [h.strip() for h in lines[0].strip("|").split("|")]
    for ln in lines[2:]:
        cells = [x.strip() for x in ln.strip("|").split("|")]
        rid = cells[0].split("`")[1]
        table[rid] = dict(zip(head, cells))
    rows = []
    for rid, g in load(f"{out}/depth.jsonl").items():
        t = table[rid]
        rows.append({
            "id": rid,
            "core_admission": t["stellar-core_admission"],
            "core_print_xdr": t["stellar-core_print-xdr"],
            "stellar_base": ("ok" if g.get("roundtrip_equal") else "ok*") if g["ok"] else "REJ",
            "stellar_base_error": g.get("error"),
        })
    return rows


def main():
    work, out = sys.argv[1], sys.argv[2]
    res = {
        "replay_env": replay(work, out, "env"),
        "replay_meta": replay(work, out, "meta"),
        "hostile": hostile(work, out),
        "depth": depth(out),
    }
    json.dump(res, open(f"{out}/compare.json", "w"), indent=1)
    for k in ("replay_env", "replay_meta"):
        print(k, json.dumps(res[k]["counts"]))
    print("hostile: stellar_base disagrees with stellar-core on:")
    for r in res["hostile"]:
        if not r["agrees_with_core"]:
            print(f"  {r['id']}: core {r['stellar_core']}, stellar_base {r['stellar_base']} {r['stellar_base_error'] or ''}")
    print("depth: rows where stellar_base differs from core admission or print-xdr:")
    for r in res["depth"]:
        sb = "ok" if r["stellar_base"].startswith("ok") else "REJ"
        if sb != r["core_admission"] or sb != r["core_print_xdr"]:
            print(f"  {r['id']}: admission {r['core_admission']}, print-xdr {r['core_print_xdr']}, stellar_base {r['stellar_base']}")


if __name__ == "__main__":
    main()
