# decode_xdr/1 is declared (XDR.Declaration) to return {:ok, ...} or
# {:error, reason}. On malformed input it raises instead, for some inputs, and
# returns {:error, ...} for others.
Code.eval_file("common.exs", __DIR__)
alias StellarBase.XDR

R.try_decode("A. Memo with discriminant 5", fn -> XDR.Memo.decode_xdr(<<0, 0, 0, 5>>) end)
R.try_decode("B. TransactionEnvelope with discriminant 1 (SCP)", fn -> XDR.TransactionEnvelope.decode_xdr(<<0, 0, 0, 1>>) end)
R.try_decode("C. OptionalMuxedAccount with flag 2", fn -> XDR.OptionalMuxedAccount.decode_xdr(<<0, 0, 0, 2>>) end)
R.try_decode("D. TransactionEnvelope, 3 bytes", fn -> XDR.TransactionEnvelope.decode_xdr(<<0, 0, 0>>) end)
