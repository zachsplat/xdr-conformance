// Candidate 10: an XDR bool of 2 decodes as true and re-encodes as 1.
// RFC 4506 4.4 defines bool as enum { FALSE = 0, TRUE = 1 }.
// ignore_for_file: implementation_imports
import 'package:stellar_flutter_sdk/src/xdr/xdr.dart';

void main() {
  const b64 = 'AAAAAAAAAAI='; // SCV_BOOL with value 2
  var v = XdrSCVal.fromBase64EncodedXdrString(b64);
  print('in : $b64 -> b=${v.b}');
  print('out: ${v.toBase64EncodedXdrString()}');
}
