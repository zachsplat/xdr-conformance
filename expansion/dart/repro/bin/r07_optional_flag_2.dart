// Candidate 7: an optional's presence flag of 2 is read as "present" and
// re-encoded as 1. XDR (RFC 4506 4.19) allows only 0 or 1; stellar-core rejects
// it ("xdr::pointer size must be 0 or 1").
// ignore_for_file: implementation_imports
import 'package:stellar_flutter_sdk/src/xdr/xdr.dart';

void main() {
  // Operation: sourceAccount flag 2, muxed ed25519 account of zeros, body INFLATION (void).
  const b64 = 'AAAAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAk=';
  var op = XdrOperation.fromBase64EncodedXdrString(b64);
  print('in : $b64');
  print('out: ${op.toBase64EncodedXdrString()}');
}
