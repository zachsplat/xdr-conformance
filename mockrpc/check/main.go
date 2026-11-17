// check reads every ledger back through the two paths an indexer uses and compares each
// LedgerCloseMeta byte for byte, and each ledger hash, with the lake:
//  1. RPC: go-stellar-sdk's RPCLedgerBackend against the mock (getHealth + getLedgers), per range,
//     plus a raw getLedgers walk that follows the cursor;
//  2. Datastore: go-stellar-sdk's BufferedStorageBackend over the exported Galexie layout.
package main

import (
	"bytes"
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"strconv"
	"time"

	"github.com/stellar/go-stellar-sdk/clients/rpcclient"
	"github.com/stellar/go-stellar-sdk/ingest/ledgerbackend"
	protocol "github.com/stellar/go-stellar-sdk/protocols/rpc"
	"github.com/stellar/go-stellar-sdk/support/datastore"
	"github.com/stellar/go-stellar-sdk/xdr"

	"xdrconf-mockrpc/internal/lake"
)

var fails int

func cmp(path string, want *lake.Ledger, got xdr.LedgerCloseMeta) {
	b, err := got.MarshalBinary()
	if err != nil || !bytes.Equal(b, want.Meta) || got.LedgerHash().HexString() != want.Hash {
		fails++
		log.Printf("FAIL %s ledger %d: bytes equal=%v hash %s vs %s err=%v", path, want.Seq, bytes.Equal(b, want.Meta), got.LedgerHash().HexString(), want.Hash, err)
	}
}

func main() {
	src := flag.String("lake", "", "lake directory")
	url := flag.String("rpc", "http://127.0.0.1:8000", "mock base URL")
	store := flag.String("datastore", "", "exported Galexie datastore root")
	flag.Parse()
	ctx := context.Background()
	ledgers, ranges, err := lake.Load(*src)
	if err != nil {
		log.Fatal(err)
	}
	nRPC, nWalk, nStore := 0, 0, 0
	for _, rg := range ranges {
		ep := fmt.Sprintf("%s/r/%d-%d", *url, rg.First, rg.Last)
		be := ledgerbackend.NewRPCLedgerBackend(ledgerbackend.RPCLedgerBackendOptions{RPCServerURL: ep, BufferSize: 10})
		if err := be.PrepareRange(ctx, ledgerbackend.BoundedRange(rg.First, rg.Last)); err != nil {
			log.Fatalf("%s PrepareRange: %v", ep, err)
		}
		for s := rg.First; s <= rg.Last; s++ {
			m, err := be.GetLedger(ctx, s)
			if err != nil {
				log.Fatalf("%s GetLedger %d: %v", ep, s, err)
			}
			cmp("rpc-backend", ledgers[s], m)
			nRPC++
		}
		_ = be.Close()
		// raw walk with the cursor, the way an indexer pages through getLedgers
		cl := rpcclient.NewClient(ep, nil)
		req := protocol.GetLedgersRequest{StartLedger: rg.First, Pagination: &protocol.LedgerPaginationOptions{Limit: 7}}
		next := rg.First
		for {
			resp, err := cl.GetLedgers(ctx, req)
			if err != nil {
				log.Fatalf("%s getLedgers: %v", ep, err)
			}
			if len(resp.Ledgers) == 0 {
				break
			}
			for _, li := range resp.Ledgers {
				if li.Sequence != next {
					log.Fatalf("%s walk: got %d, want %d", ep, li.Sequence, next)
				}
				var m xdr.LedgerCloseMeta
				if err := xdr.SafeUnmarshalBase64(li.LedgerMetadata, &m); err != nil {
					log.Fatal(err)
				}
				cmp("rpc-walk", ledgers[li.Sequence], m)
				var h xdr.LedgerHeaderHistoryEntry
				if err := xdr.SafeUnmarshalBase64(li.LedgerHeader, &h); err != nil || h.Header.LedgerSeq != xdr.Uint32(li.Sequence) {
					fails++
					log.Printf("FAIL rpc-walk header %d: %v", li.Sequence, err)
				}
				next++
				nWalk++
			}
			req = protocol.GetLedgersRequest{Pagination: &protocol.LedgerPaginationOptions{Cursor: resp.Cursor, Limit: 7}}
		}
		if next != rg.Last+1 {
			fails++
			log.Printf("FAIL rpc-walk %s stopped at %d", ep, next)
		}
		cl.Close()
		// out-of-range start must be refused the way stellar-rpc refuses it
		if _, err := cl.GetLedgers(ctx, protocol.GetLedgersRequest{StartLedger: rg.Last + 1}); err == nil {
			fails++
			log.Printf("FAIL %s accepted a start ledger past the latest", ep)
		}
	}
	if *store != "" {
		cfg := datastore.DataStoreConfig{Type: "Filesystem", Params: map[string]string{"destination_path": *store}}
		ds, err := datastore.NewDataStore(ctx, cfg)
		if err != nil {
			log.Fatal(err)
		}
		schema, err := datastore.LoadSchema(ctx, ds, cfg)
		if err != nil {
			log.Fatal(err)
		}
		for _, rg := range ranges {
			be, err := ledgerbackend.NewBufferedStorageBackend(ledgerbackend.BufferedStorageBackendConfig{BufferSize: 10, NumWorkers: 2,
				RetryLimit: 2, RetryWait: time.Second}, ds, schema)
			if err != nil {
				log.Fatal(err)
			}
			if err := be.PrepareRange(ctx, ledgerbackend.BoundedRange(rg.First, rg.Last)); err != nil {
				log.Fatal(err)
			}
			for s := rg.First; s <= rg.Last; s++ {
				m, err := be.GetLedger(ctx, s)
				if err != nil {
					log.Fatalf("datastore GetLedger %d: %v", s, err)
				}
				cmp("datastore", ledgers[s], m)
				nStore++
			}
			_ = be.Close()
		}
	}
	fmt.Printf("ranges %d; ledgers %d; rpc-backend %d; rpc-walk %d; datastore %d; failures %s\n", len(ranges), len(ledgers), nRPC, nWalk, nStore, strconv.Itoa(fails))
	if fails > 0 {
		os.Exit(1)
	}
}
