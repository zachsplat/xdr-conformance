#!/usr/bin/env python3
"""Download LedgerCloseMetaBatch files from the public Galexie data lake.

The AWS Open Data bucket aws-public-blockchain holds every pubnet ledger as one
zstd-compressed LedgerCloseMetaBatch per object (ledgersPerBatch=1,
batchesPerPartition=64000, see .config.json at the prefix). No credentials or
keys are needed.

Usage: fetch_galexie.py OUT_DIR FIRST LAST [FIRST LAST ...]
"""
import os
import sys
import urllib.request

BASE = "https://aws-public-blockchain.s3.us-east-2.amazonaws.com/v1.1/stellar/ledgers/pubnet"
PER_PARTITION = 64000


def key(seq: int) -> str:
    start = seq // PER_PARTITION * PER_PARTITION
    end = start + PER_PARTITION - 1
    part = f"{0xFFFFFFFF - start:08X}--{start}-{end}"
    return f"{part}/{0xFFFFFFFF - seq:08X}--{seq}.xdr.zst"


def main() -> None:
    out = sys.argv[1]
    ranges = [int(x) for x in sys.argv[2:]]
    os.makedirs(out, exist_ok=True)
    for first, last in zip(ranges[::2], ranges[1::2]):
        for seq in range(first, last + 1):
            dest = os.path.join(out, f"{seq}.xdr.zst")
            if os.path.exists(dest):
                continue
            req = urllib.request.Request(f"{BASE}/{key(seq)}", headers={"User-Agent": "xdr-conformance-proof"})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            with open(dest + ".part", "wb") as f:
                f.write(data)
            os.replace(dest + ".part", dest)
    print(f"{len(os.listdir(out))} files in {out}")


if __name__ == "__main__":
    main()
