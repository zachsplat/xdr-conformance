TITLE: XDR decoding accepts an optional flag of 2, trailing bytes and missing end padding, which stellar-core rejects

## What happens

The binary decoder accepts three kinds of malformed input that stellar-core refuses, and re-encodes each to different, canonical bytes:

1. An optional's presence flag other than 0 or 1 is read as "present" and written back as 1.
2. Bytes after a complete value are ignored.
3. When the input ends where padding should be, the missing padding is skipped without an error.

Impact is low. No ledger holds such bytes, because core rejects them. What breaks is that code which validates, signs or relays envelopes with the SDK accepts them, and `AbstractTransaction.fromEnvelopeXdrString(xdr).hash(network)` returns the hash of a different, valid transaction for them. This is a different gap from #291 (schema maximums).

## Reproduction

stellar_flutter_sdk 3.12.0 (pub.dev), Dart 3.12.0, run with `dart run` importing `src/xdr/xdr.dart` (the top-level library needs Flutter on the Dart VM).

```dart
// ignore_for_file: implementation_imports
import 'package:stellar_flutter_sdk/src/network.dart';
import 'package:stellar_flutter_sdk/src/transaction.dart';
import 'package:stellar_flutter_sdk/src/util.dart';
import 'package:stellar_flutter_sdk/src/xdr/xdr.dart';

void main() {
  // 1. Operation: sourceAccount flag 2, ed25519 muxed account of zeros, body INFLATION.
  var op = XdrOperation.fromBase64EncodedXdrString(
      'AAAAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAk=');
  print(op.toBase64EncodedXdrString());

  // 2. MEMO_NONE followed by four zero bytes.
  print(XdrMemo.fromBase64EncodedXdrString('AAAAAAAAAAA=').toBase64EncodedXdrString());
  // Pubnet envelope 4adfa3a9... (ledger 40000001) with four zero bytes appended.
  const env = 'AAAAAgAAAABSTh04F5yGRuzDsfhzZtQUhnLaHgY4Bf9HZXhQw+kkTwADDUABIfX+AAmFkwAAAAAAAAABAAAABTEwNDk4AAAAAAAAAQAAAAEAAAAAYSd9wNMUgqCI7bmo8/YYUMD8Tgt5AWP+LEM7SThIB7kAAAABAAAAAOXDqt/kCw0khZz7brrwCR79i8j1W5kyVZKR8d8S3vVOAAAAAAAAAAAk8WXAAAAAAAAAAAHD6SRPAAAAQHcPWaF0qqogZBBO8hAuiUZMpflFXC29MZqz5qN1xKrbfRNjdB17TGR5PPaInWmgYHHnBxrIrmLeU6p0R8wHbwAAAAAA';
  print(Util.bytesToHex(AbstractTransaction.fromEnvelopeXdrString(env).hash(Network.PUBLIC)).toLowerCase());

  // 3. MEMO_TEXT "abc" (11 bytes) with its one padding byte missing at end of input.
  print(XdrMemo.fromBase64EncodedXdrString('AAAAAQAAAANhYmM=').toBase64EncodedXdrString());
}
```

Observed (each decode succeeds):

```
AAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAk=
AAAAAA==
4adfa3a9189ba0c41c9407be284cb84cc7aa8f7844aea4e238f317627bb5b204
AAAAAQAAAANhYmMA
```

Expected: each decode throws.

## Evidence for the expected behaviour

- Optional flag: RFC 4506 section 4.19 defines optional data as a bool, so only 0 and 1 are valid. stellar-core 30.0.0 rejects the pubnet envelope above with the operation's flag set to 2 (`xdr::pointer size must be 0 or 1`). rs-stellar-xdr 30.0.0 returns `xdr value invalid`, and go-stellar-sdk returns `DecodeBool: bool not 0 or 1`. The SDK accepts that envelope and returns `4adfa3a9...`, the hash of the unmodified transaction.
- Trailing bytes: stellar-core 30.0.0 rejects the envelope with the four extra bytes (`unmarshaling did not consume whole message`). rs-stellar-xdr rejects it, and go-stellar-sdk returns `input not fully consumed`. The SDK returns `4adfa3a9...` for it.
- Missing end padding: RFC 4506 sections 4.10 and 4.11 require the padding bytes. For the same pubnet envelope with its last signature declared as 63 bytes and the input ending without the padding byte, stellar-core 30.0.0 rejects it (`message size not multiple of 4`), rs-stellar-xdr returns `length limit exceeded`, and go-stellar-sdk returns `EOF while decoding 1 bytes`. The SDK accepts it. A trailing-bytes check alone would not catch this one, because `pad()` leaves the offset at the end of input.

## Likely cause

- Optional flag: the generated decoders read `xPresent = stream.readInt(); if (xPresent != 0)`, for example [`lib/src/xdr/xdr_operation.dart` L41-L42](https://github.com/Soneso/stellar_flutter_sdk/blob/3.12.0/lib/src/xdr/xdr_operation.dart#L41-L42). There are 30 such sites in 18 files.
- Trailing bytes: `fromBase64EncodedXdrString` (for example [`lib/src/xdr/xdr_transaction.dart` L105-L108](https://github.com/Soneso/stellar_flutter_sdk/blob/3.12.0/lib/src/xdr/xdr_transaction.dart#L105-L108)) and `AbstractTransaction.fromEnvelopeXdrString` decode one value and never check that the input was fully consumed.
- Missing padding: [`lib/src/xdr/xdr_data_io.dart` L64-L80](https://github.com/Soneso/stellar_flutter_sdk/blob/3.12.0/lib/src/xdr/xdr_data_io.dart#L64-L80): `pad()` calls `readByte(false)`, which returns -129 at end of input, and then breaks out of the loop instead of throwing.

Suggested fix: throw when a presence flag is not 0 or 1, when bytes remain after the top-level value, and when `pad()` reaches end of input.

## Related

The same classes were fixed in stellar-php-sdk (Soneso/stellar-php-sdk#223, trailing bytes), java-stellar-sdk (lightsail-network/java-stellar-sdk#833) and py-stellar-base (StellarCN/py-stellar-base#1263, optional flag).

I found this with an open-source conformance kit (https://github.com/zachsplat/xdr-conformance) that replays pubnet ledgers through several SDKs.
