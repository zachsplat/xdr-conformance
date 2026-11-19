// Candidate 4: a string whose bytes start with EF BB BF (a UTF-8 byte order
// mark) decodes, but the BOM is dropped, so re-encoding gives other bytes and
// the transaction hash changes. stellar-core accepts the input unchanged.
// ignore_for_file: implementation_imports
import 'package:stellar_flutter_sdk/src/network.dart';
import 'package:stellar_flutter_sdk/src/transaction.dart';
import 'package:stellar_flutter_sdk/src/util.dart';
import 'package:stellar_flutter_sdk/src/xdr/xdr.dart';

void main() {
  const memo = 'AAAAAQAAAAXvu79hYgAAAA=='; // MEMO_TEXT, bytes EF BB BF 61 62
  var m = XdrMemo.fromBase64EncodedXdrString(memo);
  print('XdrMemo  in : $memo');
  print('XdrMemo out : ${m.toBase64EncodedXdrString()}');
  const sc = 'AAAADgAAAAXvu79hYgAAAA=='; // SCV_STRING, same bytes
  print('XdrSCVal in : $sc');
  print('XdrSCVal out: ${XdrSCVal.fromBase64EncodedXdrString(sc).toBase64EncodedXdrString()}');

  // A real pubnet envelope (ledger 40000001) with only its memo text replaced.
  const env = 'AAAAAgAAAABSTh04F5yGRuzDsfhzZtQUhnLaHgY4Bf9HZXhQw+kkTwADDUABIfX+AAmFkwAAAAAAAAABAAAABe+7v2FiAAAAAAAAAQAAAAEAAAAAYSd9wNMUgqCI7bmo8/YYUMD8Tgt5AWP+LEM7SThIB7kAAAABAAAAAOXDqt/kCw0khZz7brrwCR79i8j1W5kyVZKR8d8S3vVOAAAAAAAAAAAk8WXAAAAAAAAAAAHD6SRPAAAAQHcPWaF0qqogZBBO8hAuiUZMpflFXC29MZqz5qN1xKrbfRNjdB17TGR5PPaInWmgYHHnBxrIrmLeU6p0R8wHbwA=';
  var tx = AbstractTransaction.fromEnvelopeXdrString(env);
  print('SDK hash : ${Util.bytesToHex(tx.hash(Network.PUBLIC)).toLowerCase()}');
  print('expected : 6f974d516bad6884082b4780a75a915a4b07a77400b6622681fabe56af869771 (rs-stellar-xdr 30.0.0)');
  print('envelope re-encodes the same: ${XdrTransactionEnvelope.fromBase64EncodedXdrString(env).toBase64EncodedXdrString() == env}');
}
