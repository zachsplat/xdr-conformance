// Command xdrc-extract cuts one transaction out of a Galexie ledger object
// (zstd LedgerCloseMetaBatch) into corpus entry files: envelope.xdr and
// meta.xdr (the TransactionResultMeta or TransactionResultMetaV1 exactly as
// the ledger holds it). It prints the facts the manifest needs as JSON.
//
//	xdrc-extract -lcm 4437357.xdr.zst -network testnet -tx HASH -out DIR
package main

import (
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/stellar/go-stellar-sdk/network"
	"github.com/stellar/go-stellar-sdk/support/compressxdr"
	"github.com/stellar/go-stellar-sdk/xdr"
)

func main() {
	lcmPath := flag.String("lcm", "", "Galexie object")
	netFlag := flag.String("network", "pubnet", "pubnet, testnet or standalone")
	txHash := flag.String("tx", "", "transaction hash")
	out := flag.String("out", "", "entry directory to write")
	flag.Parse()
	pass := map[string]string{"pubnet": network.PublicNetworkPassphrase, "testnet": network.TestNetworkPassphrase,
		"standalone": "Standalone Network ; February 2017"}[*netFlag]

	var batch xdr.LedgerCloseMetaBatch
	f, err := os.Open(*lcmPath)
	check(err)
	_, err = compressxdr.NewXDRDecoder(compressxdr.DefaultCompressor, &batch).ReadFrom(f)
	check(err)
	lcm := batch.LedgerCloseMetas[0]

	// Find the envelope by hash in the tx set, and its position in apply order.
	var env *xdr.TransactionEnvelope
	for _, e := range lcm.TransactionEnvelopes() {
		h, err := network.HashTransactionInEnvelope(e, pass)
		check(err)
		if hex.EncodeToString(h[:]) == *txHash {
			e := e
			env = &e
		}
	}
	if env == nil {
		check(fmt.Errorf("transaction %s not in ledger %d", *txHash, lcm.LedgerSequence()))
	}
	var metaBytes []byte
	metaType := ""
	applyIndex := -1
	for i := 0; i < lcm.CountTransactions(); i++ {
		th := lcm.TransactionHash(i)
		if hex.EncodeToString(th[:]) != *txHash {
			continue
		}
		applyIndex = i
		switch lcm.V {
		case 1:
			metaBytes, err = lcm.V1.TxProcessing[i].MarshalBinary()
			metaType = "TransactionResultMeta"
		case 2:
			metaBytes, err = lcm.V2.TxProcessing[i].MarshalBinary()
			metaType = "TransactionResultMetaV1"
		default:
			err = fmt.Errorf("LedgerCloseMeta v%d not supported", lcm.V)
		}
		check(err)
	}
	envBytes, err := env.MarshalBinary()
	check(err)
	check(os.MkdirAll(*out, 0o755))
	check(os.WriteFile(filepath.Join(*out, "envelope.xdr"), envBytes, 0o644))
	check(os.WriteFile(filepath.Join(*out, "meta.xdr"), metaBytes, 0o644))
	json.NewEncoder(os.Stdout).Encode(map[string]any{
		"ledger":           lcm.LedgerSequence(),
		"protocol_version": lcm.ProtocolVersion(),
		"closed_at":        time.Unix(int64(lcm.LedgerCloseTime()), 0).UTC().Format(time.RFC3339),
		"apply_index":      applyIndex,
		"meta_xdr_type":    metaType,
		"lcm_version":      lcm.V,
	})
}

func check(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "xdrc-extract:", err)
		os.Exit(1)
	}
}
