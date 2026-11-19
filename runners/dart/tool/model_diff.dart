// Diagnostic, not part of the protocol: for each envelope request, rebuild the
// envelope through the SDK's transaction model (AbstractTransaction) and report
// every SEP-51 JSON path (up to 8) where the model's envelope differs from the
// decoded one. Prints {"id", "path", "decoded", "model"} per differing input.
// ignore_for_file: implementation_imports
import 'dart:convert';
import 'dart:io';

import 'package:stellar_flutter_sdk/src/transaction.dart';
import 'package:stellar_flutter_sdk/src/xdr/xdr.dart';

void allDiffs(Object? a, Object? b, String path, List<List> out) {
  if (out.length >= 8) return;
  if (a is Map && b is Map) {
    for (var k in {...a.keys, ...b.keys}) {
      if (!a.containsKey(k) || !b.containsKey(k)) {
        out.add([path + '.' + k, a[k], b[k]]);
      } else {
        allDiffs(a[k], b[k], path + '.' + k, out);
      }
    }
    return;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      out.add([path + '[len]', a.length, b.length]);
      return;
    }
    for (var i = 0; i < a.length; i++) {
      allDiffs(a[i], b[i], '$path[$i]', out);
    }
    return;
  }
  if (a != b) out.add([path, a, b]);
}

String short(Object? v) {
  var s = jsonEncode(v);
  return s.length > 200 ? s.substring(0, 200) : s;
}

void main() {
  while (true) {
    var line = stdin.readLineSync();
    if (line == null) break;
    if (line.trim().isEmpty) continue;
    var req = jsonDecode(line);
    try {
      var env = XdrTransactionEnvelope.fromBase64EncodedXdrString(req['b64']);
      var tx = AbstractTransaction.fromEnvelopeXdr(env);
      var back = tx.toEnvelopeXdr();
      var diffs = <List>[];
      allDiffs(env.toXdrJsonValue(), back.toXdrJsonValue(), r'$', diffs);
      for (var d in diffs) {
        stdout.writeln(jsonEncode({'id': req['id'], 'path': d[0], 'decoded': short(d[1]), 'model': short(d[2])}));
      }
    } catch (e) {
      stdout.writeln(jsonEncode({'id': req['id'], 'error': '$e'.substring(0, ('$e').length.clamp(0, 200))}));
    }
  }
}
