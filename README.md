# xdr-conformance (proof of concept)

A shared test kit for code that decodes the Stellar ledger: a corpus of rare but valid ledger and transaction shapes, a hostile set judged by stellar-core's own decoder, and a runner that puts every entry through rs-stellar-xdr, go-stellar-sdk, js-stellar-sdk, py-stellar-base and py-stellar-xdr and reports where they differ from the network and from each other.

This is the two-day proof behind an application to the Stellar Community Fund RFP "XDR/CAP-Coverage Audit Tool and Indexer-Hardening Guide". Run on 2026-11-15. Apache-2.0.

## Layout

| path | what |
|---|---|
| `corpus/manifest.schema.json` | draft manifest schema (entry ID, CAPs, protocol version, source, synthetic flag, expected values) |
| `corpus/manifest.json`, `corpus/entries/` | 23 real entries, one per rare shape: 22 from pubnet history (Galexie public data lake), 1 from testnet history |
| `corpus/hostile-manifest.json`, `corpus/hostile/` | 21 entries derived from three real pubnet envelopes, one change each, with stellar-core's verdict |
| `runners/` | one adapter per implementation, same JSONL protocol: `rust/` (also the scanner), `go/`, `js/`, `python/` (both Python libraries), `core/` (stellar-core `print-xdr` as the reference) |
| `tools/` | `fetch_galexie.py`, `pick_corpus.py`, `pick_bases.py`, `mutate.py`, `write_hostile.py`, `diff_results.py`, `lockstep.py`, `check_corpus.py` (the conformance runner) |
| `sweeps/` | nesting-depth sweep, table printer, run-all-adapters script |
| `sightings/` | js-stellar-sdk#1766, #1785, #1789 reproduced on the last tag before each fix and the first after |
| `findings/` | new discrepancies, each with a minimal reproduction and draft issue text |
| `reports/` | `corpus-matrix.md`, `hostile-matrix.md`, `depth-sweep.md`, `raw/` (diff summaries, pool census, ledger hashes, pattern counts) |
| `ci/conformance.yml` | example workflow that gates a pull request on the corpus |
| `run.sh` | rebuilds everything from public data: `fetch`, `build`, `scan`, `replay`, `hostile`, `depth`, `corpus`, `sightings` |

## What was run

| | |
|---|---|
| Ledger sample | 380 pubnet ledgers in five eras: 28,000,000 (protocol 12), 40,000,000 (18), 50,460,000 (20), 59,000,000 (23), 65,486,000 to 65,486,299 (29). Object hashes in `reports/raw/ledger-sample-sha256.txt` |
| Inputs compared | 380 whole `LedgerCloseMetaBatch` files, 112,278 `TransactionEnvelope`s, 44,057 result metas |
| Reference | stellar-core 30.0.0 (0e49751, the build pubnet runs today): `print-xdr` in `stellar/stellar-core:latest`, plus its protocol-28 admission parse (rs-stellar-xdr at depth 1000) for depth |
| Implementations | rs-stellar-xdr 30.0.0, go-stellar-sdk v0.9.0 (xdr, network, txnbuild), js-stellar-sdk 17.4.0, py-stellar-base 17.0.1, py-stellar-xdr 0.2.0 |
| Checks | decodes; re-encodes to the same bytes; transaction hash through each SDK's own model; SEP-51 XDR-JSON equal; Rust's SEP-51 JSON reads back to the same bytes |

## Results on real history

| check | rs-stellar-xdr | go-stellar-sdk | js-stellar-sdk | py-stellar-xdr | py-stellar-base |
|---|---|---|---|---|---|
| 380 ledgers decode and round-trip | yes | yes | yes | yes | not run |
| 112,278 envelopes decode, round-trip, same hash | yes | yes | yes | yes | yes |
| SEP-51 JSON equal to Rust (envelopes / metas / whole ledgers) | reference | no JSON encoder | 0 / 0 / 0 differences | 0 / 0 / 0 differences | 17 envelopes and all 44,057 metas differ (F1) |
| Reads Rust's JSON back to identical bytes | yes | n/a | yes | yes | 17 of 112,278 fail (F1) |

On what the network actually wrote, the decoders agree. The differences live in shapes that history does not contain, so the corpus needs generated entries as well as captured ones.

## The pool census: a shape the old bug kept off pubnet

js-stellar-sdk#1766: JS ordered liquidity-pool assets by issuer strkey text instead of key bytes. For random key pairs the two orders disagree 7.9% of the time. Pubnet has 39,489 liquidity pools; 639 pair two assets with the same code; in none of them do the issuers sort differently as text and as bytes, against about 50 expected by chance. Testnet has 12 such pools out of 13, all created between 2026-11-02 and 2026-11-14. This fits pool-creation tools having been unable to build those pairs while the bug existed in JS (and in Python until py-stellar-base#1247 on 2026-11-05). Either way, a corpus taken only from pubnet would never contain the shape.

## Sightings reproduced (RFP section 6)

