// Conformance adapter for go-stellar-sdk (xdr, network, txnbuild).
// Same JSONL protocol as runners/rust/src/facts.rs. Go has no SEP-51 JSON
// encoder, so results carry decode, round-trip and hash only.
package main

import (
	"bufio"
	"bytes"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/stellar/go-stellar-sdk/network"
	"github.com/stellar/go-stellar-sdk/txnbuild"
	"github.com/stellar/go-stellar-sdk/xdr"
)

type req struct {
	ID      string `json:"id"`
	Op      string `json:"op"`
	Type    string `json:"type"`
	B64     string `json:"b64"`
	Network string `json:"network"`
}

type marshaler interface{ MarshalBinary() ([]byte, error) }

func newValue(t string) (marshaler, error) {
	switch strings.ToLower(t) {
	case "transactionenvelope":
		return &xdr.TransactionEnvelope{}, nil
	case "transactionresultmeta":
		return &xdr.TransactionResultMeta{}, nil
	case "transactionresultmetav1":
		return &xdr.TransactionResultMetaV1{}, nil
	case "ledgerclosemetabatch":
		return &xdr.LedgerCloseMetaBatch{}, nil
	case "ledgerclosemeta":
		return &xdr.LedgerCloseMeta{}, nil
	case "scval":
		return &xdr.ScVal{}, nil
	case "ledgerentry":
		return &xdr.LedgerEntry{}, nil
	case "ledgerkey":
		return &xdr.LedgerKey{}, nil
	case "transactionresult":
		return &xdr.TransactionResult{}, nil
	case "transactionmeta":
		return &xdr.TransactionMeta{}, nil
	case "sorobanauthorizationentry":
		return &xdr.SorobanAuthorizationEntry{}, nil
	case "memo":
		return &xdr.Memo{}, nil
	case "muxedaccount":
		return &xdr.MuxedAccount{}, nil
	case "signerkey":
		return &xdr.SignerKey{}, nil
	case "asset":
		return &xdr.Asset{}, nil
	case "changetrustasset":
		return &xdr.ChangeTrustAsset{}, nil
	}
	return nil, fmt.Errorf("unknown type %s", t)
}

func decode(r req) map[string]any {
	out := map[string]any{"id": r.ID}
	raw, err := base64.StdEncoding.DecodeString(r.B64)
	if err != nil {
		out["ok"], out["error"] = false, "base64: "+err.Error()
		return out
	}
	v, err := newValue(r.Type)
	if err != nil {
		out["ok"], out["error"] = false, err.Error()
		return out
	}
	if err := xdr.SafeUnmarshalBase64(r.B64, v); err != nil {
		out["ok"], out["error"] = false, err.Error()
		return out
	}
	back, err := v.MarshalBinary()
	if err != nil {
		out["ok"], out["error"] = false, "re-encode: "+err.Error()
		return out
	}
	out["ok"] = true
	out["roundtrip_equal"] = bytes.Equal(back, raw)
	if !bytes.Equal(back, raw) {
		out["reencoded_b64"] = base64.StdEncoding.EncodeToString(back)
	}
	if env, ok := v.(*xdr.TransactionEnvelope); ok && r.Network != "" {
		if h, err := network.HashTransactionInEnvelope(*env, r.Network); err == nil {
			out["hash"] = hex.EncodeToString(h[:])
		} else {
			out["hash"] = "error: " + err.Error()
		}
		// Second opinion through txnbuild's own transaction model.
		if gt, err := txnbuild.TransactionFromXDR(r.B64); err == nil {
			var hs string
			if tx, ok := gt.Transaction(); ok {
				h, e := tx.HashHex(r.Network)
				hs = h
				if e != nil {
					hs = "error: " + e.Error()
				}
			} else if fb, ok := gt.FeeBump(); ok {
				h, e := fb.HashHex(r.Network)
				hs = h
				if e != nil {
					hs = "error: " + e.Error()
				}
			}
			out["txnbuild_hash"] = hs
		} else {
			out["txnbuild_hash"] = "error: " + err.Error()
		}
	}
	return out
}

func main() {
	sc := bufio.NewScanner(os.Stdin)
	sc.Buffer(make([]byte, 64<<20), 1<<30)
	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()
	enc := json.NewEncoder(w)
	for sc.Scan() {
		line := sc.Bytes()
		if len(bytes.TrimSpace(line)) == 0 {
			continue
		}
		var r req
		if err := json.Unmarshal(line, &r); err != nil {
			continue
		}
		enc.Encode(decode(r))
	}
}
