// Candidate 9: when the input ends where XDR padding should be, the padding is
// skipped without error. stellar-core rejects such input ("message size not
// multiple of 4") and rs-stellar-xdr rejects it too.
// ignore_for_file: implementation_imports
import 'package:stellar_flutter_sdk/src/xdr/xdr.dart';

void main() {
  const b64 = 'AAAAAQAAAANhYmM='; // MEMO_TEXT "abc", 11 bytes, the 1 padding byte missing
  var m = XdrMemo.fromBase64EncodedXdrString(b64);
  print('in : $b64 -> text "${m.text}"');
  print('out: ${m.toBase64EncodedXdrString()}');
}
