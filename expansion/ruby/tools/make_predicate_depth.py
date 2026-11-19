#!/usr/bin/env python3
"""Nest the first claimant's ClaimPredicate N levels deep (NOT around NOT ...)
in the corpus entry claimable-balance-create, to find where each decoder stops.
This is the only recursive type in classic (protocol 19) transactions.

Usage: make_predicate_depth.py CORPUS_DIR OUT.jsonl  (needs stellar_sdk 17.0.1)
"""
import base64
import json
import os
import sys

import stellar_sdk.xdr as X

PASS = "Public Global Stellar Network ; September 2015"


def main():
    corpus, dst = sys.argv[1], sys.argv[2]
    raw = open(os.path.join(corpus, "entries/claimable-balance-create/envelope.xdr"), "rb").read()
    with open(dst, "w") as w:
        for n in (4, 50, 100, 200, 300, 500, 1000, 2000, 5000):
            env = X.TransactionEnvelope.from_xdr_bytes(raw)
            tx = env.v1.tx if env.v1 else env.v0.tx
            op = next(o for o in tx.operations if o.body.create_claimable_balance_op)
            c = op.body.create_claimable_balance_op.claimants[0].v0
            p = X.ClaimPredicate(X.ClaimPredicateType.CLAIM_PREDICATE_UNCONDITIONAL)
            for _ in range(n):
                p = X.ClaimPredicate(X.ClaimPredicateType.CLAIM_PREDICATE_NOT, not_predicate=p)
            c.predicate = p
            b = env.to_xdr_bytes()
            w.write(json.dumps({"id": f"predicate/{n}", "op": "decode", "type": "TransactionEnvelope",
                                "b64": base64.b64encode(b).decode(), "network": PASS}) + "\n")


if __name__ == "__main__":
    sys.setrecursionlimit(100000)
    main()
