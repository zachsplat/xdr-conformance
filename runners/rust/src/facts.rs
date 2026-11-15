//! Conformance adapter for rs-stellar-xdr.
//!
//! Reads JSONL requests on stdin and writes one JSONL result per request:
//!   {"id", "op": "decode", "type", "b64", "network"?}
//!     -> {"id", "ok", "error"?, "roundtrip_equal", "reencoded_b64"?, "json", "hash"?}
//!   {"id", "op": "from_json", "type", "json"}
//!     -> {"id", "ok", "error"?, "b64"}
//! "type" is the XDR type name as written in the .x files (TransactionEnvelope,
//! ScVal, LedgerCloseMetaBatch, ...).

use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::io::{BufRead, Write};
use std::str::FromStr;
use stellar_xdr::{Limited, Limits, ReadXdr, TransactionEnvelope, Type, TypeVariant, WriteXdr};

fn b64d(s: &str) -> Result<Vec<u8>, String> {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD.decode(s).map_err(|e| e.to_string())
}
fn b64e(b: &[u8]) -> String {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD.encode(b)
}

fn variant(name: &str) -> Option<TypeVariant> {
    use stellar_xdr::Name;
    TypeVariant::from_str(name)
        .ok()
        .or_else(|| TypeVariant::VARIANTS.iter().copied().find(|v| v.name().eq_ignore_ascii_case(name)))
}

fn decode(req: &Value) -> Value {
    let id = req["id"].clone();
    let ty = req["type"].as_str().unwrap_or("");
    let variant = match variant(ty) {
        Some(v) => v,
        None => return json!({"id": id, "ok": false, "error": format!("unknown type {ty}")}),
    };
    let bytes = match b64d(req["b64"].as_str().unwrap_or("")) {
        Ok(b) => b,
        Err(e) => return json!({"id": id, "ok": false, "error": format!("base64: {e}")}),
    };
    // Depth 500 unless XDRCONF_DEFAULTS=1; input length bounds every allocation.
    // XDRCONF_DEFAULTS=1 uses Limits::none(), what most callers pass.
    // XDRCONF_DEPTH=1000 reproduces stellar-core's admission check from protocol 28
    // (validateXDRForProtocol -> can_parse_transaction, depth 1000).
    let depth = std::env::var("XDRCONF_DEPTH").ok().and_then(|d| d.parse().ok()).unwrap_or(500);
    let limits = if std::env::var("XDRCONF_DEFAULTS").as_deref() == Ok("1") {
        Limits::none()
    } else {
        Limits { depth, len: bytes.len() }
    };
    let mut cur = Limited::new(std::io::Cursor::new(&bytes[..]), limits);
    let t = match Type::read_xdr_to_end(variant, &mut cur) {
        Ok(t) => t,
        Err(e) => return json!({"id": id, "ok": false, "error": e.to_string()}),
    };
    let back = t.to_xdr(Limits::none()).unwrap_or_default();
    let mut out = json!({
        "id": id,
        "ok": true,
        "roundtrip_equal": back == bytes,
        "json": serde_json::to_value(&t).unwrap_or(Value::Null),
    });
    if back != bytes {
        out["reencoded_b64"] = json!(b64e(&back));
    }
    if ty == "TransactionEnvelope" {
        if let Some(pass) = req.get("network").and_then(|v| v.as_str()) {
            let nid: [u8; 32] = Sha256::digest(pass.as_bytes()).into();
            if let Ok(env) = TransactionEnvelope::from_xdr(&bytes, Limits::none()) {
                if let Ok(h) = env.hash(nid) {
                    out["hash"] = json!(hex::encode(h));
                }
            }
        }
    }
    out
}

fn from_json(req: &Value) -> Value {
    let id = req["id"].clone();
    let ty = req["type"].as_str().unwrap_or("");
    let variant = match variant(ty) {
        Some(v) => v,
        None => return json!({"id": id, "ok": false, "error": format!("unknown type {ty}")}),
    };
    let text = serde_json::to_string(&req["json"]).unwrap();
    match Type::from_json(variant, text.as_bytes()) {
        Ok(t) => match t.to_xdr(Limits::none()) {
            Ok(b) => json!({"id": id, "ok": true, "b64": b64e(&b)}),
            Err(e) => json!({"id": id, "ok": false, "error": e.to_string()}),
        },
        Err(e) => json!({"id": id, "ok": false, "error": e.to_string()}),
    }
}

fn main() {
    let stdin = std::io::stdin();
    let mut out = std::io::BufWriter::new(std::io::stdout());
    for line in stdin.lock().lines() {
        let line = line.unwrap();
        if line.trim().is_empty() {
            continue;
        }
        let req: Value = serde_json::from_str(&line).unwrap();
        let res = match req["op"].as_str().unwrap_or("decode") {
            "from_json" => from_json(&req),
            _ => decode(&req),
        };
        writeln!(out, "{res}").unwrap();
    }
}
