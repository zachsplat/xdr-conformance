#!/usr/bin/env python3
"""Pick one real transaction per rare pattern and write corpus entries.

Inputs: the scanner's txs.jsonl, the uncompressed ledger dir it wrote, the
Rust adapter's results for the envelopes (expected SEP-51 JSON and hash), and
optionally extra entries (testnet) as JSON files.
Outputs corpus/entries/<id>/{envelope.xdr,meta.xdr,envelope.json} and
corpus/manifest.json.

Usage: pick_corpus.py txs.jsonl LCM_DIR rust_env.jsonl CORPUS_DIR [extra.json ...]
"""
import base64
import hashlib
import json
import os
import sys

import stellar_xdr as X

# pattern tag -> (entry id, CAPs, what the shape is)
PATTERNS = [
    ("envelope_tx_v0", "tx-v0-envelope", ["CAP-0015"], "Pre-protocol-13 TransactionV0Envelope (ed25519 source, no muxed account)."),
    ("fee_bump", "fee-bump", ["CAP-0015"], "FeeBumpTransactionEnvelope wrapping a V1 transaction."),
    ("muxed_account:destination", "muxed-destination", ["CAP-0027"], "Operation destination is an M... muxed account."),
    ("muxed_account:source_account", "muxed-source", ["CAP-0027"], "Transaction or operation source is an M... muxed account."),
    ("muxed_account:account_merge", "muxed-merge-destination", ["CAP-0027"], "AccountMerge into an M... muxed account."),
    ("signed_payload_signer:extra_signers", "signed-payload-extra-signer", ["CAP-0040", "CAP-0021"], "PreconditionsV2 extra signer of type ed25519 signed payload (P... strkey)."),
    ("precond_min_seq_num", "precond-min-seq-num", ["CAP-0021"], "PreconditionsV2 with minSeqNum set."),
    ("memo_text_escaped_bytes", "memo-text-not-utf8", [], "Memo text whose bytes are not printable UTF-8; stellar-core passes memos through unvalidated."),
    ("memo_text_long", "memo-text-max-len", [], "Memo text at its maximum length of 28 bytes."),
    ("ops_100", "operations-max-100", [], "Transaction with 100 operations, the maximum the schema allows."),
    ("path_max_len_5", "path-max-len-5", [], "Path payment with a 5-asset path, the maximum the schema allows."),
    ("auth_tree_depth_2", "auth-tree-nested", ["CAP-0046"], "Soroban authorization entry whose root invocation has nested sub-invocations."),
    ("op:create_claimable_balance", "claimable-balance-create", ["CAP-0023"], "CreateClaimableBalance with claimant predicates."),
    ("op:clawback", "clawback", ["CAP-0035"], "Clawback operation (its XDR field is named from)."),
    ("op:set_trust_line_flags", "set-trust-line-flags", ["CAP-0035"], "SetTrustLineFlags operation."),
    ("op:liquidity_pool_deposit", "liquidity-pool-deposit", ["CAP-0038"], "LiquidityPoolDeposit operation."),
    ("op:begin_sponsoring_future_reserves", "sponsorship-sandwich", ["CAP-0033"], "BeginSponsoringFutureReserves sandwich."),
    ("op:extend_footprint_ttl", "extend-footprint-ttl", ["CAP-0046"], "ExtendFootprintTTL Soroban operation."),
    ("op:allow_trust", "allow-trust-asset-code", [], "AllowTrust, whose asset field is the AssetCode union."),
    ("scval_u256", "scval-u256", ["CAP-0046"], "Soroban value of type U256."),
    ("meta_scaddress_L", "meta-event-lp-address", ["CAP-0067"], "Result meta with a contract event naming a liquidity pool ScAddress (L...)."),
    ("meta_scaddress_B", "meta-event-claimable-balance-address", ["CAP-0067"], "Result meta with a contract event naming a claimable balance ScAddress (B...)."),
]


