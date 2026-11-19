<?php declare(strict_types=1);
/*
 * Conformance adapter for soneso/stellar-php-sdk (Soneso\StellarSDK\Xdr).
 *
 * Same JSONL protocol as runners/rust/src/facts.rs and runners/python/facts.py:
 *   request  {"id", "op": "decode" | "from_json", "type", "b64" | "json", "network"?}
 *   decode   {"id", "ok", "error"?, "roundtrip_equal", "reencoded_b64"?, "hash"?, "json"?}
 *   from_json {"id", "ok", "error"?, "b64"?}
 *
 * "json" is the SDK's own SEP-51 output (toJson()), embedded verbatim.
 * "hash" goes through the SDK transaction model:
 *   AbstractTransaction::fromEnvelopeXdr($env)->hash(new Network($passphrase)).
 * The SDK is used exactly as shipped (its own depth limits).
 *
 * Run (see runners/php/run.sh): php facts.php < req.jsonl > out.jsonl
 * XDRCONF_PHP_VENDOR points at the composer vendor dir (default ./vendor).
 */

$vendor = getenv('XDRCONF_PHP_VENDOR') ?: __DIR__ . '/vendor';
require $vendor . '/autoload.php';

use Soneso\StellarSDK\AbstractTransaction;
use Soneso\StellarSDK\Network;
use Soneso\StellarSDK\Xdr\XdrBuffer;

ini_set('memory_limit', '4G');
error_reporting(E_ALL);
// Turn PHP warnings and notices raised inside the SDK into exceptions so a
// decode that only "works" with a warning is visible as a failure.
set_error_handler(function (int $no, string $str, string $file, int $line) {
    throw new ErrorException($str, 0, $no, $file, $line);
});

function xdr_class(string $type): string
{
    $cls = 'Soneso\\StellarSDK\\Xdr\\Xdr' . $type;
    if (!class_exists($cls)) {
        throw new InvalidArgumentException("no SDK class for XDR type $type");
    }
    return $cls;
}

function err_text(Throwable $e): string
{
    $s = get_class($e) . ': ' . $e->getMessage();
    if (!($e instanceof InvalidArgumentException)) {
        // Non-validation failures are the interesting ones; keep the origin.
        $s .= ' @' . basename($e->getFile()) . ':' . $e->getLine();
    }
    return substr($s, 0, 300);
}

function decode_req(array $req): string
{
    $id = $req['id'];
    try {
        $raw = base64_decode($req['b64'], true);
        if ($raw === false) {
            throw new InvalidArgumentException('bad base64');
        }
        $cls = xdr_class($req['type']);
        // fromBase64Xdr() is the SDK's reader for one complete value (on main it
        // also rejects trailing bytes); decode() is the nested-value reader.
        $v = method_exists($cls, 'fromBase64Xdr') ? $cls::fromBase64Xdr($req['b64']) : $cls::decode(new XdrBuffer($raw));
        $back = $v->encode();
    } catch (Throwable $e) {
        return json_encode(['id' => $id, 'ok' => false, 'error' => err_text($e)], JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
    }
    $out = ['id' => $id, 'ok' => true, 'roundtrip_equal' => ($back === $raw)];
    if ($back !== $raw) {
        $out['reencoded_b64'] = base64_encode($back);
    }
    if ($req['type'] === 'TransactionEnvelope' && !empty($req['network'])) {
        try {
            $tx = AbstractTransaction::fromEnvelopeXdr($v);
            $out['hash'] = bin2hex($tx->hash(new Network($req['network'])));
        } catch (Throwable $e) {
            $out['hash'] = 'error: ' . substr(err_text($e), 0, 200);
        }
    }
    // SEP-51 JSON is a separate check: a failure here is reported as
    // json_error and does not turn a successful decode into ok=false.
    $json = null;
    try {
        $json = $v->toJson();
    } catch (Throwable $e) {
        $out['json_error'] = err_text($e);
    }
    $line = json_encode($out, JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
    if ($json === null) {
        return $line;
    }
    // Embed the SDK's JSON text verbatim so {} vs [] is exactly what it wrote.
    return substr($line, 0, -1) . ',"json":' . $json . '}';
}

function from_json_req(array $req, string $line): string
{
    $id = $req['id'];
    try {
        $cls = xdr_class($req['type']);
        // Decode as objects so {} stays {} when the value is handed back as text.
        $obj = json_decode($line, false, 100000, JSON_THROW_ON_ERROR | JSON_BIGINT_AS_STRING);
        $text = json_encode($obj->json, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION | JSON_THROW_ON_ERROR);
        $v = $cls::fromJson($text);
        return json_encode(['id' => $id, 'ok' => true, 'b64' => base64_encode($v->encode())], JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
    } catch (Throwable $e) {
        return json_encode(['id' => $id, 'ok' => false, 'error' => err_text($e)], JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
    }
}

$in = fopen('php://stdin', 'r');
$out = fopen('php://stdout', 'w');
while (($line = fgets($in)) !== false) {
    if (trim($line) === '') {
        continue;
    }
    try {
        $req = json_decode($line, true, 100000, JSON_THROW_ON_ERROR | JSON_BIGINT_AS_STRING);
        $res = (($req['op'] ?? 'decode') === 'from_json') ? from_json_req($req, $line) : decode_req($req);
    } catch (Throwable $e) {
        $res = json_encode(['id' => $req['id'] ?? null, 'ok' => false, 'error' => 'adapter: ' . err_text($e)], JSON_INVALID_UTF8_SUBSTITUTE);
    }
    fwrite($out, $res . "\n");
}
