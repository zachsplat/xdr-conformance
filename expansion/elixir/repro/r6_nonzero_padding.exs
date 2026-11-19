# XDR padding must be zero (RFC 4506 4.9 to 4.11); stellar-core and
# rs-stellar-xdr refuse non-zero padding. stellar_base accepts it and
# re-encodes to different bytes, so two different envelopes decode to the same
# value and get the same transaction hash through the SDK's structs.
Code.eval_file("common.exs", __DIR__)
alias StellarBase.XDR

ok = <<0, 0, 0, 1, 0, 0, 0, 5, "10498", 0, 0, 0>>
bad = <<0, 0, 0, 1, 0, 0, 0, 5, "10498", 1, 0, 0>>
{:ok, {m1, ""}} = XDR.Memo.decode_xdr(ok)
{:ok, {m2, ""}} = XDR.Memo.decode_xdr(bad)
{:ok, back} = XDR.Memo.encode_xdr(m2)
IO.puts("A. memo text with padding 01 00 00 decodes: #{inspect(m2.value.value)}")
IO.puts("  same value as the zero-padded memo: #{m1 == m2}")
IO.puts("  re-encodes to the input bytes: #{back == bad} (re-encoded #{Base.encode16(back)})")
