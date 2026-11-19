// Conformance adapter for java-stellar-sdk (network.lightsail:stellar-sdk).
// Same JSONL protocol as runners/rust/src/facts.rs and runners/python/facts.py:
// one request per line on stdin, one result per line on stdout.
//
// Each result carries:
//   ok, error                decode through org.stellar.sdk.xdr.<Type>.fromXdrByteArray (as shipped)
//   roundtrip_equal          re-encode through the same generated class gives the same bytes
//   json                     the SDK's own SEP-51 JSON (XdrElement.toJson)
//   json_roundtrip_equal     fromJson(toJson(v)) re-encodes to the input bytes
// and, for a TransactionEnvelope with "network":
//   hash                     AbstractTransaction.fromEnvelopeXdr(...).hashHex(), the SDK's model
//   xdr_hash                 sha256 of the TransactionSignaturePayload built from the decoded XDR,
//                            no model involved (a second opinion, like txnbuild_hash in runners/go)
//   model_roundtrip_equal    the model's toEnvelopeXdr() gives the input bytes
//   model                    strkeys the model produced: source, fee source, per-operation
//                            source account and destination
// Nothing a single input does may stop the runner: every request is wrapped in catch Throwable.
import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.stellar.sdk.AbstractTransaction;
import org.stellar.sdk.FeeBumpTransaction;
import org.stellar.sdk.Network;
import org.stellar.sdk.Transaction;
import org.stellar.sdk.operations.AccountMergeOperation;
import org.stellar.sdk.operations.ClawbackOperation;
import org.stellar.sdk.operations.CreateAccountOperation;
import org.stellar.sdk.operations.Operation;
import org.stellar.sdk.operations.PathPaymentStrictReceiveOperation;
import org.stellar.sdk.operations.PathPaymentStrictSendOperation;
import org.stellar.sdk.operations.PaymentOperation;
import org.stellar.sdk.xdr.EnvelopeType;
import org.stellar.sdk.xdr.Hash;
import org.stellar.sdk.xdr.TransactionEnvelope;
import org.stellar.sdk.xdr.TransactionSignaturePayload;
import org.stellar.sdk.xdr.XdrElement;

public class Facts {
  static final Gson GSON = new Gson();
  static final Map<String, Class<?>> TYPES = new HashMap<>();
  static final Map<Class<?>, Method[]> METHODS = new HashMap<>();

  static Class<?> cls(String name) throws Exception {
    String k = name.toLowerCase();
    Class<?> c = TYPES.get(k);
    if (c != null) return c;
    // Generated class names match the .x names (TransactionResultMetaV1, SCVal, ...).
    for (String cand : new String[] {name, name.replace("Sc", "SC")}) {
      try {
        c = Class.forName("org.stellar.sdk.xdr." + cand);
        break;
      } catch (ClassNotFoundException e) {
        // try next
      }
    }
    if (c == null) throw new IllegalArgumentException("unknown type " + name);
    TYPES.put(k, c);
    return c;
  }

  static Method[] methods(Class<?> c) throws Exception {
    Method[] m = METHODS.get(c);
    if (m == null) {
      m =
          new Method[] {
            c.getMethod("fromXdrByteArray", byte[].class), c.getMethod("fromJson", String.class)
          };
      METHODS.put(c, m);
    }
    return m;
  }

  static String err(Throwable t) {
    Throwable root = t;
    if (t instanceof java.lang.reflect.InvocationTargetException && t.getCause() != null) {
      root = t.getCause();
    }
    String s = root.getClass().getSimpleName() + ": " + root.getMessage();
    return s.length() > 300 ? s.substring(0, 300) : s;
  }

  static String hex(byte[] b) {
    StringBuilder sb = new StringBuilder(b.length * 2);
    for (byte x : b) sb.append(String.format("%02x", x & 0xff));
    return sb.toString();
  }

  /** Builds the result line by hand so the SDK's JSON text goes out unchanged. */
  static String decode(JsonObject req) {
    String id = req.get("id").getAsString();
    LinkedHashMap<String, Object> out = new LinkedHashMap<>();
    out.put("id", id);
    String rawJson = null;
    try {
      byte[] raw = Base64.getDecoder().decode(req.get("b64").getAsString());
      String type = req.get("type").getAsString();
      Class<?> c = cls(type);
      Method[] m = methods(c);
      XdrElement v;
      try {
        v = (XdrElement) m[0].invoke(null, (Object) raw);
      } catch (Throwable t) {
        out.put("ok", false);
        out.put("error", err(t));
        return GSON.toJson(out);
      }
      byte[] back = v.toXdrByteArray();
      boolean eq = Arrays.equals(back, raw);
      out.put("ok", true);
      out.put("roundtrip_equal", eq);
      if (!eq) out.put("reencoded_b64", Base64.getEncoder().encodeToString(back));
      try {
        rawJson = v.toJson();
        try {
          XdrElement j = (XdrElement) m[1].invoke(null, rawJson);
          byte[] jb = j.toXdrByteArray();
          boolean jeq = Arrays.equals(jb, raw);
          out.put("json_roundtrip_equal", jeq);
          if (!jeq) out.put("json_reencoded_b64", Base64.getEncoder().encodeToString(jb));
        } catch (Throwable t) {
          out.put("json_roundtrip_equal", false);
          out.put("json_roundtrip_error", err(t));
        }
      } catch (Throwable t) {
        out.put("json_error", err(t));
        rawJson = null;
      }
      if (v instanceof TransactionEnvelope
          && req.has("network")
          && !req.get("network").isJsonNull()) {
        model((TransactionEnvelope) v, raw, req.get("network").getAsString(), out);
      }
    } catch (Throwable t) {
      out.put("ok", false);
      out.put("error", "adapter: " + err(t));
      rawJson = null;
    }
    String s = GSON.toJson(out);
    if (rawJson != null) {
      s = s.substring(0, s.length() - 1) + ",\"json\":" + rawJson + "}";
    }
    return s;
  }

