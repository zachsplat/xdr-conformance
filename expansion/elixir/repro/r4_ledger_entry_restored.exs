# LedgerEntryChangeType gained LEDGER_ENTRY_RESTORED = 4 in protocol 23
# (CAP-66). stellar_base 0.17.0 says it supports protocol 23 (it has
# TransactionMetaV4) but its enum stops at LEDGER_ENTRY_STATE = 3.
Code.eval_file("common.exs", __DIR__)
alias StellarBase.XDR

# A "restored" TTL change from the result meta of pubnet tx 65486053:349
# (protocol 29), re-encoded by rs-stellar-xdr 30.0.0 (52 bytes).
ch = Base.decode64!("AAAABAPnPOUAAAAJvB7uPkn7hr+4aZvWxO2uYZHlIQT6L1YLa7AMxkxOo2EEBuDkAAAAAA==")
R.try_decode("A. real LedgerEntryChange (restored)", fn -> XDR.LedgerEntryChange.decode_xdr(ch) end)
