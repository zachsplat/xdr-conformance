// js-stellar-sdk#1766 on real testnet history: a change_trust into a pool whose
// two USD issuers sort one way as key bytes and the other way as strkey text.
import fs from "node:fs";
const t = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const PASS = "Test SDF Network ; September 2015";
for (const pkg of ["sdk1720", "sdk1721", "sdk1740"]) {
  const { TransactionBuilder, LiquidityPoolAsset, Asset, getLiquidityPoolId } = await import(pkg);
  const ver = JSON.parse(fs.readFileSync(`node_modules/${pkg}/package.json`, "utf8")).version;
  let verdict;
  try {
    const tx = TransactionBuilder.fromXDR(t.envelope_xdr, PASS);
    const op = tx.operations.find((o) => o.type === "changeTrust" && o.line && o.line.assetA);
    if (!op) throw new Error(`no pool change_trust among ${tx.operations.map((o) => o.type).join(",")}`);
    const lp = op.line;
    const params = { assetA: lp.assetA, assetB: lp.assetB, fee: lp.fee };
    const id = Buffer.from(getLiquidityPoolId("constant_product", params)).toString("hex");
    verdict = `ok   decoded; pool id ${id} ${id === t.pool ? "matches" : "DIFFERS FROM"} Horizon`;
  } catch (e) {
    verdict = `FAIL ${e.message}`;
  }
  console.log(`@stellar/stellar-sdk ${ver}: ${verdict}`);
}
