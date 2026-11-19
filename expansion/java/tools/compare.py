#!/usr/bin/env python3
"""Full comparison of the java adapter's results with the rs-stellar-xdr reference.

Usage: compare.py OUT.json rust.jsonl java.jsonl [--rename-result-arms] [ids.txt]

Beyond tools/diff_results.py (first JSON difference only), this lists every
differing SEP-51 JSON path (indices folded to [*]) and checks the Java-only
fields: xdr_hash and the model hash against the reference hash, the model's
re-encoding, the SDK reading its own JSON back, and the strkeys the transaction
model produced against the reference JSON. With ids.txt, only those ids count.
"""
import collections
import json
import re
import sys


def walk(a, b, path, out):
    if type(a) is not type(b):
        out.append((path, a, b))
        return
    if isinstance(a, dict):
        for k in list(a) + [k for k in b if k not in a]:
            if k not in a or k not in b:
                out.append((f"{path}.{k}", a.get(k, "<missing>"), b.get(k, "<missing>")))
            else:
                walk(a[k], b[k], f"{path}.{k}", out)
    elif isinstance(a, list):
        if len(a) != len(b):
            out.append((f"{path}[len]", len(a), len(b)))
        for i, (x, y) in enumerate(zip(a, b)):
            walk(x, y, f"{path}[{i}]", out)
    elif a != b:
        out.append((path, a, b))


# Java writes TransactionResultCode arms without the underscore after "tx"/"op"
# (txsuccess, opinner). With --rename-result-arms those keys are renamed to the
# SEP-51 names first, so the comparison can look at everything underneath them.
ARM_RENAMES = {"txsuccess": "tx_success", "txfailed": "tx_failed",
               "txfee_bump_inner_success": "tx_fee_bump_inner_success",
               "txfee_bump_inner_failed": "tx_fee_bump_inner_failed", "opinner": "op_inner"}


def rename_arms(v):
    if isinstance(v, dict):
        return {ARM_RENAMES.get(k, k): rename_arms(x) for k, x in v.items()}
    if isinstance(v, list):
        return [rename_arms(x) for x in v]
    return v


def fold(p):
    return re.sub(r"\[\d+\]", "[*]", p)


def short(v):
    s = json.dumps(v)
    return s if len(s) < 140 else s[:137] + "..."


def ref_strkeys(j):
    """(fee_source, source, [(op_source, dest)]) from the reference SEP-51 JSON."""
    fee = None
    if "tx_fee_bump" in j:
        fb = j["tx_fee_bump"]["tx"]
        fee = fb["fee_source"]
        j = fb["inner_tx"]
    if "tx_v0" in j:
        tx = j["tx_v0"]["tx"]
        src = tx["source_account_ed25519"]
    else:
        tx = j["tx"]["tx"]
        src = tx["source_account"]
    ops = []
    for op in tx["operations"]:
        body = op["body"]
        dest = None
        if isinstance(body, dict):
            (k, v), = body.items()
            if k in ("payment", "path_payment_strict_receive", "path_payment_strict_send", "create_account"):
                dest = v["destination"]
            elif k == "account_merge":
                dest = v
            elif k == "clawback":
                dest = v["from"]
        ops.append((op.get("source_account"), dest))
    return fee, src, ops


def main():
    out_path, rust_path, java_path = sys.argv[1:4]
    args = sys.argv[4:]
    rename = "--rename-result-arms" in args
    args = [a for a in args if a != "--rename-result-arms"]
    only = set(open(args[0]).read().split()) if args else None
    ref = {}
    for l in open(rust_path):
        r = json.loads(l)
        if only is None or r["id"] in only:
            ref[r["id"]] = r
    kinds = collections.defaultdict(list)
    paths = collections.defaultdict(list)
    n = 0
    for l in open(java_path):
        o = json.loads(l)
        rid = o["id"]
        if rid not in ref:
            continue
        n += 1
        r = ref.pop(rid)
        if r.get("ok") != o.get("ok"):
            kinds["decode_ok_differs"].append({"id": rid, "rust": r.get("error", "ok"), "java": o.get("error", "ok")})
            continue
        if not o.get("ok"):
            continue
        if r.get("roundtrip_equal") != o.get("roundtrip_equal"):
            kinds["roundtrip_differs"].append({"id": rid, "rust": r.get("roundtrip_equal"), "java": o.get("roundtrip_equal")})
        if o.get("json_roundtrip_equal") is False:
            kinds["java_reads_own_json_wrong"].append({"id": rid, "error": o.get("json_roundtrip_error")})
        if "json_error" in o:
            kinds["java_json_error"].append({"id": rid, "error": o["json_error"]})
        if "hash" in r:
            if o.get("hash") != r["hash"]:
                kinds["model_hash_differs"].append({"id": rid, "rust": r["hash"], "java": o.get("hash")})
            if "xdr_hash" in o and o["xdr_hash"] != r["hash"]:
                kinds["xdr_hash_differs"].append({"id": rid, "rust": r["hash"], "java": o["xdr_hash"]})
            if o.get("model_roundtrip_equal") is False:
                kinds["model_reencode_differs"].append({"id": rid, "error": o.get("model_roundtrip_error"), "model_reencoded_b64": (o.get("model_reencoded_b64") or "")[:80]})
            if "model_error" in o:
                kinds["model_error"].append({"id": rid, "error": o["model_error"]})
            if "model" in o and "json" in r:
                fee, src, ops = ref_strkeys(r["json"])
                m = o["model"]
                bad = []
                if fee is not None and m.get("fee_source") != fee:
                    bad.append(("fee_source", fee, m.get("fee_source")))
                if not (len(src) == 64 and m["source"].startswith("G")) and m["source"] != src:
                    bad.append(("source", src, m["source"]))
                for i, ((osrc, odest), mo) in enumerate(zip(ops, m["ops"])):
                    if osrc != mo.get("source"):
                        bad.append((f"ops[{i}].source", osrc, mo.get("source")))
                    if odest is not None and odest != mo.get("dest"):
                        bad.append((f"ops[{i}].dest", odest, mo.get("dest")))
                if len(ops) != len(m["ops"]):
                    bad.append(("ops[len]", len(ops), len(m["ops"])))
                if bad:
                    kinds["model_strkey_differs"].append({"id": rid, "diffs": bad[:3]})
        if "json" in r and "json" in o:
            if rename:
                o["json"] = rename_arms(o["json"])
            d = []
            walk(r["json"], o["json"], "$", d)
            seen = set()
            for p, a, b in d:
                fp = fold(p)
                if fp in seen:
                    continue
                seen.add(fp)
                paths[fp].append({"id": rid, "rust": short(a), "java": short(b)})
    for rid in ref:
        kinds["missing"].append({"id": rid})
    summary = {
        "compared": n,
        "kinds": {k: {"count": len(v), "examples": v[:10]} for k, v in sorted(kinds.items())},
        "json_paths": {p: {"inputs": len(v), "examples": v[:5]} for p, v in sorted(paths.items(), key=lambda kv: -len(kv[1]))},
    }
    json.dump(summary, open(out_path, "w"), indent=1)
    print(f"compared {n}")
    for k, v in summary["kinds"].items():
        print(f"  {k:<28} {v['count']}  e.g. {short(v['examples'][0])}")
    print(f"  distinct SEP-51 JSON paths that differ: {len(paths)}")
    for p, v in list(summary["json_paths"].items())[:60]:
        print(f"    {v['inputs']:>6}  {p}  rust={v['examples'][0]['rust'][:60]} java={v['examples'][0]['java'][:60]}")


if __name__ == "__main__":
    main()
