# Technical architecture: Stellar XDR conformance kit

This is the technical architecture for my Stellar Community Fund Build application to the RFP "XDR/CAP-Coverage Audit Tool and Indexer-Hardening Guide". It describes the system, how each part uses Stellar, what already runs in this repository today, and what each tranche adds. It is meant to be read on its own; links point to files in this repository for anyone who wants to check a claim.

Applicant: Zachary Alexander, as an individual (working as Nonceworks, nonceworks.com). One-person team: I am the project lead and sole developer. Budget: $60,000 for 600 hours at $100 an hour, over 6 months at about 25 hours a week. License: Apache-2.0 for code; corpus entries will be released under CC0.

## 1. What the system does

Every application that reads the Stellar ledger has to decode XDR, and rare but valid ledger shapes keep breaking those readers. This kit gives them one shared test set:

- a **corpus** of rare but valid Stellar ledger and transaction shapes, one entry per shape, each tagged with the CAP that introduced it and the protocol version, plus a **hostile set** of malformed variants judged by stellar-core's own decoder;
- a **generator** that rebuilds the corpus from public network history and from a local stellar-core;
- a **conformance runner** that puts every entry through the Rust, Go, JavaScript and Python XDR libraries and reports where they differ from the network and from each other;
- a **replay harness** that feeds the same corpus to an indexer through the inputs real pipelines already read (the Galexie data lake layout and Stellar RPC `getLedgers`) and reports what the indexer handled, mishandled or dropped, with **wallet-backend** as the reference adapter;
- a **Go linter** and an **indexer-hardening guide** for the three ingestion mistakes the RFP names.

## 2. Architecture and data flow

```
Galexie data lake (pubnet, testnet) ---+
local stellar-core (both passphrases) -+--> generator ----+
mutation rules ---------------------------> hostile set --+--> corpus: XDR files + one JSON manifest

corpus --> conformance runner --> adapters: Rust, Go, JavaScript, Python (two libraries)
                              --> stellar-core print-xdr (reference verdict for hostile entries)
                              --> divergence matrix and sibling issues
corpus --> replay harness (Galexie layout or Stellar RPC) --> indexer adapter (wallet-backend first)
                              --> per-entry pass / mishandled / dropped report
corpus --> field table --> indexer-hardening guide and Go linter
```

In plain terms: the corpus is a folder of XDR files and one JSON manifest. Each entry records where it came from (ledger and transaction hash, or "local stellar-core", or "mutation of entry X"), the CAP that introduced the shape, the protocol version, and what a correct decoder must produce: the SEP-51 JSON, the transaction hash, and that re-encoding gives the same bytes. Each SDK gets a small adapter that reads requests on stdin and writes results on stdout, so adding Java or Swift later means writing one file. stellar-core's own decoder judges hostile entries. The replay harness feeds the same corpus to an indexer through the Galexie lake layout, which wallet-backend and stellar-etl already read, or over Stellar RPC, and reports for each entry whether the indexer handled it, mishandled it or dropped it. The manifest also drives a field table that the guide and the linter share.

### Which Stellar pieces each part uses

| component | Stellar pieces it uses |
|---|---|
| Corpus and generator | Galexie public data lake on AWS Open Data (`aws-public-blockchain`, `v1.1/stellar/ledgers/pubnet` and testnet), one zstd `LedgerCloseMetaBatch` per ledger; Horizon for testnet lookups; a local standalone stellar-core 30.0.0 (stellar/quickstart; the tranche 1 generator runs it under both the testnet and pubnet passphrases); rs-stellar-xdr for the scanner; CAP numbers from stellar-protocol |
| Manifest | XDR type names as written in the stellar-xdr `.x` files; network passphrases; SEP-51 XDR-JSON as the expected decoded form; CAP tags |
| Conformance runner | rs-stellar-xdr 30.0.0, go-stellar-sdk v0.9.0 (`xdr`, `network`, `txnbuild`), js-stellar-sdk 17.4.0, py-stellar-base 17.0.1, py-stellar-xdr (0.2.1 gating, 0.2.0 kept as a before column) |
| Referee | stellar-core 30.0.0 `print-xdr` (xdrpp), and its protocol-28 admission parse (`validateXDRForProtocol`, rs-stellar-xdr at depth 1000); stellar-core's golden LedgerCloseMeta (`--check-lcm`, `test-lcm-current`) |
| Replay harness | `LedgerCloseMeta` delivered through the Galexie datastore layout and Stellar RPC `getLedgers`; go-stellar-sdk `RPCLedgerBackend` and `BufferedStorageBackend` as the check |
| wallet-backend adapter | wallet-backend's own `indexer.ProcessLedger`, its BYTEA column encoders and decoders, at pinned commits |
| Linter and guide | wallet-backend (Go) as the clean target; SEP-23 strkeys (muxed M... and signed-payload P... addresses); the manifest's field table |

