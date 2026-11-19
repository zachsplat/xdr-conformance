#!/usr/bin/env python3
"""Extra one-change variants of the three hostile baselines, written for the
Dart run after reading the SDK's decoder. Each one targets a code path seen in
lib/src/xdr/xdr_data_io.dart or a generated type. stellar-core print-xdr and
rs-stellar-xdr judge them; nothing is assumed.

Usage: make_probes.py HOSTILE_REQ.jsonl OUT.jsonl   (needs py-stellar-xdr for offsets)
"""
import base64
import json
import struct
import sys

import stellar_xdr as X

PASS = "Public Global Stellar Network ; September 2015"


def u32(n):
    return struct.pack(">I", n)


def enc(v):
    return v.to_xdr_bytes()


def xstr(b):
    return u32(len(b)) + b + b"\0" * ((4 - len(b) % 4) % 4)


def memo_offsets(raw):
    tx = X.TransactionEnvelope.from_xdr_bytes(raw).v1.tx
    m = 4 + len(enc(tx.source_account)) + 4 + 8 + len(enc(tx.cond))
    return m, m + len(enc(tx.memo))


def arg0_at(raw):
    tx = X.TransactionEnvelope.from_xdr_bytes(raw).v1.tx
    ic = tx.operations[0].body.invoke_host_function_op.host_function.invoke_contract
    first = enc(ic.args[0])
    at = raw.find(enc(ic.function_name) + u32(len(ic.args)) + first)
    assert at > 0
    at += len(enc(ic.function_name)) + 4
    return at, len(first)


def main():
    base = {}
    for l in open(sys.argv[1]):
        r = json.loads(l)
        if r["id"].endswith("/baseline"):
            base[r["id"].split("/")[1]] = base64.b64decode(r["b64"])
    out = []
    cls, sor = base["cls"], base["sor"]
    m, mend = memo_offsets(cls)
    bom = b"\xef\xbb\xbfab"
    out.append(("memo_text_utf8_bom", cls[:m] + u32(1) + xstr(bom) + cls[mend:],
                "Memo text EF BB BF 61 62: valid UTF-8 starting with a byte order mark."))
    # Last signature: hint(4) len(4) sig(64). Make it 63 bytes and end the input
    # right after them, so the one padding byte is missing at end of input.
    assert cls[-68:-64] == u32(64)
    out.append(("signature_63_padding_missing_at_eof", cls[:-68] + u32(63) + cls[-64:-1],
                "Last signature declared 63 bytes; the input ends after them, without the 1 padding byte."))
    at, n = arg0_at(sor)
    bad = bytes([0xFF, 0xFE, 0x00, 0x41, 0xC3])
    out.append(("scval_string_non_utf8", sor[:at] + u32(14) + xstr(bad) + sor[at + n:],
                "First contract argument replaced by SCV_STRING with bytes FF FE 00 41 C3 (not UTF-8)."))
    out.append(("scval_string_utf8_bom", sor[:at] + u32(14) + xstr(bom) + sor[at + n:],
                "First contract argument replaced by SCV_STRING EF BB BF 61 62 (valid UTF-8 with a BOM)."))
    out.append(("scval_bytes_baseline_like", sor[:at] + u32(13) + xstr(bad) + sor[at + n:],
                "Control: same 5 bytes as SCV_BYTES, which every decoder should accept."))
    with open(sys.argv[2], "w") as f:
        for name, raw, desc in out:
            f.write(json.dumps({"id": f"probe/{name}", "op": "decode", "type": "TransactionEnvelope",
                                "b64": base64.b64encode(raw).decode(), "network": PASS, "description": desc}) + "\n")


if __name__ == "__main__":
    main()
