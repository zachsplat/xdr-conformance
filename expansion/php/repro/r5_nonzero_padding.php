<?php
// Non-zero XDR padding is accepted and silently replaced by zeros, so two different byte
// strings decode to one value. Input: Memo MEMO_TEXT "a" with padding bytes 01 00 00.
require getenv('SDK_VENDOR') . '/autoload.php';
use Soneso\StellarSDK\Xdr\XdrMemo;

$b64 = 'AAAAAQAAAAFhAQAA';
$m = XdrMemo::fromBase64Xdr($b64);
echo "observed: accepted, text=", json_encode($m->getText()), ", re-encodes as ", $m->toBase64Xdr(), " (input $b64)\n";
echo "expected: rejected (rs-stellar-xdr: \"xdr padding contains non-zero bytes\"; stellar-core print-xdr: \"Non-zero padding bytes encountered\")\n";