## 3. What exists today

All of this is in this repository and was built before the application; none of it is billed.

- **Real history at scale.** 380 pubnet ledgers from the Galexie data lake in five eras: 28,000,000 (protocol 12), 40,000,000 (18), 50,460,000 (20), 59,000,000 (23), 65,486,000 to 65,486,299 (29). That is 112,278 transaction envelopes and 44,057 sampled result metas. Every envelope and sampled meta was decoded by rs-stellar-xdr 30.0.0, go-stellar-sdk v0.9.0, js-stellar-sdk 17.4.0, py-stellar-xdr 0.2.0 and py-stellar-base 17.0.1, and the 380 whole ledgers by the first four. The libraries agree on bytes and transaction hashes for all of it. This was a one-off local run with docker on 2026-11-15, repeated from a clean clone; CI runs the 44-entry corpus, not the 380 ledgers.
- **Corpus: 48 entries.** 23 real entries, one per rare shape (22 from pubnet history, 1 from testnet history); 21 hostile entries (three real pubnet envelopes and 18 variants, one change each) with stellar-core's verdict; and 4 indexer entries (one testnet transaction from the public data lake and three from a local stellar-core 30 network, each kept with the whole ledger core wrote). The entries cover CAP-15, 21, 23, 27, 33, 35, 38, 40, 46, 67 and 73.
- **Conformance runner in public CI.** `.github/workflows/conformance.yml` runs the 44 corpus entries through all five libraries on every push to master and every pull request, with every version pinned, against `ci/known-findings.json`. Each green run prints `44 entries x 5 adapters: 11 known findings reproduced, 0 undocumented failures, 0 known findings changed, 0 files with a wrong hash`. A deliberate downgrade of py-stellar-xdr to 0.2.0 on a throwaway branch turned the build red on exactly the cell 0.2.0 gets wrong.
- **stellar-core as referee.** 18 hostile variants of three real pubnet envelopes (non-zero padding, an optional flag of 2, a bool of 2, a 29-byte memo, 101 operations, deep nesting, empty and 65-byte signed payloads, and others) run through `stellar-core print-xdr` and the five libraries. Five variants split them.
- **Two upstream fixes.** py-stellar-xdr refused authorization trees from 199 levels that stellar-core admits: filed as lightsail-network/py-stellar-xdr#17, fixed in #19 and released as stellar-xdr 0.2.1 the same day. py-stellar-base 17.0.1 wrote SEP-51 JSON that differs on four shapes: filed as StellarCN/py-stellar-base#1269, closed as fixed on main by #1268.
- **RFP sightings reproduced.** js-stellar-sdk#1766 fails on 17.2.0 and passes on 17.2.1 using a real testnet transaction (ledger 5,521,445); #1785 and #1789 fail on 17.2.1 and pass on 17.3.0.
- **wallet-backend reproductions.** A first version of the wallet-backend adapter reproduces #716, #729 and #731 on pre-fix commits and passes on the fixed ones, and reproduces #804, still open on main. 231 results (33 inputs at 7 commits) are pinned.
- **Hosted mock Stellar RPC and Galexie export.** The 380 ledgers are served over Stellar RPC at https://rpc.nonceworks.com and written in Galexie's datastore layout; both read back 380 of 380 ledgers byte for byte through go-stellar-sdk's own backends.

## 4. Components

### 4.1 Corpus and generator

