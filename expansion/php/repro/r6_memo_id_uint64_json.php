<?php
// toJson() throws for a memo id from 2^63 up. Input: Memo MEMO_ID 14566324710427066368
// (the memo of pubnet ledger 40000000, transaction index 5).
require getenv('SDK_VENDOR') . '/autoload.php';
use Soneso\StellarSDK\Xdr\XdrMemo;

$b64 = 'AAAAAsol+yYAAAAA';
$m = XdrMemo::fromBase64Xdr($b64);
try {
    $json = $m->toJson();
    echo "observed: $json\n";
} catch (Throwable $e) {
    echo "observed: ", get_class($e), ": ", $e->getMessage(), "\n";
}
echo "expected (rs-stellar-xdr 30.0.0): {\"id\":\"14566324710427066368\"}\n";
