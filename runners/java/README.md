# runners/java: java-stellar-sdk adapter

Adapter for `network.lightsail:stellar-sdk` (java-stellar-sdk), pinned in `pom.xml` (6.0.0, the latest release on Maven Central on 2026-11-19). Same JSONL protocol as `runners/python/facts.py` and `runners/go/main.go`.

Build and run, docker only (Maven on Temurin 21 builds; plain `eclipse-temurin:21` runs):

```
./build.sh                                   # writes ~/.cache/xdrconf/java-cache/facts-java
~/.cache/xdrconf/java-cache/facts-java < requests.jsonl > results.jsonl
```

Fields per result, besides `id`, `ok`, `error`, `roundtrip_equal`, `reencoded_b64`:

- `json`: the SDK's own SEP-51 XDR-JSON (`XdrElement.toJson()`), copied into the line unchanged.
- `json_roundtrip_equal`: `fromJson(toJson(v))` re-encodes to the input bytes.
- For a `TransactionEnvelope` with `network`: `hash` from the SDK's transaction model (`AbstractTransaction.fromEnvelopeXdr(...).hashHex()`); `xdr_hash`, the SHA-256 of the `TransactionSignaturePayload` built from the decoded XDR with no model (not for v0 envelopes); `model_roundtrip_equal` (the model's `toEnvelopeXdr()` gives the input bytes); `model`, the strkeys the model produced (source, fee source, each operation's source and destination).

Decoding uses `fromXdrByteArray`, so the SDK's default limits apply (`XdrDataInputStream.DEFAULT_MAX_DEPTH` = 200). Every request is wrapped in `catch (Throwable)`, so one input cannot stop the run.