| sighting | input | last tag before the fix | first tag after |
|---|---|---|---|
| js-stellar-sdk#1766 | real testnet transaction, ledger 5,521,445 (`corpus/entries/lp-issuers-strkey-vs-bytes-order`) | 17.2.0: `Assets are not in lexicographic order` | 17.2.1: decodes, pool ID matches Horizon |
| js-stellar-sdk#1789 | ScMap with keys u32 1 and symbol "1" | 17.2.1: returns `{"1":20}`, one entry lost | 17.3.0: throws |
| js-stellar-sdk#1785 | muxed account ID `"0x10"` | 17.2.1: accepted, `id()` says "0x10", M-address encodes 16 | 17.3.0: rejected |

## Hostile entries

`reports/hostile-matrix.md`; Rust runs with depth 500 and py-stellar-xdr with `max_depth=500` here.

| variant | stellar-core | who differs |
|---|---|---|
| non-zero padding after memo text | refuses | py-stellar-base accepts (filed by others: py-stellar-base#1262) |
| optional flag = 2 | refuses | py-stellar-base accepts (py-stellar-base#1263) |
| ScVal bool = 2 | accepts, reads TRUE | rs-stellar-xdr reads FALSE (rs-stellar-xdr#622, #629); Go, JS, py-stellar-xdr refuse; py-stellar-base reads True |
| 200 nested ScVal vecs | accepts (and admits) | rs-stellar-xdr at depth 500 and py-stellar-xdr refuse |
| empty signed-payload extra signer | decodes, then validation refuses | py-stellar-xdr refuses at decode (F3, minor) |
| trailing bytes, 29-byte memo, unknown union arm, unknown asset type, 101 operations, count 0xFFFFFFFF with no data, envelope type SCP, 65-byte signed payload, 1000 nested vecs | refuses | none |
| non-UTF-8 memo with a NUL, unsorted ScMap keys, symbol with invalid characters | accepts | none |

## Depth sweep

`reports/depth-sweep.md`, in one real Soroban transaction. stellar-core decodes with xdrpp (`print-xdr`), then, from protocol 28, re-parses every submitted envelope with rs-stellar-xdr at depth 1000 (`validateXDRForProtocol`); the second check decides admission. Largest nesting each decoder accepts with its shipped defaults:

| shape | stellar-core admission | stellar-core print-xdr | rs-stellar-xdr `Limits::none()` | go-stellar-sdk | js-stellar-sdk | py-stellar-base | py-stellar-xdr |
|---|---|---|---|---|---|---|---|
| nested ScVal vecs in a contract argument | 246 | 496 | over 1,000 | 600 to 799 | 334 to 399 | 250 to 299 | **199** |
| nested authorization sub-invocations | 490 | over 600 | over 600 | over 600 | 494 to 499 | 494 to 499 | **198** |

Go and JS are looser than admission (already filed: go-stellar-sdk#6047, js-stellar-sdk#1908). py-stellar-xdr is stricter than admission, so it refuses transactions that can be in a ledger (F2).

## New findings (none filed by anyone as of 2026-11-15)

- **F1** py-stellar-base 17.0.1 SEP-51 JSON: `txsuccess`/`opinner` for `tx_success`/`op_inner`, `from_` for `from`, `AssetCode` as an object, `ContractEvent.contract_id` as hex. Found on pubnet transactions.
- **F2** py-stellar-xdr 0.2.0 default `max_depth=200` refuses authorization trees from 199 levels and ScVal nesting from 200, which stellar-core admits (up to 490 and 246 in the tested transaction). It matters because py-stellar-base draft PR #1268 adopts py-stellar-xdr.
- **F3** (minor) py-stellar-xdr refuses an empty signed-payload signer that core's decoder takes and core's validation then refuses.

Already filed by others and reproduced here: rs-stellar-xdr#622 and #629, py-stellar-base#1262 and #1263, js-stellar-sdk#1901 and #1908, go-stellar-sdk#6047.

## Data lake note

The Galexie lake stores meta for every sampled ledger, protocol 12 and 18 included, as `TransactionMeta` v4 with CAP-67 events: it was regenerated by a newer stellar-core, not captured when those ledgers closed. The manifest records this per entry (`meta_note`).

## Limits

No indexer replay yet (wallet-backend, stellar-etl); Java, Swift, Dart and PHP SDKs not run; hostile variants come from three base transactions; depth thresholds measured in one envelope context; core admission measured by running core's own admission parser settings (rs-stellar-xdr at depth 1000), not by submitting to a local network.

## Reproduce

```
./run.sh build && ./run.sh fetch && ./run.sh scan
./run.sh replay      # the long one: about 160,000 inputs through each implementation
./run.sh hostile && ./run.sh depth && ./run.sh sightings
```

Needs docker (images `rust:1.93-slim`, `golang:1.25-alpine`, `stellar/stellar-core:latest`), Node 24 and Python 3.12 or later. No keys, accounts or funds.
