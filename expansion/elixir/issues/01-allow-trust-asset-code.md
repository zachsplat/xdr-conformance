TITLE: AllowTrust decodes its asset as an Asset with an issuer instead of an AssetCode, so real AllowTrust transactions fail or misparse

## What happens

`StellarBase.XDR.Operations.AllowTrust` declares its second field as `asset_code: Asset`, but in the XDR the field is an `AssetCode`, which has no issuer. The decoder reads 36 bytes too many. Every real AllowTrust operation either fails to decode or, when enough bytes follow it, decodes "successfully" with an issuer and an `authorize` value taken from the next operation. The same layout is used for encoding, so an AllowTrust built with stellar_base is not what the network expects.

## Reproduction

stellar_base 0.17.0 (Hex), elixir_xdr 0.3.11, Elixir 1.18.6 / OTP 28. The input is the 48-byte `AllowTrustOp` of operation 0 of pubnet transaction `c27ee075895e9b682862aadd0a5abb6200a6e08e63dada5c988943aaf0bdf9a4` (ledger 50460006): trustor `GDABKBZ5XUWWTGVSXWHWJC7BVXZWPEJAOTNXGJNSILR6XCI5LCFDR4OQ`, asset code `FIL`, authorize 0.

```elixir
Mix.install([{:stellar_base, "== 0.17.0"}])
alias StellarBase.XDR

op = Base.decode64!("AAAAAMAVBz29LWmasr2PZIvhrfNnkSB023MlskLj64kdWIo4AAAAAUZJTAAAAAAA")
XDR.Operations.AllowTrust.decode_xdr(op)
# raises XDR.FixedOpaqueError: The length is bigger than the byte size of the XDR

# The same 48 bytes followed by the next 36 bytes of the real envelope
# (the start of the following Clawback operation):
next36 = Base.decode16!("00000000000000130000000146494C0000000000190BB50BD22BFC576640606EFA22480D")
{:ok, {v, ""}} = XDR.Operations.AllowTrust.decode_xdr(op <> next36)
# decodes, with issuer GAAAAAAAAAAAAEYAAAAACRSJJQAAAAAAAAMQXNIL2IV7YV3GIBQG42L3
# (bytes of the next operation) and authorize 4196550669 (the real value is 0)
```

Decoding the whole envelope of that transaction (`XDR.TransactionEnvelope.decode_xdr/1`, 576 bytes) raises `XDR.EnumError`.

Expected: the op decodes as trustor, asset code `FIL` (`ASSET_TYPE_CREDIT_ALPHANUM4`) and authorize 0, consuming exactly 48 bytes.

## Evidence for the expected behaviour

- [Stellar-transaction.x L271-L278](https://github.com/stellar/stellar-xdr/blob/v30.0/Stellar-transaction.x#L271-L278): `struct AllowTrustOp { AccountID trustor; AssetCode asset; uint32 authorize; }`. `AssetCode` is a union of a 4-byte or 12-byte code with no issuer.
- rs-stellar-xdr 30.0.0 decodes the 48-byte op (and the same op with authorize 1) and round-trips it byte for byte. stellar-core print-xdr and py-stellar-xdr decode the full envelope; core shows the asset as `{type, assetCode4}` with no issuer.
- In 380 sampled pubnet ledgers (112,278 envelopes), all 16 envelopes that contain an AllowTrust operation fail to decode.

## Likely cause

[`lib/xdr/transactions/operations/allow_trust.ex` L9](https://github.com/kommitters/stellar_base/blob/v0.17.0/lib/xdr/transactions/operations/allow_trust.ex#L9): `XDR.Struct.new(trustor: AccountID, asset_code: Asset, authorize: UInt32)`. `StellarBase.XDR.AssetCode` exists but is not used here.

Suggested fix: declare the field as `AssetCode` (and update `new/3` and the tests, which encode the same wrong layout).

I found this with an open-source conformance kit (https://github.com/zachsplat/xdr-conformance) that replays pubnet ledgers through several SDKs.
