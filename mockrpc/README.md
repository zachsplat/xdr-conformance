# Mock Stellar RPC and Galexie datastore

**Hosted:** `https://rpc.nonceworks.com` serves the same sample (POST JSON-RPC; opening it in a browser shows a short page with an example, and `GET /ranges` lists the endpoints). Limits there: 20 ledgers per `getLedgers` page, 240 requests a minute per client, three page requests at a time. It holds only the 380 ledgers below, so it is a test fixture, not a general RPC.

```
curl -s -X POST https://rpc.nonceworks.com/ -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"getLedgers","params":{"startLedger":65486000,"pagination":{"limit":2}}}'
```

An indexer can ingest the proof's real pubnet ledgers without changing its code, by either of the two routes production indexers use:

- **Stellar RPC.** `serve` answers `getHealth`, `getLatestLedger`, `getNetwork`, `getVersionInfo` and `getLedgers` (base64 XDR, `startLedger` or `cursor` paging) from the sample. Request validation is go-stellar-sdk's own `GetLedgersRequest.Validate`, so out-of-range starts and bad paging are refused with the same messages stellar-rpc uses. Each run of consecutive ledgers is one endpoint, `/r/<first>-<last>`; `/` is the longest run (65,486,000 to 65,486,299) and `/ranges` lists them all. With `PACE=2s` each endpoint starts at its first ledger and adds one ledger every two seconds, so an indexer that tails the chain sees ledgers arrive.
- **Galexie datastore.** `export` lays the same files out exactly as Galexie writes the public data lake (same object keys, same `.config.json`), so go-stellar-sdk's `BufferedStorageBackend`, or anything else that reads a Galexie filesystem or S3 datastore, reads it unchanged.

```
./run.sh fetch           # 380 ledgers from the public lake, about 62 MB
./run.sh mockrpc         # serve on 127.0.0.1:8000 (ADDR=..., PACE=... to change)
./run.sh mockrpc-check   # build, export, serve, read everything back, exit 1 on any difference
```

Point the indexer's RPC URL at `http://127.0.0.1:8000` (or one of the `/r/...` endpoints), or its datastore at `$WORK/galexie` (default `~/.cache/xdrconf/galexie`).

## What the check proves

`mockrpc-check` reads every ledger back three ways and compares each `LedgerCloseMeta` byte for byte, and each ledger hash, with the file Galexie stored:

1. go-stellar-sdk's `RPCLedgerBackend` (the RPC ingestion path, which calls `getHealth` and `getLedgers`), per range;
2. a raw `getLedgers` walk that pages with the returned `cursor`, also decoding `headerXdr`;
3. go-stellar-sdk's `BufferedStorageBackend` over the exported datastore.

It also checks that a start ledger past the latest is refused. On loading, `serve` stops if re-encoding a ledger would change a single byte, so what it serves is exactly what the lake holds.

Result on 2026-11-17 (`reports/mockrpc-check.txt`): 5 ranges, 380 ledgers, 380 read back on each path, 0 failures. The same check against the hosted endpoint (RPC paths only): 380 of 380 on both, 0 failures (`reports/mockrpc-check-hosted.txt`).

## Limits

- Only the methods above, and only the sampled ledgers. `getTransactions`, `getEvents`, `getLedgerEntries` and `simulateTransaction` are not served; `xdrFormat: json` is refused.
- The sample is five separate runs of pubnet ledgers, so each run is its own endpoint rather than one continuous chain.
- The synthetic hostile entries in `corpus/hostile` are single XDR values, not whole ledgers, so they are not served here. Wrapping them in valid ledgers is planned work in the application.
