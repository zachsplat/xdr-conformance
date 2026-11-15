# xdr-conformance (proof of concept)

[![conformance](https://github.com/zachsplat/xdr-conformance/actions/workflows/conformance.yml/badge.svg?branch=master)](https://github.com/zachsplat/xdr-conformance/actions/workflows/conformance.yml?query=branch%3Amaster)

A shared test kit for code that decodes the Stellar ledger: a corpus of rare but valid ledger and transaction shapes, a hostile set judged by stellar-core's own decoder, and a runner that puts every entry through rs-stellar-xdr, go-stellar-sdk, js-stellar-sdk, py-stellar-base and py-stellar-xdr and reports where they differ from the network and from each other.

This is the two-day proof behind my application to the Stellar Community Fund RFP "XDR/CAP-Coverage Audit Tool and Indexer-Hardening Guide". Run on 2026-11-15. Apache-2.0.

## Check it in five minutes

Needs git, Node 24 and Python 3.12 or later. No docker, keys or accounts.

```
git clone https://github.com/zachsplat/xdr-conformance && cd xdr-conformance
./run.sh quick
```

It took 13 seconds on my machine with empty npm and pip caches. Each step compares a fresh run with the output committed here and prints `same as ...` or `DIFFERS`. What you should see:

1. **RFP sightings** on the js-stellar-sdk tags before and after each fix (`sightings/`). 17.2.0: `FAIL Assets are not in lexicographic order` on the real testnet transaction; 17.2.1 and 17.4.0 decode it and compute pool ID `7188b01c...97ec3b`, the one Horizon reports. 17.2.1 returns `{"1":20}` from a two-entry map (#1789) and accepts `"0x10"` as a muxed ID (#1785); 17.3.0 and 17.4.0 throw on both.
2. **The conformance runner** (`tools/check_corpus.py`) on all 44 corpus entries with the two Python adapters, at the versions CI pins: `44 entries x 2 adapters: 7 known findings reproduced, 0 undocumented failures, 0 known findings changed, 0 files with a wrong hash`. Every failing cell matches an entry in `ci/known-findings.json` (F1, F3, py-stellar-base#1262 and #1263, and the recorded bool-2 behaviour). The runner exits 1 on an undocumented failure, on a known finding that stops reproducing, or on a file whose hash differs from the manifest, which is what lets it gate CI.
3. **F1** rerun against py-stellar-base 17.0.1: the four SEP-51 JSON differences, identical to `findings/F1-py-stellar-base-sep51-json/output.txt`.
4. **F2 before and after the upstream fix:** with stellar-xdr 0.2.0 the auth trees of 199, 490 and 491 levels fail with `XdrDepthError: nesting deeper than max_depth=200`; with 0.2.1, released after I reported it, all four decode.

The full rebuild (Rust and Go adapters, stellar-core, the 380 ledgers) needs docker and is under [Reproduce](#reproduce).

## What CI checks

`.github/workflows/conformance.yml` runs on every push to master, on every pull request and on manual dispatch, with every library version pinned. It builds the Rust adapter (rs-stellar-xdr 30.0.0) and the Go adapter (go-stellar-sdk v0.9.0), installs js-stellar-sdk 17.4.0 and the Python libraries, and then:

- checks every corpus file (the XDR and the expected SEP-51 JSON) against the sha256 in its manifest;
- runs all 44 corpus entries through the five adapters against `ci/known-findings.json`: decode, byte round-trip, transaction hash, SEP-51 JSON, and for hostile entries stellar-core's recorded verdict;
- runs the F2 depth entries (`findings/F2-py-stellar-xdr-default-depth/manifest.json`) with each library's shipped defaults, next to stellar-core's admission parse (rs-stellar-xdr at depth 1000), with stellar-xdr 0.2.0 and 0.2.1 as separate columns;
- reruns the three JS sightings and diffs them against the committed transcripts.

A divergence that is not in `ci/known-findings.json` fails the run, and so does a listed one that stops reproducing, so a library upgrade that fixes or breaks something shows up as a red build. stellar-core is not run in CI; its verdicts are recorded in the manifests.

F2 is listed for the 0.2.0 column only. The gating py-stellar-xdr column pins 0.2.1, the first release with the fix, so the 0.2.0 column is there as a before and after and can be dropped. The other listed cells are F1 and F3, py-stellar-base#1262 and #1263, rs-stellar-xdr#622, the bool-2 cells (Go, JS and py-stellar-xdr refuse a bool of 2, stricter than core; py-stellar-base reads it as true, as core does, but re-encodes it as 1; recorded rather than reported), and one setting of this runner (Rust at depth 500 in the corpus run). Versions are pinned in `runners/rust/Cargo.lock`, `runners/go/go.sum`, `sightings/package-lock.json` and `ci/requirements*.txt`; the Rust build and package downloads are cached. Each run's summary page shows the full matrices, and they are attached to the run as an artifact.

To check that the gate fails when it should, I ran the same workflow on a branch that pins stellar-xdr back to 0.2.0 and changes nothing else (`demo/gate-catches-pyxdr-downgrade`, one line in `ci/requirements.txt`). It went red on the one corpus cell 0.2.0 gets wrong even at `max_depth=500` (`hostile-sor-scval_nested_vec_200 / py-stellar-xdr: refuses (core accepts)`): https://github.com/zachsplat/xdr-conformance/actions/runs/43758099461

First run, on commit cd87c05 (2026-11-15, 2 min 44 s, green): https://github.com/zachsplat/xdr-conformance/actions/runs/43757458433

```
44 entries x 5 adapters: 11 known findings reproduced, 0 undocumented failures, 0 known findings changed, 0 files with a wrong hash
3 entries x 7 adapters: 2 known findings reproduced, 0 undocumented failures, 0 known findings changed, 0 files with a wrong hash
```

## Where the findings stand upstream

| finding | filed | status on 2026-11-15 |
|---|---|---|
| F2: py-stellar-xdr's default depth refuses transactions stellar-core admits | [lightsail-network/py-stellar-xdr#17](https://github.com/lightsail-network/py-stellar-xdr/issues/17) | Confirmed by the maintainer and fixed the same day in [#19](https://github.com/lightsail-network/py-stellar-xdr/pull/19) (default `max_depth` 200 to 500, recursive arrays read in loops); released in stellar-xdr 0.2.1. I reran the four files against the fix: all decode and round-trip through JSON. |
| F1: py-stellar-base SEP-51 JSON differs on four shapes | [StellarCN/py-stellar-base#1269](https://github.com/StellarCN/py-stellar-base/issues/1269) | Open. Filed the way the maintainer asks in #1264: the new stellar-xdr package already writes all four shapes correctly. |
| F3: empty signed-payload signer refused at decode | not filed | Minor: stellar-core's validation refuses the same transaction a step later. |

## Layout

| path | what |
|---|---|
| `corpus/manifest.schema.json` | draft manifest schema (entry ID, CAPs, protocol version, source, synthetic flag, expected values) |
| `corpus/manifest.json`, `corpus/entries/` | 23 real entries, one per rare shape: 22 from pubnet history (Galexie public data lake), 1 from testnet history |
| `corpus/hostile-manifest.json`, `corpus/hostile/` | 21 entries with stellar-core's verdict: three real pubnet envelopes and 18 variants of them, one change each |
| `runners/` | one adapter per implementation, same JSONL protocol: `rust/` (also the scanner), `go/`, `js/`, `python/` (both Python libraries), `core/` (stellar-core `print-xdr` as the reference) |
| `tools/` | `fetch_galexie.py`, `pick_corpus.py`, `pick_bases.py`, `mutate.py`, `write_hostile.py`, `diff_results.py`, `lockstep.py`, `check_corpus.py` (the conformance runner) |
| `sweeps/` | nesting-depth sweep, table printer, run-all-adapters script |
| `sightings/` | js-stellar-sdk#1766, #1785, #1789 reproduced on the last tag before each fix and the first after |
| `findings/` | new discrepancies, each with a minimal reproduction and draft issue text |
| `reports/` | `corpus-matrix.md`, `hostile-matrix.md`, `depth-sweep.md`, `raw/` (diff summaries, pool census, ledger hashes, pattern counts) |
| `.github/workflows/conformance.yml` | the CI job: builds the Rust and Go adapters, runs the corpus, the F2 depth entries and the sightings on every push to master and every pull request |
| `ci/known-findings.json`, `ci/requirements*.txt` | the divergences CI expects with the pinned versions (each tied to a finding, an upstream issue or a recorded behaviour), and the Python pins |
| `run.sh` | `quick` (the five-minute check above), and rebuilds everything from public data: `fetch`, `build`, `scan`, `replay`, `hostile`, `depth`, `corpus`, `sightings` |

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

Go and JS are looser than admission (already filed: go-stellar-sdk#6047, js-stellar-sdk#1908). py-stellar-xdr 0.2.0 was stricter than admission, so it refused transactions that can be in a ledger (F2). The table was measured on 0.2.0. Since the fix (0.2.1, default `max_depth` 500) the four F2 files decode with the defaults, and the runner's py-stellar-xdr cell for `hostile-sor-scval_nested_vec_200` passes.

## New findings

None of these had been filed by anyone when I found them; status is in [Where the findings stand upstream](#where-the-findings-stand-upstream).

- **F1** py-stellar-base 17.0.1 SEP-51 JSON: `txsuccess`/`opinner` for `tx_success`/`op_inner`, `from_` for `from`, `AssetCode` as an object, `ContractEvent.contract_id` as hex. Found on pubnet transactions. Filed as StellarCN/py-stellar-base#1269.
- **F2** py-stellar-xdr 0.2.0 default `max_depth=200` refuses authorization trees from 199 levels and ScVal nesting from 200, which pass stellar-core's XDR admission checks (up to 490 and 246 in the tested transaction). It mattered because py-stellar-base draft PR #1268 adopts py-stellar-xdr. Filed as lightsail-network/py-stellar-xdr#17; fixed in #19 and released in 0.2.1.
- **F3** (minor) py-stellar-xdr refuses an empty signed-payload signer that core's decoder takes and core's validation then refuses. Not filed.

Already filed by others and reproduced here: rs-stellar-xdr#622 and #629, py-stellar-base#1262 and #1263, js-stellar-sdk#1901 and #1908, go-stellar-sdk#6047.

## Data lake note

The Galexie lake stores meta for every sampled ledger, protocol 12 and 18 included, as `TransactionMeta` v4 with CAP-67 events: it was regenerated by a newer stellar-core, not captured when those ledgers closed. The manifest records this per entry (`meta_note`).

## Limits

No indexer replay yet (wallet-backend, stellar-etl); Java, Swift, Dart and PHP SDKs not run; hostile variants come from three base transactions; depth thresholds measured in one envelope context; core admission measured by running core's own admission parser settings (rs-stellar-xdr at depth 1000), not by submitting to a local network.

## Reproduce

```
./run.sh quick       # no docker; the five-minute check
./run.sh build && ./run.sh fetch && ./run.sh scan
./run.sh replay      # the long one: about 160,000 inputs through each implementation
./run.sh hostile && ./run.sh depth && ./run.sh sightings
```

Needs docker (images `rust:1.93-slim`, `golang:1.25-alpine`, `stellar/stellar-core:latest`), Node 24 and Python 3.12 or later. No keys, accounts or funds.
