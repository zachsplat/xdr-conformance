#!/usr/bin/env python3
"""Classify the .NET adapter's extra checks against the Rust reference.

Usage: classify.py REQ.jsonl RUST.jsonl DOTNET.jsonl OUT.json
For each request: XDR decode/round-trip/hash versus Rust; model errors grouped by
message; model re-encode mismatches grouped by the operation types in the
envelope (from the Rust SEP-51 JSON) and by the field path of the first change;
strkeys the model reports that the Rust JSON does not contain; meta model errors.
"""
import base64
import collections
import json
import re
import sys

STRKEY = re.compile(r"^[GMCBLWPST][A-Z2-7]{55,}$")


def crc16(data):
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else crc << 1
            crc &= 0xFFFF
    return crc


def g_address(hexkey):
    payload = bytes([6 << 3]) + bytes.fromhex(hexkey)
    c = crc16(payload)
    return base64.b32encode(payload + bytes([c & 0xFF, c >> 8])).decode()


def strkeys(v, out):
    if isinstance(v, dict):
        for k, x in v.items():
            if k == "source_account_ed25519" and isinstance(x, str):
                out.add(g_address(x))
        for x in v.values():
            strkeys(x, out)
    elif isinstance(v, list):
        for x in v:
            strkeys(x, out)
    elif isinstance(v, str) and STRKEY.match(v):
        out.add(v)
    return out


def ops(js):
    # operation body kinds from the SEP-51 JSON of an envelope
    kinds = []
    for arm in js.values():
        tx = arm.get("tx", {})
        if "inner_tx" in tx:
            tx = list(tx["inner_tx"].values())[0]["tx"]
        for op in tx.get("operations", []):
            b = op["body"]
            kinds.append(b if isinstance(b, str) else next(iter(b)))
    return kinds


def main():
    req_p, rust_p, net_p, out_p = sys.argv[1:5]
    rust = {}
    for l in open(rust_p):
        r = json.loads(l)
        rust[r["id"]] = r
    reqs = {}
    for l in open(req_p):
        r = json.loads(l)
        reqs[r["id"]] = r
    cnt = collections.Counter()
    groups = collections.defaultdict(list)
    for l in open(net_p):
        r = json.loads(l)
        i = r["id"]
        f = rust.get(i)
        cnt["total"] += 1
        if f is None:
            groups["missing_reference"].append(i)
            continue
        if bool(r.get("ok")) != bool(f.get("ok")):
            groups[f"decode_ok rust={f.get('ok')} dotnet={r.get('ok')}: {r.get('error', '')[:80]}"].append(i)
            continue
        if not r.get("ok"):
            continue
        cnt["decoded"] += 1
        if r.get("roundtrip_equal") != f.get("roundtrip_equal"):
            groups["roundtrip_differs"].append(i)
        if r.get("trailing_bytes"):
            groups["trailing_bytes"].append(i)
        if "xdr_hash" in r and f.get("hash") and r["xdr_hash"] != f["hash"]:
            groups["xdr_hash_differs"].append(i)
        me = r.get("model_error")
        if me:
            groups["model_error: " + re.sub(r"\d+", "N", me)[:120]].append(i)
        elif "hash" in r and f.get("hash") and r["hash"] != f["hash"]:
            kinds = ",".join(sorted(set(ops(f["json"])))) if "json" in f else "?"
            groups["model_hash_differs, ops=" + kinds].append(i)
        if r.get("model_roundtrip_equal") is False and not me and r.get("roundtrip_equal"):
            if not ("hash" in r and f.get("hash") and r["hash"] != f["hash"]):
                groups["model_reencode_differs_hash_same"].append(i)
        if "strkeys" in r and "json" in f:
            extra = set(r["strkeys"]) - strkeys(f["json"], set())
            if extra:
                groups["model_strkey_not_in_rust_json"].append({"id": i, "extra": sorted(extra)[:3]})
        mm = r.get("model_meta")
        if mm and mm != "ok":
            groups["model_meta: " + re.sub(r"\d+", "N", mm)[:120]].append(i)
    summary = {"counts": dict(cnt), "groups": {k: {"count": len(v), "examples": v[:15]} for k, v in
                                               sorted(groups.items(), key=lambda kv: -len(kv[1]))}}
    json.dump(summary, open(out_p, "w"), indent=1)
    print(json.dumps(cnt))
    for k, v in summary["groups"].items():
        print(f"{v['count']:>7}  {k}   e.g. {v['examples'][:2]}")


if __name__ == "__main__":
    main()
