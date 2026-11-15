| entry | rs-stellar-xdr | go-stellar-sdk | js-stellar-sdk | py-stellar-base | py-stellar-xdr |
|---|---|---|---|---|---|
| `tx-v0-envelope` | pass | pass | pass | pass | pass |
| `fee-bump` | pass | pass | pass | pass | pass |
| `muxed-destination` | pass | pass | pass | pass | pass |
| `muxed-source` | pass | pass | pass | pass | pass |
| `muxed-merge-destination` | pass | pass | pass | pass | pass |
| `signed-payload-extra-signer` | pass | pass | pass | pass | pass |
| `precond-min-seq-num` | pass | pass | pass | pass | pass |
| `memo-text-not-utf8` | pass | pass | pass | pass | pass |
| `memo-text-max-len` | pass | pass | pass | pass | pass |
| `operations-max-100` | pass | pass | pass | pass | pass |
| `path-max-len-5` | pass | pass | pass | pass | pass |
| `auth-tree-nested` | pass | pass | pass | pass | pass |
| `claimable-balance-create` | pass | pass | pass | pass | pass |
| `clawback` | pass | pass | pass | JSON differs at asset | pass |
| `set-trust-line-flags` | pass | pass | pass | pass | pass |
| `liquidity-pool-deposit` | pass | pass | pass | pass | pass |
| `sponsorship-sandwich` | pass | pass | pass | pass | pass |
| `extend-footprint-ttl` | pass | pass | pass | pass | pass |
| `allow-trust-asset-code` | pass | pass | pass | JSON differs at asset | pass |
| `scval-u256` | pass | pass | pass | pass | pass |
| `meta-event-lp-address` | pass | pass | pass | pass | pass |
| `meta-event-claimable-balance-address` | pass | pass | pass | pass | pass |
| `lp-issuers-strkey-vs-bytes-order` | pass | pass | pass | pass | pass |
| `hostile-cls-baseline` | pass | pass | pass | pass | pass |
| `hostile-cls-memo_text_nonzero_padding` | pass | pass | pass | accepts (core refuses) | pass |
| `hostile-cls-optional_flag_2` | pass | pass | pass | accepts (core refuses) | pass |
| `hostile-cls-trailing_bytes` | pass | pass | pass | pass | pass |
| `hostile-cls-memo_text_len_29` | pass | pass | pass | pass | pass |
| `hostile-cls-memo_type_unknown` | pass | pass | pass | pass | pass |
| `hostile-cls-envelope_type_scp` | pass | pass | pass | pass | pass |
| `hostile-cls-asset_type_unknown` | pass | pass | pass | pass | pass |
| `hostile-cls-operations_101` | pass | pass | pass | pass | pass |
| `hostile-cls-operations_count_huge_truncated` | pass | pass | pass | pass | pass |
| `hostile-cls-memo_text_non_utf8_nul` | pass | pass | pass | pass | pass |
| `hostile-sor-baseline` | pass | pass | pass | pass | pass |
| `hostile-sor-scval_bool_2` | accepts, re-encodes to other bytes | refuses (core accepts) | refuses (core accepts) | accepts, re-encodes to other bytes | refuses (core accepts) |
| `hostile-sor-scval_nested_vec_90` | pass | pass | pass | pass | pass |
| `hostile-sor-scval_nested_vec_200` | refuses (core accepts) | pass | pass | pass | refuses (core accepts) |
| `hostile-sor-scval_nested_vec_1000` | pass | pass | pass | pass | pass |
| `hostile-sor-scmap_unsorted_keys` | pass | pass | pass | pass | pass |
| `hostile-sor-scsymbol_invalid_chars` | pass | pass | pass | pass | pass |
| `hostile-ext-baseline` | pass | pass | pass | pass | pass |
| `hostile-ext-signed_payload_len_65` | pass | pass | pass | pass | pass |
| `hostile-ext-signed_payload_len_0` | pass | pass | pass | pass | refuses (core accepts) |
