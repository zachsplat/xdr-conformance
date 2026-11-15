# wallet-backend replay results

Written by `summarize.py` from `results/*.jsonl`. One row per input, one column per wallet-backend commit (oldest first).

`pass`: every address read back as written (or an M... as its own G..., the documented choice since #693) and every account, trustline or signer the ledger created has a state change. `mishandled`: an address was stored lossily or a ledger fact has no state change. `halts`: the column encoder refuses a value, so the persist transaction fails and ingestion retries the ledger. `error`: the commit cannot read the input (its go-stellar-sdk predates the ledger's protocol).

| commit | role |
|---|---|
| [`79ea2acd`](https://github.com/stellar/wallet-backend/commit/79ea2acd) | #715 merged; last commit before #693 (#716 was found while reviewing #715) |
| [`6e5a5910`](https://github.com/stellar/wallet-backend/commit/6e5a5910) | #693 merged: M... reduced to the base account; other non-32-byte keys refused |
| [`2a0a84ea`](https://github.com/stellar/wallet-backend/commit/2a0a84ea) | last commit before #729 |
| [`2c873353`](https://github.com/stellar/wallet-backend/commit/2c873353) | #729 merged: signer keys stored in full (SignerKeyBytea) |
| [`764a4f5b`](https://github.com/stellar/wallet-backend/commit/764a4f5b) | last commit before #734 |
| [`c152783c`](https://github.com/stellar/wallet-backend/commit/c152783c) | #734 merged: state changes for SAC-created trustlines (closes #731) |
| [`3e22515a`](https://github.com/stellar/wallet-backend/commit/3e22515a) | main on 2026-11-15 |

| input | `79ea2acd` | `6e5a5910` | `2a0a84ea` | `2c873353` | `764a4f5b` | `c152783c` | `3e22515a` |
|---|---|---|---|---|---|---|---|
| `corpus:signer-signed-payload-setoptions` (6 addresses at main) | **mishandled** | **halts** | **halts** | pass | pass | pass | pass |
| `corpus:sac-trust-creates-trustline` (8 addresses at main) | **mishandled** | **mishandled** | **mishandled** | **mishandled** | **mishandled** | pass | pass |
| `corpus:soroban-muxed-source` (4 addresses at main) | **mishandled** | pass | pass | pass | pass | pass | pass |
| `corpus:sac-native-transfer-creates-account` (10 addresses at main) | **mishandled** | **mishandled** | **mishandled** | **mishandled** | **mishandled** | **mishandled** | **mishandled** |
| `corpus:tx-v0-envelope` (11 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:fee-bump` (12 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:muxed-destination` (11 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:muxed-source` (5 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:muxed-merge-destination` (22 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:signed-payload-extra-signer` (4 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:precond-min-seq-num` (4 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:memo-text-not-utf8` (11 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:memo-text-max-len` (25 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:operations-max-100` (703 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:path-max-len-5` (4 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:auth-tree-nested` (12 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:claimable-balance-create` (8 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:clawback` (9 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:set-trust-line-flags` (31 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:liquidity-pool-deposit` (27 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:sponsorship-sandwich` (12 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:extend-footprint-ttl` (4 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:allow-trust-asset-code` (9 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:scval-u256` (4 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:meta-event-lp-address` (26 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `corpus:meta-event-claimable-balance-address` (275 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `pubnet:65486002.xdr.zst` (3047 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `pubnet:65486006.xdr.zst` (3686 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `pubnet:65486052.xdr.zst` (3373 addresses at main) | pass | pass | pass | pass | pass | pass | pass |
| `standalone:ledger-43.xdr.zst` (8 addresses at main) | **error** | **error** | **error** | **error** | **error** | **error** | pass |
| `standalone:ledger-45.xdr.zst` (4 addresses at main) | **error** | **error** | **error** | **error** | **error** | **error** | pass |
| `standalone:ledger-26.xdr.zst` (10 addresses at main) | **error** | **error** | **error** | **error** | **error** | **error** | **mishandled** |
| `testnet:4437357.xdr.zst` (6 addresses at main) | **mishandled** | **halts** | **halts** | pass | pass | pass | pass |

## What the adapter saw on the issue inputs

### `corpus:soroban-muxed-source`: wallet-backend#716, muxed source (producer 1)

- `79ea2acd` **mishandled**: transactions_accounts.account_id: `MCEEMG2XFPLCETNPSGQFQPBCJVSH6EQQQLWE2WID2WFGHIZG3B5BKAAAAAAETFQC2KPHU` undecodable, stored 33 bytes, read back `MCEEMG2XFPLCETNPSGQFQPBCJVSH6EQQQLWE2WID2WFGHIZG3B5BL3OJ` (invalid payload length 32, expected 40); operations_accounts.account_id: `MCEEMG2XFPLCETNPSGQFQPBCJVSH6EQQQLWE2WID2WFGHIZG3B5BKAAAAAAETFQC2KPHU` undecodable, stored 33 bytes, read back `MCEEMG2XFPLCETNPSGQFQPBCJVSH6EQQQLWE2WID2WFGHIZG3B5BL3OJ` (invalid payload length 32, expected 40)
- `6e5a5910` **pass**: transactions_accounts.account_id: `MCEEMG2XFPLCETNPSGQFQPBCJVSH6EQQQLWE2WID2WFGHIZG3B5BKAAAAAAETFQC2KPHU` read back as `GCEEMG2XFPLCETNPSGQFQPBCJVSH6EQQQLWE2WID2WFGHIZG3B5BKJHW` (reduced to base account); operations_accounts.account_id: `MCEEMG2XFPLCETNPSGQFQPBCJVSH6EQQQLWE2WID2WFGHIZG3B5BKAAAAAAETFQC2KPHU` read back as `GCEEMG2XFPLCETNPSGQFQPBCJVSH6EQQQLWE2WID2WFGHIZG3B5BKJHW` (reduced to base account)
- `2a0a84ea`: same
- `2c873353`: same
- `764a4f5b`: same
- `c152783c`: same
- `3e22515a` **pass**: no anomalies, no facts

### `corpus:signer-signed-payload-setoptions`: wallet-backend#716 producer 3, then #729

- `79ea2acd` **mishandled**: state_changes.signer_account_id: `PBCK2RYYLIYOSHBEL2FQLAVRSHRH3GP3ID476SGKBV7BEZHMQ6NSAAAAAAB55LN6AANMS` undecodable, stored 33 bytes, read back `PBCK2RYYLIYOSHBEL2FQLAVRSHRH3GP3ID476SGKBV7BEZHMQ6NSBYVM` (invalid signed payload length 32, expected at least 36); signer_added in op 1 (SetOptions) for `GBCK2RYYLIYOSHBEL2FQLAVRSHRH3GP3ID476SGKBV7BEZHMQ6NSBB7B`: recorded as SIGNER/ADD
- `6e5a5910` **halts**: state_changes.signer_account_id: `PBCK2RYYLIYOSHBEL2FQLAVRSHRH3GP3ID476SGKBV7BEZHMQ6NSAAAAAAB55LN6AANMS` encode_error (stellar address PBCK2RYYLIYOSHBEL2FQLAVRSHRH3GP3ID476SGKBV7BEZHMQ6NSAAAAAAB55LN6AANMS has a 40-byte key payload; the account_id column stores only 32-byte account/contract keys); signer_added in op 1 (SetOptions) for `GBCK2RYYLIYOSHBEL2FQLAVRSHRH3GP3ID476SGKBV7BEZHMQ6NSBB7B`: recorded as SIGNER/ADD
- `2a0a84ea`: same
- `2c873353` **pass**: signer_added in op 1 (SetOptions) for `GBCK2RYYLIYOSHBEL2FQLAVRSHRH3GP3ID476SGKBV7BEZHMQ6NSBB7B`: recorded as SIGNER/ADD
- `764a4f5b`: same
- `c152783c`: same
- `3e22515a`: same

### `testnet:4437357.xdr.zst`: same transaction, replayed inside its whole testnet ledger

- `79ea2acd` **mishandled**: state_changes.signer_account_id: `PBCK2RYYLIYOSHBEL2FQLAVRSHRH3GP3ID476SGKBV7BEZHMQ6NSAAAAAAB55LN6AANMS` undecodable, stored 33 bytes, read back `PBCK2RYYLIYOSHBEL2FQLAVRSHRH3GP3ID476SGKBV7BEZHMQ6NSBYVM` (invalid signed payload length 32, expected at least 36); signer_added in op 1 (SetOptions) for `GBCK2RYYLIYOSHBEL2FQLAVRSHRH3GP3ID476SGKBV7BEZHMQ6NSBB7B`: recorded as SIGNER/ADD
- `6e5a5910` **halts**: state_changes.signer_account_id: `PBCK2RYYLIYOSHBEL2FQLAVRSHRH3GP3ID476SGKBV7BEZHMQ6NSAAAAAAB55LN6AANMS` encode_error (stellar address PBCK2RYYLIYOSHBEL2FQLAVRSHRH3GP3ID476SGKBV7BEZHMQ6NSAAAAAAB55LN6AANMS has a 40-byte key payload; the account_id column stores only 32-byte account/contract keys); signer_added in op 1 (SetOptions) for `GBCK2RYYLIYOSHBEL2FQLAVRSHRH3GP3ID476SGKBV7BEZHMQ6NSBB7B`: recorded as SIGNER/ADD
- `2a0a84ea`: same
- `2c873353` **pass**: signer_added in op 1 (SetOptions) for `GBCK2RYYLIYOSHBEL2FQLAVRSHRH3GP3ID476SGKBV7BEZHMQ6NSBB7B`: recorded as SIGNER/ADD
- `764a4f5b`: same
- `c152783c`: same
- `3e22515a`: same

### `corpus:sac-trust-creates-trustline`: wallet-backend#731

- `79ea2acd` **mishandled**: trustline_created in op 1 (InvokeHostFunction) for `GCEEMG2XFPLCETNPSGQFQPBCJVSH6EQQQLWE2WID2WFGHIZG3B5BKJHW`: **no state change**
- `6e5a5910`: same
- `2a0a84ea`: same
- `2c873353`: same
- `764a4f5b`: same
- `c152783c` **pass**: trustline_created in op 1 (InvokeHostFunction) for `GCEEMG2XFPLCETNPSGQFQPBCJVSH6EQQQLWE2WID2WFGHIZG3B5BKJHW`: recorded as TRUSTLINE/ADD
- `3e22515a`: same

### `corpus:sac-native-transfer-creates-account`: wallet-backend#804 (open)

- `79ea2acd` **mishandled**: account_created in op 1 (InvokeHostFunction) for `GDNUUT6J7UYDGHXGK4R2DPBZXNHGHMRZV7II4SEH3YVNCR2QFC3YH54V`: **no state change**
- `6e5a5910`: same
- `2a0a84ea`: same
- `2c873353`: same
- `764a4f5b`: same
- `c152783c`: same
- `3e22515a`: same

expected.tsv: 231 cells checked, 0 differ.