  static void model(TransactionEnvelope env, byte[] raw, String passphrase, Map<String, Object> out) {
    Network net = new Network(passphrase);
    // XDR-level hash, no model.
    try {
      TransactionSignaturePayload.TransactionSignaturePayloadTaggedTransaction tagged =
          new TransactionSignaturePayload.TransactionSignaturePayloadTaggedTransaction();
      if (env.getDiscriminant() == EnvelopeType.ENVELOPE_TYPE_TX_FEE_BUMP) {
        tagged.setDiscriminant(EnvelopeType.ENVELOPE_TYPE_TX_FEE_BUMP);
        tagged.setFeeBump(env.getFeeBump().getTx());
      } else if (env.getDiscriminant() == EnvelopeType.ENVELOPE_TYPE_TX) {
        tagged.setDiscriminant(EnvelopeType.ENVELOPE_TYPE_TX);
        tagged.setTx(env.getV1().getTx());
      } else {
        // A v0 envelope is hashed as the equivalent v1 transaction (CAP-15); the
        // model below does that conversion, the XDR layer has no helper for it.
        tagged = null;
      }
      if (tagged != null) {
        TransactionSignaturePayload p =
            TransactionSignaturePayload.builder()
                .networkId(new Hash(net.getNetworkId()))
                .taggedTransaction(tagged)
                .build();
        out.put("xdr_hash", hex(MessageDigest.getInstance("SHA-256").digest(p.toXdrByteArray())));
      }
    } catch (Throwable t) {
      out.put("xdr_hash", "error: " + err(t));
    }
    AbstractTransaction tx;
    try {
      tx = AbstractTransaction.fromEnvelopeXdr(env, net);
    } catch (Throwable t) {
      out.put("hash", "error: " + err(t));
      out.put("model_error", err(t));
      return;
    }
    try {
      out.put("hash", tx.hashHex());
    } catch (Throwable t) {
      out.put("hash", "error: " + err(t));
    }
    try {
      byte[] mb = tx.toEnvelopeXdr().toXdrByteArray();
      boolean meq = Arrays.equals(mb, raw);
      out.put("model_roundtrip_equal", meq);
      if (!meq) out.put("model_reencoded_b64", Base64.getEncoder().encodeToString(mb));
    } catch (Throwable t) {
      out.put("model_roundtrip_equal", false);
      out.put("model_roundtrip_error", err(t));
    }
    try {
      LinkedHashMap<String, Object> mo = new LinkedHashMap<>();
      Transaction inner = tx instanceof FeeBumpTransaction ? ((FeeBumpTransaction) tx).getInnerTransaction() : (Transaction) tx;
      if (tx instanceof FeeBumpTransaction) mo.put("fee_source", ((FeeBumpTransaction) tx).getFeeSource());
      mo.put("source", inner.getSourceAccount());
      List<Object> ops = new ArrayList<>();
      for (Operation op : inner.getOperations()) {
        LinkedHashMap<String, Object> o = new LinkedHashMap<>();
        o.put("source", op.getSourceAccount());
        String dest = null;
        if (op instanceof PaymentOperation) dest = ((PaymentOperation) op).getDestination();
        else if (op instanceof PathPaymentStrictReceiveOperation) dest = ((PathPaymentStrictReceiveOperation) op).getDestination();
        else if (op instanceof PathPaymentStrictSendOperation) dest = ((PathPaymentStrictSendOperation) op).getDestination();
        else if (op instanceof AccountMergeOperation) dest = ((AccountMergeOperation) op).getDestination();
        else if (op instanceof CreateAccountOperation) dest = ((CreateAccountOperation) op).getDestination();
        else if (op instanceof ClawbackOperation) dest = ((ClawbackOperation) op).getFrom();
        if (dest != null) o.put("dest", dest);
        ops.add(o);
      }
      mo.put("ops", ops);
      out.put("model", mo);
    } catch (Throwable t) {
      out.put("model_error", err(t));
    }
  }

  public static void main(String[] args) throws Exception {
    BufferedReader in =
        new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8), 1 << 20);
    BufferedWriter w =
        new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.UTF_8), 1 << 20);
    String line;
    while ((line = in.readLine()) != null) {
      if (line.isBlank()) continue;
      String res;
      JsonObject req;
      try {
        req = JsonParser.parseString(line).getAsJsonObject();
      } catch (Throwable t) {
        continue;
      }
      try {
        res = decode(req);
      } catch (Throwable t) {
        LinkedHashMap<String, Object> o = new LinkedHashMap<>();
        o.put("id", req.has("id") ? req.get("id").getAsString() : null);
        o.put("ok", false);
        o.put("error", "adapter: " + err(t));
        res = GSON.toJson(o);
      }
      w.write(res);
      w.write('\n');
      if (System.getenv("XDRCONF_FLUSH") != null) w.flush();
    }
    w.flush();
  }
}
