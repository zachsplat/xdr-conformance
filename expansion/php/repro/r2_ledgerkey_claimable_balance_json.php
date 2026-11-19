<?php
// LedgerKey CLAIMABLE_BALANCE is written without its balance_id member in SEP-51 JSON,
// and the canonical form is refused on input.
// Input: LedgerKey, type 4 (CLAIMABLE_BALANCE), ClaimableBalanceID v0 with hash 00 01 .. 1f.
require getenv('SDK_VENDOR') . '/autoload.php';
use Soneso\StellarSDK\Xdr\XdrLedgerKey;

$b64 = 'AAAABAAAAAAAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHw==';
echo "observed: ", XdrLedgerKey::fromBase64Xdr($b64)->toJson(), "\n";
$canonical = '{"claimable_balance":{"balance_id":"BAAAAAICAMCAKBQHBAEQUCYMBUHA6EARCIJRIFIWC4MBSGQ3DQOR4H2TOM"}}';
echo "expected (rs-stellar-xdr 30.0.0): $canonical\n";
try {
    $out = XdrLedgerKey::fromJson($canonical)->toBase64Xdr();
    echo "canonical JSON -> XDR: $out\n";
} catch (Throwable $e) {
    echo "canonical JSON -> XDR: ", get_class($e), ": ", $e->getMessage(), "\n";
}
