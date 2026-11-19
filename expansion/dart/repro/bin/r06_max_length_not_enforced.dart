// Candidate 6: the binary decoder does not enforce declared maximum lengths
// (string<28> memo text, opaque<64> signed payload, Operation<100>). The value
// decodes and re-encodes, while the SDK's own SEP-51 writer refuses it.
// stellar-core rejects all of these ("xstring overflow", "xvector overflow").
// ignore_for_file: implementation_imports
import 'package:stellar_flutter_sdk/src/xdr/xdr.dart';

void show(String name, String b64, Object Function(String) dec, String Function(Object) enc, String Function(Object) json) {
  var v = dec(b64);
  print('$name decodes; re-encodes the same: ${enc(v) == b64}');
  try {
    json(v);
    print('  SEP-51 JSON written');
  } catch (e) {
    print('  SEP-51 JSON: $e');
  }
}

void main() {
  // MEMO_TEXT of 29 bytes ("a" x 29); Memo is string<28>.
  show('XdrMemo(29-byte text)', 'AAAAAQAAAB1hYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYQAAAA==',
      (s) => XdrMemo.fromBase64EncodedXdrString(s),
      (v) => (v as XdrMemo).toBase64EncodedXdrString(),
      (v) => (v as XdrMemo).toXdrJson());
  // SIGNER_KEY_TYPE_ED25519_SIGNED_PAYLOAD with a 65-byte payload; payload is opaque<64>.
  show('XdrSignerKey(65-byte payload)',
      'AAAAAxERERERERERERERERERERERERERERERERERERERERERAAAAQSIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiAAAA',
      (s) => XdrSignerKey.fromBase64EncodedXdrString(s),
      (v) => (v as XdrSignerKey).toBase64EncodedXdrString(),
      (v) => (v as XdrSignerKey).toXdrJson());
}
