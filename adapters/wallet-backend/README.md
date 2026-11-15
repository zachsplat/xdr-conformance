# wallet-backend replay adapter (first version)

The application promises a wallet-backend reference adapter in tranche 2, checked by reproducing wallet-backend#716, #729 and #731 on pre-fix commits and passing on the fixed ones. This is the first version of that adapter. It does that check today, on real wallet-backend code at seven commits, offline, and it also reproduces #804, which is still open on main.

Run on 2026-11-15. Full table: [`results/summary.md`](results/summary.md). Raw reports: `results/<commit>.jsonl`.

## Result

| input | before the fix | after the fix | main (`3e22515a`) |
|---|---|---|---|
| #716, muxed source on a Soroban operation (`soroban-muxed-source`) | `79ea2acd`: the M... address is stored as 33 bytes and reads back as `MCEEMG2X...B5BL3OJ`, which does not decode (`invalid payload length 32, expected 40`) | `6e5a5910` (#693): reads back as its own G... base account | pass |
| #716, signed-payload signer (`signer-signed-payload-setoptions`, the only signed-payload signer in testnet ledger 4,437,357, the ledger #729 names) | `79ea2acd`: the P... signer is stored as 33 bytes and reads back undecodable (`invalid signed payload length 32, expected at least 36`) | `6e5a5910` and `2a0a84ea`: the column encoder refuses it (**halts**, see below); `2c873353` (#729): stored and read back exactly | pass |
| #731, `trust()` on an asset contract (`sac-trust-creates-trustline`) | `764a4f5b` and the four earlier commits tested: trustline created in InvokeHostFunction, no state change | `c152783c` (#734): recorded as TRUSTLINE/ADD | pass |
| #804 (open), native-asset contract transfer creates an account (`sac-native-transfer-creates-account`) | | no fix yet | account created in InvokeHostFunction, no ACCOUNT/CREATE state change |
| controls: the 22 pubnet entries of the SDK corpus, and pubnet ledgers 65,486,002, 65,486,006 and 65,486,052 replayed whole (over 10,000 addresses per commit) | pass at every commit | | pass |

`expected.tsv` holds the expected result for every input at every commit (33 inputs, 231 cells); `run.sh replay` fails if any cell differs or an input goes missing.

Between #693 and #729 the signed-payload signer went from silently truncated to refused: #693 made `AddressBytea.Value()` reject any key that is not 32 bytes, and a P... key is 40 to 100 bytes. #729's description says what that does in production: the COPY encode fails, the persist transaction rolls back with the cursor, and ingestion retries the same ledger. The adapter shows the refusal on the real testnet transaction, both on its own and inside its whole ledger (4,437,357).

## Issue state, checked 2026-11-15

