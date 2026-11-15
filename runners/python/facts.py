#!/usr/bin/env python3
"""Conformance adapter for the two Python XDR implementations.

  facts.py sdk     -> stellar_sdk.xdr (py-stellar-base generated code, xdrlib3)
  facts.py pyxdr   -> stellar_xdr (lightsail-network/py-stellar-xdr, pre-1.0)

Same JSONL protocol as runners/rust/src/facts.rs.
"""
import base64
import json
import os
import sys

LIB = sys.argv[1]
# XDRCONF_DEFAULTS=1 runs each library exactly as shipped (default depth and
# recursion limits). Otherwise depth is set to 500 to match stellar-core.
DEFAULTS = os.environ.get("XDRCONF_DEFAULTS") == "1"
if LIB == "sdk":
    import stellar_sdk.xdr as X
else:
    import stellar_xdr as X

_NAMES = {n.lower(): n for n in dir(X) if not n.startswith("_")}


def cls(name):
    return getattr(X, _NAMES[name.lower()])


def decode(req):
    out = {"id": req["id"]}
    try:
        raw = base64.b64decode(req["b64"], validate=True)
        T = cls(req["type"])
        if LIB == "sdk":
            v = T.from_xdr_bytes(raw)
            back = v.to_xdr_bytes()
            js = json.loads(v.to_json())
        else:
            v = T.from_xdr_bytes(raw) if DEFAULTS else T.from_xdr_bytes(raw, max_depth=500)
            back = v.to_xdr_bytes()
            js = v.to_json_value()
    except RecursionError:
        out.update(ok=False, error="RecursionError (Python stack exhausted)")
        return out
    except Exception as e:  # report, never crash the runner
        out.update(ok=False, error=f"{type(e).__name__}: {e}"[:300])
        return out
    out.update(ok=True, roundtrip_equal=(back == raw), json=js)
    if back != raw:
        out["reencoded_b64"] = base64.b64encode(back).decode()
    if req["type"] == "TransactionEnvelope" and req.get("network"):
        out["hash"] = tx_hash(raw, req["network"])
    return out


def tx_hash(raw, passphrase):
    # Only the SDK has its own transaction model; the hash goes through it.
    if LIB != "sdk":
        return None
    from stellar_sdk.helpers import parse_transaction_envelope_from_xdr

    try:
        env = parse_transaction_envelope_from_xdr(base64.b64encode(raw).decode(), passphrase)
        return env.hash_hex()
    except Exception as e:
        return f"error: {type(e).__name__}: {e}"[:200]


def from_json(req):
    out = {"id": req["id"]}
    try:
        T = cls(req["type"])
        if LIB == "sdk":
            v = T.from_json(json.dumps(req["json"]))
        else:
            v = T.from_json_value(req["json"], max_depth=500)
        out.update(ok=True, b64=base64.b64encode(v.to_xdr_bytes()).decode())
    except Exception as e:
        out.update(ok=False, error=f"{type(e).__name__}: {e}"[:300])
    return out


def main():
    if not DEFAULTS:
        sys.setrecursionlimit(20000)
    w = sys.stdout
    for line in sys.stdin:
        if not line.strip():
            continue
        req = json.loads(line)
        res = from_json(req) if req.get("op") == "from_json" else decode(req)
        if "hash" in res and res["hash"] is None:
            del res["hash"]
        w.write(json.dumps(res) + "\n")


if __name__ == "__main__":
    main()
