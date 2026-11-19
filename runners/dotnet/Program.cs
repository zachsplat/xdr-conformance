// Conformance adapter for the .NET Stellar SDK (Beans-BV/dotnet-stellar-sdk,
// NuGet stellar-dotnet-sdk and stellar-dotnet-sdk-xdr). Same JSONL protocol as
// runners/rust/src/facts.rs and runners/go/main.go. The SDK has no SEP-51 JSON
// form, so results carry decode, round-trip and hash, plus these extra fields:
//
//   trailing_bytes         bytes left unread after a successful Decode (the
//                          generated decoders do not check that the input is used up)
//   hash                   transaction hash through the SDK's own transaction model
//                          (TransactionBuilder.FromEnvelopeXdr, then Hash(Network))
//   xdr_hash               the same hash built straight from the decoded XDR
//                          objects (TransactionSignaturePayload), as a cross-check
//   model_roundtrip_equal  the model turned back into an envelope (ToEnvelopeXdr)
//                          gives the original bytes; model_reencoded_b64 if not
//   model_error            the transaction or meta model threw on this input
//   strkeys                every strkey-shaped string found by walking the model
//                          (the transaction model, or each ledger entry change of a meta)
//   model_meta             Soroban.TransactionMeta.FromXdrBase64 on txApplyProcessing
//   model_result           Responses.Results.TransactionResult.FromXdrBase64 on the result
//   model_changes[_failed] LedgerEntryChange.FromXdr on every change in the meta, one by one
//
// Environment: XDRCONF_DEPTH=N decodes with maxDepth N instead of the SDK's
// default (XdrDataInputStream.DefaultMaxDepth). Each request runs on a worker
// thread with a large stack and a time limit, so one bad input cannot take the
// runner down.
using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Threading;
using StellarDotnetSdk;
using StellarDotnetSdk.Accounts;
using StellarDotnetSdk.Transactions;
using X = StellarDotnetSdk.Xdr;

internal static class Program
{
    private static readonly Assembly XdrAsm = typeof(X.TransactionEnvelope).Assembly;
    private static readonly Dictionary<string, Type> XdrTypes = XdrAsm.GetTypes()
        .Where(t => t.IsPublic && t.Namespace == "StellarDotnetSdk.Xdr")
        .GroupBy(t => t.Name.ToLowerInvariant())
        .ToDictionary(g => g.Key, g => g.First());

    private static readonly int? Depth =
        int.TryParse(Environment.GetEnvironmentVariable("XDRCONF_DEPTH"), out var d) ? d : null;

    private static readonly int TimeoutMs =
        int.TryParse(Environment.GetEnvironmentVariable("XDRCONF_TIMEOUT_MS"), out var t) ? t : 60000;

    private static readonly Regex StrKeyRe = new("^[GMCBLWPST][A-Z2-7]{55,}$", RegexOptions.Compiled);

