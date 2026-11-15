| input | stellar-core | rs-stellar-xdr | go-stellar-sdk | js-stellar-sdk | py-stellar-base | py-stellar-xdr |
|---|---|---|---|---|---|---|
| `hostile/cls/baseline` | ok | ok | ok | ok | ok | ok |
| `hostile/cls/memo_text_nonzero_padding` **diverges** | REJ | REJ | REJ | REJ | ok* | REJ |
| `hostile/cls/optional_flag_2` **diverges** | REJ | REJ | REJ | REJ | ok* | REJ |
| `hostile/cls/trailing_bytes` | REJ | REJ | REJ | REJ | REJ | REJ |
| `hostile/cls/memo_text_len_29` | REJ | REJ | REJ | REJ | REJ | REJ |
| `hostile/cls/memo_type_unknown` | REJ | REJ | REJ | REJ | REJ | REJ |
| `hostile/cls/envelope_type_scp` | REJ | REJ | REJ | REJ | REJ | REJ |
| `hostile/cls/asset_type_unknown` | REJ | REJ | REJ | REJ | REJ | REJ |
| `hostile/cls/operations_101` | REJ | REJ | REJ | REJ | REJ | REJ |
| `hostile/cls/operations_count_huge_truncated` | REJ | REJ | REJ | REJ | REJ | REJ |
| `hostile/cls/memo_text_non_utf8_nul` | ok | ok | ok | ok | ok | ok |
| `hostile/sor/baseline` | ok | ok | ok | ok | ok | ok |
| `hostile/sor/scval_bool_2` **diverges** | ok | ok* | REJ | REJ | ok* | REJ |
| `hostile/sor/scval_nested_vec_90` | ok | ok | ok | ok | ok | ok |
| `hostile/sor/scval_nested_vec_200` **diverges** | ok | REJ | ok | ok | ok | REJ |
| `hostile/sor/scval_nested_vec_1000` | REJ | REJ | REJ | REJ | REJ | REJ |
| `hostile/sor/scmap_unsorted_keys` | ok | ok | ok | ok | ok | ok |
| `hostile/sor/scsymbol_invalid_chars` | ok | ok | ok | ok | ok | ok |
| `hostile/ext/baseline` | ok | ok | ok | ok | ok | ok |
| `hostile/ext/signed_payload_len_65` | REJ | REJ | REJ | REJ | REJ | REJ |
| `hostile/ext/signed_payload_len_0` **diverges** | ok | ok | ok | ok | ok | REJ |
