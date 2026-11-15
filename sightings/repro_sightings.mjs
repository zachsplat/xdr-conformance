// js-stellar-sdk#1785 and #1789 on the last tag before each fix and on the
// first tag after it. Inputs are synthetic (the shapes the issues describe).
import fs from "node:fs";
const G = "GA7QYNF7SOWQ3GLR2BGMZEHXAVIRZA4KVWLTJJFC7MGXUA74P7UJVSGZ";
for (const pkg of ["sdk1721", "sdk1730", "sdk1740"]) {
  const { xdr, scValToNative, MuxedAccount, Account, Operation, Asset } = await import(pkg);
  const ver = JSON.parse(fs.readFileSync(`node_modules/${pkg}/package.json`, "utf8")).version;
  // #1789: u32 1 and symbol "1" are distinct ScMap keys.
  let r1789;
  try {
    const m = xdr.ScVal.scvMap([
      new xdr.ScMapEntry({ key: xdr.ScVal.scvU32(1), val: xdr.ScVal.scvU32(10) }),
      new xdr.ScMapEntry({ key: xdr.ScVal.scvSymbol("1"), val: xdr.ScVal.scvU32(20) }),
    ]);
    const n = scValToNative(m);
    r1789 = `returned ${JSON.stringify(n)} (2 entries in, ${Object.keys(n).length} out)`;
  } catch (e) {
    r1789 = `throws: ${e.message.slice(0, 90)}`;
  }
  // #1785: a hex ID string for a muxed account.
  let r1785;
  try {
    const mx = new MuxedAccount(new Account(G, "0"), "0x10");
    r1785 = `accepted "0x10": id() = ${JSON.stringify(mx.id())}, M-address encodes id ${MuxedAccount.fromAddress(mx.accountId(), "0").id()}`;
  } catch (e) {
    r1785 = `rejects "0x10": ${e.message.slice(0, 80)}`;
  }
  console.log(`@stellar/stellar-sdk ${ver}\n  #1789 ${r1789}\n  #1785 ${r1785}`);
}
