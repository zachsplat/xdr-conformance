// stellar-dotnet-sdk 17.0.0: the divergences this kit found that are already
// reported upstream. Each case parses an envelope from inputs/ the way an
// application would (TransactionBuilder.FromEnvelopeXdr), then prints the hash
// the SDK computes or the exception, next to what the network says.
using StellarDotnetSdk;
using StellarDotnetSdk.Transactions;
using X = StellarDotnetSdk.Xdr;

foreach (var line in File.ReadAllLines("inputs/cases.tsv"))
{
    var f = line.Split('\t');
    var (name, network, expected) = (f[0], f[1], f[2]);
    var b64 = File.ReadAllText($"inputs/{name}.b64").Trim();
    var raw = Convert.FromBase64String(b64);
    Console.WriteLine($"== {name}");
    Console.WriteLine($"   expected: {expected}");
    try
    {
        var x = X.TransactionEnvelope.Decode(new X.XdrDataInputStream(raw));
        var w = new X.XdrDataOutputStream();
        X.TransactionEnvelope.Encode(w, x);
        Console.WriteLine($"   XDR layer: decodes, re-encodes to the same bytes: {w.ToArray().SequenceEqual(raw)}");
    }
    catch (Exception e)
    {
        Console.WriteLine($"   XDR layer: {e.GetType().Name}: {e.Message}");
    }

    try
    {
        var tx = TransactionBuilder.FromEnvelopeXdr(b64);
        var hash = network == "" ? "(no network)" : Convert.ToHexString(tx.Hash(new Network(network))).ToLowerInvariant();
        Console.WriteLine($"   TransactionBuilder.FromEnvelopeXdr: ok, hash {hash}"
                          + (expected.Length == 64 ? (hash == expected ? "  (matches)" : "  (WRONG)") : ""));
    }
    catch (Exception e)
    {
        Console.WriteLine($"   TransactionBuilder.FromEnvelopeXdr: {e.GetType().Name}: {e.Message}");
    }
}
