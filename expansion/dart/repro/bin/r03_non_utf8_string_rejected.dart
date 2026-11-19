// Candidate 3: an XDR `string` that is not UTF-8 makes the whole value
// undecodable (FormatException), although XDR strings are bytes and
// stellar-core accepts them. Memo text, SCV_STRING and SCV_SYMBOL are affected.
// ignore_for_file: implementation_imports
import 'package:stellar_flutter_sdk/src/transaction.dart';
import 'package:stellar_flutter_sdk/src/xdr/xdr.dart';

void tryIt(String name, Object Function() f) {
  try {
    f();
    print('$name: decoded');
  } catch (e) {
    print('$name: $e');
  }
}

void main() {
  // Memo MEMO_TEXT with the 5 bytes FF FE 00 41 C3.
  tryIt('XdrMemo', () => XdrMemo.fromBase64EncodedXdrString('AAAAAQAAAAX//gBBwwAAAA=='));
  // ScVal SCV_STRING with the same 5 bytes.
  tryIt('XdrSCVal', () => XdrSCVal.fromBase64EncodedXdrString('AAAADgAAAAX//gBBwwAAAA=='));
  // A real pubnet envelope (ledger 40000001) with only its memo text replaced by those bytes;
  // stellar-core 30.0.0 print-xdr decodes it.
  const env = 'AAAAAgAAAABSTh04F5yGRuzDsfhzZtQUhnLaHgY4Bf9HZXhQw+kkTwADDUABIfX+AAmFkwAAAAAAAAABAAAABf/+AEHDAAAAAAAAAQAAAAEAAAAAYSd9wNMUgqCI7bmo8/YYUMD8Tgt5AWP+LEM7SThIB7kAAAABAAAAAOXDqt/kCw0khZz7brrwCR79i8j1W5kyVZKR8d8S3vVOAAAAAAAAAAAk8WXAAAAAAAAAAAHD6SRPAAAAQHcPWaF0qqogZBBO8hAuiUZMpflFXC29MZqz5qN1xKrbfRNjdB17TGR5PPaInWmgYHHnBxrIrmLeU6p0R8wHbwA=';
  tryIt('XdrTransactionEnvelope', () => XdrTransactionEnvelope.fromBase64EncodedXdrString(env));
  tryIt('AbstractTransaction', () => AbstractTransaction.fromEnvelopeXdrString(env));
}
