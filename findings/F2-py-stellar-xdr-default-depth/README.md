# F2. py-stellar-xdr 0.2.0 refuses, with its default limits, envelopes that stellar-core admits

Status: filed as [lightsail-network/py-stellar-xdr#17](https://github.com/lightsail-network/py-stellar-xdr/issues/17) on 2026-11-15. The maintainer confirmed it and fixed it the same day in [#19](https://github.com/lightsail-network/py-stellar-xdr/pull/19) (default `max_depth` 200 to 500, recursive arrays read in loops), released in stellar-xdr 0.2.1. With 0.2.1 all four files below decode with the defaults (`./run.sh quick`, step 4) and round-trip through SEP-51 JSON to the same bytes. The rest of this page describes 0.2.0, as reported.

## What happens

`TransactionEnvelope.from_xdr_bytes()` and `to_json_value()` default to `max_depth=200`. A Soroban transaction whose authorization tree is nested 199 levels raises `XdrDepthError`. stellar-core 30.0.0's XDR checks admit it. (Admission here means the XDR decode and depth checks only; the test envelopes are mutated, so their signatures are not valid and they were not submitted to a network.)

stellar-core has two decoders on the submission path. xdrpp decodes the envelope (that is what `stellar-core print-xdr` runs), and from protocol 28 `validateXDRForProtocol` re-parses it with rs-stellar-xdr at depth 1000 (`src/transactions/TransactionUtils.cpp`, `can_parse_transaction` in `src/rust/src/soroban_proto_any.rs`, v30.0.0 at 0e49751). The second check is the stricter one, so the "admission" column below is rs-stellar-xdr 30.0.0 at depth 1000. js-stellar-sdk#1901 shows, with a standalone stellar-core, that an admitted deep transaction that then fails at apply stays in the ledger's transaction set.

| input | stellar-core admission | stellar-core print-xdr | py-stellar-xdr 0.2.0 (defaults) | py-stellar-base 17.0.1 | js-stellar-sdk 17.4.0 | go-stellar-sdk v0.9.0 |
|---|---|---|---|---|---|---|
| auth tree 198 levels | admits | decodes | decodes | decodes | decodes | decodes |
| auth tree 199 levels | admits | decodes | **XdrDepthError** | decodes | decodes | decodes |
| auth tree 490 levels (deepest admitted in this transaction) | admits | decodes | **XdrDepthError** | decodes | decodes | decodes |
| auth tree 491 levels | refuses | decodes | XdrDepthError | decodes | decodes | decodes |

The same limit applies to nested `ScVal` in a contract argument: py-stellar-xdr stops at 199 levels; stellar-core admits 246 (`../../reports/depth-sweep.md`).

## Why it mattered

py-stellar-base PR #1268 replaces the SDK's generated XDR code with py-stellar-xdr. The SDK as released (17.0.1) decodes all the admitted envelopes above. With the change on 0.2.0, a Python service reading ledgers with default settings would have stopped on any ledger holding such a transaction, and Galexie's `LedgerCloseMetaBatch` files add more levels on top of the envelope. #1268 now requires stellar-xdr 0.2.1 or later.

## Minimal reproduction

`auth-tree-198.xdr`, `auth-tree-199.xdr`, `auth-tree-490.xdr`, `auth-tree-491.xdr` here: a real pubnet Soroban transaction (ledger 59000003, tx `06ff45db8393c6ada64f84807d69d7303d7e43f4ea2aca22f6f75b1ab5373a3e`) with its authorization root replaced by a chain of n nested sub-invocations. The four files are synthetic. `repro.py` (needs `pip install stellar-xdr==0.2.0`) prints, in full in `output.txt`:

```
auth tree 198 levels: decodes with defaults
auth tree 199 levels: XdrDepthError: nesting deeper than max_depth=200 at offset 33180
auth tree 490 levels: XdrDepthError: nesting deeper than max_depth=200 at offset 33180
```

## Draft issue text

Title: Default max_depth=200 refuses transactions stellar-core admits (auth trees from 199 levels, ScVal from 200)

Body: the table above, the four files, `repro.py`, and the two stellar-core source references. Suggested direction, for the maintainer to choose: a default at least as permissive as stellar-core's admission check for a whole `LedgerCloseMetaBatch`, or a documented constant that ingesters are told to pass. js-stellar-sdk#1908 and go-stellar-sdk#6047 discuss the same question for JS and Go, where the libraries are looser than core rather than stricter.
