#!/usr/bin/env python3
"""Derive hostile and edge-case variants from real mainnet envelopes.

Every variant starts from the bytes of a real pubnet TransactionEnvelope and
changes exactly one thing at a known offset. Variants are marked synthetic.
The expected verdict is not assumed: stellar-core's own decoder
(runners/core) is run on every variant and its answer is the reference.

Usage: mutate.py bases.json OUT_requests.jsonl OUT_manifest_fragment.json
Needs stellar_xdr (py-stellar-xdr) only to locate offsets.
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


def v1_offsets(raw):
    """Byte offsets of the pieces of a TransactionV1Envelope."""
    e = X.TransactionEnvelope.from_xdr_bytes(raw)
    tx = e.v1.tx
    off = {"type": 0}
    pos = 4
    for name in ("source_account", "fee", "seq_num", "cond", "memo"):
        off[name] = pos
        val = getattr(tx, name)
        if name == "fee":
            pos += 4
        elif name == "seq_num":
            pos += 8
        else:
            pos += len(enc(val))
    off["operations"] = pos
    pos += 4
    ops = []
    for op in tx.operations:
        ops.append((pos, len(enc(op))))
        pos += len(enc(op))
    off["ops"] = ops
    off["ext"] = pos
    return e, tx, off


def classic_variants(raw):
    e, tx, off = v1_offsets(raw)
    out = []
    text = bytes(tx.memo.text)
    m = off["memo"]  # memo: type(4) len(4) bytes pad
    pad_at = m + 8 + len(text)
    padlen = (4 - len(text) % 4) % 4
    assert padlen and raw[pad_at:pad_at + padlen] == b"\0" * padlen

    out.append(("memo_text_nonzero_padding", raw[:pad_at] + b"\x01" + raw[pad_at + 1:],
                "One padding byte after an odd-length memo text set to 0x01 (RFC 4506 4.9-4.11 says padding is zero)."))

    op0, op0len = off["ops"][0]
    assert raw[op0:op0 + 4] == u32(1), "op source account flag should be present"
    out.append(("optional_flag_2", raw[:op0] + u32(2) + raw[op0 + 4:],
                "The operation's optional sourceAccount flag set to 2 instead of 1."))

    out.append(("trailing_bytes", raw + b"\0\0\0\0", "Four zero bytes appended after a complete envelope."))

    t29 = b"a" * 29
    memo29 = u32(1) + u32(29) + t29 + b"\0\0\0"
    out.append(("memo_text_len_29", raw[:m] + memo29 + raw[off["operations"]:],
                "Memo text of 29 bytes; the schema says string<28>."))

    out.append(("memo_type_unknown", raw[:m] + u32(5) + raw[m + 4:],
                "Memo union discriminant 5, which no MemoType names."))

    out.append(("envelope_type_scp", u32(1) + raw[4:],
                "TransactionEnvelope discriminant 1 (ENVELOPE_TYPE_SCP), not an arm of the union."))

    body = op0 + 4 + len(enc(tx.operations[0].source_account))
    # body: type(4)=PAYMENT, destination MuxedAccount, asset
    dest_len = len(enc(tx.operations[0].body.payment_op.destination))
    asset_at = body + 4 + dest_len
    out.append(("asset_type_unknown", raw[:asset_at] + u32(4) + raw[asset_at + 4:],
                "Payment asset discriminant 4, which no AssetType names."))

    ops101 = u32(101) + raw[op0:op0 + op0len] * 101
    out.append(("operations_101", raw[:off["operations"]] + ops101 + raw[off["ext"]:],
                "The single operation repeated 101 times; the schema says Operation operations<100>."))

    out.append(("operations_count_huge_truncated", raw[:off["operations"]] + u32(0xFFFFFFFF),
                "Operation count 0xFFFFFFFF and the input ends there; a decoder must fail without reserving memory for the count."))

    nonutf8 = bytes([0xFF, 0xFE, 0x00, 0x41, 0xC3])  # invalid UTF-8, embedded NUL
    memo_bin = u32(1) + u32(len(nonutf8)) + nonutf8 + b"\0" * ((4 - len(nonutf8) % 4) % 4)
    out.append(("memo_text_non_utf8_nul", raw[:m] + memo_bin + raw[off["operations"]:],
                "Memo text bytes FF FE 00 41 C3: not UTF-8 and with a NUL. stellar-core passes memos through untouched."))
    return out


def find_unique(hay, needle):
    i = hay.find(needle)
    assert i >= 0 and hay.find(needle, i + 1) < 0, "needle not unique"
    return i


def soroban_variants(raw):
    e, tx, off = v1_offsets(raw)
    out = []
    op = tx.operations[0]
    ihf = op.body.invoke_host_function_op.host_function
    args = ihf.invoke_contract.args
    first = enc(args[0])
    # The same invocation is repeated in the auth tree; the host function comes first.
    at = raw.find(enc(ihf.invoke_contract.function_name) + u32(len(args)) + first)
    assert at > 0
    at += len(enc(ihf.invoke_contract.function_name)) + 4

    def replace_arg0(new):
        return raw[:at] + new + raw[at + len(first):]

    SCV_BOOL, SCV_VEC, SCV_MAP, SCV_U32, SCV_SYMBOL, SCV_STRING = 0, 16, 17, 3, 15, 14
    out.append(("scval_bool_2", replace_arg0(u32(SCV_BOOL) + u32(2)),
                "First contract argument replaced by an ScVal bool whose 4-byte value is 2."))

    def deep(n):
        # n nested SCV_VEC, each an optional present vec of one element, ending in u32 7.
        b = u32(SCV_U32) + u32(7)
        for _ in range(n):
            b = u32(SCV_VEC) + u32(1) + u32(1) + b
        return b

    for n in (90, 200, 1000):
        out.append((f"scval_nested_vec_{n}", replace_arg0(deep(n)),
                    f"First contract argument replaced by {n} nested ScVal vecs around a u32."))

    def sym(s):
        p = (4 - len(s) % 4) % 4
        return u32(SCV_SYMBOL) + u32(len(s)) + s + b"\0" * p

    m = u32(SCV_MAP) + u32(1) + u32(2) + sym(b"b") + u32(SCV_U32) + u32(1) + sym(b"a") + u32(SCV_U32) + u32(2)
    out.append(("scmap_unsorted_keys", replace_arg0(m),
                "ScMap with keys b, a (not ascending). Valid XDR; only the host rejects it."))
    out.append(("scsymbol_invalid_chars", replace_arg0(sym(b"a b!")),
                "ScSymbol 'a b!' (space and '!' are outside the symbol charset). Valid XDR; only the host rejects it."))
    return out


def extra_signer_variants(raw):
    e, tx, off = v1_offsets(raw)
    out = []
    cond = tx.cond
    signers = cond.v2.extra_signers
    sp = signers[0].ed25519_signed_payload
    payload = bytes(sp.payload)
    old = u32(3) + bytes(sp.ed25519) + u32(len(payload)) + payload + b"\0" * ((4 - len(payload) % 4) % 4)
    at = find_unique(raw, old)
    p65 = bytes(range(65))
    new = u32(3) + bytes(sp.ed25519) + u32(65) + p65 + b"\0\0\0"
    out.append(("signed_payload_len_65", raw[:at] + new + raw[at + len(old):],
                "Extra signer of type signed payload with a 65-byte payload; the schema says opaque payload<64>."))
    new0 = u32(3) + bytes(sp.ed25519) + u32(0)
    out.append(("signed_payload_len_0", raw[:at] + new0 + raw[at + len(old):],
                "Extra signer of type signed payload with an empty payload. Valid XDR (CAP-40 allows 0..64 at the XDR level)."))
    return out


def main():
    bases = json.load(open(sys.argv[1]))
    reqs, manifest = [], []
    for key, fn in (("cls", classic_variants), ("sor", soroban_variants), ("ext", extra_signer_variants)):
        b = bases[key]
        raw = base64.b64decode(b["envelope_b64"])
        for name, data, why in [("baseline", raw, "Unmodified mainnet envelope.")] + fn(raw):
            rid = f"hostile/{key}/{name}"
            reqs.append({"id": rid, "op": "decode", "type": "TransactionEnvelope",
                         "b64": base64.b64encode(data).decode(), "network": PASS})
            manifest.append({"id": rid, "derived_from": {"ledger": b["ledger"], "tx_hash": b["hash"]},
                             "synthetic": name != "baseline", "mutation": name, "description": why})
    with open(sys.argv[2], "w") as f:
        for r in reqs:
            f.write(json.dumps(r) + "\n")
    json.dump(manifest, open(sys.argv[3], "w"), indent=1)
    print(len(reqs), "requests")


if __name__ == "__main__":
    main()