**Today.** `tools/fetch_galexie.py` downloads ledgers from the public lake. The Rust scanner (`runners/rust/src/scan.rs`, on rs-stellar-xdr) walks every transaction and tags rare shapes; `tools/pick_corpus.py` picks one real transaction per shape and writes its envelope, result meta, expected SEP-51 JSON and manifest entry. `tools/pick_bases.py`, `tools/mutate.py` and `tools/write_hostile.py` build the hostile set from three real pubnet envelopes. The indexer entries come from `adapters/wallet-backend/gen/main.go`, which builds, simulates, signs and submits real transactions against a local stellar-core 30.0.0 network (docker `--network none`) and saves what core wrote: the envelope, the result meta and the whole ledger.

**Why generated entries are needed.** Pubnet has 39,489 liquidity pools, 639 with two assets of the same code, and in none of them do the issuers sort differently as strkey text and as key bytes; by chance about 50 should. On testnet, 12 of its 13 same-code pools have that shape. The shape behind js-stellar-sdk#1766 is missing from pubnet history, so a corpus captured only from pubnet would never have caught it. The corpus has to include entries produced by a local stellar-core as well as captured ones, and the manifest says which is which.

**Data lake note.** The Galexie lake stores meta for every sampled ledger, protocol 12 and 18 included, as `TransactionMeta` v4 with CAP-67 events, because it was regenerated by a newer stellar-core. The manifest records this per entry (`meta_note`).

**Planned.** Tranche 1: corpus v0.1 (at least 60 new entries beyond the 48 here) and a generator that rebuilds the corpus bit for bit (`run.sh generate`) from the lake for pubnet and testnet and from a local standalone stellar-core under both passphrases, offline after the download. Tranche 3: corpus v1.0 with entries for every CAP from protocol 13 to 30 that changed a transaction, result, meta or ledger-entry shape.

### 4.2 Manifest schema

The schema is JSON Schema 2020-12 ([`corpus/manifest.schema.json`](../corpus/manifest.schema.json)). Top level: `version` (1) and `entries`. Each entry:

| field | required | meaning |
|---|---|---|
| `id` | yes | lowercase slug, also the entry's directory name |
| `caps` | yes | list of `CAP-NNNN`; empty for shapes as old as the protocol |
| `protocol_version` | yes | ledger protocol when applied, or the version the generator targeted |
| `network`, `network_passphrase` | yes | `pubnet`, `testnet` or `standalone`, and its passphrase |
| `synthetic` | yes | true if any byte was written by hand or by mutation |
| `source` | yes | `kind`: `galexie-public-datalake`, `horizon-testnet`, `horizon-pubnet`, `local-stellar-core` or `mutation`; plus `ledger`, `tx_hash`, `index_in_tx_set` or `derived_from` |
| `files` | yes | at least `envelope`; each file has `path`, `xdr_type` (the name in the stellar-xdr `.x` files) and `sha256` |
| `expected` | yes | `tx_hash`; `roundtrip: identity`; path and sha256 of the SEP-51 JSON a conforming decoder writes; for hostile entries `stellar_core_decode` and `stellar_core_admission`, each `accept` or `reject` |
| `description` | yes | what the shape is |
| `pattern`, `sightings`, `meta_note` | no | scanner tag; public issues the entry reproduces; notes on how the meta was produced |

A sample entry from the corpus, abridged (description, pattern, passphrase and JSON hash left out):

```json
{
  "id": "signed-payload-extra-signer",
  "caps": ["CAP-0040", "CAP-0021"],
  "protocol_version": 29,
  "network": "pubnet",
  "synthetic": false,
  "source": {"kind": "galexie-public-datalake", "ledger": 65486006,
             "tx_hash": "7018fca10754729a4705c524e803d31a6972e90c0eb85ee6e357644acf9f2898", "index_in_tx_set": 133},
  "files": {"envelope": {"path": "entries/signed-payload-extra-signer/envelope.xdr", "xdr_type": "TransactionEnvelope",
                         "sha256": "5a30e54be1f96a532a2a7692bb12487891ed645beb835ea0dcdf6c9f9b885e5c"},
            "meta": {"path": "entries/signed-payload-extra-signer/meta.xdr", "xdr_type": "TransactionResultMetaV1",
                     "sha256": "1e889b86f4e681da21c900adb3161c2be251814134f8e2497e764aaae828c0b9"}},
  "expected": {"envelope_sep51_json": "entries/signed-payload-extra-signer/envelope.json",
               "tx_hash": "7018fca10754729a4705c524e803d31a6972e90c0eb85ee6e357644acf9f2898", "roundtrip": "identity"}
}
```

