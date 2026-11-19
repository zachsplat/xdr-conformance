# Issue drafts (not posted)

Drafted 2026-11-19 from the CONFIRMED verdicts only. Every reproduction was rerun today against the published versions and gave the same output; the snippets in the Dart, .NET and Ruby drafts were run exactly as written. Duplicate check on 2026-11-19 (issues and PRs, open and closed, including those by ErenTopaal and hackcat29): no existing report of any of these root causes.

| File | Target repo | Title | Status |
|---|---|---|---|
| dart/issues/01-precond-v2-rewritten-as-precond-time.md | Soneso/stellar_flutter_sdk | A PRECOND_V2 with only time bounds set is re-encoded as PRECOND_TIME, so the transaction hash is wrong | ready |
| dart/issues/02-fee-bump-signatures-dropped.md | Soneso/stellar_flutter_sdk | A fee bump parsed with fromEnvelopeXdrString loses its fee-bump signatures | ready |
| dart/issues/03-decoder-accepts-malformed-xdr.md | Soneso/stellar_flutter_sdk | XDR decoding accepts an optional flag of 2, trailing bytes and missing end padding, which stellar-core rejects | ready (C7 + C8 + C9) |
| dotnet/issues/01-ledger-entry-ext-v1-null-sponsor-nre.md | Beans-BV/dotnet-stellar-sdk | LedgerEntryExtensionV1.FromXdr throws NullReferenceException when sponsoringID is absent | ready |
| elixir/issues/01-allow-trust-asset-code.md | kommitters/stellar_base | AllowTrust decodes its asset as an Asset with an issuer instead of an AssetCode, so real AllowTrust transactions fail or misparse | ready |
| elixir/issues/02-liquidity-pool-entry-field-order.md | kommitters/stellar_base | LiquidityPoolEntry fields are declared in the wrong order, so any meta with a liquidity pool entry fails to decode | ready |
| elixir/issues/03-claimable-balance-claimants-array.md | kommitters/stellar_base | ClaimableBalanceEntry reads claimants<10> as a single Claimant, so every claimable balance entry fails to decode | ready |
| elixir/issues/04-protocol-23-xdr-not-supported.md | kommitters/stellar_base | Protocol 23 XDR missing: LEDGER_ENTRY_RESTORED and SorobanTransactionData ext v1 fail to decode | ready (C4 + C5; related tracker kommitters/stellar_sdk#379 is generic and names neither gap) |
| elixir/issues/05-nonzero-padding-accepted.md | kommitters/elixir_xdr | Non-zero padding bytes are accepted and dropped on re-encode | ready (C6; filed against elixir_xdr, where the code is, not stellar_base) |
| elixir/issues/06-decode-xdr-raises-on-malformed-input.md | kommitters/elixir_xdr | decode_xdr/1 raises on malformed input instead of returning {:error, reason} | ready (C7; filed against elixir_xdr, where the code is; low severity) |
| ruby/issues/01-vararray-count-read-as-signed.md | astroband/ruby-xdr | VarArray reads the element count as a signed int, so a count of 2^31 or more decodes as an empty array | ready (the xdr gem's rubygems source_code_uri and bug_tracker_uri point to astroband/ruby-xdr; stellar/ruby-xdr redirects there; not archived, issues enabled) |

Skipped: none of the confirmed candidates.

Not drafted because their verdict was not CONFIRMED: dart C1, C3, C4, C6 (DUPLICATE of #296, #297, #297, #291), dart C10 (REFUTED); dotnet D1 to D8 (DUPLICATE); all java and php candidates (DUPLICATE).
