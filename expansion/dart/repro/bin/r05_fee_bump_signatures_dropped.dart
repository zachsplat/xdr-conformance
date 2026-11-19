// Candidate 5: AbstractTransaction.fromEnvelopeXdrString on a fee-bump envelope
// drops the outer (fee source) signatures, so toEnvelopeXdrBase64() writes an
// envelope with no fee-bump signatures. Inner signatures are kept.
// Input: pubnet fee-bump transaction (ledger 65486182, index 92).
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
