#!/usr/bin/env python3
"""Turn results/*.jsonl into results/summary.md and check them against expected.tsv.

Usage: summarize.py ADAPTER_DIR    (exit 1 if any cell differs from expected.tsv, or an input is in one and not the other)
"""
import json
import os
import sys

ISSUES = [
    ("corpus:soroban-muxed-source", "wallet-backend#716, muxed source (producer 1)"),
    ("corpus:signer-signed-payload-setoptions", "wallet-backend#716 producer 3, then #729"),
    ("testnet:4437357.xdr.zst", "same transaction, replayed inside its whole testnet ledger"),
    ("corpus:sac-trust-creates-trustline", "wallet-backend#731"),
    ("corpus:sac-native-transfer-creates-account", "wallet-backend#804 (open)"),
]


def main():
    here = sys.argv[1]
    commits = [l.split()[0][:8] for l in open(os.path.join(here, "commits.txt")) if l.strip() and not l.startswith("#")]
    roles = {l.split()[0][:8]: l.split(None, 1)[1].strip() for l in open(os.path.join(here, "commits.txt")) if l.strip() and not l.startswith("#")}
    res = {}
    order = []
    for c in commits:
        for line in open(os.path.join(here, "results", c + ".jsonl")):
            r = json.loads(line)
            res[(r["input"], c)] = r
            if r["input"] not in order:
                order.append(r["input"])

    exp_rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(here, "expected.tsv")) if l.strip() and not l.startswith("#")]
    head, rows = exp_rows[0], exp_rows[1:]
    expected = {row[0]: dict(zip(head[1:], row[1:])) for row in rows}
    mismatches, checked = [], 0
    for inp in expected:
        if inp not in order:
            mismatches.append(f"{inp}: listed in expected.tsv, missing from results/")
    for inp in order:
        want = expected.get(inp)
        if want is None:
            mismatches.append(f"{inp}: in results/, not listed in expected.tsv")
            continue
        for c in commits:
            got = res.get((inp, c), {}).get("result", "missing")
            checked += 1
            if want.get(c) != got:
                mismatches.append(f"{inp} at {c}: expected {want.get(c)}, got {got}")

    out = []
    out.append("# wallet-backend replay results\n")
    out.append("Written by `summarize.py` from `results/*.jsonl`. One row per input, one column per wallet-backend commit (oldest first).\n")
    out.append("`pass`: every address read back as written (or an M... as its own G..., the documented choice since #693) and every account, trustline or signer the ledger created has a state change. "
               "`mishandled`: an address was stored lossily or a ledger fact has no state change. "
               "`halts`: the column encoder refuses a value, so the persist transaction fails and ingestion retries the ledger. "
               "`error`: the commit cannot read the input (its go-stellar-sdk predates the ledger's protocol).\n")
    out.append("| commit | role |\n|---|---|")
    for c in commits:
        out.append(f"| [`{c}`](https://github.com/stellar/wallet-backend/commit/{c}) | {roles[c]} |")
    out.append("")
    out.append("| input | " + " | ".join(f"`{c}`" for c in commits) + " |")
    out.append("|---|" + "---|" * len(commits))
    for inp in order:
        cells = []
        for c in commits:
            r = res.get((inp, c))
            cells.append("missing" if r is None else (f"**{r['result']}**" if r["result"] != "pass" else "pass"))
        n = res.get((inp, commits[-1]), {}).get("addresses_checked", 0)
        out.append(f"| `{inp}` ({n} addresses at main) | " + " | ".join(cells) + " |")
    out.append("")
    out.append("## What the adapter saw on the issue inputs\n")
    for inp, label in ISSUES:
        out.append(f"### `{inp}`: {label}\n")
        prev = None
        for c in commits:
            r = res.get((inp, c))
            if r is None:
                continue
            lines = []
            for a in r["address_anomalies"]:
                if a["verdict"] == "reduced":
                    lines.append(f"{a['where']}: `{a['in']}` read back as `{a['out']}` (reduced to base account)")
                    continue
                s = f"{a['where']}: `{a['in']}` {a['verdict']}"
                if a.get("stored_bytes"):
                    s += f", stored {a['stored_bytes']} bytes"
                if a.get("out"):
                    s += f", read back `{a['out']}`"
                if a.get("error"):
                    s += f" ({a['error']})"
                lines.append(s)
            for f in r["facts"]:
                lines.append(f"{f['kind']} in op {f['op_index']} ({f['op_type'].replace('OperationType', '')}) for `{f['account']}`: "
                             + (f"recorded as {f['recorded_as']}" if f["recorded"] else "**no state change**"))
            body = "; ".join(lines) if lines else "no anomalies, no facts"
            key = (r["result"], body)
            if key == prev:
                out.append(f"- `{c}`: same")
            else:
                out.append(f"- `{c}` **{r['result']}**: {body}")
            prev = key
        out.append("")
    out.append(f"expected.tsv: {checked} cells checked, {len(mismatches)} differ.\n")
    for m in mismatches:
        out.append(f"- DIFFERS: {m}")
    text = "\n".join(out) + "\n"
    open(os.path.join(here, "results", "summary.md"), "w").write(text)
    print(text)
    sys.exit(1 if mismatches else 0)


if __name__ == "__main__":
    main()