Hostile entries carry `"synthetic": true`, `"source": {"kind": "mutation", ...}` and `"expected": {"stellar_core_decode": "accept" | "reject"}`. The manifest is language-neutral: any pipeline that reads JSON and XDR files can use it.

### 4.3 Conformance runner and SDK adapters

**Protocol.** Every adapter speaks the same JSONL protocol on stdin and stdout. A request is `{"id", "op": "decode", "type", "b64", "network"}`; the result is `{"id", "ok", "error", "roundtrip_equal", "reencoded_b64", "json", "hash"}`. A second operation, `from_json`, reads SEP-51 JSON back to bytes. Adapters today: `runners/rust` (rs-stellar-xdr), `runners/go` (go-stellar-sdk), `runners/js` (js-stellar-sdk), `runners/python` (py-stellar-base and py-stellar-xdr), and `runners/core` (stellar-core, below).

**Checks per entry and library.** The file decodes; re-encoding gives the same bytes; the transaction hash, computed through each SDK's own model with the entry's network passphrase, matches the manifest; the SEP-51 JSON equals the expected JSON (for libraries that write it); and every XDR and JSON file matches its sha256 in the manifest. Hostile entries are checked against stellar-core's recorded verdict instead.

**Gate.** `tools/check_corpus.py` compares every failing cell with `ci/known-findings.json`, where each expected divergence is tied to a finding, an upstream issue or a recorded behaviour. It exits 1 on an undocumented failure, on a listed finding that stops reproducing, or on a file with a wrong hash, so an SDK release that fixes or breaks a shape turns the build red. The run also writes a divergence matrix to the CI summary.

**Planned.** Tranche 1: packaged as a reusable GitHub Actions workflow that an SDK repository calls in one line with its own known-failures file, running the v0.1 corpus through all five libraries at each one's latest release and the two before it, with a divergence matrix (entry x SDK x version) on every run. Tranche 3: the job offered as a pull request to js-stellar-sdk, go-stellar-sdk and rs-stellar-xdr, a sibling issue filed in each affected SDK for every divergence, and an SDK divergence report.

### 4.4 stellar-core as referee

`runners/core/core_oracle.py` runs stellar-core 30.0.0 (0e49751, the build pubnet runs) `print-xdr` in the `stellar/stellar-core` image over the same JSONL requests, one container per batch. For depth, it also records the protocol-28 admission parse: from protocol 28, core re-parses every submitted envelope with rs-stellar-xdr at depth 1000 (`validateXDRForProtocol`), and that check decides admission. These verdicts are stored in the manifest (`stellar_core_decode`, `stellar_core_admission`), so CI does not need to run stellar-core.

The depth sweep shows why the referee matters. In one real Soroban transaction, stellar-core admits authorization trees up to 490 levels. py-stellar-xdr 0.2.0 refused them from 199 levels, so it refused transactions that can be in a ledger; js-stellar-sdk#1901 showed such a transaction staying in the ledger after failing at apply.

**Planned.** Tranche 1: every corpus entry whose shape appears in stellar-core v30.0.0's golden LedgerCloseMeta (`test-lcm-current`, the `--check-lcm` mode from stellar-core#5435) is compared with it, and the manifest lists which were compared.

### 4.5 Replay harness and indexer adapters

**Inputs.** The harness delivers ledgers through inputs that existing pipelines already consume: the Galexie data lake layout first (wallet-backend and stellar-etl read it), and Stellar RPC `getLedgers` second (already working for the 380 sample ledgers, section 4.6).

**wallet-backend adapter today** (`adapters/wallet-backend/`). `replay/main.go` is copied into a wallet-backend checkout and run there, offline (docker `--network none`), so it drives that commit's own code:

1. `indexer.ProcessLedger` fills an `IndexerBuffer` from a `LedgerCloseMeta`, the same call live ingestion makes.
2. Every address the buffer would write to a BYTEA column goes through that commit's own encoder (what the COPY path stores) and decoder (what a read returns), and is classed `exact`, `reduced` (M... read back as its own G...), `truncated`, `undecodable`, `scan_error` or `encode_error`.
3. The adapter separately reads the same ledger with go-stellar-sdk and lists what the ledger did (accounts created, trustlines created, signers added); each must have a matching state change.
4. Result per input: `pass`, `mishandled`, `halts` (an encoder refused a value, which in production stops ingestion) or `error`.

