// J3: the default decoding depth (200) refuses Soroban envelopes stellar-core admits.
// Inputs: a real pubnet Soroban transaction (ledger 59000003, tx 06ff45db...) with its
// authorization root replaced by n nested sub-invocations, or its first contract argument
// replaced by n nested SCV_VEC values (sweeps/depth_sweep.py).
import java.nio.file.*;
import org.stellar.sdk.xdr.TransactionEnvelope;

public class DepthLimit {
  public static void main(String[] a) throws Exception {
    for (String f : a) {
      String b64 = Files.readString(Path.of(f)).trim();
      try {
        TransactionEnvelope.fromXdrBase64(b64);
        System.out.println(f + ": decodes");
      } catch (Exception e) {
        System.out.println(f + ": " + e);
      }
    }
  }
}
