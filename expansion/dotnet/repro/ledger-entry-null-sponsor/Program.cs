// stellar-dotnet-sdk 17.0.0: a LedgerEntry whose ext is v1 with an absent
// sponsoringID (SponsorshipDescriptor is AccountID*, so null is valid) makes the
// SDK model throw NullReferenceException.
using StellarDotnetSdk.Responses.SorobanRpc;
using X = StellarDotnetSdk.Xdr;

// 1. One LedgerEntryChange: the STATE of a trustline, pubnet ledger 65486020,
//    transaction 210 (hash 65ce16557e8a5b119db24e3ec67a0a3b28ac5075e32086c03ae1d90219fb88b1).
const string change = "AAAAAwPnO74AAAABAAAAALPujGdsVBJSBxWA0Rpe5htne/qrM14kksTD08BZ+offAAAAAlNUQVJEVVNUAAAAAAAAAACetoGrvOujea9ERvctnWgd259IfiAcinMCntrxEZ07fgAAt7iMAUTSf/////////8AAAABAAAAAAAAAAEAAAAAAAAAAA==";

// 2. The TransactionMeta (what Stellar RPC getTransaction returns as resultMetaXdr) of
//    pubnet ledger 50460015, transaction 161 (hash 44b2d7dfb1c270b98769f7095ee0115062666bea29c53567497007e6f0f1821b).
const string meta = "AAAABAAAAAAAAAACAAAAAwMB9W8AAAAAAAAAAMNeM4F8YGyAFCD1SOx1Dbcf7fu7WrGuMz6jYIA0VpiMAAAAAAwCxUYC3oOmAAIMUwAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAAAAAAAAAAAAAAAAAAMAAAAAAwH1bQAAAABl1RRAAAAAAQAAAAAAAAAAAAAAAQMB9W8AAAAAAAAAAMNeM4F8YGyAFCD1SOx1Dbcf7fu7WrGuMz6jYIA0VpiMAAAAAAwCxUYC3oOmAAIMVAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAAAAAAAAAAAAAAAAAAMAAAAAAwH1bwAAAABl1RRLAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAASW0/NhZrsL6Y0hDjEibPDwQyYttIb5P08swy2iVPvl3AAAAAQAAAAAAAAACAAAADwAAAANmZWUAAAAAEgAAAAAAAAAAw14zgXxgbIAUIPVI7HUNtx/t+7tasa4zPqNggDRWmIwAAAAKAAAAAAAAAAAAAAAAAAAAZAAAAAA=";

var raw = Convert.FromBase64String(change);
var x = X.LedgerEntryChange.Decode(new X.XdrDataInputStream(raw));
var w = new X.XdrDataOutputStream();
X.LedgerEntryChange.Encode(w, x);
Console.WriteLine("XDR layer: decodes, ext = v" + x.State.Ext.Discriminant + ", sponsoringID (AccountID*) absent: "
    + (x.State.Ext.V1.SponsoringID.InnerValue == null) + ", re-encodes to the same bytes: " + w.ToArray().SequenceEqual(raw));

Try("LedgerEntryChange.FromXdrBase64(change)", () => StellarDotnetSdk.LedgerEntries.LedgerEntryChange.FromXdrBase64(change));
Try("Soroban.TransactionMeta.FromXdrBase64(meta)", () => StellarDotnetSdk.Soroban.TransactionMeta.FromXdrBase64(meta));
Try("new GetTransactionResponse { ResultMetaXdr = meta }.TransactionMeta",
    () => new GetTransactionResponse { ResultMetaXdr = meta }.TransactionMeta);

static void Try(string what, Func<object> f)
{
    try
    {
        var r = f();
        Console.WriteLine(what + " -> " + (r == null ? "null" : r.GetType().Name));
    }
    catch (Exception e)
    {
        Console.WriteLine(what + " -> " + e.GetType().FullName + ": " + e.Message);
        Console.WriteLine("    " + e.StackTrace.Split('\n')[0].Trim());
    }
}
