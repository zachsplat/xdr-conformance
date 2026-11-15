#!/usr/bin/env python3
"""py-stellar-xdr's default max_depth refuses envelopes stellar-core decodes.

  pip install stellar-xdr==0.2.0
  python repro.py
The three envelopes are a real pubnet Soroban transaction (ledger 59000003,
tx 06ff45db...) with its authorization root invocation replaced by a chain of
n nested sub-invocations.
"""
import stellar_xdr as X

for n in (198, 199, 493):
    raw = open(f"auth-tree-{n}.xdr", "rb").read()
    try:
        X.TransactionEnvelope.from_xdr_bytes(raw)
        print(f"auth tree {n} levels: decodes with defaults")
    except Exception as e:
        print(f"auth tree {n} levels: {type(e).__name__}: {e}")
    v = X.TransactionEnvelope.from_xdr_bytes(raw, max_depth=2000)
    try:
        v.to_json_value()
        print("   to_json_value() with defaults: ok")
    except Exception as e:
        print(f"   to_json_value() with defaults: {type(e).__name__}: {e}")