Inputs are either a corpus entry wrapped in a one-transaction ledger, or a whole Galexie ledger object. Results at seven commits:

| issue | input | before the fix | after the fix |
|---|---|---|---|
| wallet-backend#716 | an M... transaction source on a Soroban transaction (local stellar-core 30) | `79ea2acd`: stored as 33 bytes, reads back undecodable | `6e5a5910` (#693): reads back as the base G... account |
| wallet-backend#716 and #729 | the only signed-payload signer in testnet ledger 4,437,357, the ledger #729 names | `79ea2acd`: reads back undecodable; `6e5a5910` and `2a0a84ea`: the encoder refuses it, which halts ingestion | `2c873353` (#729): stored and read back exactly |
| wallet-backend#731 | `trust()` on an asset contract (local stellar-core 30) | `764a4f5b`: trustline created, no state change | `c152783c` (#734): TRUSTLINE/ADD |
| wallet-backend#804 (still open) | a native-asset contract transfer that creates an account (local stellar-core 30) | main `3e22515a`: account created, no ACCOUNT/CREATE row | no fix yet |

The 22 pubnet corpus entries and three whole pubnet ledgers are controls and pass at every commit. All 231 results are pinned in `adapters/wallet-backend/expected.tsv`, and the replay fails if any of them changes.

**Planned.** Tranche 2: the replay harness with a documented adapter interface; the full corpus served both as a Galexie datastore and over Stellar RPC (extending the mock to `getTransactions` and `getEvents`), with the hostile entries wrapped in valid ledgers so an indexer ingests them with no code changes; bounded memory on the full corpus, checked in CI; a per-entry pass / mishandled / dropped report. The wallet-backend adapter v1 moves onto that interface and runs the full corpus at current main against a real Postgres, so a halt is observed in ingestion rather than inferred, and adds #716 producer 2 (a muxed address in a SEP-41 token event). stellar-etl is a stretch target in tranche 3, not a promise.

### 4.6 Hosted mock Stellar RPC and Galexie export

`mockrpc/serve` answers `getHealth`, `getLatestLedger`, `getNetwork`, `getVersionInfo` and `getLedgers` (base64 XDR, `startLedger` or `cursor` paging) from the Galexie files. Request validation is go-stellar-sdk's own `GetLedgersRequest.Validate`, so bad paging is refused with the messages stellar-rpc uses. Each run of consecutive ledgers is its own endpoint; with `PACE=2s` ledgers arrive one at a time like a live network. On loading, the server stops if re-encoding a ledger would change a single byte, so it serves exactly what the lake holds. `mockrpc/export` writes the same ledgers in Galexie's datastore layout (same object keys, same `.config.json`).

`mockrpc/check` reads every ledger back three ways and compares each `LedgerCloseMeta` byte for byte, and each ledger hash, with the stored file: go-stellar-sdk's `RPCLedgerBackend`, a raw `getLedgers` cursor walk, and `BufferedStorageBackend` over the export. Result: 380 of 380 on each path, 0 failures. Through the hosted endpoint https://rpc.nonceworks.com, the RPC paths read back 380 of 380 on 2026-11-17, 0 failures.

Hosted limits: at most 20 ledgers per `getLedgers` page, 240 requests a minute per client IP, three page requests served at a time. It holds only the sample ledgers, so it is a test fixture, not a general RPC.

### 4.7 Go linter

**Planned, tranche 2.** A linter for Go, wallet-backend's language, with one rule ID for each of the three mistakes in section 3 of the RFP: trusting unvalidated fields, missing depth and size caps on recursive structures such as authorization trees and nested ScVals, and deriving participants from the envelope instead of the meta. It reads which fields are validated from the same field table the guide uses. Check: it flags seeded violations for each rule and runs clean on current wallet-backend.

### 4.8 Indexer-hardening guide

