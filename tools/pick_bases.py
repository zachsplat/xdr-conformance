#!/usr/bin/env python3
"""Pick the three real pubnet envelopes the mutation set starts from.

  cls: V1 envelope, odd-length text memo, one payment op with its own source
  sor: small Soroban invoke with an authorization tree
  ext: PreconditionsV2 with a signed-payload extra signer
Usage: pick_bases.py txs.jsonl OUT_bases.json
"""
import base64
import json
import sys

import stellar_xdr as X


def main():
    best = {}
    for l in open(sys.argv[1]):
        r = json.loads(l)
        t = set(r["tags"])
        raw = base64.b64decode(r["envelope_b64"])
        if raw[:4] != b"\x00\x00\x00\x02":
            continue
        if "cls" not in best:
            tx = X.TransactionEnvelope.from_xdr_bytes(raw).v1.tx
            m = tx.memo
            if (type(m).__name__ == "Text" and len(bytes(m.text)) % 4 and len(tx.operations) == 1
                    and type(tx.operations[0].body).__name__ == "Payment" and tx.operations[0].source_account is not None):
                best["cls"] = r
        if "sor" not in best and "op:invoke_host_function" in t and len(raw) < 3000:
            best["sor"] = r
        if "ext" not in best and "precond_extra_signers" in t:
            best["ext"] = r
        if len(best) == 3:
            break
    json.dump(best, open(sys.argv[2], "w"))


if __name__ == "__main__":
    main()
