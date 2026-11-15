# F1. py-stellar-base 17.0.1 writes SEP-51 XDR-JSON that differs from the other implementations, on four shapes found in pubnet history

Status: filed as [StellarCN/py-stellar-base#1269](https://github.com/StellarCN/py-stellar-base/issues/1269) on 2026-11-15, open. `main` at 1b33206507 had the same generated code that day. PR #1268 (replace the generated XDR with py-stellar-xdr) would remove it as a side effect.

## How it was found

The conformance runner decoded 112,278 pubnet transaction envelopes and 44,057 result metas (380 ledgers from the Galexie public data lake, protocols 12 to 29) with rs-stellar-xdr 30.0.0, py-stellar-xdr 0.2.0, js-stellar-sdk 17.4.0 and py-stellar-base 17.0.1, and compared their SEP-51 JSON. The first three agree on every input. py-stellar-base differs on these shapes:

| shape | rs-stellar-xdr, py-stellar-xdr, js-stellar-sdk | py-stellar-base 17.0.1 | inputs affected in the sample | py-stellar-base reads the SEP-51 form back |
|---|---|---|---|---|
| `TransactionResult` arms from `txSUCCESS`, `txFAILED`, `txFEE_BUMP_INNER_SUCCESS`, `txFEE_BUMP_INNER_FAILED` (and `opINNER`) | `tx_success`, `op_inner` | `txsuccess`, `opinner` | every result meta (44,057 of 44,057) | not tested |
| `ClawbackOp.from` | `"from"` | `"from_"` (the Python keyword escape leaks into JSON) | 35 operations in 17 envelopes | no: `KeyError: 'from_'` |
| `AllowTrustOp.asset` (`AssetCode` union) | `"FIL"` | `{"credit_alphanum4": "FIL"}` | 64 operations in 16 envelopes (all 16 also hold a clawback) | no: `ValueError: Expected a single-key object for AssetCode` |
| `ContractEvent.contract_id` (`ContractID`) | `"C..."` strkey | 64-char hex | every meta with contract events | not tested |

Byte round-trips and transaction hashes agree in all four implementations; only the JSON differs.

## Minimal reproduction

`repro.py` reads four corpus entries (`../../corpus`) and prints both JSON forms; `output.txt` is its output.

```
pip install stellar-sdk==17.0.1 stellar-xdr==0.2.0
python repro.py ../../corpus
```

## Draft issue text

Title: `to_json()` differs from SEP-51 (and from stellar-xdr) for result codes, ClawbackOp.from, AssetCode and ContractEvent.contract_id

Body: the table above, the four ledger and transaction references from `../../corpus/manifest.json`, and `repro.py`. Following the maintainer's request in #1264, say that the new `stellar-xdr` package (0.2.0) writes all four shapes correctly, so the problem is only in `stellar_sdk`. Note that #1268 would fix all four if it lands, so the issue mainly records the behavior of 17.0.1 for anyone storing its JSON.
