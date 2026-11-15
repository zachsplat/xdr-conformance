#!/usr/bin/env python3
"""Write mutation variants as corpus files, with stellar-core's verdict.

Usage: write_hostile.py requests.jsonl mutate_manifest.json core_results.jsonl CORPUS_DIR
"""
import base64
import hashlib
import json
import os
import sys


def main():
    reqs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
    meta = {m["id"]: m for m in json.load(open(sys.argv[2]))}
    core = {json.loads(l)["id"]: json.loads(l) for l in open(sys.argv[3]) if l.strip()}
    corpus = sys.argv[4]
    out = []
    for r in reqs:
        m = meta[r["id"]]
        raw = base64.b64decode(r["b64"])
        name = r["id"].replace("hostile/", "").replace("/", "-")
        path = f"hostile/{name}.xdr"
        os.makedirs(os.path.join(corpus, "hostile"), exist_ok=True)
        open(os.path.join(corpus, path), "wb").write(raw)
        c = core[r["id"]]
        out.append({
            "id": f"hostile-{name}",
            "description": m["description"],
            "caps": [],
            "protocol_version": 30,
            "network": "pubnet",
            "network_passphrase": r["network"],
            "synthetic": m["synthetic"],
            "source": {"kind": "mutation" if m["synthetic"] else "galexie-public-datalake",
                       "ledger": m["derived_from"]["ledger"], "tx_hash": m["derived_from"]["tx_hash"]},
            "files": {"envelope": {"path": path, "xdr_type": "TransactionEnvelope", "sha256": hashlib.sha256(raw).hexdigest()}},
            "expected": {"stellar_core_decode": "accept" if c["ok"] else "reject",
                         **({"stellar_core_error": c["error"].replace("Could not decode with type 'tx' : ", "")} if not c["ok"] else {})},
            "mutation": m["mutation"],
        })
    json.dump({"schema": "manifest.schema.json", "version": 1, "entries": out},
              open(os.path.join(corpus, "hostile-manifest.json"), "w"), indent=1)
    print(len(out), "hostile entries")


if __name__ == "__main__":
    main()
