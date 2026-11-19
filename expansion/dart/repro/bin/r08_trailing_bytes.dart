// Candidate 8: fromBase64EncodedXdrString and AbstractTransaction
// .fromEnvelopeXdrString ignore bytes after a complete value. stellar-core
// rejects such an envelope ("unmarshaling did not consume whole message").
// ignore_for_file: implementation_imports
import 'package:stellar_flutter_sdk/src/network.dart';
import 'package:stellar_flutter_sdk/src/transaction.dart';
import 'package:stellar_flutter_sdk/src/util.dart';
import 'package:stellar_flutter_sdk/src/xdr/xdr.dart';

void main() {
  // MEMO_NONE followed by four zero bytes.
  var m = XdrMemo.fromBase64EncodedXdrString('AAAAAAAAAAA=');
  print('XdrMemo in : AAAAAAAAAAA=  out: ${m.toBase64EncodedXdrString()}');
  // Real pubnet envelope 4adfa3a9... (ledger 40000001) with four zero bytes appended.
  const env = 'AAAAAgAAAABSTh04F5yGRuzDsfhzZtQUhnLaHgY4Bf9HZXhQw+kkTwADDUABIfX+AAmFkwAAAAAAAAABAAAABTEwNDk4AAAAAAAAAQAAAAEAAAAAYSd9wNMUgqCI7bmo8/YYUMD8Tgt5AWP+LEM7SThIB7kAAAABAAAAAOXDqt/kCw0khZz7brrwCR79i8j1W5kyVZKR8d8S3vVOAAAAAAAAAAAk8WXAAAAAAAAAAAHD6SRPAAAAQHcPWaF0qqogZBBO8hAuiUZMpflFXC29MZqz5qN1xKrbfRNjdB17TGR5PPaInWmgYHHnBxrIrmLeU6p0R8wHbwAAAAAA';
  var tx = AbstractTransaction.fromEnvelopeXdrString(env);
  print('hash of the padded envelope: ${Util.bytesToHex(tx.hash(Network.PUBLIC)).toLowerCase()}');
  print('(same as the unmodified transaction 4adfa3a9189ba0c41c9407be284cb84cc7aa8f7844aea4e238f317627bb5b204)');
}
