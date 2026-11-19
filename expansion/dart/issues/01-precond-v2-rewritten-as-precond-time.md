TITLE: A PRECOND_V2 with only time bounds set is re-encoded as PRECOND_TIME, so the transaction hash is wrong

## What happens

When an envelope carries `PRECOND_V2` and every V2 field except `timeBounds` has its default value (here `minSeqNum` present and 0), `TransactionPreconditions.toXdr()` writes it back as `PRECOND_TIME`. `AbstractTransaction.fromEnvelopeXdrString(xdr).hash(network)` then hashes a different transaction and returns a hash the network never saw.

## Reproduction

stellar_flutter_sdk 3.12.0 (pub.dev), Dart 3.12.0. The input is the pubnet fee bump `b48ed2676e987cd2a258e0d1cd0c03e1819c881d51d6959d67c7f78cfc8ddf43` in ledger 65486054. I ran it with `dart run` and imported the `src/` libraries because the top-level library needs Flutter on the Dart VM; the same classes are exported from `package:stellar_flutter_sdk/stellar_flutter_sdk.dart`.

```dart
// ignore_for_file: implementation_imports
import 'package:stellar_flutter_sdk/src/network.dart';
import 'package:stellar_flutter_sdk/src/transaction.dart';
import 'package:stellar_flutter_sdk/src/util.dart';
import 'package:stellar_flutter_sdk/src/xdr/xdr.dart';

const b64 = 'AAAABQAAAABIlh0MBJIUGNXtFAE1GZwbvIkLVkJ/W68qOzeIr59BJgAAAAAARKomAAAAAgAAAABK6mxmjpjABEUqazC64ZyiLoQy7GDw6goaYiEQXS22yAAAAGYDjzwLAAAa3gAAAAIAAAABAAAAAGr0nrUAAAAAav3GdQAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAABAAAAAQAAAABIlh0MBJIUGNXtFAE1GZwbvIkLVkJ/W68qOzeIr59BJgAAAAIAAAABeVhMTQAAAAAiNtdw/g0+AVIZddXPesSEK3CV1rGp12jT6aYy6ZkGvgAAAAAAfZrFAAAAAEiWHQwEkhQY1e0UATUZnBu8iQtWQn9bryo7N4ivn0EmAAAAAAAAAAAAfZrFAAAAAgAAAAJ5VVNEQwAAAAAAAAAAAAAAzTraTOMNLk/59bkX2cI5NI9EZRILk0tjcD212hOLctkAAAABODE4AAAAAABAIAF6Dwmw6EUjhz1on4+tyZ7dD+D00TcQUv9Oyl8zHwAAAAAAAAACXS22yAAAAEDE12V7ZD+VZbtu9ywJGuf0MHVCr6DQikZX71x8wyIILGFRTqRPl1RpOWslOUrl+0EzwVkNjgf+vR9MLs4v7bEAr59BJgAAAEAszqFD3DAyKRTHMzYjmVAfIgeRqHqbZB0SeRUZXRx0UHePsRoyEofhxmVv/P3NmjpJVFWwLqSUjNS5YRs4vlsLAAAAAAAAAAo0pSUjAAAAQOihtln5QjzQgMtf+slCJsPpVFuRs+ji0ldM1++pWYrbMO8xm+wEliLxlPjeUcvM7/r1/T22rFtF/tIk2NNZSQ4fHArWAAAAAXUAAACSGkiBAAAAAXgAAADe+2SjAAAAATgAAABbk/bwAAAAAWwAAAAptJ/OAAAAATMAAAA8mv4pAAAAAWcAAADVnACdAAAAAWIAAAAn+1fpAAAAATAAAADsE6s1AAAAATIAAAA=';

void main() {
  var env = XdrTransactionEnvelope.fromBase64EncodedXdrString(b64);
  var tx = AbstractTransaction.fromEnvelopeXdrString(b64);
  print('SDK hash : ${Util.bytesToHex(tx.hash(Network.PUBLIC)).toLowerCase()}');
  var inner = env.feeBump!.tx.innerTx.v1!.tx.cond;
  var model = (tx as FeeBumpTransaction).innerTransaction.preconditions!.toXdr();
  print('cond in envelope : ${inner.discriminant.value}, minSeqNum=${inner.v2?.minSeqNum?.sequenceNumber}');
  print('cond after model : ${model.discriminant.value}');
}
```

Observed:

```
SDK hash : 67700f6b85d19c72db1401921cdf165d5fef5bb2af8f42b1ca854339e33db76a
cond in envelope : 2, minSeqNum=0
cond after model : 1
```

Expected: `b48ed2676e987cd2a258e0d1cd0c03e1819c881d51d6959d67c7f78cfc8ddf43`, and the condition should stay `PRECOND_V2`.

## Evidence for the expected value

- The ledger's `TransactionResultPair.transactionHash` for this transaction is `b48ed267...`. Horizon returns the same hash and shows `min_account_sequence` 0.
- rs-stellar-xdr 30.0.0, go-stellar-sdk (xdr and txnbuild) and py-stellar-base 17.0.1 all hash the envelope to `b48ed267...`.
- The precondition type is part of the hashed bytes: `union Preconditions switch (PreconditionType type)` in [Stellar-transaction.x L839](https://github.com/stellar/stellar-xdr/blob/v30.0/Stellar-transaction.x#L839), and `minSeqNum` is an optional `SequenceNumber*` ([L814](https://github.com/stellar/stellar-xdr/blob/v30.0/Stellar-transaction.x#L814)), so a present 0 is a valid, distinct value.
- In 380 sampled pubnet ledgers (112,278 envelopes), 166 envelopes have this shape (165 fee bumps and 1 v1 transaction, all in ledgers 65486000 to 65486299) and all 166 get the wrong hash from the SDK.

The same re-encoding also applies to `toEnvelopeXdrBase64()`, so a parsed transaction written back out carries signatures for a different hash.

## Likely cause

[`lib/src/transaction.dart` L1319-L1325](https://github.com/Soneso/stellar_flutter_sdk/blob/3.12.0/lib/src/transaction.dart#L1319-L1325): `hasV2()` treats `minSeqNumber == 0`, `minSeqAge == 0` and `minSeqLedgerGap == 0` as unset, and `toXdr()` (L1328) picks the discriminant from `hasV2()`. A `PRECOND_V2` with every field at its default comes back as `PRECOND_NONE`.

Suggested fix: remember the precondition type read in `fromXdr` and write that type back in `toXdr`.

## Related

The same class was reported and fixed in stellar-php-sdk (Soneso/stellar-php-sdk#222) and reported for java-stellar-sdk (lightsail-network/java-stellar-sdk#844).

I found this with an open-source conformance kit (https://github.com/zachsplat/xdr-conformance) that replays pubnet ledgers through several SDKs.
