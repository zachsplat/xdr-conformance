# ClaimableBalanceEntry has "Claimant claimants<10>" (an array). stellar_base
# declares a single "claimant: Claimant", so it reads the array length as the
# ClaimantType discriminant.
Code.eval_file("common.exs", __DIR__)
alias StellarBase.XDR

# ClaimableBalanceEntry created by pubnet tx 40000000:19 (2 claimants, 200 ELON),
# re-encoded by rs-stellar-xdr 30.0.0 (208 bytes).
cb = Base.decode64!("AAAAAGAOzZXB2hbZJXeu2eVyzkE8qroWKfBr6ku3hzURF9MYAAAAAgAAAAAAAAAAYALXX84TRhZtZAGnn4w1PIpDX1PEev3Ls9mMOiI7fnIAAAADAAAAAQAAAAQAAAAAYizz9wAAAAAAAAAA91h+qEXgrJXqRF1nIuWu5CYfGzChnkFG+OOZjZ9kS5IAAAAEAAAAAGI2L+cAAAABRUxPTgAAAACrCOf0lOd1hXDMwIRQJaQwq/0dQKfXrOZksSo32Yci8gAAAASoF8gAAAAAAA==")
R.try_decode("A. real ClaimableBalanceEntry (2 claimants)", fn -> XDR.ClaimableBalanceEntry.decode_xdr(cb) end)
<<_::binary-size(36), n::32, _::binary>> = cb
IO.puts("  the 4 bytes the SDK reads as ClaimantType are the claimants array length: #{n}")
