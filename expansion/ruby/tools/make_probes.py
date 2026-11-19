#!/usr/bin/env python3
"""Write extra hostile variants aimed at the xdr gem's array length read.

Usage: make_probes.py hostile/req.jsonl OUT.jsonl  (needs stellar_sdk 17.0.1)
Base: hostile/cls/baseline (pubnet ledger 40000001, tx 4adfa3a9...).
Each variant sets a variable-length array count to a value >= 2^31 and drops
the elements that followed it.
"""
import base64
import json
import struct
import sys

import stellar_sdk.xdr as X

PASS = "Public Global Stellar Network ; September 2015"


def main():
    src, dst = sys.argv[1], sys.argv[2]
    base = next(json.loads(l) for l in open(src) if json.loads(l)["id"] == "hostile/cls/baseline")
    raw = base64.b64decode(base["b64"])
    env = X.TransactionEnvelope.from_xdr_bytes(raw)
    tx = env.v1.tx
    out = []

    # signatures<20>: last field of the envelope.
    nsig = len(env.v1.signatures)
    sig_bytes = sum(len(s.to_xdr_bytes()) for s in env.v1.signatures)
    head = raw[: len(raw) - sig_bytes - 4]
    for count in (0x80000000, 0xFFFFFFFF):
        out.append((f"probe/signatures_count_{count:08x}", head + struct.pack(">I", count)))

    # operations<100>: after sourceAccount, fee, seqNum, cond, memo.
    prefix = (tx.source_account.to_xdr_bytes() + tx.fee.to_xdr_bytes() + tx.seq_num.to_xdr_bytes()
              + tx.cond.to_xdr_bytes() + tx.memo.to_xdr_bytes())
    off = 4 + len(prefix)
    assert struct.unpack(">I", raw[off:off + 4])[0] == len(tx.operations)
    ops_len = sum(len(o.to_xdr_bytes()) for o in tx.operations)
    for count in (0x80000000, 0xFFFFFFFF):
        v = raw[:off] + struct.pack(">I", count) + raw[off + 4 + ops_len:]
        out.append((f"probe/operations_count_{count:08x}", v))

    with open(dst, "w") as w:
        for pid, b in out:
            w.write(json.dumps({"id": pid, "op": "decode", "type": "TransactionEnvelope",
                                "b64": base64.b64encode(b).decode(), "network": PASS}) + "\n")
    print(len(out), "probes; baseline signatures:", nsig, "operations:", len(tx.operations))


if __name__ == "__main__":
    main()