**Planned, tranche 3.** The guide follows the RFP's fixed outline: validated vs. unvalidated fields, recommended depth and size caps, participants-from-meta, muxed and signed-payload handling including the SEP-23 strkey forms, and a checklist that carries the linter's checks to indexers in other languages. The field-by-field table is generated from the manifest, and CI checks that it matches. The guide is opened as a pull request to stellar/stellar-docs with review requested from a core or platform engineer, and stays marked draft until that review.

## 5. Planned work per tranche

All rows are new work; cost is $100 an hour. SCF pays 10% on acceptance, then 20%, 30% and 40% on the three tranches.

### Tranche 1: MVP (months 1 and 2), $18,000, 180 hours

| deliverable | how a reviewer checks it | cost |
|---|---|---|
| Corpus v0.1: at least 60 new entries beyond the 48 in the proof, covering CAP-15, 21, 23, 27, 33, 35, 38, 40, 46, 67 and 73 plus the RFP's pre-CAP shapes, including entries from a local stellar-core, each tagged with CAP and protocol version | schema validation; every entry round-trips through rs-stellar-xdr; entries whose shape appears in stellar-core v30.0.0's golden LedgerCloseMeta (`test-lcm-current`) agree with it, and the manifest lists which were compared | $8,000 (80 h) |
| Generator from the Galexie lake (pubnet and testnet) and a local standalone stellar-core, reproducible for both passphrases | `run.sh generate` rebuilds the corpus bit for bit from a clean machine, offline after the download | $4,000 (40 h) |
| Conformance runner v0.1 as a reusable GitHub Actions workflow; all five libraries at the latest release and the two before it; divergence matrix on every run | workflow public and green on every PR; a fork of one SDK calls it in one line; matrix covers every v0.1 entry at three versions of each library | $6,000 (60 h) |

### Tranche 2: testnet-equivalent (months 3 and 4), $18,000, 180 hours

| deliverable | how a reviewer checks it | cost |
|---|---|---|
| Replay harness with a documented adapter interface; full corpus as a Galexie datastore and over Stellar RPC (adding `getTransactions` and `getEvents`), hostile entries wrapped in valid ledgers; bounded memory | an unmodified indexer reads every v0.1 corpus ledger through both routes; memory flat across the full corpus in CI; per-entry report | $5,000 (50 h) |
| wallet-backend reference adapter v1: full corpus at current main against a real Postgres; adds #716 producer 2 | per-entry report with halts observed against Postgres; producer 2 reproduces at `79ea2acd` and its result at all seven commits is pinned | $4,000 (40 h) |
| Go linter, one rule ID per RFP mistake | flags seeded violations for each rule; runs clean on current wallet-backend | $5,000 (50 h) |
| Findings report from the corpus run against wallet-backend (issue link, corpus entry, severity, CAP, component), each failure triaged and filed upstream | every failure maps to a filed issue | $2,000 (20 h) |
| STRIDE threat model and monitoring plan for the corpus pipeline, releases and hosted RPC (section 6) | both documents in docs/, each threat mapped to a control and a monitored signal, nightly job live | $2,000 (20 h) |

### Tranche 3: production release, mainnet-equivalent (months 5 and 6), $24,000, 240 hours

| deliverable | how a reviewer checks it | cost |
|---|---|---|
| Indexer-hardening guide in the RFP's outline, field table generated from the manifest | table matches the manifest in CI; PR to stellar/stellar-docs with review requested, draft until reviewed | $8,000 (80 h) |
| Conformance job offered as a PR to js-stellar-sdk, go-stellar-sdk and rs-stellar-xdr; sibling issues for every divergence; SDK divergence report | links to the PRs and issues; every divergence in the matrix maps to a filed issue | $7,000 (70 h) |
| Corpus v1.0: every CAP from protocol 13 to 30 that changed a transaction, result, meta or ledger-entry shape: CAP-15, 18, 19, 27 (protocol 13); 23, 33 (14); 35 (17); 38 (18); 21, 40 (19); 46 (20); 54 (21); 58 (22); 63, 66, 67 (23); 73, 77 (26); 71 (27); 83, 85 (28); 84, 88 (30). Stretch: stellar-etl | per-CAP coverage table generated from the manifest; CI fails if a listed CAP has no entry | $5,000 (50 h) |
| v1.0 release (signed tag, checksums), documentation, unit tests for generator, runner, harness and linter in the public workflow, and a protocol-upgrade runbook rehearsed on the protocol 29 to 30 change | tagged release with checksums; tests in the public workflow; rehearsal log and diff in the repo | $4,000 (40 h) |

