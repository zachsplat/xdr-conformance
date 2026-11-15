#!/usr/bin/env python3
"""Nesting-depth sweep: at what ScVal nesting does each decoder stop?

Takes the real Soroban envelope from bases.json, replaces its first contract
argument by n nested SCV_VEC values, and writes one request per n. Run every
adapter on the output (once with XDRCONF_DEFAULTS=1) and compare with
stellar-core, which is the decoder that decides what reaches the ledger.

Usage: depth_sweep.py bases.json OUT_requests.jsonl
"""
import base64
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import mutate  # noqa: E402

AUTH_NS = [50, 100, 150, 198, 199, 200, 250, 300, 400, 490, 491, 493, 494, 500, 600]
NS = [10, 50, 90, 100, 120, 150, 170, 199, 200, 246, 247, 250, 300, 334, 400, 450, 496, 497, 500, 600, 800, 1000]


def main():
    bases = json.load(open(sys.argv[1]))
    raw = base64.b64decode(bases["sor"]["envelope_b64"])
    e, tx, off = mutate.v1_offsets(raw)
    ihf = tx.operations[0].body.invoke_host_function_op.host_function
    args = ihf.invoke_contract.args
    first = mutate.enc(args[0])
    at = raw.find(mutate.enc(ihf.invoke_contract.function_name) + mutate.u32(len(args)) + first)
    at += len(mutate.enc(ihf.invoke_contract.function_name)) + 4
    with open(sys.argv[2], "w") as f:
        for n in NS:
            b = mutate.u32(3) + mutate.u32(7)
            for _ in range(n):
                b = mutate.u32(16) + mutate.u32(1) + mutate.u32(1) + b
            data = raw[:at] + b + raw[at + len(first):]
            f.write(json.dumps({"id": f"depth/{n}", "op": "decode", "type": "TransactionEnvelope",
                                "b64": base64.b64encode(data).decode()}) + "\n")
        # Authorization tree: root invocation with n nested sub_invocations,
        # the shape wallet-backend found unbounded.
        root = tx.operations[0].body.invoke_host_function_op.auth[0].root_invocation
        rb = mutate.enc(root)
        rat = raw.find(rb)
        assert rat > 0
        fn = mutate.enc(root.function)
        for n in AUTH_NS:
            inv = fn + mutate.u32(0)
            for _ in range(n):
                inv = fn + mutate.u32(1) + inv
            data = raw[:rat] + inv + raw[rat + len(rb):]
            f.write(json.dumps({"id": f"auth/{n}", "op": "decode", "type": "TransactionEnvelope",
                                "b64": base64.b64encode(data).decode()}) + "\n")


if __name__ == "__main__":
    main()
