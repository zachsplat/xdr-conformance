<?php
// toJson() throws for a transaction stellar-core admits: a real pubnet Soroban envelope whose
// authorization tree was deepened to 250 levels (kit depth sweep input auth/250; stellar-core 30
// print-xdr and its protocol-28 admission parse both accept it, reports/depth-sweep.md).
require getenv('SDK_VENDOR') . '/autoload.php';
use Soneso\StellarSDK\Xdr\XdrTransactionEnvelope;

$b64 = trim(file_get_contents(__DIR__ . '/auth250.b64'));
$env = XdrTransactionEnvelope::fromEnvelopeBase64XdrString($b64);
echo "binary decode ok, re-encodes to the same bytes: ", var_export($env->toBase64Xdr() === $b64, true), "\n";
try {
    $json = $env->toJson();
    echo "toJson ok, ", strlen($json), " chars\n";
} catch (Throwable $e) {
    echo "toJson: ", get_class($e), ": ", $e->getMessage(), "\n";
}
echo "expected: SEP-51 JSON (rs-stellar-xdr 30.0.0 writes it: 90,632 chars, 514 JSON levels)\n";
