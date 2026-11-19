TITLE: ClaimableBalanceEntry reads claimants<10> as a single Claimant, so every claimable balance entry fails to decode

## What happens

`StellarBase.XDR.ClaimableBalanceEntry` declares `claimant: Claimant`, but the XDR field is an array, `Claimant claimants<10>`. The decoder reads the array length as the `ClaimantType` discriminant. The only valid `ClaimantType` is 0 and an entry has at least one claimant, so every real claimable balance entry raises `XDR.EnumError`, and so does every transaction meta that contains one.

## Reproduction

stellar_base 0.17.0 (Hex), elixir_xdr 0.3.11, Elixir 1.18.6 / OTP 28. The input is the `ClaimableBalanceEntry` created by pubnet transaction `9dd5d4654f0adf705b49d67104ef75c130920bb856a0da6c3ff9c1e9c5492b94` (ledger 40000000): 200 ELON, 2 claimants, 208 bytes.

```elixir
Mix.install([{:stellar_base, "== 0.17.0"}])
alias StellarBase.XDR

cb = Base.decode64!("AAAAAGAOzZXB2hbZJXeu2eVyzkE8qroWKfBr6ku3hzURF9MYAAAAAgAAAAAAAAAAYALXX84TRhZtZAGnn4w1PIpDX1PEev3Ls9mMOiI7fnIAAAADAAAAAQAAAAQAAAAAYizz9wAAAAAAAAAA91h+qEXgrJXqRF1nIuWu5CYfGzChnkFG+OOZjZ9kS5IAAAAEAAAAAGI2L+cAAAABRUxPTgAAAACrCOf0lOd1hXDMwIRQJaQwq/0dQKfXrOZksSo32Yci8gAAAASoF8gAAAAAAA==")
XDR.ClaimableBalanceEntry.decode_xdr(cb)
# raises XDR.EnumError: The key which you try to encode doesn't belong to the current declarations

<<_::binary-size(36), n::32, _::binary>> = cb
n
# 2  (the claimants array length, which the SDK reads as ClaimantType)
```

Expected: the entry decodes with a list of 2 claimants.

## Evidence for the expected behaviour

- [Stellar-ledger-entries.x L438](https://github.com/stellar/stellar-xdr/blob/v30.0/Stellar-ledger-entries.x#L438): `Claimant claimants<10>;` in `struct ClaimableBalanceEntry`.
- rs-stellar-xdr 30.0.0 and py-stellar-xdr decode the 208 bytes with 2 claimants and round-trip them byte for byte.
- In 380 sampled pubnet ledgers, 524 of 44,057 transaction metas fail at this point (`Claimant > ClaimantType`).

## Likely cause

[`lib/xdr/ledger_entries/claimable_balance_entry.ex` L9-L15](https://github.com/kommitters/stellar_base/blob/v0.17.0/lib/xdr/ledger_entries/claimable_balance_entry.ex#L9-L15): the struct spec has `claimant: Claimant`.

Suggested fix: declare the field as `claimants: Claimants`, the max-10 array type that `CreateClaimableBalance` already uses (`lib/xdr/ledger_entries/claimants.ex`).

I found this with an open-source conformance kit (https://github.com/zachsplat/xdr-conformance) that replays pubnet ledgers through several SDKs.
