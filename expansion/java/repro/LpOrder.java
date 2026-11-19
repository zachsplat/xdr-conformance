// J1: a real testnet ChangeTrust into a same-code liquidity pool cannot be read by the transaction model.
// Input: testnet ledger 5,521,445, tx b79f02ec... (corpus/entries/lp-issuers-strkey-vs-bytes-order).
import org.stellar.sdk.*;
import org.stellar.sdk.xdr.TransactionEnvelope;

public class LpOrder {
  static final String ENV = "AAAAAgAAAABwm1egqg61kl+sbyG39Uhz+O1b6svKdmooOxjBQ+QEAgAAASwAVEAjAAAAAQAAAAAAAAAAAAAAAwAAAAAAAAAGAAAAAVVTRAAAAAAAywAq868W2hpjMFU9nws/BsEP427/SmaodctC0Vf0HQl//////////wAAAAAAAAAGAAAAAVVTRAAAAAAA+FmP//u0HmlrWaIyODMphovD/Squcbd5Wzsj5p34kNh//////////wAAAAAAAAAGAAAAAwAAAAAAAAABVVNEAAAAAADLACrzrxbaGmMwVT2fCz8GwQ/jbv9KZqh1y0LRV/QdCQAAAAFVU0QAAAAAAPhZj//7tB5pa1miMjgzKYaLw/0qrnG3eVs7I+ad+JDYAAAAHn//////////AAAAAAAAAAFD5AQCAAAAQDrwk4Ts77VQU/+bwL/3XWfU2A/avJb8Xammjo55O0CJB7b8ybY5JlupZ/pDu0MmbrRd2bGAeGj6V2Dhj491mgU=";

  public static void main(String[] args) throws Exception {
    System.out.println("XDR layer decodes: " + (TransactionEnvelope.fromXdrBase64(ENV) != null));
    try {
      AbstractTransaction tx = AbstractTransaction.fromEnvelopeXdr(ENV, Network.TESTNET);
      System.out.println("model hash " + tx.hashHex());
    } catch (Exception e) {
      System.out.println("fromEnvelopeXdr: " + e);
    }
    // The pool as the network stores it: asset_a issuer GDFQ..., asset_b issuer GD4F...
    Asset a = Asset.createNonNativeAsset("USD", "GDFQAKXTV4LNUGTDGBKT3HYLH4DMCD7DN37UUZVIOXFUFUKX6QOQTN2L");
    Asset b = Asset.createNonNativeAsset("USD", "GD4FTD777O2B42LLLGRDEOBTFGDIXQ75FKXHDN3ZLM5SHZU57CINQCG3");
    System.out.println("a.compareTo(b) = " + a.compareTo(b) + " (the network orders a before b)");
    try {
      System.out.println("pool id " + new LiquidityPool(a, b).getLiquidityPoolId());
    } catch (Exception e) {
      System.out.println("new LiquidityPool(a, b): " + e);
    }
  }
}
