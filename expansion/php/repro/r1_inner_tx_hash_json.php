<?php
// Fee-bump inner transaction hash is written as the hex of its hex in SEP-51 JSON,
// and the SDK cannot read its own JSON (or the canonical JSON) back.
// Input: the TransactionResultPair of pubnet ledger 50460000, tx 3940d27a...6267 (a fee bump).
require getenv('SDK_VENDOR') . '/autoload.php';
use Soneso\StellarSDK\Xdr\XdrTransactionResultPair;

$b64 = 'OUDSen17JmXAc2dCwh5hOjb4E9rWoxSDn73zAS9mYmcAAAAAAAAAyAAAAAGi3HCf/UJ5m7RCqwwL5Vt9fZjNzPHLtD4ijcbs7q7RAwAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAQAAAAAAAAAAAAAAAA==';
$pair = XdrTransactionResultPair::fromBase64Xdr($b64);
$json = $pair->toJsonValue();
$inner = $json['result']['result']['tx_fee_bump_inner_success']['transaction_hash'];
echo "observed inner transaction_hash: $inner (", strlen($inner), " chars)\n";
echo "expected (rs-stellar-xdr 30.0.0): a2dc709ffd42799bb442ab0c0be55b7d7d98cdccf1cbb43e228dc6eceeaed103 (64 chars)\n";

// Read the canonical SEP-51 JSON (as rs-stellar-xdr writes it for these bytes) and re-encode.
$canonical = '{"result":{"ext":"v0","fee_charged":"200","result":{"tx_fee_bump_inner_success":{"result":{"ext":"v0","fee_charged":"0","result":{"tx_success":[{"op_inner":{"payment":"success"}}]}},"transaction_hash":"a2dc709ffd42799bb442ab0c0be55b7d7d98cdccf1cbb43e228dc6eceeaed103"}}},"transaction_hash":"3940d27a7d7b2665c0736742c21e613a36f813dad6a314839fbdf3012f666267"}';
$warnings = [];
set_error_handler(function ($no, $str) use (&$warnings) { $warnings[] = $str; return true; });
try {
    $back = XdrTransactionResultPair::fromJson($canonical)->toBase64Xdr();
    echo "canonical JSON -> XDR equals input: ", var_export($back === $b64, true), "\n";
} catch (Throwable $e) {
    echo "canonical JSON -> XDR: ", get_class($e), ": ", $e->getMessage(), "\n";
}
echo "PHP warnings raised: ", count($warnings), ($warnings ? " (first: " . preg_replace('/[^\x20-\x7e]/', '?', $warnings[0]) . ")" : ""), "\n";