def sha(b):
    return hashlib.sha256(b).hexdigest()


def protocol_of(lcm_dir, seq, cache={}):
    if seq not in cache:
        raw = open(os.path.join(lcm_dir, f"{seq}.xdr"), "rb").read()
        batch = X.LedgerCloseMetaBatch.from_xdr_bytes(raw, max_depth=2000)
        lcm = batch.ledger_close_metas[0]
        inner = getattr(lcm, "v0", None) or getattr(lcm, "v1", None) or getattr(lcm, "v2", None)
        cache[seq] = int(inner.ledger_header.header.ledger_version)
    return cache[seq]


def write_entry(corpus, eid, env_b64, meta_b64, meta_type, expected_json, expected_hash, meta_fields):
    d = os.path.join(corpus, "entries", eid)
    os.makedirs(d, exist_ok=True)
    env = base64.b64decode(env_b64)
    open(os.path.join(d, "envelope.xdr"), "wb").write(env)
    files = {"envelope": {"path": f"entries/{eid}/envelope.xdr", "xdr_type": "TransactionEnvelope", "sha256": sha(env)}}
    if meta_b64:
        meta = base64.b64decode(meta_b64)
        open(os.path.join(d, "meta.xdr"), "wb").write(meta)
        files["meta"] = {"path": f"entries/{eid}/meta.xdr", "xdr_type": meta_type, "sha256": sha(meta)}
    with open(os.path.join(d, "envelope.json"), "w") as f:
        json.dump(expected_json, f, indent=1, sort_keys=True)
    entry = {"id": eid, "files": files,
             "expected": {"envelope_sep51_json": f"entries/{eid}/envelope.json", "tx_hash": expected_hash,
                          "roundtrip": "identity"}}
    entry.update(meta_fields)
    return entry


def main():
    txs_path, lcm_dir, rust_env, corpus = sys.argv[1:5]
    extras = sys.argv[5:]
    rust = {}
    for l in open(rust_env):
        r = json.loads(l)
        rust[r["id"]] = r
    chosen = {}
    for l in open(txs_path):
        r = json.loads(l)
        for tag, eid, caps, why in PATTERNS:
            if eid in chosen or tag not in r["tags"]:
                continue
            # Prefer small envelopes so entries stay readable.
            if len(r["envelope_b64"]) > 6000 and tag not in ("ops_100",):
                continue
            chosen[eid] = (r, tag, caps, why)
    entries = []
    for tag, eid, caps, why in PATTERNS:
        if eid not in chosen:
            print("no example for", tag, file=sys.stderr)
            continue
        r, tag, caps, why = chosen[eid]
        rid = f"{r['ledger']}:{r['index_in_set']}"
        res = rust[rid]
        entries.append(write_entry(corpus, eid, r["envelope_b64"], r["meta_b64"], r["meta_type"], res["json"], res["hash"], {
            "pattern": tag, "caps": caps, "description": why,
            "network": "pubnet", "network_passphrase": "Public Global Stellar Network ; September 2015",
            "protocol_version": protocol_of(lcm_dir, r["ledger"]),
            "source": {"kind": "galexie-public-datalake", "ledger": r["ledger"], "tx_hash": r["hash"],
                       "index_in_tx_set": r["index_in_set"]},
            "synthetic": False,
        }))
    for path in extras:
        x = json.load(open(path))
        entries.append(write_entry(corpus, x["id"], x["envelope_b64"], x.get("meta_b64"), x.get("meta_type"),
                                   x["expected_json"], x["tx_hash"], {k: v for k, v in x.items() if k in (
                                       "pattern", "caps", "description", "network", "network_passphrase",
                                       "protocol_version", "source", "synthetic", "sightings")}))
    manifest = {"schema": "manifest.schema.json", "version": 1, "entries": entries}
    with open(os.path.join(corpus, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    print(len(entries), "entries")


if __name__ == "__main__":
    main()
