TITLE: Non-zero padding bytes are accepted and dropped on re-encode

## What happens

`XDR.FixedOpaque.decode_xdr/2` skips the padding bytes after an opaque without checking that they are zero. Strings and variable-length opaques go through it, so input with non-zero padding decodes to the same value as the zero-padded input and re-encodes to different bytes. For stellar_base users this means two different envelopes decode to the same value and get the same transaction hash, while stellar-core rejects one of them.

Impact is low: no ledger holds such bytes. It matters for code that checks, stores or hashes untrusted XDR and relies on the decoder to reject malformed input.

## Reproduction

elixir_xdr 0.3.11 (Hex, latest) through stellar_base 0.17.0, Elixir 1.18.6 / OTP 28. A `MEMO_TEXT` "10498" with padding `01 00 00` instead of `00 00 00`.

```elixir
Mix.install([{:stellar_base, "== 0.17.0"}])
alias StellarBase.XDR

ok  = <<0, 0, 0, 1, 0, 0, 0, 5, "10498", 0, 0, 0>>   # AAAAAQAAAAUxMDQ5OAAAAA==
bad = <<0, 0, 0, 1, 0, 0, 0, 5, "10498", 1, 0, 0>>   # AAAAAQAAAAUxMDQ5OAEAAA==
{:ok, {m1, ""}} = XDR.Memo.decode_xdr(ok)
{:ok, {m2, ""}} = XDR.Memo.decode_xdr(bad)
m1 == m2                      # true
XDR.Memo.encode_xdr(m2)       # {:ok, <<0,0,0,1,0,0,0,5,"10498",0,0,0>>}
```

Observed: `bad` decodes, equals the zero-padded memo, and re-encodes to the zero-padded bytes.

Expected: decoding `bad` returns an error.

## Evidence for the expected behaviour

- RFC 4506 sections 4.9 to 4.11: the padding bytes are zero.
- stellar-core 30.0.0 print-xdr rejects a pubnet envelope (ledger 40000001, transaction `4adfa3a9189ba0c41c9407be284cb84cc7aa8f7844aea4e238f317627bb5b204`) whose memo padding byte is set to 1, with `Non-zero padding bytes encountered`. stellar_base accepts that envelope and computes the hash of the unmodified transaction, `4adfa3a9...`.
- rs-stellar-xdr 30.0.0 rejects the memo above with `xdr padding contains non-zero bytes`. go-xdr, js-xdr and py-stellar-xdr reject non-zero padding as well.

## Likely cause

[`lib/xdr/fixed_opaque.ex` L67-L71](https://github.com/kommitters/elixir_xdr/blob/v0.3.11/lib/xdr/fixed_opaque.ex#L67-L71): the binary match `<<fixed_opaque::bytes-size(length), _padding::bytes-size(required_padding), rest::binary>>` discards the padding.

Suggested fix: match the padding against `<<0::size(required_padding * 8)>>` and return an error otherwise.

The same class was fixed in py-stellar-base (StellarCN/py-stellar-base#1262).

I found this with an open-source conformance kit (https://github.com/zachsplat/xdr-conformance) that replays pubnet ledgers through several SDKs.
