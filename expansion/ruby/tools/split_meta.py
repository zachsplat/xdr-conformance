#!/usr/bin/env python3
"""Split the replay result metas into the parts stellar-base 0.32.0 has types
for, so its decoder sees real meta data even though it has no type for
TransactionMeta v3/v4 or TransactionResultMetaV1.

Usage: split_meta.py req_meta.jsonl OUT.jsonl   (needs stellar_sdk 17.0.1)
Writes decode requests for: TransactionResultPair (the result), and every
LedgerEntryChanges (fee processing, tx changes before/after, per-operation
changes, post-apply fee processing). Ids are "<meta id>/<part>".
"""
import base64
import json
import sys

import stellar_sdk.xdr as X


def parts(m):
    yield "result", "TransactionResultPair", m.result
    yield "fee", "LedgerEntryChanges", m.fee_processing
    if getattr(m, "post_tx_apply_fee_processing", None) is not None:
        yield "postfee", "LedgerEntryChanges", m.post_tx_apply_fee_processing
    tm = m.tx_apply_processing
    v = None
    for arm in ("v4", "v3", "v2", "v1"):
        v = getattr(tm, arm, None)
        if v is not None:
            break
    if v is None:
        return
    if getattr(v, "tx_changes_before", None) is not None:
        yield "before", "LedgerEntryChanges", v.tx_changes_before
    if getattr(v, "tx_changes_after", None) is not None:
        yield "after", "LedgerEntryChanges", v.tx_changes_after
    for i, op in enumerate(v.operations or []):
        yield f"op{i}", "LedgerEntryChanges", op.changes


def main():
    src, dst = sys.argv[1], sys.argv[2]
    n = 0
    with open(src) as f, open(dst, "w") as w:
        for line in f:
            r = json.loads(line)
            T = getattr(X, r["type"])
            m = T.from_xdr(r["b64"])
            for name, ty, val in parts(m):
                b64 = base64.b64encode(val.to_xdr_bytes()).decode()
                w.write(json.dumps({"id": f"{r['id']}/{name}", "op": "decode", "type": ty, "b64": b64}) + "\n")
                n += 1
    print(n, "requests")


if __name__ == "__main__":
    main()
