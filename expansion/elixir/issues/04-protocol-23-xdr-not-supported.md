TITLE: Protocol 23 XDR missing: LEDGER_ENTRY_RESTORED and SorobanTransactionData ext v1 fail to decode

## What happens

The 0.17.0 changelog says "Support Protocol 22, 23, and 26 features" and the release adds `TransactionMetaV4`, but two protocol 23 (CAP-66) XDR changes are missing:

1. `LedgerEntryChangeType` stops at `LEDGER_ENTRY_STATE = 3`. A `LEDGER_ENTRY_RESTORED = 4` change raises `XDR.EnumError`, so any meta that restores an archived entry fails to decode.
2. `SorobanTransactionData.ext` is still `ExtensionPoint` (arm 0 only). A transaction that restores archived entries uses arm 1 (`SorobanResourcesExtV0`), and decoding its envelope raises `FunctionClauseError` from `XDR.UnionError.exception/1`. Because it is a `FunctionClauseError` and not an XDR error, code that rescues XDR errors does not catch it.

Both show up on a real pubnet transaction that restores an archived entry.

## Reproduction

stellar_base 0.17.0 (Hex), elixir_xdr 0.3.11, Elixir 1.18.6 / OTP 28. Both inputs come from pubnet transaction `4c5f2f0ea4861831f8c4fce1e710bab9f342a06c590ef47c7de1021f341cfb76` (ledger 65486053): a restored TTL change from its meta (52 bytes) and its `SorobanTransactionData`.

```elixir
Mix.install([{:stellar_base, "== 0.17.0"}])
alias StellarBase.XDR

ch = Base.decode64!("AAAABAPnPOUAAAAJvB7uPkn7hr+4aZvWxO2uYZHlIQT6L1YLa7AMxkxOo2EEBuDkAAAAAA==")
XDR.LedgerEntryChange.decode_xdr(ch)
# raises XDR.EnumError: The key which you try to encode doesn't belong to the current declarations

sd = Base.decode64!("AAAAAQAAAAEAAAABAAAACgAAAAYAAAABQYFMGWdiCpgN+OtU0n20rkwTaa9PxHhJjSTLVzbSHwMAAAAUAAAAAQAAAAYAAAABjdJYuNKFa2MERRiIm9aQIFWOPYE6VgrY11u/XB02JicAAAAQAAAAAQAAAAEAAAAPAAAAE0V4ZWN1dG9yc1B1YmxpY0tleXMAAAAAAQAAAAYAAAABjdJYuNKFa2MERRiIm9aQIFWOPYE6VgrY11u/XB02JicAAAAQAAAAAQAAAAEAAAAPAAAAFFB1Ymxpc2hlcnNQdWJsaWNLZXlzAAAAAQAAAAYAAAABjdJYuNKFa2MERRiIm9aQIFWOPYE6VgrY11u/XB02JicAAAAUAAAAAQAAAAYAAAABre/OWa7lKWj3YGHUlMJSW3Vln6QpamX0me8p5WR35JYAAAAUAAAAAQAAAAYAAAABsgQFpBbjMfH+QgBpCeRCp2/i7UW2NoQrX2PWHRxlUQAAAAAQAAAAAQAAAAIAAAAPAAAADENvb3JkaW5hdG9ycwAAABIAAAABjdJYuNKFa2MERRiIm9aQIFWOPYE6VgrY11u/XB02JicAAAABAAAABgAAAAGyBAWkFuMx8f5CAGkJ5EKnb+LtRbY2hCtfY9YdHGVRAAAAABQAAAABAAAABwcJf4Pa47dG2326MmPZzDNO+4ipp9VFD7lsoZ8z0oSwAAAAB4SogBOCjUxPTk9dD6L2hgUNaYiThKBE6rPsSxFp+BDqAAAAB9RkX980QeSaZZvAuP1v5ih+qN9QSGMPKvM0LBdprle4AAAAAwAAAAEAAAAAT3Pag3YeNQ0El1z3YaaUZjWSq+dwMAd4sDE5u95VSLEAAAABVVNEQwAAAAA7mRE4Dv6Yi6CokA6xz+RPNm99vpRr7QdyQPf2JN8VxQAAAAYAAAABjdJYuNKFa2MERRiIm9aQIFWOPYE6VgrY11u/XB02JicAAAAQAAAAAQAAAAIAAAAPAAAABU5vbmNlAAAAAAAAEgAAAAFBgUwZZ2IKmA3461TSfbSuTBNpr0/EeEmNJMtXNtIfAwAAAAEAAAAGAAAAAa3vzlmu5Slo92Bh1JTCUlt1ZZ+kKWpl9JnvKeVkd+SWAAAAEAAAAAEAAAACAAAADwAAAAdCYWxhbmNlAAAAABIAAAABQYFMGWdiCpgN+OtU0n20rkwTaa9PxHhJjSTLVzbSHwMAAAABADqERQAAATAAAAIQAAAAAAAEscA=")
XDR.SorobanTransactionData.decode_xdr(sd)
# raises FunctionClauseError: no function clause matching in XDR.UnionError.exception/1
```

Expected: a `LedgerEntryChange` of type `LEDGER_ENTRY_RESTORED`, and a `SorobanTransactionData` whose ext is v1 with `archived_soroban_entries` `[1]`.

## Evidence for the expected behaviour

- [Stellar-ledger.x L351](https://github.com/stellar/stellar-xdr/blob/v30.0/Stellar-ledger.x#L351): `LEDGER_ENTRY_RESTORED = 4`, with its arm at L364.
- [Stellar-transaction.x L880-L888](https://github.com/stellar/stellar-xdr/blob/v30.0/Stellar-transaction.x#L880-L888): `SorobanTransactionData.ext` is `union switch (int v) { case 0: void; case 1: SorobanResourcesExtV0 resourceExt; }`.
- Both were added to stellar-xdr for protocol 23 (commit 91c3958).
- rs-stellar-xdr 30.0.0 and py-stellar-xdr decode both inputs and round-trip them byte for byte. stellar-core print-xdr decodes the full envelope and shows `resourceExt.archivedSorobanEntries`, and the network applied the transaction.
- In 380 sampled pubnet ledgers, 3 of 44,057 transaction metas fail on `LEDGER_ENTRY_RESTORED` and 3 of 112,278 envelopes fail on the ext (this transaction and two fee bumps).

## Likely cause

- [`lib/xdr/ledger_entries/ledger_entry_change_type.ex` L13-L18](https://github.com/kommitters/stellar_base/blob/v0.17.0/lib/xdr/ledger_entries/ledger_entry_change_type.ex#L13-L18): the declarations end at `LEDGER_ENTRY_STATE: 3`, and `LedgerEntryChange` has no arm for it.
- [`lib/xdr/transactions/soroban_transaction_data.ex` L19-L20](https://github.com/kommitters/stellar_base/blob/v0.17.0/lib/xdr/transactions/soroban_transaction_data.ex#L19-L20): `ext: ExtensionPoint`. There is no `SorobanResourcesExtV0` module.
- The `FunctionClauseError` comes from elixir_xdr: `XDR.UnionError.exception/1` has no clause for `:invalid_arm`.

Suggested fix: regenerate these types from stellar-xdr v23 or later, as kommitters/stellar_sdk#379 asks; this issue names two concrete gaps that 0.17.0 still has.

I found this with an open-source conformance kit (https://github.com/zachsplat/xdr-conformance) that replays pubnet ledgers through several SDKs.
