// J4: an envelope followed by 4 zero bytes is accepted and hashes like the original.
import org.stellar.sdk.*;

public class TrailingBytes {
  static final String BASE = "AAAAAgAAAABSTh04F5yGRuzDsfhzZtQUhnLaHgY4Bf9HZXhQw+kkTwADDUABIfX+AAmFkwAAAAAAAAABAAAABTEwNDk4AAAAAAAAAQAAAAEAAAAAYSd9wNMUgqCI7bmo8/YYUMD8Tgt5AWP+LEM7SThIB7kAAAABAAAAAOXDqt/kCw0khZz7brrwCR79i8j1W5kyVZKR8d8S3vVOAAAAAAAAAAAk8WXAAAAAAAAAAAHD6SRPAAAAQHcPWaF0qqogZBBO8hAuiUZMpflFXC29MZqz5qN1xKrbfRNjdB17TGR5PPaInWmgYHHnBxrIrmLeU6p0R8wHbwA=";
  static final String TRAILING = "AAAAAgAAAABSTh04F5yGRuzDsfhzZtQUhnLaHgY4Bf9HZXhQw+kkTwADDUABIfX+AAmFkwAAAAAAAAABAAAABTEwNDk4AAAAAAAAAQAAAAEAAAAAYSd9wNMUgqCI7bmo8/YYUMD8Tgt5AWP+LEM7SThIB7kAAAABAAAAAOXDqt/kCw0khZz7brrwCR79i8j1W5kyVZKR8d8S3vVOAAAAAAAAAAAk8WXAAAAAAAAAAAHD6SRPAAAAQHcPWaF0qqogZBBO8hAuiUZMpflFXC29MZqz5qN1xKrbfRNjdB17TGR5PPaInWmgYHHnBxrIrmLeU6p0R8wHbwAAAAAA";

  public static void main(String[] a) {
    for (String s : new String[] {BASE, TRAILING}) {
      try {
        AbstractTransaction tx = AbstractTransaction.fromEnvelopeXdr(s, Network.PUBLIC);
        System.out.println((s == BASE ? "original " : "+4 bytes ") + "accepted, hash " + tx.hashHex()
            + ", re-encodes to original: " + tx.toEnvelopeXdrBase64().equals(BASE));
      } catch (Exception e) {
        System.out.println((s == BASE ? "original " : "+4 bytes ") + "rejected: " + e);
      }
    }
  }
}