Total: $60,000 for 600 hours. No audit, marketing, legal or past-work costs are included. The RFP reproduction checks the proof already meets (js-stellar-sdk#1766, #1785, #1789; wallet-backend#716, #729, #731) stay as regression gates and are not billed. Hosting the RPC and the 12 months of maintenance after the final tranche are not billed either.

## 6. Security, threat model and monitoring

The tools need no keys or funds and hold no user assets. Findings that could affect funds or a network's availability go to the maintainer's security contact first; everything else is a public issue.

This is an off-chain developer tool, so "onchain monitoring" here means watching the things that could make the kit give wrong answers or stop serving. In tranche 2 I will write a STRIDE threat model (following SDF's Threat Modeling How-To) and a monitoring plan (following SDF's builders template) for the corpus pipeline, its releases and the hosted RPC. The threats in scope: tampered corpus entries or releases, poisoned packages, hostile entries crashing CI, and RPC abuse. The monitored signals: a nightly run on each SDK's newest release that opens an issue on a new divergence, release checksum checks, and an RPC uptime check.

## 7. Infrastructure and user tracking

Everything runs from this public git repository, in GitHub Actions or on any machine with Docker. Inputs are public: the Galexie data lake on AWS Open Data, Horizon, and a local stellar-core. Nothing needs mainnet keys or funds. The tools collect no telemetry and use the network only to download ledgers and packages.

The one optional hosted service is https://rpc.nonceworks.com, a read-only mock Stellar RPC behind Cloudflare. The server keeps no request log: it writes one line at start-up listing the ledger ranges it serves, and logs nothing per request. It holds client IP addresses in memory only to apply the rate limit, and that table is cleared on restart or once it holds more than 10,000 addresses. Cloudflare keeps its own standard records of requests to the site, and the Cloudflare tunnel connector logs a request's path when it cannot reach the server. I will host it through the grant and for 12 months after the final tranche.

Stack: Rust (generator and scanner, on rs-stellar-xdr), Go, TypeScript and Python adapters, Python for orchestration, Docker for stellar-core, GitHub Actions for CI. Versions are pinned in `runners/rust/Cargo.lock`, `runners/go/go.sum`, `sightings/package-lock.json` and `ci/requirements*.txt`, and moved forward with each protocol release.

## 8. Protocol upgrades and maintenance

After the final tranche I will maintain the corpus, runner, harness, linter and guide for 12 months, unpaid, as sole maintainer, at about 4 hours a month: corpus updates for each new protocol version, including the first protocol upgrade after delivery, and keeping CI green. A new CAP's entries land once its XDR is final, listed as expected failures per SDK until that SDK ships support, so no SDK's CI goes red on a shape it has not implemented. The tranche 3 runbook, rehearsed on the protocol 29 to 30 change, is the procedure for each upgrade. If SDF or an SDK team wants the repository, I will transfer it.

## 9. Related work

Another public project answers this RFP: ErenTopaal/shapekit (Apache-2.0, created 2026-11-13, v0.1.0 released 2026-11-14), with a corpus of 712 entries (590 from a local stellar-core), a Rust, Go and JavaScript runner, a local replay server, a wallet-backend harness, a Go linter and a draft guide. This kit differs in three ways: it covers the two Python libraries, where both of my upstream fixes came from; it checks decoders against what the network actually wrote, at scale (380 pubnet ledgers from protocol 12 to 29, 112,278 envelopes, five libraries), alongside entries from a local stellar-core; and it serves the corpus from a hosted Stellar RPC an indexer can point at without running anything, as well as in the Galexie layout. It also keeps stellar-core's own decoder and admission parse as the referee for hostile entries.

## 10. Limits today

Indexer replay covers wallet-backend only (four indexer entries, seven commits, no database), not stellar-etl. Java, Swift, Dart and PHP SDKs are not run. Hostile variants come from three base transactions. Depth thresholds were measured in one envelope context. The mock RPC serves only the sampled ledgers and only the methods listed above; the hostile entries are single XDR values and are not yet wrapped in ledgers.
