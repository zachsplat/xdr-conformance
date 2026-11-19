#!/usr/bin/env python3
"""Write one decode request per XDR file in the corpus (envelopes and metas of the
main, hostile and indexer manifests). Usage: corpus_requests.py CORPUS_DIR OUT.jsonl"""
import base64
import json
import os
import sys

corpus, out = sys.argv[1], sys.argv[2]
with open(out, "w") as w:
    for mf in ("manifest.json", "hostile-manifest.json", "indexer/manifest.json"):
        base = os.path.join(corpus, os.path.dirname(mf))
        for e in json.load(open(os.path.join(corpus, mf)))["entries"]:
            for part, f in e["files"].items():
                if part not in ("envelope", "meta"):
                    continue
                raw = open(os.path.join(base, f["path"]), "rb").read()
                req = {"id": f"{e['id']}/{part}", "op": "decode", "type": f["xdr_type"],
                       "b64": base64.b64encode(raw).decode()}
                if part == "envelope":
                    req["network"] = e["network_passphrase"]
                w.write(json.dumps(req) + "\n")
