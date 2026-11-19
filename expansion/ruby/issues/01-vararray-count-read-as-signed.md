TITLE: VarArray reads the element count as a signed int, so a count of 2^31 or more decodes as an empty array

## What happens

`XDR::VarArray#read` reads the count with `XDR::Int.read`, which is signed. A count from `0x80000000` to `0xFFFFFFFF` comes out negative, passes the `length > @length` check, and `length.times.map` returns `[]`. So input that declares a huge array and has no elements decodes without an error as an empty array, and re-encodes to different bytes.

Impact is low: stellar-core rejects these bytes, so they never come from a ledger. It matters for code that decodes untrusted XDR and relies on the decoder to reject malformed input (signers, SEP-10 servers, anything that hashes or stores the bytes after decoding). In stellar-base this applies to every bounded array in the schema, for example `operations<100>` and `signatures<20>`.

## Reproduction

xdr 3.0.3 (latest) with stellar-base 0.32.0 (latest), Ruby 3.3.

```ruby
require "stellar-base"

# 1. The bare gem: count 0x80000000, max 20, no elements.
p XDR::VarArray[XDR::Int, 20].from_xdr("\x80\x00\x00\x00".b)

# 2. Pubnet envelope 4adfa3a9... (ledger 40000001) with the operations<100>
#    count set to 0x80000000 and its one operation removed.
b64 = "AAAAAgAAAABSTh04F5yGRuzDsfhzZtQUhnLaHgY4Bf9HZXhQw+kkTwADDUABIfX+AAmFkwAAAAAAAAABAAAABTEwNDk4AAAAgAAAAAAAAAAAAAABw+kkTwAAAEB3D1mhdKqqIGQQTvIQLolGTKX5RVwtvTGas+ajdcSq230TY3Qde0xkeTz2iJ1poGBx5wcayK5i3lOqdEfMB28A"
raw = Base64.strict_decode64(b64)
env = Stellar::TransactionEnvelope.from_xdr(raw)
puts "operations=#{env.tx.operations.length} signatures=#{env.signatures.length}"
puts "re-encodes to the same bytes: #{env.to_xdr == raw}"
Stellar.on_network(Stellar::Networks::PUBLIC) { puts env.tx.hash.unpack1("H*") }
```

Observed:

```
[]
operations=0 signatures=1
re-encodes to the same bytes: false
27728efb0c727bf89f5367d5f5dd8e962ced2df67faf3cc553c2219c999f7d53
```

The same happens for `signatures<20>`: with the count set to `0x80000000` and the signature removed, the envelope decodes with no signatures. A count of `0xFFFFFFFF` gives `[]` as well.

Expected: `XDR::ReadError`, the same error this code raises for a count of 101 against `operations<100>`.

## Evidence for the expected behaviour

- RFC 4506 section 4.13: the element count of a variable-length array is an unsigned integer. The gem's own `XDR::MAX_SIZE` is 4294967295.
- On all four probes (both arrays, counts `0x80000000` and `0xFFFFFFFF`): stellar-core 30.0.0 print-xdr rejects with `xvector overflow`, rs-stellar-xdr 30.0.0 with `xdr value max length exceeded`, and go-stellar-sdk with `data size (2147483648) exceeds size limit (100)` (and the matching message for the other three). stellar-base 0.32.0 accepts all four.
- The base envelope is the real pubnet transaction `4adfa3a9189ba0c41c9407be284cb84cc7aa8f7844aea4e238f317627bb5b204`; only the count and the removed element differ.

## Likely cause

[`lib/xdr/var_array.rb` L25-L33](https://github.com/astroband/ruby-xdr/blob/v3.0.3/lib/xdr/var_array.rb#L25-L33): `length = XDR::Int.read(io)`, and `XDR::Int.read` unpacks with `"l>"` (signed). The same line is on `main`. `XDR::String` and `XDR::VarOpaque` read their length the same way, but there a negative length makes `io.read` raise, so only arrays decode silently.

Suggested fix: read the count with `XDR::UnsignedInt.read(io)` in `VarArray`, `VarOpaque` and `String`.

I found this with an open-source conformance kit (https://github.com/zachsplat/xdr-conformance) that replays pubnet ledgers through several SDKs.
