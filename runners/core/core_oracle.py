#!/usr/bin/env python3
"""Reference adapter: stellar-core's own XDR decoder (xdrpp) via `print-xdr`.

Reads the same JSONL requests as the other adapters (TransactionEnvelope only,
filetype tx) and writes {"id", "ok", "error"?}. Runs one container for the
whole batch. Needs docker and the stellar/stellar-core image.

Usage: core_oracle.py IMAGE < requests.jsonl > results.jsonl
"""
import json
import os
import subprocess
import sys
import tempfile

FILETYPE = {"TransactionEnvelope": "tx", "TransactionResult": "result", "TransactionMeta": "meta",
            "LedgerEntry": "ledgerentry", "LedgerHeader": "ledgerheader", "Asset": "asset"}


def main():
    image = sys.argv[1]
    reqs = [json.loads(l) for l in sys.stdin if l.strip()]
    with tempfile.TemporaryDirectory() as d:
        os.chmod(d, 0o777)
        script = ["#!/bin/sh"]
        for i, r in enumerate(reqs):
            ft = FILETYPE.get(r["type"])
            if not ft:
                continue
            with open(os.path.join(d, f"{i}.b64"), "w") as f:
                f.write(r["b64"] + "\n")
            script.append(f"stellar-core print-xdr --filetype {ft} --base64 --compact /c/{i}.b64 > /c/{i}.out 2>&1")
        with open(os.path.join(d, "run.sh"), "w") as f:
            f.write("\n".join(script) + "\n")
        subprocess.run(["docker", "run", "--rm", "-u", f"{os.getuid()}:{os.getgid()}", "-v", f"{d}:/c",
                        "--entrypoint", "sh", image, "/c/run.sh"], check=True, capture_output=True)
        for i, r in enumerate(reqs):
            p = os.path.join(d, f"{i}.out")
            if not os.path.exists(p):
                print(json.dumps({"id": r["id"], "ok": None, "error": "type not supported by print-xdr"}))
                continue
            txt = "\n".join(l for l in open(p, errors="replace").read().splitlines() if not l.startswith("Warning: running non-release"))
            if "Could not decode" in txt or not txt.strip().startswith("{"):
                print(json.dumps({"id": r["id"], "ok": False, "error": txt.strip()[:300]}))
            else:
                print(json.dumps({"id": r["id"], "ok": True}))


if __name__ == "__main__":
    main()
