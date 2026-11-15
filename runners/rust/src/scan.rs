//! Scan Galexie LedgerCloseMetaBatch files, check that each one round-trips
//! byte for byte through rs-stellar-xdr, and tag every transaction with the
//! rare shapes it contains. Output feeds tools/pick_corpus.py.
//!
//! Usage: scan IN_DIR OUT_DIR PASSPHRASE
//! Writes OUT_DIR/lcm/<seq>.xdr (uncompressed batch) and OUT_DIR/txs.jsonl.

use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
use std::fs;
use std::io::Write;
use std::path::Path;
use stellar_xdr::{
    GeneralizedTransactionSet, LedgerCloseMeta, LedgerCloseMetaBatch, Limits, ReadXdr,
    TransactionEnvelope, TransactionPhase, TxSetComponent, WriteXdr,
};

fn envelopes(set: &GeneralizedTransactionSet) -> Vec<TransactionEnvelope> {
    let mut out = vec![];
    let GeneralizedTransactionSet::V1(v1) = set;
    for phase in v1.phases.iter() {
        match phase {
            TransactionPhase::V0(comps) => {
                for c in comps.iter() {
                    let TxSetComponent::TxsetCompTxsMaybeDiscountedFee(c) = c;
                    out.extend(c.txs.iter().cloned());
                }
            }
            TransactionPhase::V1(p) => {
                for stage in p.execution_stages.iter() {
                    for cluster in stage.0.iter() {
                        out.extend(cluster.0.iter().cloned());
                    }
                }
            }
        }
    }
    out
}

/// Every string leaf in document order, with the key it sits under.
fn walk<'a>(v: &'a Value, key: &str, out: &mut Vec<(String, &'a Value)>) {
    out.push((key.to_string(), v));
    match v {
        Value::Object(m) => {
            for (k, c) in m {
                walk(c, k, out);
            }
        }
        Value::Array(a) => {
            for c in a {
                walk(c, key, out);
            }
        }
        _ => {}
    }
}

fn depth_of(v: &Value, field: &str) -> usize {
    // Depth of nesting of `field` arrays (e.g. sub_invocations).
    match v {
        Value::Object(m) => {
            let mut best = 0;
            for (k, c) in m {
                let d = depth_of(c, field);
                let d = if k == field { if let Value::Array(a) = c { if a.is_empty() { d } else { d + 1 } } else { d } } else { d };
                best = best.max(d);
            }
            best
        }
        Value::Array(a) => a.iter().map(|c| depth_of(c, field)).max().unwrap_or(0),
        _ => 0,
    }
}

fn pred_depth(v: &Value) -> usize {
    match v {
        Value::Object(m) => {
            let inner = m.values().map(pred_depth).max().unwrap_or(0);
            if m.contains_key("and") || m.contains_key("or") || m.contains_key("not") {
                inner + 1
            } else {
                inner
            }
        }
        Value::Array(a) => a.iter().map(pred_depth).max().unwrap_or(0),
        _ => 0,
    }
}

fn issuer_bytes(s: &str) -> Option<[u8; 32]> {
    match stellar_strkey::Strkey::from_string(s).ok()? {
        stellar_strkey::Strkey::PublicKeyEd25519(k) => Some(k.0),
        _ => None,
    }
}

fn asset_parts(a: &Value) -> Option<(String, String, String)> {
    let m = a.as_object()?;
    let (ty, body) = m.iter().next()?;
    let b = body.as_object()?;
    Some((
        ty.clone(),
        b.get("asset_code")?.as_str()?.to_string(),
        b.get("issuer")?.as_str()?.to_string(),
    ))
}

