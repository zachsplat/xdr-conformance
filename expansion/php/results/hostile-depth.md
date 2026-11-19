## Hostile set (21)

| input | stellar-core print-xdr | rs-stellar-xdr 30.0.0 | stellar-php-sdk 1.18.0 | SDK main 0fb4246 |
|---|---|---|---|---|
| `hostile/cls/baseline` | accept | ok | ok | ok |
| `hostile/cls/memo_text_nonzero_padding` | reject | REJ | ok, bytes change | ok, bytes change |
| `hostile/cls/optional_flag_2` | reject | REJ | REJ (XdrOperation.sourceAccount presence flag must be 0 or 1, got 2) | REJ (XdrOperation.sourceAccount presence flag must be 0 or 1, got 2) |
| `hostile/cls/trailing_bytes` | reject | REJ | ok, bytes change | REJ (Soneso\StellarSDK\Xdr\XdrTransactionEnvelope leaves 4 of 252 bytes unr) |
| `hostile/cls/memo_text_len_29` | reject | REJ | ok | REJ (maxLength of 28 exceeded (string is 29 bytes)) |
| `hostile/cls/memo_type_unknown` | reject | REJ | REJ (Unknown enum value: 5) | REJ (Unknown enum value: 5) |
| `hostile/cls/envelope_type_scp` | reject | REJ | REJ (Unknown XdrTransactionEnvelope discriminant: 1) | REJ (Unknown XdrTransactionEnvelope discriminant: 1) |
| `hostile/cls/asset_type_unknown` | reject | REJ | REJ (Unknown enum value: 4) | REJ (Unknown enum value: 4) |
| `hostile/cls/operations_101` | reject | REJ | ok | REJ (XDR array count 101 exceeds the declared maximum of 100) |
| `hostile/cls/operations_count_huge_truncated` | reject | REJ | REJ (XDR array count cannot be negative, got -1) | REJ (XDR array count cannot be negative, got -1) |
| `hostile/cls/memo_text_non_utf8_nul` | accept | ok | ok | ok |
| `hostile/sor/baseline` | accept | ok | ok | ok |
| `hostile/sor/scval_bool_2` | accept | ok, bytes change | REJ (Unexpected XDR for a boolean value) | REJ (Unexpected XDR for a boolean value) |
| `hostile/sor/scval_nested_vec_90` | accept | ok | ok | ok |
| `hostile/sor/scval_nested_vec_200` | accept | REJ | ok | ok |
| `hostile/sor/scval_nested_vec_1000` | reject | REJ | REJ (XDR decode recursion limit (500) exceeded) | REJ (XDR decode recursion limit (500) exceeded) |
| `hostile/sor/scmap_unsorted_keys` | accept | ok | ok | ok |
| `hostile/sor/scsymbol_invalid_chars` | accept | ok | ok | ok |
| `hostile/ext/baseline` | accept | ok | ok | ok |
| `hostile/ext/signed_payload_len_65` | reject | REJ | ok, toJson throws: Signed payload length 65 exceeds the maximum of 64 bytes (XD | REJ (length of 65 exceeds max length of 64) |
| `hostile/ext/signed_payload_len_0` | accept | ok | ok, toJson throws: Zero-length signed payload has no SEP-23 strkey representati | ok, toJson throws: Zero-length signed payload has no SEP-23 strkey representati |

## Depth set (37)

| input | stellar-core admission | stellar-core print-xdr | stellar-php-sdk 1.18.0 |
|---|---|---|---|
| `depth/10` | ok | ok | ok |
| `depth/50` | ok | ok | ok |
| `depth/90` | ok | ok | ok |
| `depth/100` | ok | ok | ok |
| `depth/120` | ok | ok | ok |
| `depth/150` | ok | ok | ok |
| `depth/170` | ok | ok | ok |
| `depth/199` | ok | ok | ok |
| `depth/200` | ok | ok | ok |
| `depth/246` | ok | ok | ok |
| `depth/247` | REJ | ok | ok |
| `depth/250` | REJ | ok | ok |
| `depth/300` | REJ | ok | ok, toJson throws: Maximum stack depth exceeded |
| `depth/334` | REJ | ok | ok, toJson throws: Maximum stack depth exceeded |
| `depth/400` | REJ | ok | ok, toJson throws: Maximum stack depth exceeded |
| `depth/450` | REJ | ok | ok, toJson throws: Maximum stack depth exceeded |
| `depth/496` | REJ | ok | ok, toJson throws: Maximum stack depth exceeded |
| `depth/497` | REJ | REJ | ok, toJson throws: Maximum stack depth exceeded |
| `depth/500` | REJ | REJ | REJ (XDR decode recursion limit (500) exceeded) |
| `depth/600` | REJ | REJ | REJ (XDR decode recursion limit (500) exceeded) |
| `depth/800` | REJ | REJ | REJ (XDR decode recursion limit (500) exceeded) |
| `depth/1000` | REJ | REJ | REJ (XDR decode recursion limit (500) exceeded) |
| `auth/50` | ok | ok | ok |
| `auth/100` | ok | ok | ok |
| `auth/150` | ok | ok | ok |
| `auth/198` | ok | ok | ok |
| `auth/199` | ok | ok | ok |
| `auth/200` | ok | ok | ok |
| `auth/250` | ok | ok | ok, toJson throws: Maximum stack depth exceeded |
| `auth/300` | ok | ok | ok, toJson throws: Maximum stack depth exceeded |
| `auth/400` | ok | ok | ok, toJson throws: Maximum stack depth exceeded |
| `auth/490` | ok | ok | ok, toJson throws: Maximum stack depth exceeded |
| `auth/491` | REJ | ok | ok, toJson throws: Maximum stack depth exceeded |
| `auth/493` | REJ | ok | ok, toJson throws: Maximum stack depth exceeded |
| `auth/494` | REJ | ok | ok, toJson throws: Maximum stack depth exceeded |
| `auth/500` | REJ | ok | REJ (XDR decode recursion limit (500) exceeded) |
| `auth/600` | REJ | ok | REJ (XDR decode recursion limit (500) exceeded) |
