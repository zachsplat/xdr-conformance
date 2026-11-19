// Candidate 1: the transaction model reduces a ManageSellOffer / ManageBuyOffer
// price fraction, so AbstractTransaction.hash() is not the network's hash.
// Input: pubnet transaction 8467c5a7... (ledger 59000001, index 85), price 390602/1000000.
// ignore_for_file: implementation_imports
import 'dart:typed_data';
import 'package:stellar_flutter_sdk/src/network.dart';
import 'package:stellar_flutter_sdk/src/transaction.dart';
import 'package:stellar_flutter_sdk/src/util.dart';
import 'package:stellar_flutter_sdk/src/xdr/xdr.dart';

const b64 = 'AAAAAgAAAADuQ1r07oMnl0gPB5e97K2iSs3PPjrAPK5hfNU8eSSKCAAPQkADfo8xAANeSAAAAAEAAAAAAAAAAAAAAABozVAdAAAAAAAAAAEAAAAAAAAAAwAAAAAAAAABVVNEQwAAAAA7mRE4Dv6Yi6CokA6xz+RPNm99vpRr7QdyQPf2JN8VxQAAAAZJU04AAAX1ygAPQkAAAAAAarZoPAAAAAAAAAABeSSKCAAAAEBagnNoKONDzZi3ewGRVhmRrBT4hS84rjPjQntLyZqBeHPFtb1YTV+obnuuJ0NstAolK0tvhJZNeemsNCQcJFMG';
const ledgerHash = '8467c5a77620dd9f0c1f7252213aa515105feebca1b2e114bcad4f7905ec8bee';

void main() {
  var tx = AbstractTransaction.fromEnvelopeXdrString(b64);
  print('SDK hash : ${Util.bytesToHex(tx.hash(Network.PUBLIC)).toLowerCase()}');
  print('expected : $ledgerHash (TransactionResultPair.transactionHash in the ledger)');

  // The same hash computed from the decoded XDR, without the model:
  var env = XdrTransactionEnvelope.fromBase64EncodedXdrString(b64);
  var o = XdrDataOutputStream();
  XdrTransaction.encode(o, env.v1!.tx);
  var base = <int>[...Network.PUBLIC.networkId, 0, 0, 0, 2, ...o.bytes];
  print('XDR hash : ${Util.bytesToHex(Util.hash(Uint8List.fromList(base))).toLowerCase()}');

  var p = env.v1!.tx.operations[0].body.manageSellOfferOp!.price;
  var q = tx.toEnvelopeXdr().v1!.tx.operations[0].body.manageSellOfferOp!.price;
  print('price in envelope : ${p.n.int32}/${p.d.int32}');
  print('price after model : ${q.n.int32}/${q.d.int32}');
  print('model re-encodes the same envelope: ${tx.toEnvelopeXdrBase64() == b64}');
}