    private static int Main()
    {
        var stdin = new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false), false, 1 << 20);
        var stdout = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false), 1 << 20);
        var worker = new Worker();
        string line;
        while ((line = stdin.ReadLine()) != null)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            JsonObject req;
            try
            {
                req = JsonNode.Parse(line)!.AsObject();
            }
            catch
            {
                continue;
            }

            var id = req["id"]?.GetValue<string>() ?? "";
            JsonObject res;
            if (!worker.TryRun(() => Handle(req), TimeoutMs, out res, out var crash))
            {
                res = new JsonObject { ["id"] = id, ["ok"] = false, ["error"] = crash };
                if (crash.StartsWith("timeout")) worker = new Worker();
            }

            stdout.Write(res.ToJsonString());
            stdout.Write('\n');
        }

        stdout.Flush();
        return 0;
    }

    private static JsonObject Handle(JsonObject req)
    {
        var op = req["op"]?.GetValue<string>() ?? "decode";
        return op == "decode" ? Decode(req) : new JsonObject
        {
            ["id"] = req["id"]?.GetValue<string>(), ["ok"] = false, ["error"] = "unsupported op " + op,
        };
    }

    private static string Err(Exception e)
    {
        var s = e.GetType().Name + ": " + e.Message;
        return s.Length > 300 ? s[..300] : s;
    }

    private static (object value, X.XdrDataInputStream stream) DecodeXdr(Type type, byte[] raw)
    {
        var stream = new X.XdrDataInputStream(raw);
        MethodInfo m;
        object[] args;
        if (Depth is int depth)
        {
            m = type.GetMethod("Decode", BindingFlags.Public | BindingFlags.Static, null,
                new[] { typeof(X.XdrDataInputStream), typeof(int) }, null);
            args = new object[] { stream, depth };
        }
        else
        {
            m = type.GetMethod("Decode", BindingFlags.Public | BindingFlags.Static, null,
                new[] { typeof(X.XdrDataInputStream) }, null);
            args = new object[] { stream };
        }

        if (m == null) throw new InvalidOperationException("no Decode method on " + type.Name);
        try
        {
            return (m.Invoke(null, args), stream);
        }
        catch (TargetInvocationException tie) when (tie.InnerException != null)
        {
            System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(tie.InnerException).Throw();
            throw;
        }
    }

    private static byte[] EncodeXdr(Type type, object value)
    {
        var w = new X.XdrDataOutputStream();
        var m = type.GetMethod("Encode", BindingFlags.Public | BindingFlags.Static, null,
            new[] { typeof(X.XdrDataOutputStream), type }, null);
        if (m == null) throw new InvalidOperationException("no Encode method on " + type.Name);
        try
        {
            m.Invoke(null, new[] { w, value });
        }
        catch (TargetInvocationException tie) when (tie.InnerException != null)
        {
            System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(tie.InnerException).Throw();
            throw;
        }

        return w.ToArray();
    }

    private static JsonObject Decode(JsonObject req)
    {
        var id = req["id"]?.GetValue<string>();
        var typeName = req["type"]?.GetValue<string>() ?? "";
        var b64 = req["b64"]?.GetValue<string>() ?? "";
        var network = req["network"]?.GetValue<string>();
        var outp = new JsonObject { ["id"] = id };

        byte[] raw;
        try
        {
            raw = Convert.FromBase64String(b64);
        }
        catch (Exception e)
        {
            outp["ok"] = false;
            outp["error"] = "base64: " + Err(e);
            return outp;
        }

        if (!XdrTypes.TryGetValue(typeName.ToLowerInvariant(), out var type))
        {
            outp["ok"] = false;
            outp["error"] = "unknown type " + typeName;
            return outp;
        }

        object value;
        byte[] back;
        try
        {
            var (v, stream) = DecodeXdr(type, raw);
            value = v;
            var left = stream.GetRemainingInputLen();
            if (left > 0) outp["trailing_bytes"] = left;
            back = EncodeXdr(type, value);
        }
        catch (Exception e)
        {
            outp["ok"] = false;
            outp["error"] = Err(e);
            return outp;
        }

        var equal = back.AsSpan().SequenceEqual(raw);
        outp["ok"] = true;
        outp["roundtrip_equal"] = equal;
        if (!equal) outp["reencoded_b64"] = Convert.ToBase64String(back);

        if (value is X.TransactionEnvelope env)
        {
            EnvelopeModel(env, raw, b64, network, outp);
        }
        else if (value is X.TransactionResultMeta trm)
        {
            MetaModel(trm.TxApplyProcessing, outp);
            ResultModel(trm.Result.Result, outp);
            ChangesModel(trm, outp);
        }
        else if (value is X.TransactionResultMetaV1 trm1)
        {
            MetaModel(trm1.TxApplyProcessing, outp);
            ResultModel(trm1.Result.Result, outp);
            ChangesModel(trm1, outp);
        }

        return outp;
    }

    // The SDK's TransactionResult model (Responses.Results.TransactionResult.FromXdrBase64).
    private static void ResultModel(X.TransactionResult result, JsonObject outp)
    {
        try
        {
            var w = new X.XdrDataOutputStream();
            X.TransactionResult.Encode(w, result);
            StellarDotnetSdk.Responses.Results.TransactionResult.FromXdrBase64(Convert.ToBase64String(w.ToArray()));
            outp["model_result"] = "ok";
        }
        catch (Exception e)
        {
            outp["model_result"] = "error: " + Err(e);
        }
    }

    // Every LedgerEntryChange in the meta through LedgerEntryChange.FromXdr one by one, so a
    // failure in one change does not hide a different failure in another.
    private static void ChangesModel(object xdrMeta, JsonObject outp)
    {
        var changes = new List<X.LedgerEntryChange>();
        CollectXdr(xdrMeta, changes, new HashSet<object>(ReferenceEqualityComparer.Instance), 0);
        var errors = new SortedSet<string>(StringComparer.Ordinal);
        var keys = new List<string>();
        var failed = 0;
        foreach (var c in changes)
        {
            try
            {
                var m = StellarDotnetSdk.LedgerEntries.LedgerEntryChange.FromXdr(c);
                Walk(m, keys, new HashSet<object>(ReferenceEqualityComparer.Instance), 0);
            }
            catch (Exception e)
            {
                failed++;
                var top = e.StackTrace?.Split('\n').FirstOrDefault()?.Trim() ?? "";
                errors.Add(Err(e) + " @ " + top);
            }
        }

        outp["model_changes"] = changes.Count;
        if (failed > 0)
        {
            outp["model_changes_failed"] = failed;
            outp["model_changes_errors"] = new JsonArray(errors.Select(x => (JsonNode)JsonValue.Create(x)).ToArray());
        }

        outp["strkeys"] = new JsonArray(keys.Distinct().OrderBy(k => k, StringComparer.Ordinal)
            .Select(k => (JsonNode)JsonValue.Create(k)).ToArray());
    }

    private static void CollectXdr<T>(object o, List<T> found, HashSet<object> seen, int depth) where T : class
    {
        if (o == null || depth > 1000) return;
        var t = o.GetType();
        if (t.IsPrimitive || t.IsEnum || o is string || o is byte[]) return;
        if (!t.IsValueType && !seen.Add(o)) return;
        if (o is T hit)
        {
            found.Add(hit);
            return;
        }

        if (o is IEnumerable en)
        {
            foreach (var item in en) CollectXdr(item, found, seen, depth + 1);
            return;
        }

        if (t.Namespace == null || !t.Namespace.StartsWith("StellarDotnetSdk.Xdr")) return;
        foreach (var p in t.GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            if (p.GetIndexParameters().Length > 0 || p.PropertyType.IsPrimitive || p.PropertyType.IsEnum) continue;
            object v;
            try
            {
                v = p.GetValue(o);
            }
            catch
            {
                continue;
            }

            CollectXdr(v, found, seen, depth + 1);
        }
    }

    private static void EnvelopeModel(X.TransactionEnvelope env, byte[] raw, string b64, string network,
        JsonObject outp)
    {
        if (!string.IsNullOrEmpty(network))
        {
            try
            {
                outp["xdr_hash"] = Convert.ToHexString(XdrHash(env, network)).ToLowerInvariant();
            }
            catch (Exception e)
            {
                outp["xdr_hash"] = "error: " + Err(e);
            }
        }

        TransactionBase model;
        try
        {
            // The documented entry point: parse a base64 envelope into the SDK's transaction model.
            // With a custom depth the string overload would decode again at the default depth, so the
            // already-decoded object goes through the object overload instead.
            model = Depth is null ? TransactionBuilder.FromEnvelopeXdr(b64) : TransactionBuilder.FromEnvelopeXdr(env);
        }
        catch (Exception e)
        {
            outp["model_error"] = Err(e);
            if (!string.IsNullOrEmpty(network)) outp["hash"] = "error: " + Err(e);
            return;
        }

        if (!string.IsNullOrEmpty(network))
        {
            try
            {
                outp["hash"] = Convert.ToHexString(model.Hash(new Network(network))).ToLowerInvariant();
            }
            catch (Exception e)
            {
                outp["hash"] = "error: " + Err(e);
            }
        }

        try
        {
            var version = env.Discriminant.InnerValue == X.EnvelopeType.EnvelopeTypeEnum.ENVELOPE_TYPE_TX_V0
                ? TransactionBase.TransactionXdrVersion.V0
                : TransactionBase.TransactionXdrVersion.V1;
            var back = model.Signatures.Count > 0
                ? model.ToEnvelopeXdr(version)
                : model.ToUnsignedEnvelopeXdr(version);
            var w = new X.XdrDataOutputStream();
            X.TransactionEnvelope.Encode(w, back);
            var bytes = w.ToArray();
            var eq = bytes.AsSpan().SequenceEqual(raw);
            outp["model_roundtrip_equal"] = eq;
            if (!eq) outp["model_reencoded_b64"] = Convert.ToBase64String(bytes);
        }
        catch (Exception e)
        {
            outp["model_roundtrip_equal"] = false;
            outp["model_error"] = "re-encode: " + Err(e);
        }

        try
        {
            var keys = new List<string>();
            Walk(model, keys, new HashSet<object>(ReferenceEqualityComparer.Instance), 0);
            outp["strkeys"] = new JsonArray(keys.Distinct().OrderBy(k => k, StringComparer.Ordinal)
                .Select(k => (JsonNode)JsonValue.Create(k)).ToArray());
        }
        catch (Exception e)
        {
            outp["strkeys_error"] = Err(e);
        }
    }

    // sha256(networkId || TransactionSignaturePayload.taggedTransaction), built from the
    // decoded XDR objects alone. V0 envelopes hash as ENVELOPE_TYPE_TX with the ed25519
    // source as a KEY_TYPE_ED25519 MuxedAccount (the stellar-core rule).
    private static byte[] XdrHash(X.TransactionEnvelope env, string passphrase)
    {
        var w = new X.XdrDataOutputStream();
        w.Write(SHA256.HashData(Encoding.UTF8.GetBytes(passphrase)), 0, 32);
        switch (env.Discriminant.InnerValue)
        {
            case X.EnvelopeType.EnvelopeTypeEnum.ENVELOPE_TYPE_TX_V0:
            {
                var v0 = env.V0.Tx;
                var tx = new X.Transaction
                {
                    SourceAccount = new X.MuxedAccount
                    {
                        Discriminant = X.CryptoKeyType.Create(X.CryptoKeyType.CryptoKeyTypeEnum.KEY_TYPE_ED25519),
                        Ed25519 = v0.SourceAccountEd25519,
                    },
                    Fee = v0.Fee,
                    SeqNum = v0.SeqNum,
                    Cond = v0.TimeBounds == null
                        ? new X.Preconditions { Discriminant = X.PreconditionType.Create(X.PreconditionType.PreconditionTypeEnum.PRECOND_NONE) }
                        : new X.Preconditions { Discriminant = X.PreconditionType.Create(X.PreconditionType.PreconditionTypeEnum.PRECOND_TIME), TimeBounds = v0.TimeBounds },
                    Memo = v0.Memo,
                    Operations = v0.Operations,
                    Ext = new X.Transaction.TransactionExt { Discriminant = 0 },
                };
                w.WriteInt((int)X.EnvelopeType.EnvelopeTypeEnum.ENVELOPE_TYPE_TX);
                X.Transaction.Encode(w, tx);
                break;
            }
            case X.EnvelopeType.EnvelopeTypeEnum.ENVELOPE_TYPE_TX:
                w.WriteInt((int)X.EnvelopeType.EnvelopeTypeEnum.ENVELOPE_TYPE_TX);
                X.Transaction.Encode(w, env.V1.Tx);
                break;
            case X.EnvelopeType.EnvelopeTypeEnum.ENVELOPE_TYPE_TX_FEE_BUMP:
                w.WriteInt((int)X.EnvelopeType.EnvelopeTypeEnum.ENVELOPE_TYPE_TX_FEE_BUMP);
                X.FeeBumpTransaction.Encode(w, env.FeeBump.Tx);
                break;
            default:
                throw new InvalidDataException("not a transaction envelope");
        }

        return SHA256.HashData(w.ToArray());
    }

    private static void MetaModel(X.TransactionMeta meta, JsonObject outp)
    {
        try
        {
            var w = new X.XdrDataOutputStream();
            X.TransactionMeta.Encode(w, meta);
            StellarDotnetSdk.Soroban.TransactionMeta.FromXdrBase64(Convert.ToBase64String(w.ToArray()));
            outp["model_meta"] = "ok";
        }
        catch (Exception e)
        {
            outp["model_meta"] = "error: " + Err(e);
        }
    }

    // Collects strkey-shaped strings reachable from the SDK model: IAccountId.Address,
    // ScAddress.InnerValue, and any other public string property in strkey form.
    private static void Walk(object o, List<string> keys, HashSet<object> seen, int depth)
    {
        if (o == null || depth > 2000) return;
        var t = o.GetType();
        if (t.IsPrimitive || t.IsEnum || o is decimal || o is byte[]) return;
        if (o is string s)
        {
            if (StrKeyRe.IsMatch(s)) keys.Add(s);
            return;
        }

        if (!t.IsValueType && !seen.Add(o)) return;
        if (t.Namespace != null && t.Namespace.StartsWith("StellarDotnetSdk.Xdr")) return;
        if (o is IAccountId acc)
        {
            try
            {
                keys.Add(acc.Address);
            }
            catch (Exception e)
            {
                keys.Add("error: " + Err(e));
            }

            return;
        }

        if (o is IEnumerable en && o is not IDictionary)
        {
            foreach (var item in en) Walk(item, keys, seen, depth + 1);
            return;
        }

        if (t.Namespace == null || !t.Namespace.StartsWith("StellarDotnetSdk")) return;
        foreach (var p in t.GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            if (p.GetIndexParameters().Length > 0) continue;
            object v;
            try
            {
                v = p.GetValue(o);
            }
            catch
            {
                continue;
            }

            Walk(v, keys, seen, depth + 1);
        }
    }

    // One long-lived thread with a large stack; a request that times out abandons it.
    private sealed class Worker
    {
        private readonly BlockingCollection<(Func<JsonObject> fn, ManualResetEventSlim done, Box box)> _q = new();

        public Worker()
        {
            var th = new Thread(Loop, 512 * 1024 * 1024) { IsBackground = true };
            th.Start();
        }

        private void Loop()
        {
            foreach (var (fn, done, box) in _q.GetConsumingEnumerable())
            {
                try
                {
                    box.Result = fn();
                }
                catch (Exception e)
                {
                    box.Crash = "crash: " + Err(e);
                }

                done.Set();
            }
        }

        public bool TryRun(Func<JsonObject> fn, int timeoutMs, out JsonObject result, out string crash)
        {
            var done = new ManualResetEventSlim(false);
            var box = new Box();
            _q.Add((fn, done, box));
            if (!done.Wait(timeoutMs))
            {
                _q.CompleteAdding();
                result = null;
                crash = "timeout after " + timeoutMs + " ms";
                return false;
            }

            result = box.Result;
            crash = box.Crash;
            return box.Result != null;
        }

        private sealed class Box
        {
            public string Crash;
            public JsonObject Result;
        }
    }
}
