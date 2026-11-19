// J2: XDR-JSON (toJson/fromJson) uses names that are not SEP-51 for TransactionResultCode and
// OperationResultCode arms, and writes AssetCode as a union object instead of the bare code.
import org.stellar.sdk.xdr.*;

public class ResultJson {
  public static void main(String[] a) throws Exception {
    // TransactionResult of pubnet ledger 28000000, tx index 0 (fee 100, one successful payment).
    TransactionResult r = TransactionResult.fromXdrBase64("AAAAAAAAAGQAAAAAAAAAAQAAAAAAAAABAAAAAAAAAAA=");
    System.out.println("TransactionResult.toJson: " + r.toJson());
    String sep51 = "{\"fee_charged\":\"100\",\"result\":{\"tx_success\":[{\"op_inner\":{\"payment\":\"success\"}}]},\"ext\":\"v0\"}";
    try {
      System.out.println("fromJson(SEP-51) -> " + TransactionResult.fromJson(sep51).toXdrBase64());
    } catch (Exception e) {
      System.out.println("TransactionResult.fromJson(SEP-51 form): " + e);
    }
    System.out.println("OperationResultCode.opTOO_MANY_SUBENTRIES.toJson: " + OperationResultCode.opTOO_MANY_SUBENTRIES.toJson());
    // AssetCode "FIL" (credit_alphanum4), as in AllowTrustOp.asset.
    AssetCode c = AssetCode.fromXdrBase64("AAAAAUZJTAA=");
    System.out.println("AssetCode.toJson: " + c.toJson());
    try {
      System.out.println("fromJson(\"FIL\") -> " + AssetCode.fromJson("\"FIL\"").toXdrBase64());
    } catch (Exception e) {
      System.out.println("AssetCode.fromJson(\"FIL\"): " + e);
    }
  }
}
