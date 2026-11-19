TITLE: LiquidityPoolEntry fields are declared in the wrong order, so any meta with a liquidity pool entry fails to decode

## What happens

`StellarBase.XDR.LiquidityPoolEntry` declares `body` before `liquidity_pool_id`. The XDR has the pool id first. `XDR.Struct` decodes in declaration order, so the first 4 bytes of the pool id are read as the `LiquidityPoolType` discriminant and decoding raises `XDR.EnumError`. Every transaction meta that contains a liquidity pool ledger entry fails to decode.

## Reproduction

stellar_base 0.17.0 (Hex), elixir_xdr 0.3.11, Elixir 1.18.6 / OTP 28. The input is the `LiquidityPoolEntry` of pool `LAFEERBXA3KBSOZQXS5XZXDHGBQEJHBJYCLNV7QZ6PI4CHEYPVXTKAHA` (AMM / yUSDC) from the meta of pubnet transaction `bd20cb31fcb246fb5885a5d7bda1416b923474c727c3c448b9e46bbf200184d0` (ledger 40000000), 148 bytes.

```elixir
Mix.install([{:stellar_base, "== 0.17.0"}])
alias StellarBase.XDR

lp = Base.decode64!("CkJENwbUGTswvLt83GcwYEScKcCW2v4Z89HBHJh9bzUAAAAAAAAAAUFNTQAAAAAAIw+7qXhHoY6kKXOl1sf/w4kL6vxYZH7dMuNZWefIWmAAAAACeVVTREMAAAAAAAAAAAAAAM062kzjDS5P+fW5F9nCOTSPRGUSC5NLY3A9tdoTi3LZAAAAHgAAAAsZ3jlhAAAAAAUuo+sAAAAAdLhWNgAAAAAAAAAP")
XDR.LiquidityPoolEntry.decode_xdr(lp)
# raises XDR.EnumError: The key which you try to encode doesn't belong to the current declarations

# Move the 32-byte pool id from the front to the back and it decodes:
swapped = binary_part(lp, 32, byte_size(lp) - 32) <> binary_part(lp, 0, 32)
{:ok, {_entry, ""}} = XDR.LiquidityPoolEntry.decode_xdr(swapped)
```

Expected: the original 148 bytes decode, with `liquidity_pool_id` `0a42443706d4193b...`.

## Evidence for the expected behaviour

- [Stellar-ledger-entries.x L464-L466](https://github.com/stellar/stellar-xdr/blob/v30.0/Stellar-ledger-entries.x#L464-L466): `struct LiquidityPoolEntry { PoolID liquidityPoolID; union switch (LiquidityPoolType type) { ... } body; }`.
- rs-stellar-xdr 30.0.0 and py-stellar-xdr decode the 148 bytes and round-trip them byte for byte.
- In 380 sampled pubnet ledgers, 4,635 of 44,057 transaction metas fail at this point (`LiquidityPoolEntryBody > LiquidityPoolType`). Liquidity pools exist since protocol 18, so this affects every era after that.

## Likely cause

[`lib/xdr/ledger_entries/liquidity_pool_entry.ex` L10](https://github.com/kommitters/stellar_base/blob/v0.17.0/lib/xdr/ledger_entries/liquidity_pool_entry.ex#L10): `XDR.Struct.new(body: LiquidityPoolEntryBody, liquidity_pool_id: PoolID)`.

Suggested fix: declare `liquidity_pool_id: PoolID` first, then `body`, in the struct spec and in `encode_xdr`/`decode_xdr`.

I found this with an open-source conformance kit (https://github.com/zachsplat/xdr-conformance) that replays pubnet ledgers through several SDKs.
