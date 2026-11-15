#!/usr/bin/env python3
"""py-stellar-base SEP-51 XDR-JSON differs from rs-stellar-xdr, py-stellar-xdr
and js-stellar-sdk on four shapes found in real pubnet transactions.

  pip install stellar-sdk==17.0.1 stellar-xdr==0.2.0
  python repro.py ../../corpus
"""
import json
import sys

import stellar_sdk.xdr as sdk
import stellar_xdr as ref  # py-stellar-xdr agrees with rs-stellar-xdr on all 156,335 inputs we compared

corpus = sys.argv[1] if len(sys.argv) > 1 else "../../corpus"
man = {e["id"]: e for e in json.load(open(f"{corpus}/manifest.json"))["entries"]}


def load(eid, part):
    f = man[eid]["files"][part]
    return f["xdr_type"], open(f"{corpus}/{f['path']}", "rb").read()


def find(v, pred, path="$", want_parent=False):
    if isinstance(v, dict):
        for k, c in v.items():
            if pred(k, c):
                return (path, v) if want_parent else (f"{path}.{k}", c)
            r = find(c, pred, f"{path}.{k}", want_parent)
            if r:
                return r
    if isinstance(v, list):
        for i, c in enumerate(v):
            r = find(c, pred, f"{path}[{i}]", want_parent)
            if r:
                return r
    return None


cases = [
    ("clawback", "envelope", "ClawbackOp field `from`", lambda k, c: k in ("from", "from_"), "ClawbackOp"),
    ("allow-trust-asset-code", "envelope", "AllowTrustOp `asset` (AssetCode union)", lambda k, c: k == "asset", "AllowTrustOp"),
    ("muxed-source", "meta", "TransactionResult arm for txSUCCESS / txFEE_BUMP_INNER_*", lambda k, c: k.startswith("tx") and isinstance(c, (list, dict)) and k not in ("tx_apply_processing", "tx_changes_before", "tx_changes_after"), None),
    ("meta-event-lp-address", "meta", "ContractEvent `contract_id` (ContractID)", lambda k, c: k == "contract_id" and c is not None, None),
]
for eid, part, label, pred, subtype in cases:
    ty, raw = load(eid, part)
    a = getattr(ref, ty).from_xdr_bytes(raw, max_depth=2000).to_json_value(max_depth=2000)
    b = json.loads(getattr(sdk, ty).from_xdr_bytes(raw).to_json())
    ra, rb = find(a, pred), find(b, pred)
    print(f"{label}  [{eid}, ledger {man[eid]['source']['ledger']}]")
    print(f"  py-stellar-xdr / rs-stellar-xdr: {ra[0].split('.')[-1]} = {json.dumps(ra[1])[:90]}")
    print(f"  py-stellar-base 17.0.1:          {rb[0].split('.')[-1]} = {json.dumps(rb[1])[:90]}")
    if subtype:
        try:
            getattr(sdk, subtype).from_json(json.dumps(find(a, pred, want_parent=True)[1]))
            print("  py-stellar-base reads the SEP-51 form: yes")
        except Exception as e:
            print(f"  py-stellar-base reads the SEP-51 form: no ({type(e).__name__}: {str(e)[:70]})")
    print()
