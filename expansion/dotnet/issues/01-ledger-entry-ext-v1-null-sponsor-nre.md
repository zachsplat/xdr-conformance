TITLE: LedgerEntryExtensionV1.FromXdr throws NullReferenceException when sponsoringID is absent

## What happens

A ledger entry whose `ext` is v1 with no sponsor (`sponsoringID` absent) makes the model throw `NullReferenceException` in `LedgerEntryExtensionV1.FromXdr`. That breaks `LedgerEntryChange.FromXdrBase64`, `Soroban.TransactionMeta.FromXdrBase64` and the `TransactionMeta` property of `GetTransactionResponse` for real pubnet transactions. The generated XDR classes decode and re-encode the same bytes without a problem; only the model fails.

## Reproduction

stellar-dotnet-sdk 17.0.0 (NuGet), .NET 9.

- `change`: the STATE of a trustline from the meta of pubnet transaction `65ce16557e8a5b119db24e3ec67a0a3b28ac5075e32086c03ae1d90219fb88b1` (ledger 65486020).
- `meta`: the TransactionMeta of pubnet transaction `44b2d7dfb1c270b98769f7095ee0115062666bea29c53567497007e6f0f1821b` (ledger 50460015).

```csharp
using StellarDotnetSdk.Responses.SorobanRpc;
using X = StellarDotnetSdk.Xdr;

const string change = "AAAAAwPnO74AAAABAAAAALPujGdsVBJSBxWA0Rpe5htne/qrM14kksTD08BZ+offAAAAAlNUQVJEVVNUAAAAAAAAAACetoGrvOujea9ERvctnWgd259IfiAcinMCntrxEZ07fgAAt7iMAUTSf/////////8AAAABAAAAAAAAAAEAAAAAAAAAAA==";
const string meta = "AAAABAAAAAAAAAACAAAAAwMB9W8AAAAAAAAAAMNeM4F8YGyAFCD1SOx1Dbcf7fu7WrGuMz6jYIA0VpiMAAAAAAwCxUYC3oOmAAIMUwAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAAAAAAAAAAAAAAAAAAMAAAAAAwH1bQAAAABl1RRAAAAAAQAAAAAAAAAAAAAAAQMB9W8AAAAAAAAAAMNeM4F8YGyAFCD1SOx1Dbcf7fu7WrGuMz6jYIA0VpiMAAAAAAwCxUYC3oOmAAIMVAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAAAAAAAAAAAAAAAAAAMAAAAAAwH1bwAAAABl1RRLAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAASW0/NhZrsL6Y0hDjEibPDwQyYttIb5P08swy2iVPvl3AAAAAQAAAAAAAAACAAAADwAAAANmZWUAAAAAEgAAAAAAAAAAw14zgXxgbIAUIPVI7HUNtx/t+7tasa4zPqNggDRWmIwAAAAKAAAAAAAAAAAAAAAAAAAAZAAAAAA=";

var raw = Convert.FromBase64String(change);
var x = X.LedgerEntryChange.Decode(new X.XdrDataInputStream(raw));
var w = new X.XdrDataOutputStream();
X.LedgerEntryChange.Encode(w, x);
Console.WriteLine("XDR layer: sponsoringID absent: " + (x.State.Ext.V1.SponsoringID.InnerValue == null)
    + ", re-encodes to the same bytes: " + w.ToArray().SequenceEqual(raw));

Try("LedgerEntryChange.FromXdrBase64(change)", () => StellarDotnetSdk.LedgerEntries.LedgerEntryChange.FromXdrBase64(change));
Try("Soroban.TransactionMeta.FromXdrBase64(meta)", () => StellarDotnetSdk.Soroban.TransactionMeta.FromXdrBase64(meta));
Try("GetTransactionResponse.TransactionMeta", () => new GetTransactionResponse { ResultMetaXdr = meta }.TransactionMeta);

static void Try(string what, Func<object> f)
{
    try { Console.WriteLine(what + " -> " + f()?.GetType().Name); }
    catch (Exception e) { Console.WriteLine(what + " -> " + e.GetType().FullName + "\n    " + e.StackTrace.Split('\n')[0].Trim()); }
}
```

Observed:

```
XDR layer: sponsoringID absent: True, re-encodes to the same bytes: True
LedgerEntryChange.FromXdrBase64(change) -> System.NullReferenceException
    at StellarDotnetSdk.LedgerEntries.LedgerEntryExtensionV1.FromXdr(LedgerEntryExtensionV1 xdrEntryExtensionV1)
Soroban.TransactionMeta.FromXdrBase64(meta) -> System.NullReferenceException
    at StellarDotnetSdk.LedgerEntries.LedgerEntryExtensionV1.FromXdr(LedgerEntryExtensionV1 xdrEntryExtensionV1)
GetTransactionResponse.TransactionMeta -> System.NullReferenceException
    at StellarDotnetSdk.LedgerEntries.LedgerEntryExtensionV1.FromXdr(LedgerEntryExtensionV1 xdrEntryExtensionV1)
```

Expected: model objects, with no sponsor on the v1 extension.

## Evidence for the expected behaviour

- `LedgerEntryExtensionV1.sponsoringID` is a `SponsorshipDescriptor`, which is `typedef AccountID* SponsorshipDescriptor`, an optional ([Stellar-ledger-entries.x L137](https://github.com/stellar/stellar-xdr/blob/v30.0/Stellar-ledger-entries.x#L137) and [L536-L538](https://github.com/stellar/stellar-xdr/blob/v30.0/Stellar-ledger-entries.x#L536-L538)). Absent is a valid value.
- rs-stellar-xdr 30.0.0 decodes both inputs, round-trips them byte for byte and shows `"sponsoring_id": null`. go-stellar-sdk also decodes and round-trips the entry.
- Both inputs are byte slices of pubnet ledger data. In 380 sampled pubnet ledgers, 176 of 44,057 transaction metas throw this exception, and they are exactly the 176 metas where rs-stellar-xdr shows `"sponsoring_id": null`. Most are recent (157 of them in ledgers 65486000 to 65486299), so `getTransaction` on current transactions can hit it.

## Likely cause

[`StellarDotnetSdk/LedgerEntries/LedgerEntryExtensionV1.cs` L30-L34](https://github.com/Beans-BV/dotnet-stellar-sdk/blob/17.0.0/StellarDotnetSdk/LedgerEntries/LedgerEntryExtensionV1.cs#L30-L34): line 33 calls `KeyPair.FromXdrPublicKey(xdrEntryExtensionV1.SponsoringID.InnerValue.InnerValue)` without checking whether `SponsoringID.InnerValue` is null. The same code is on `main`. `AccountEntryExtensionV2` already handles the same optional with a null check.

Suggested fix: return a `LedgerEntryExtensionV1` with `SponsoringId = null` when `SponsoringID.InnerValue` is null.

I found this with an open-source conformance kit (https://github.com/zachsplat/xdr-conformance) that replays pubnet ledgers through several SDKs.
