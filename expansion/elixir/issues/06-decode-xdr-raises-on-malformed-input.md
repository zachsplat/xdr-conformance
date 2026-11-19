TITLE: decode_xdr/1 raises on malformed input instead of returning {:error, reason}

## What happens

`XDR.Declaration` documents `decode_xdr` as returning `{:ok, ...}` or `{:error, reason}`, with `decode_xdr!` as the raising variant. On malformed input, `decode_xdr` of a union or struct mostly raises instead, and for some inputs it raises `FunctionClauseError` rather than an XDR error. The same function returns `{:error, ...}` for some bad inputs and raises for others.

This is low severity and about the API contract, not about which inputs are rejected: the rejections themselves are correct. What breaks for a user is code that pattern-matches `{:error, _}` on untrusted input (an indexer or a service that decodes submitted envelopes). It crashes instead of handling the error.

## Reproduction

elixir_xdr 0.3.11 (Hex, latest) through stellar_base 0.17.0, Elixir 1.18.6 / OTP 28.

```elixir
Mix.install([{:stellar_base, "== 0.17.0"}])
alias StellarBase.XDR

XDR.Memo.decode_xdr(<<0, 0, 0, 5>>)                  # Memo discriminant 5
XDR.TransactionEnvelope.decode_xdr(<<0, 0, 0, 1>>)   # envelope type 1 (SCP)
XDR.OptionalMuxedAccount.decode_xdr(<<0, 0, 0, 2>>)  # optional flag 2
XDR.TransactionEnvelope.decode_xdr(<<0, 0, 0>>)      # 3 bytes
```

Observed (each call run on its own):

```
Memo, discriminant 5          raises XDR.EnumError
TransactionEnvelope, type 1   {:error, :invalid_arm}
OptionalMuxedAccount, flag 2  raises XDR.EnumError
TransactionEnvelope, 3 bytes  raises FunctionClauseError (no function clause matching in XDR.Int.decode_xdr/2)
```

Expected: `{:error, reason}` from all four.

## Evidence for the expected behaviour

The `XDR.Declaration` behaviour, which stellar_base modules implement with `@behaviour`/`@impl`, specs `decode_xdr` as `{:ok, ...} | {:error, atom()}`, and the elixir_xdr docs describe the tuple form. The second call above shows that form already works in some cases.

## Likely cause

- `XDR.Union` decodes the discriminant with the raising `decode_xdr!` ([`lib/xdr/union.ex` L103 and L108](https://github.com/kommitters/elixir_xdr/blob/v0.3.11/lib/xdr/union.ex#L103-L108)) and the arm with `decode_xdr!` (L158), so an `EnumError` escapes `decode_xdr/2`.
- `XDR.Int.decode_xdr/2` ([`lib/xdr/int.ex` L53-L56](https://github.com/kommitters/elixir_xdr/blob/v0.3.11/lib/xdr/int.ex#L53-L56)) has no clause for a binary shorter than 4 bytes.
- `XDR.UnionError.exception/1` ([`lib/xdr/error.ex` L454](https://github.com/kommitters/elixir_xdr/blob/v0.3.11/lib/xdr/error.ex#L454)) has no clause for `:invalid_arm`, so a `decode_xdr!` that hits an unknown arm raises `FunctionClauseError` instead of `XDR.UnionError`. stellar_base 0.17.0 hits this on real pubnet transactions that use `SorobanTransactionData` ext v1 (I am reporting that missing type to stellar_base separately).

Suggested fix: have `decode_xdr/2` in `Union`, `Struct` and the other composite types call the non-raising `decode_xdr` of their parts and return the first `{:error, reason}`; add a short-input clause to the integer types and an `:invalid_arm` clause to `UnionError`.

I found this with an open-source conformance kit (https://github.com/zachsplat/xdr-conformance) that replays pubnet ledgers through several SDKs.
