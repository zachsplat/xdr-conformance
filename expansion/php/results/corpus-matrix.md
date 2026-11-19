| entry | stellar-php-sdk |
|---|---|
| `tx-v0-envelope` | pass |
| `fee-bump` | pass |
| `muxed-destination` | pass |
| `muxed-source` | pass |
| `muxed-merge-destination` | pass |
| `signed-payload-extra-signer` | pass |
| `precond-min-seq-num` | pass |
| `memo-text-not-utf8` | pass |
| `memo-text-max-len` | pass |
| `operations-max-100` | pass |
| `path-max-len-5` | pass |
| `auth-tree-nested` | pass |
| `claimable-balance-create` | pass |
| `clawback` | pass |
| `set-trust-line-flags` | pass |
| `liquidity-pool-deposit` | pass |
| `sponsorship-sandwich` | pass |
| `extend-footprint-ttl` | pass |
| `allow-trust-asset-code` | pass |
| `scval-u256` | pass |
| `meta-event-lp-address` | pass |
| `meta-event-claimable-balance-address` | pass |
| `lp-issuers-strkey-vs-bytes-order` | pass |
| `hostile-cls-baseline` | pass |
| `hostile-cls-memo_text_nonzero_padding` | **accepts (core refuses)** |
| `hostile-cls-optional_flag_2` | pass |
| `hostile-cls-trailing_bytes` | **accepts (core refuses)** |
| `hostile-cls-memo_text_len_29` | **accepts (core refuses)** |
| `hostile-cls-memo_type_unknown` | pass |
| `hostile-cls-envelope_type_scp` | pass |
| `hostile-cls-asset_type_unknown` | pass |
| `hostile-cls-operations_101` | **accepts (core refuses)** |
| `hostile-cls-operations_count_huge_truncated` | pass |
| `hostile-cls-memo_text_non_utf8_nul` | pass |
| `hostile-sor-baseline` | pass |
| `hostile-sor-scval_bool_2` | **refuses (core accepts)** |
| `hostile-sor-scval_nested_vec_90` | pass |
| `hostile-sor-scval_nested_vec_200` | pass |
| `hostile-sor-scval_nested_vec_1000` | pass |
| `hostile-sor-scmap_unsorted_keys` | pass |
| `hostile-sor-scsymbol_invalid_chars` | pass |
| `hostile-ext-baseline` | pass |
| `hostile-ext-signed_payload_len_65` | **accepts (core refuses)** |
| `hostile-ext-signed_payload_len_0` | pass |
