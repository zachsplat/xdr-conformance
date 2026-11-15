// Conformance adapter for js-stellar-sdk (v17 bundles stellar-base and js-xdr).
// Usage: node facts.mjs <package-name>   e.g. node facts.mjs @stellar/stellar-sdk
// Same JSONL protocol as runners/rust/src/facts.rs.
import readline from "node:readline";
import { once } from "node:events";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";

// Resolve the package from the current directory, so one adapter can test
// several installed versions (npm aliases such as sdk1720@npm:@stellar/stellar-sdk@17.2.0).
const pkg = process.argv[2] || "@stellar/stellar-sdk";
const resolved = createRequire(process.cwd() + "/").resolve(pkg);
const sdk = await import(pathToFileURL(resolved).href);
const { xdr, TransactionBuilder } = sdk;
const names = new Map(Object.keys(xdr).map((k) => [k.toLowerCase(), k]));

function cls(name) {
  const k = names.get(name.toLowerCase());
  if (!k) throw new Error(`unknown type ${name}`);
  return xdr[k];
}

function b64(u8) {
  return Buffer.from(u8).toString("base64");
}

function decode(req) {
  const out = { id: req.id };
  let v;
  const raw = Buffer.from(req.b64, "base64");
  try {
    const T = cls(req.type);
    v = T.fromXdr ? T.fromXdr(req.b64, "base64") : T.fromXDR(req.b64, "base64");
  } catch (e) {
    out.ok = false;
    out.error = String(e && e.message ? e.message : e).slice(0, 300);
    return out;
  }
  try {
    const back = Buffer.from(v.toXdr ? v.toXdr("raw") : v.toXDR("raw"));
    out.ok = true;
    out.roundtrip_equal = back.equals(raw);
    if (!out.roundtrip_equal) out.reencoded_b64 = b64(back);
    if (typeof v.toJson === "function") out.json = v.toJson();
  } catch (e) {
    out.ok = false;
    out.error = "re-encode or toJson failed: " + String(e && e.message ? e.message : e).slice(0, 280);
    return out;
  }
  if (req.type === "TransactionEnvelope" && req.network) {
    try {
      out.hash = Buffer.from(TransactionBuilder.fromXDR(req.b64, req.network).hash()).toString("hex");
    } catch (e) {
      out.hash = "error: " + String(e && e.message ? e.message : e).slice(0, 200);
    }
  }
  return out;
}

function fromJson(req) {
  const out = { id: req.id };
  try {
    const T = cls(req.type);
    if (typeof T.fromJson !== "function") throw new Error("no fromJson");
    const v = T.fromJson(req.json);
    out.ok = true;
    out.b64 = b64(v.toXdr("raw"));
  } catch (e) {
    out.ok = false;
    out.error = String(e && e.message ? e.message : e).slice(0, 300);
  }
  return out;
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of rl) {
  if (!line.trim()) continue;
  const req = JSON.parse(line);
  const res = req.op === "from_json" ? fromJson(req) : decode(req);
  // Respect backpressure: whole-ledger results are tens of MB each.
  if (!process.stdout.write(JSON.stringify(res) + "\n")) await once(process.stdout, "drain");
}
