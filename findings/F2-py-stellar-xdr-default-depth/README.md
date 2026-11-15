# F2. py-stellar-xdr 0.2.0 refuses, with its default limits, envelopes that stellar-core decodes and admits

Status on 2026-11-15: not filed (lightsail-network/py-stellar-xdr has no outside issues yet). Draft issue text below.

## What happens

`TransactionEnvelope.from_xdr_bytes()` and `to_json_value()` default to `max_depth=200`. A transaction whose Soroban authorization tree is nested 199 levels raises `XdrDepthError`. stellar-core 30.0.0 decodes the same bytes. js-stellar-sdk#1901 reports, from a standalone stellar-core 30.0.0, that core admits authorization trees up to 493 levels into a ledger (the transaction then fails at apply and stays in the transaction set), and rejects 494 as `txMALFORMED`.

| input | stellar-core 30.0.0 | py-stellar-xdr 0.2.0 (defaults) | py-stellar-base 17.0.1 | js-stellar-sdk 17.4.0 | go-stellar-sdk v0.9.0 | rs-stellar-xdr 30.0.0 (`Limits::none()`) |
|---|---|---|---|---|---|---|
| auth tree 198 levels | decodes | decodes | decodes | decodes | decodes | decodes |
| auth tree 199 levels | decodes | **XdrDepthError** | decodes | decodes | decodes | decodes |
| auth tree 493 levels | decodes | **XdrDepthError** | decodes | decodes | decodes | decodes |

The same limit applies to nested `ScVal`: py-stellar-xdr stops at 199 nested vecs, stellar-core decodes up to 496 (`reports/depth-sweep.md`).

## Why it matters now

py-stellar-base PR #1268 (draft) replaces the SDK's generated XDR code with py-stellar-xdr. Today's SDK decodes these envelopes; after that change, a Python service reading ledgers with default settings would stop on any ledger that holds such a transaction. Galexie's data lake files are `LedgerCloseMetaBatch`, which adds more levels on top of the envelope.

## Minimal reproduction

`auth-tree-198.xdr`, `auth-tree-199.xdr`, `auth-tree-493.xdr` in this folder: a real pubnet Soroban transaction (ledger 59000003, tx `06ff45db8393c6ada64f84807d69d7303d7e43f4ea2aca22f6f75b1ab5373a3e`) with its authorization root replaced by a chain of n nested sub-invocations. These three files are synthetic. `repro.py` prints:

```
auth tree 198 levels: decodes with defaults
auth tree 199 levels: XdrDepthError: nesting deeper than max_depth=200 ...
auth tree 493 levels: XdrDepthError: ...
```

(full output in `output.txt`). stellar-core's verdict comes from `stellar-core print-xdr --filetype tx --base64` in the `stellar/stellar-core:latest` image (30.0.0, 0e49751).

## Suggested fix (for the maintainer to choose)

Either a default that is at least what stellar-core admits for a whole `LedgerCloseMetaBatch`, or a documented constant such as `CORE_COMPATIBLE_MAX_DEPTH` that ingesters are told to pass. js-stellar-sdk#1908 and go-stellar-sdk#6047 discuss the same question for JS and Go.