fn tag(env: &Value, meta: &Value, env_t: &TransactionEnvelope, tags: &mut BTreeSet<String>) {
    let mut leaves = vec![];
    walk(env, "", &mut leaves);
    match env_t {
        TransactionEnvelope::TxV0(_) => {
            tags.insert("envelope_tx_v0".into());
        }
        TransactionEnvelope::TxFeeBump(_) => {
            tags.insert("fee_bump".into());
        }
        _ => {}
    }
    let mut op_count = 0usize;
    for (k, v) in &leaves {
        if let Value::String(s) = v {
            let c0 = s.chars().next().unwrap_or(' ');
            if s.len() == 69 && c0 == 'M' && stellar_strkey::Strkey::from_string(s).is_ok() {
                tags.insert(format!("muxed_account:{k}"));
            }
            if c0 == 'P' && s.len() > 69 && stellar_strkey::Strkey::from_string(s).is_ok() {
                tags.insert(format!("signed_payload_signer:{k}"));
            }
            if (c0 == 'B' || c0 == 'L') && stellar_strkey::Strkey::from_string(s).is_ok() && k == "address" {
                tags.insert(format!("scaddress_{c0}"));
            }
        }
        if k == "operations" {
            if let Value::Array(a) = v {
                op_count = op_count.max(a.len());
            }
        }
        if k == "text" {
            if let Value::String(s) = v {
                if s.contains("\\x") || s.contains("\\u") {
                    tags.insert("memo_text_escaped_bytes".into());
                }
                if s.len() >= 28 {
                    tags.insert("memo_text_long".into());
                }
            }
        }
        if k == "path" {
            if let Value::Array(a) = v {
                if a.len() >= 5 {
                    tags.insert("path_max_len_5".into());
                }
            }
        }
        if k == "extra_signers" {
            if let Value::Array(a) = v {
                if !a.is_empty() {
                    tags.insert("precond_extra_signers".into());
                }
            }
        }
        if k == "min_seq_num" && !v.is_null() {
            tags.insert("precond_min_seq_num".into());
        }
        if k == "liquidity_pool_constant_product" {
            if let (Some(a), Some(b)) = (v.get("asset_a").and_then(asset_parts), v.get("asset_b").and_then(asset_parts)) {
                if a.0 == b.0 && a.1 == b.1 {
                    tags.insert("lp_same_code_pair".into());
                    if let (Some(ia), Some(ib)) = (issuer_bytes(&a.2), issuer_bytes(&b.2)) {
                        if (a.2 < b.2) != (ia < ib) {
                            tags.insert("lp_issuer_strkey_order_differs".into());
                        }
                    }
                }
            }
        }
        if k == "predicate" {
            let d = pred_depth(v);
            if d >= 2 {
                tags.insert(format!("claim_predicate_depth_{d}"));
            }
        }
        if let Value::Object(m) = v {
            for name in m.keys() {
                match name.as_str() {
                    "invoke_host_function" | "extend_footprint_ttl" | "restore_footprint" | "clawback"
                    | "clawback_claimable_balance" | "set_trust_line_flags" | "liquidity_pool_deposit"
                    | "liquidity_pool_withdraw" | "begin_sponsoring_future_reserves" | "revoke_sponsorship"
                    | "account_merge" | "inflation" | "bump_sequence" | "manage_data" | "allow_trust"
                    | "create_claimable_balance" | "claim_claimable_balance" => {
                        if k == "body" {
                            tags.insert(format!("op:{name}"));
                        }
                    }
                    "create_contract_v2" | "create_contract" | "upload_contract_wasm" => {
                        tags.insert(format!("hostfn:{name}"));
                    }
                    "map" => {
                        // ScMap whose keys are not all the same ScVal type.
                        if let Some(Value::Array(entries)) = m.get("map") {
                            let kinds: BTreeSet<String> = entries
                                .iter()
                                .filter_map(|e| e.get("key"))
                                .map(|kv| match kv {
                                    Value::Object(o) => o.keys().next().cloned().unwrap_or_default(),
                                    Value::String(s) => s.clone(),
                                    _ => "?".into(),
                                })
                                .collect();
                            if kinds.len() > 1 {
                                tags.insert("scmap_mixed_key_types".into());
                            }
                        }
                    }
                    "i128" | "i256" => {
                        if let Some(Value::String(s)) = m.get(name.as_str()) {
                            if s.starts_with('-') {
                                tags.insert(format!("{name}_negative"));
                            }
                            if s.trim_start_matches('-').len() > 19 {
                                tags.insert(format!("{name}_beyond_64_bits"));
                            }
                        }
                    }
                    "u256" => {
                        tags.insert("scval_u256".into());
                    }
                    _ => {}
                }
            }
        }
    }
    if op_count >= 100 {
        tags.insert("ops_100".into());
    }
    let auth_depth = depth_of(env, "sub_invocations");
    if auth_depth >= 2 {
        tags.insert(format!("auth_tree_depth_{}", auth_depth.min(5)));
    }
    // Meta-only shapes (CAP-67 events, SAC trustlines, LP/claimable balance addresses).
    let mut mleaves = vec![];
    walk(meta, "", &mut mleaves);
    for (k, v) in &mleaves {
        if let Value::String(s) = v {
            let c0 = s.chars().next().unwrap_or(' ');
            if (c0 == 'B' || c0 == 'L') && k == "address" && stellar_strkey::Strkey::from_string(s).is_ok() {
                tags.insert(format!("meta_scaddress_{c0}"));
            }
            if c0 == 'M' && s.len() == 69 && k == "address" {
                tags.insert("meta_scaddress_M".into());
            }
        }
        if k == "to_muxed" || k == "muxed_info" {
            tags.insert("meta_event_muxed_info".into());
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let (indir, outdir, pass) = (&args[1], &args[2], &args[3]);
    let network_id: [u8; 32] = Sha256::digest(pass.as_bytes()).into();
    fs::create_dir_all(format!("{outdir}/lcm")).unwrap();
    let mut txs = fs::File::create(format!("{outdir}/txs.jsonl")).unwrap();
    let mut files: Vec<_> = fs::read_dir(indir).unwrap().filter_map(|e| e.ok()).map(|e| e.path()).collect();
    files.sort();
    let (mut n_ledgers, mut n_txs, mut rt_fail) = (0, 0, 0);
    for f in files {
        let name = f.file_name().unwrap().to_string_lossy().to_string();
        if !name.ends_with(".xdr.zst") {
            continue;
        }
        let seq: u32 = name.trim_end_matches(".xdr.zst").parse().unwrap();
        let raw = zstd::decode_all(fs::File::open(&f).unwrap()).unwrap();
        let batch = match LedgerCloseMetaBatch::from_xdr(&raw, Limits::none()) {
            Ok(b) => b,
            Err(e) => {
                eprintln!("ledger {seq}: decode error {e}");
                rt_fail += 1;
                continue;
            }
        };
        let back = batch.to_xdr(Limits::none()).unwrap();
        if back != raw {
            eprintln!("ledger {seq}: re-encode differs");
            rt_fail += 1;
        }
        fs::write(Path::new(outdir).join("lcm").join(format!("{seq}.xdr")), &raw).unwrap();
        n_ledgers += 1;
        for lcm in batch.ledger_close_metas.iter() {
            let (version, envs, metas): (u32, Vec<TransactionEnvelope>, Vec<(Vec<u8>, &str, [u8; 32])>) = match lcm {
                LedgerCloseMeta::V0(m) => (
                    0,
                    m.tx_set.txs.to_vec(),
                    m.tx_processing.iter().map(|r| (r.to_xdr(Limits::none()).unwrap(), "TransactionResultMeta", r.result.transaction_hash.0)).collect(),
                ),
                LedgerCloseMeta::V1(m) => (
                    1,
                    envelopes(&m.tx_set),
                    m.tx_processing.iter().map(|r| (r.to_xdr(Limits::none()).unwrap(), "TransactionResultMeta", r.result.transaction_hash.0)).collect(),
                ),
                LedgerCloseMeta::V2(m) => (
                    2,
                    envelopes(&m.tx_set),
                    m.tx_processing.iter().map(|r| (r.to_xdr(Limits::none()).unwrap(), "TransactionResultMetaV1", r.result.transaction_hash.0)).collect(),
                ),
            };
            for (i, env) in envs.iter().enumerate() {
                let h = env.hash(network_id).unwrap();
                let meta = metas.iter().find(|m| m.2 == h);
                let env_json = serde_json::to_value(env).unwrap();
                let meta_json = match meta {
                    Some((b, ty, _)) => {
                        if *ty == "TransactionResultMetaV1" {
                            serde_json::to_value(stellar_xdr::TransactionResultMetaV1::from_xdr(b, Limits::none()).unwrap()).unwrap()
                        } else {
                            serde_json::to_value(stellar_xdr::TransactionResultMeta::from_xdr(b, Limits::none()).unwrap()).unwrap()
                        }
                    }
                    None => Value::Null,
                };
                let mut tags = BTreeSet::new();
                tag(&env_json, &meta_json, env, &mut tags);
                let rec = json!({
                    "ledger": seq,
                    "lcm_version": version,
                    "index_in_set": i,
                    "hash": hex::encode(h),
                    "envelope_b64": stellar_xdr::TransactionEnvelope::to_xdr_base64(env, Limits::none()).unwrap(),
                    "meta_type": meta.map(|m| m.1),
                    "meta_b64": meta.map(|m| base64_encode(&m.0)),
                    "tags": tags,
                });
                writeln!(txs, "{rec}").unwrap();
                n_txs += 1;
            }
        }
    }
    eprintln!("ledgers={n_ledgers} txs={n_txs} batch_roundtrip_failures={rt_fail}");
}

fn base64_encode(b: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut s = String::with_capacity(b.len() * 4 / 3 + 4);
    for ch in b.chunks(3) {
        let n = (ch[0] as u32) << 16 | (*ch.get(1).unwrap_or(&0) as u32) << 8 | *ch.get(2).unwrap_or(&0) as u32;
        s.push(T[(n >> 18 & 63) as usize] as char);
        s.push(T[(n >> 12 & 63) as usize] as char);
        s.push(if ch.len() > 1 { T[(n >> 6 & 63) as usize] as char } else { '=' });
        s.push(if ch.len() > 2 { T[(n & 63) as usize] as char } else { '=' });
    }
    s
}