| | state | the change that addresses it | commits tested |
|---|---|---|---|
| [#716](https://github.com/stellar/wallet-backend/issues/716) | closed 2026-09-18, no linked pull request | [#693](https://github.com/stellar/wallet-backend/pull/693) (merged 2026-08-27) reduces M... addresses to the base account; [#729](https://github.com/stellar/wallet-backend/pull/729) (merged 2026-09-08) stores signer keys in full | `79ea2acd` (parent of #693), `6e5a5910` (#693), `2a0a84ea` (parent of #729), `2c873353` (#729) |
| [#729](https://github.com/stellar/wallet-backend/pull/729) | a pull request, merged 2026-09-08 | itself | `2a0a84ea`, `2c873353` |
| [#731](https://github.com/stellar/wallet-backend/issues/731) | closed 2026-09-17 by [#734](https://github.com/stellar/wallet-backend/pull/734) | #734 | `764a4f5b` (parent of #734), `c152783c` (#734) |
| [#804](https://github.com/stellar/wallet-backend/issues/804) | open | none yet | all seven |

#716 lists three producers. This run covers producer 1 (Soroban operation source) and producer 3 (signed-payload signers). Producer 2 (a muxed address inside a SEP-41 token event) needs a custom token contract that emits one; it is not in the corpus yet.

## How it works

`replay/main.go` is copied into a wallet-backend checkout as `cmd/xdrc-replay` and run there, so it drives that commit's own code:

1. `indexer.ProcessLedger` fills an `IndexerBuffer` from a `LedgerCloseMeta`, the same call live ingestion makes.
2. Every address the buffer would write to a BYTEA column (transaction and operation participants, and every address field of every state change) goes through that commit's own `driver.Valuer` (what the COPY path stores) and `sql.Scanner` (what a read returns). Each one is classed `exact`, `reduced` (M... read back as its own G...), `truncated`, `undecodable`, `scan_error` or `encode_error`.
3. Separately, the adapter reads the same ledger with go-stellar-sdk's own reader and lists what the ledger did: accounts created, trustlines created, signers added, per operation. Each of those must have a matching state change (ACCOUNT/CREATE, TRUSTLINE/ADD, SIGNER with the exact key).
4. Result per input: `pass`; `mishandled` (something stored lossily, or a ledger fact with no state change); `halts` (an encoder refused a value); `error` (the commit cannot read the input).

The adapter calls `NewIndexer` and `ProcessLedger` through `reflect`, so one source file builds on every commit even though both signatures changed over time.

Inputs are either a corpus entry (envelope plus result meta, wrapped in a one-transaction ledger whose header carries only the ledger number, protocol and close time from the manifest) or a whole Galexie ledger object. The older commits pin go-stellar-sdk v0.7.3, which cannot read a protocol 30 ledger header, so for them the local-network ledgers report `error` and the entry path is what tests them. On main, the whole local ledgers and the wrapped entries give the same result.

## Inputs

The four indexer entries are in [`corpus/indexer/`](../../corpus/indexer/) with their own manifest (same schema as the SDK corpus).

| entry | where it came from |
|---|---|
| `signer-signed-payload-setoptions` | testnet ledger 4,437,357, transaction `d9f78749...`, from the public Galexie data lake (`v1.1/stellar/ledgers/testnet/2025-12-18`), protocol 28 |
| `sac-trust-creates-trustline` | local stellar-core 30.0.0 (stellar/quickstart, `--local`, docker `--network none`), ledger 43, protocol 30 |
| `soroban-muxed-source` | same local network, ledger 45: ExtendFootprintTTL with an M... transaction source |
| `sac-native-transfer-creates-account` | a second local run, ledger 26 |

The local entries come from `gen/main.go`, which builds, simulates, signs and submits real transactions against the local network and saves what core wrote: the envelope, the result meta, and the whole ledger. The keys are derived from fixed strings and exist only on that local network. What core said about each case is in `gen/output/`. With an M... transaction source, core 30 applied ExtendFootprintTTL and refused InvokeHostFunction (`txSOROBAN_INVALID`); I did not test an M... operation source. A regenerated entry has the same shape but different ledger numbers and hashes, because each run starts a fresh network.

`extract/main.go` cuts one transaction out of a ledger object into entry files; it made the testnet entry.

## Run it

Needs docker and about 5 GB in `$WORK` (clone, module cache, ledgers). Images: `golang:1.25-alpine`, and `stellar/quickstart:latest` only for `gen`.

```
adapters/wallet-backend/run.sh fetch     # network on: clone wallet-backend, a worktree per commit, go mod download, 4 Galexie ledgers
adapters/wallet-backend/run.sh replay    # offline: every run is docker --network none with GOPROXY=off; writes results/, checks expected.tsv
chmod -R u+w /dev/shm/xdrc-wb && rm -rf /dev/shm/xdrc-wb   # WORK defaults to /dev/shm/xdrc-wb; Go leaves its module cache read-only
```

One commit, one input:

```
adapters/wallet-backend/run.sh one 2a0a84ea12523b6c92e278c0c84b443041240095 \
  -manifest /kit/corpus/indexer/manifest.json -entry /kit/corpus/indexer/entries/signer-signed-payload-setoptions
adapters/wallet-backend/run.sh one 2c873353c1f0f3c9b145e25a7d009023ad104a1c \
  -network testnet -lcm '/lake/testnet/4437357.xdr.zst#d9f78749cd01297cd5f22c7f2c798c9eec93d56f399e1c4cc2f8977ca52b9fed'
```

Regenerate the local entries (writes to `$WORK/gen-out`; nothing leaves the machine):

```
adapters/wallet-backend/run.sh gen
```

`commits.txt` lists the commits, `ledgers.txt` the whole ledgers, `expected.tsv` the expected results.

## Limits

- No database. `halts` is the encoder error that wallet-backend's COPY path would hit (`pgtypeBytesFromNullAddressBytea` calls the same `Value()`); what that does to ingestion is from #729's description, not from running Postgres here.
- The adapter checks addresses and three kinds of ledger fact. It does not yet check balances, amounts, token metadata or the GraphQL layer.
- #716 producer 2 is not covered (see above).
- Four indexer entries. The tranche 2 work is the full corpus run against wallet-backend, with every failure triaged and filed.
