<?php
// LedgerKey CONFIG_SETTING is written without its config_setting_id member in SEP-51 JSON
// (same flattening as the claimable_balance arm), and the canonical form is refused on input.
// Input: LedgerKey, type 8 (CONFIG_SETTING), ConfigSettingID 0 (CONFIG_SETTING_CONTRACT_MAX_SIZE_BYTES).
require getenv('SDK_VENDOR') . '/autoload.php';
use Soneso\StellarSDK\Xdr\XdrLedgerKey;

$b64 = 'AAAACAAAAAA=';
echo "observed: ", XdrLedgerKey::fromBase64Xdr($b64)->toJson(), "\n";
$canonical = '{"config_setting":{"config_setting_id":"contract_max_size_bytes"}}';
echo "expected (rs-stellar-xdr 30.0.0): $canonical\n";
try {
    $out = XdrLedgerKey::fromJson($canonical)->toBase64Xdr();
    echo "canonical JSON -> XDR: $out\n";
} catch (Throwable $e) {
    echo "canonical JSON -> XDR: ", get_class($e), ": ", $e->getMessage(), "\n";
}
