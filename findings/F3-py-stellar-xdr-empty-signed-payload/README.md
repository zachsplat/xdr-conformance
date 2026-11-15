# F3 (minor). py-stellar-xdr 0.2.0 refuses an empty signed-payload signer that stellar-core decodes

Status on 2026-11-15: not filed. Low impact; listed for completeness.

| input | stellar-core 30.0.0 decode | rs-stellar-xdr | go-stellar-sdk | js-stellar-sdk | py-stellar-base | py-stellar-xdr |
|---|---|---|---|---|---|---|
| `hostile-ext-signed_payload_len_0` (corpus/hostile) | accepts | accepts | accepts | accepts | accepts | **refuses** |

The XDR schema says `opaque payload<64>`, so an empty payload is valid XDR, and stellar-core's decoder takes it. stellar-core's validation then refuses it: an empty payload in `PreconditionsV2.extraSigners` is `txMALFORMED` (TransactionFrame.cpp, v30.0.0, lines 1285-1292) and in `SetOptions` it is `SET_OPTIONS_BAD_SIGNER` (SetOptionsOpFrame.cpp, lines 308-315). So such a transaction should never reach a ledger, and the divergence matters only to code that parses transactions before submission. The likely cause is that SEP-23 cannot write an empty payload as a `P...` strkey, which SEP-51 uses for signer keys (see py-stellar-base#1256). Worth one sentence in the guide; probably not worth an issue unless the maintainer wants decode to match core.
