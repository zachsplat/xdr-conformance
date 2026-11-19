// ignore_for_file: implementation_imports
import 'dart:math';
import 'package:stellar_flutter_sdk/src/price.dart';

void main() {
  var r = Random(7);
  var pairs = <List<int>>[[2147483647, 2147483646], [2147483646, 2147483647], [1, 2147483647], [2147483647, 1], [1, 3], [2, 3], [123456789, 987654321], [1000000007, 998244353]];
  for (var i = 0; i < 200000; i++) {
    pairs.add([1 + r.nextInt(2147483647), 1 + r.nextInt(2147483647)]);
  }
  var bad = 0;
  for (var p in pairs) {
    var s = Price(p[0], p[1]).toDecimalString();
    var q = Price.fromString(s);
    if (BigInt.from(q.n) * BigInt.from(p[1]) != BigInt.from(p[0]) * BigInt.from(q.d)) {
      bad++;
      if (bad <= 5) print('value changed: ${p[0]}/${p[1]} -> "$s" -> ${q.n}/${q.d}');
    }
  }
  print('checked ${pairs.length}, value changed in $bad');
}
