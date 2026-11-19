TITLE: A fee bump parsed with fromEnvelopeXdrString loses its fee-bump signatures

## What happens

`AbstractTransaction.fromEnvelopeXdrString(xdr)` on a fee-bump envelope returns a `FeeBumpTransaction` with an empty `signatures` list, even when the envelope has fee-bump signatures. `toEnvelopeXdrBase64()` then writes the envelope without them. The inner transaction keeps its signatures, and the hash is not affected.

For a user this means a signed fee bump that goes through the model comes back unsigned at the outer level. For example, `URIScheme.signTransaction` (SEP-7) parses the envelope, adds one signature and posts or submits `toEnvelopeXdrBase64()` ([`lib/src/sep/0007/URIScheme.dart` L635-L663](https://github.com/Soneso/stellar_flutter_sdk/blob/3.12.0/lib/src/sep/0007/URIScheme.dart#L635-L663)), so signatures already collected from other fee-account signers are lost.

## Reproduction

stellar_flutter_sdk 3.12.0 (pub.dev), Dart 3.12.0. The input is the pubnet fee bump `34b6b29f3ea2ab77ace0b0a244b297cdcedd5434d1bd1b356636d7c54c2070cc` in ledger 65486182, which has 1 fee-bump signature. I ran it with `dart run` and imported the `src/` libraries because the top-level library needs Flutter on the Dart VM.

```dart
// ignore_for_file: implementation_imports
import 'package:stellar_flutter_sdk/src/transaction.dart';
import 'package:stellar_flutter_sdk/src/xdr/xdr.dart';

const b64 = 'AAAABQAAAABUBHORC+f3jADZQhru3jYxfSaTxjqXU8ckOHWA5NnKVgAAAAAAAYagAAAAAgAAAAB5hARY7qEOi72+I+T0ZzCQasTD9QawKBk2clAF7wDrSgAAAG4D3COQAAAAAgAAAAEAAAAAAAAAAAAAAABq+TiaAAAAAAAAAAEAAAAAAAAAAQAAAQAFHyABifkSWShEFCztAl8+nLogu9LkT7yeDUhww6rYIoR8vO5Rl55qAAAAAAAAAAAEQoqQAAAAAAAAAAHvAOtKAAAAQIS+M6f2STQ6JUR5jrOJiFqPkj6q7K+cUhuHkh7BXzOMGw8+mWkhoaYNqnzheOEYZJ1vlvMe/7AuGiXtFC2HagMAAAAAAAAAAeTZylYAAABAV+9/NGjQeP5GvF4QNmGl4sOWfVy8ijw8roBnFsCtpFxuXGtrR6jAfyYRIY+EoxU5Uz0CM+zogESxhI8tPBAZDw==';

void main() {
  var env = XdrTransactionEnvelope.fromBase64EncodedXdrString(b64);
  var tx = AbstractTransaction.fromEnvelopeXdrString(b64);
  print('fee-bump signatures in envelope : ${env.feeBump!.signatures.length}');
  print('FeeBumpTransaction.signatures   : ${tx.signatures.length}');
  var out = tx.toEnvelopeXdrBase64();
  print('re-encoded fee-bump signatures  : ${XdrTransactionEnvelope.fromBase64EncodedXdrString(out).feeBump!.signatures.length}');
  print('same envelope: ${out == b64}');
}
```

Observed:

```
fee-bump signatures in envelope : 1
FeeBumpTransaction.signatures   : 0
re-encoded fee-bump signatures  : 0
same envelope: false
```

Expected: 1, 1, 1, `true`.

## Evidence for the expected value

- `FeeBumpTransactionEnvelope` has `DecoratedSignature signatures<20>` next to the transaction ([Stellar-transaction.x L993-L999](https://github.com/stellar/stellar-xdr/blob/v30.0/Stellar-transaction.x#L993-L999)).
- py-stellar-base, go-stellar-sdk txnbuild and java-stellar-sdk keep the fee-bump signatures when they parse a fee-bump envelope.
- The v1 and v0 paths in this SDK (`Transaction.fromV1EnvelopeXdr`, `fromV0EnvelopeXdr`) do copy the envelope signatures.
- In 380 sampled pubnet ledgers there are 25,377 fee-bump envelopes, all with at least one fee-bump signature. In 25,373 of them the signatures are gone after a parse and re-encode through the model.

## Likely cause

[`lib/src/transaction.dart` L757-L768](https://github.com/Soneso/stellar_flutter_sdk/blob/3.12.0/lib/src/transaction.dart#L757-L768): `FeeBumpTransaction.fromFeeBumpTransactionEnvelope` builds the object from `envelope.tx` and never reads `envelope.signatures`.

Suggested fix: copy `envelope.signatures` into the new `FeeBumpTransaction`, as `fromV1EnvelopeXdr` does.

I found this with an open-source conformance kit (https://github.com/zachsplat/xdr-conformance) that replays pubnet ledgers through several SDKs.
