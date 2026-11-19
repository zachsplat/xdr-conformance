// Candidate 2: TransactionPreconditions turns a PRECOND_V2 whose only set field
// is timeBounds (minSeqNum present as 0, everything else empty) into
// PRECOND_TIME, so the hash of the parsed transaction is not the network's hash.
// Input: pubnet fee-bump transaction b48ed267... (ledger 65486054, index 181).
// ignore_for_file: implementation_imports
import 'package:stellar_flutter_sdk/src/network.dart';
import 'package:stellar_flutter_sdk/src/transaction.dart';
import 'package:stellar_flutter_sdk/src/util.dart';
import 'package:stellar_flutter_sdk/src/xdr/xdr.dart';

const b64 = 'AAAABQAAAABIlh0MBJIUGNXtFAE1GZwbvIkLVkJ/W68qOzeIr59BJgAAAAAARKomAAAAAgAAAABK6mxmjpjABEUqazC64ZyiLoQy7GDw6goaYiEQXS22yAAAAGYDjzwLAAAa3gAAAAIAAAABAAAAAGr0nrUAAAAAav3GdQAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAABAAAAAQAAAABIlh0MBJIUGNXtFAE1GZwbvIkLVkJ/W68qOzeIr59BJgAAAAIAAAABeVhMTQAAAAAiNtdw/g0+AVIZddXPesSEK3CV1rGp12jT6aYy6ZkGvgAAAAAAfZrFAAAAAEiWHQwEkhQY1e0UATUZnBu8iQtWQn9bryo7N4ivn0EmAAAAAAAAAAAAfZrFAAAAAgAAAAJ5VVNEQwAAAAAAAAAAAAAAzTraTOMNLk/59bkX2cI5NI9EZRILk0tjcD212hOLctkAAAABODE4AAAAAABAIAF6Dwmw6EUjhz1on4+tyZ7dD+D00TcQUv9Oyl8zHwAAAAAAAAACXS22yAAAAEDE12V7ZD+VZbtu9ywJGuf0MHVCr6DQikZX71x8wyIILGFRTqRPl1RpOWslOUrl+0EzwVkNjgf+vR9MLs4v7bEAr59BJgAAAEAszqFD3DAyKRTHMzYjmVAfIgeRqHqbZB0SeRUZXRx0UHePsRoyEofhxmVv/P3NmjpJVFWwLqSUjNS5YRs4vlsLAAAAAAAAAAo0pSUjAAAAQOihtln5QjzQgMtf+slCJsPpVFuRs+ji0ldM1++pWYrbMO8xm+wEliLxlPjeUcvM7/r1/T22rFtF/tIk2NNZSQ4fHArWAAAAAXUAAACSGkiBAAAAAXgAAADe+2SjAAAAATgAAABbk/bwAAAAAWwAAAAptJ/OAAAAATMAAAA8mv4pAAAAAWcAAADVnACdAAAAAWIAAAAn+1fpAAAAATAAAADsE6s1AAAAATIAAAA=';
const ledgerHash = 'b48ed2676e987cd2a258e0d1cd0c03e1819c881d51d6959d67c7f78cfc8ddf43';

void main() {
  var env = XdrTransactionEnvelope.fromBase64EncodedXdrString(b64);
  var tx = AbstractTransaction.fromEnvelopeXdrString(b64);
  print('SDK hash : ${Util.bytesToHex(tx.hash(Network.PUBLIC)).toLowerCase()}');
  print('expected : $ledgerHash (TransactionResultPair.transactionHash in the ledger)');
  var inner = env.feeBump!.tx.innerTx.v1!.tx.cond;
  var model = (tx as FeeBumpTransaction).innerTransaction.preconditions!.toXdr();
  print('cond in envelope : ${inner.discriminant.value} (2 = PRECOND_V2), minSeqNum=${inner.v2?.minSeqNum?.sequenceNumber}');
  print('cond after model : ${model.discriminant.value} (1 = PRECOND_TIME)');
}
