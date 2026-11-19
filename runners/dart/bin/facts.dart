// Conformance adapter for the Dart SDK (Soneso/stellar_flutter_sdk).
//
// Same JSONL protocol as runners/rust/src/facts.rs and runners/python/facts.py:
// one request per line on stdin, one result per line on stdout.
//   {"id", "op": "decode", "type", "b64", "network"?}
//   -> {"id", "ok", "error"?, "roundtrip_equal", "reencoded_b64"?, "json", "hash"?}
//   {"id", "op": "from_json", "type", "json"} -> {"id", "ok", "error"?, "b64"}
//
// Decoding goes through the SDK's generated XDR classes (`XdrX.decode` on an
// `XdrDataInputStream`, the same path as `fromBase64EncodedXdrString`), the JSON
// is the SDK's own SEP-51 rendering (`toXdrJsonValue`), and the transaction hash
// goes through the SDK's transaction model (`AbstractTransaction
// .fromEnvelopeXdrString(...).hash(Network(passphrase))`).
//
// The package's top-level library exports smart-account code that imports
// package:flutter, so this file imports the XDR and transaction libraries
// directly; none of them reach dart:ui, so the plain Dart VM runs them.
// ignore_for_file: implementation_imports
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:stellar_flutter_sdk/src/network.dart';
import 'package:stellar_flutter_sdk/src/transaction.dart';
import 'package:stellar_flutter_sdk/src/util.dart';
import 'package:stellar_flutter_sdk/src/xdr/xdr.dart';

class Codec {
  final Object Function(XdrDataInputStream) decode;
  final void Function(XdrDataOutputStream, Object) encode;
  final Object? Function(Object) toJson;
  final Object Function(Object?) fromJson;
  Codec(this.decode, this.encode, this.toJson, this.fromJson);
}

final Map<String, Codec> codecs = {
  'transactionenvelope': Codec(
    (s) => XdrTransactionEnvelope.decode(s),
    (o, v) => XdrTransactionEnvelope.encode(o, v as XdrTransactionEnvelope),
    (v) => (v as XdrTransactionEnvelope).toXdrJsonValue(),
    (j) => XdrTransactionEnvelope.fromXdrJsonValue(j),
  ),
  'transactionresultmeta': Codec(
    (s) => XdrTransactionResultMeta.decode(s),
    (o, v) => XdrTransactionResultMeta.encode(o, v as XdrTransactionResultMeta),
    (v) => (v as XdrTransactionResultMeta).toXdrJsonValue(),
    (j) => XdrTransactionResultMeta.fromXdrJsonValue(j),
  ),
  'transactionresultmetav1': Codec(
    (s) => XdrTransactionResultMetaV1.decode(s),
    (o, v) =>
        XdrTransactionResultMetaV1.encode(o, v as XdrTransactionResultMetaV1),
    (v) => (v as XdrTransactionResultMetaV1).toXdrJsonValue(),
    (j) => XdrTransactionResultMetaV1.fromXdrJsonValue(j),
  ),
  'transactionmeta': Codec(
    (s) => XdrTransactionMeta.decode(s),
    (o, v) => XdrTransactionMeta.encode(o, v as XdrTransactionMeta),
    (v) => (v as XdrTransactionMeta).toXdrJsonValue(),
    (j) => XdrTransactionMeta.fromXdrJsonValue(j),
  ),
  'ledgerclosemeta': Codec(
    (s) => XdrLedgerCloseMeta.decode(s),
    (o, v) => XdrLedgerCloseMeta.encode(o, v as XdrLedgerCloseMeta),
    (v) => (v as XdrLedgerCloseMeta).toXdrJsonValue(),
    (j) => XdrLedgerCloseMeta.fromXdrJsonValue(j),
  ),
  'ledgerclosemetabatch': Codec(
    (s) => XdrLedgerCloseMetaBatch.decode(s),
    (o, v) => XdrLedgerCloseMetaBatch.encode(o, v as XdrLedgerCloseMetaBatch),
    (v) => (v as XdrLedgerCloseMetaBatch).toXdrJsonValue(),
    (j) => XdrLedgerCloseMetaBatch.fromXdrJsonValue(j),
  ),
};

String errText(Object e) {
  var s = '${e.runtimeType}: $e';
  return s.length > 300 ? s.substring(0, 300) : s;
}

bool bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String? txHash(String b64, String passphrase) {
  try {
    var tx = AbstractTransaction.fromEnvelopeXdrString(b64);
    return Util.bytesToHex(tx.hash(Network(passphrase))).toLowerCase();
  } catch (e) {
    var s = 'error: ${errText(e)}';
    return s.length > 200 ? s.substring(0, 200) : s;
  }
}

Map<String, Object?> decode(Map<String, dynamic> req) {
  var out = <String, Object?>{'id': req['id']};
  var codec = codecs[(req['type'] as String).toLowerCase()];
  if (codec == null) {
    out['ok'] = false;
    out['error'] = 'unsupported type ${req['type']}';
    return out;
  }
  Uint8List raw;
  Uint8List back;
  Object? js;
  try {
    raw = base64Decode(req['b64'] as String);
    var v = codec.decode(XdrDataInputStream(raw));
    var o = XdrDataOutputStream();
    codec.encode(o, v);
    back = Uint8List.fromList(o.bytes);
    try {
      js = codec.toJson(v);
    } catch (e) {
      // The decode succeeded; only the JSON writer failed. Report it as a
      // json_error so the decode verdict still compares.
      js = null;
      out['json_error'] = errText(e);
    }
  } catch (e) {
    out['ok'] = false;
    out['error'] = errText(e);
    return out;
  }
  var eq = bytesEqual(back, raw);
  out['ok'] = true;
  out['roundtrip_equal'] = eq;
  if (js != null) out['json'] = js;
  if (!eq) out['reencoded_b64'] = base64Encode(back);
  var net = req['network'];
  if ((req['type'] as String).toLowerCase() == 'transactionenvelope' &&
      net is String &&
      net.isNotEmpty) {
    out['hash'] = txHash(req['b64'] as String, net);
  }
  return out;
}

Map<String, Object?> fromJson(Map<String, dynamic> req) {
  var out = <String, Object?>{'id': req['id']};
  try {
    var codec = codecs[(req['type'] as String).toLowerCase()]!;
    var v = codec.fromJson(req['json']);
    var o = XdrDataOutputStream();
    codec.encode(o, v);
    out['ok'] = true;
    out['b64'] = base64Encode(o.bytes);
  } catch (e) {
    out['ok'] = false;
    out['error'] = errText(e);
  }
  return out;
}

void main() {
  var sink = stdout;
  while (true) {
    var line = stdin.readLineSync(encoding: utf8);
    if (line == null) break;
    if (line.trim().isEmpty) continue;
    Map<String, dynamic> req;
    try {
      req = jsonDecode(line) as Map<String, dynamic>;
    } catch (e) {
      sink.writeln(jsonEncode({'id': null, 'ok': false, 'error': errText(e)}));
      continue;
    }
    Map<String, Object?> res;
    try {
      res = req['op'] == 'from_json' ? fromJson(req) : decode(req);
    } catch (e) {
      res = {'id': req['id'], 'ok': false, 'error': 'adapter: ${errText(e)}'};
    }
    String text;
    try {
      text = jsonEncode(res);
    } catch (e) {
      res.remove('json');
      res['json_error'] = 'jsonEncode: ${errText(e)}';
      text = jsonEncode(res);
    }
    sink.writeln(text);
  }
}
