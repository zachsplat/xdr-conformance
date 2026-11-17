// serve answers the Stellar RPC calls an indexer needs to ingest ledgers (getHealth,
// getLatestLedger, getNetwork, getVersionInfo, getLedgers) from the Galexie files in -lake.
// Each run of consecutive ledgers is its own endpoint at /r/<first>-<last>; / is the longest run.
// With -pace D, each endpoint starts at its first ledger and advances one ledger every D, like a
// live network, so an indexer that tails the chain sees new ledgers arrive.
package main

import (
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	protocol "github.com/stellar/go-stellar-sdk/protocols/rpc"

	"xdrconf-mockrpc/internal/lake"
)

const passphrase = "Public Global Stellar Network ; September 2015"

type endpoint struct {
	r       lake.Range
	ledgers map[uint32]*lake.Ledger
	start   time.Time
	pace    time.Duration
}

func (e *endpoint) latest() uint32 {
	if e.pace <= 0 {
		return e.r.Last
	}
	n := uint32(time.Since(e.start) / e.pace)
	if e.r.First+n > e.r.Last {
		return e.r.Last
	}
	return e.r.First + n
}

type rpcErr struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

var (
	defLimit = flag.Uint("default-limit", 5, "getLedgers page size when none is given")
	maxLimit = flag.Uint("max-limit", 200, "largest getLedgers page size accepted")
)

func (e *endpoint) call(method string, params json.RawMessage) (any, *rpcErr) {
	latest := e.ledgers[e.latest()]
	oldest := e.ledgers[e.r.First]
	switch method {
	case protocol.GetHealthMethodName:
		return protocol.GetHealthResponse{Status: "healthy", LatestLedger: latest.Seq, LatestLedgerCloseTime: latest.CloseTime,
			OldestLedger: oldest.Seq, OldestLedgerCloseTime: oldest.CloseTime, LedgerRetentionWindow: e.r.Last - e.r.First + 1}, nil
	case protocol.GetLatestLedgerMethodName:
		return protocol.GetLatestLedgerResponse{Hash: latest.Hash, ProtocolVersion: latest.Protocol, Sequence: latest.Seq,
			LedgerCloseTime: latest.CloseTime}, nil
	case protocol.GetNetworkMethodName:
		return protocol.GetNetworkResponse{Passphrase: passphrase, ProtocolVersion: int(latest.Protocol)}, nil
	case protocol.GetVersionInfoMethodName:
		return map[string]any{"version": "xdr-conformance mockrpc", "protocolVersion": latest.Protocol}, nil
	case protocol.GetLedgersMethodName:
		var req protocol.GetLedgersRequest
		if len(params) > 0 {
			if err := json.Unmarshal(params, &req); err != nil {
				return nil, &rpcErr{-32602, err.Error()}
			}
		}
		lr := protocol.LedgerSeqRange{FirstLedger: e.r.First, LastLedger: latest.Seq}
		if err := req.Validate(*maxLimit, lr); err != nil {
			return nil, &rpcErr{-32602, err.Error()}
		}
		if req.Format == protocol.FormatJSON {
			return nil, &rpcErr{-32602, "xdrFormat json is not supported by this mock; use base64"}
		}
		start, limit := req.StartLedger, *defLimit
		if req.Pagination != nil {
			if req.Pagination.Cursor != "" {
				c, err := strconv.ParseUint(req.Pagination.Cursor, 10, 32)
				if err != nil {
					return nil, &rpcErr{-32602, "invalid cursor"}
				}
				start = uint32(c) + 1
			}
			if req.Pagination.Limit > 0 {
				limit = req.Pagination.Limit
			}
		}
		resp := protocol.GetLedgersResponse{Ledgers: []protocol.LedgerInfo{}, LatestLedger: latest.Seq,
			LatestLedgerCloseTime: latest.CloseTime, OldestLedger: oldest.Seq, OldestLedgerCloseTime: oldest.CloseTime}
		for s := start; s <= latest.Seq && uint(len(resp.Ledgers)) < limit; s++ {
			l := e.ledgers[s]
			resp.Ledgers = append(resp.Ledgers, protocol.LedgerInfo{Hash: l.Hash, Sequence: l.Seq, LedgerCloseTime: l.CloseTime,
				LedgerHeader: base64.StdEncoding.EncodeToString(l.Header), LedgerMetadata: base64.StdEncoding.EncodeToString(l.Meta)})
		}
		if n := len(resp.Ledgers); n > 0 {
			resp.Cursor = strconv.FormatUint(uint64(resp.Ledgers[n-1].Sequence), 10)
		} else {
			resp.Cursor = strconv.FormatUint(uint64(start-1), 10)
		}
		return resp, nil
	}
	return nil, &rpcErr{-32601, "method not found: " + method}
}

func (e *endpoint) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST a JSON-RPC 2.0 request", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		ID     json.RawMessage `json:"id"`
		Method string          `json:"method"`
		Params json.RawMessage `json:"params"`
	}
	out := map[string]any{"jsonrpc": "2.0"}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		out["id"], out["error"] = nil, rpcErr{-32700, "parse error"}
	} else {
		out["id"] = req.ID
		if res, e2 := e.call(req.Method, req.Params); e2 != nil {
			out["error"] = e2
		} else {
			out["result"] = res
		}
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(out)
}

func main() {
	dir := flag.String("lake", "", "directory of <seq>.xdr.zst Galexie files")
	addr := flag.String("addr", "127.0.0.1:8000", "listen address")
	pace := flag.Duration("pace", 0, "advance one ledger per interval (0: every ledger available at once)")
	flag.Parse()
	ledgers, ranges, err := lake.Load(*dir)
	if err != nil || len(ranges) == 0 {
		log.Fatalf("load %s: %v (%d ranges)", *dir, err, len(ranges))
	}
	now := time.Now()
	mux := http.NewServeMux()
	longest := ranges[0]
	var list []string
	for _, rg := range ranges {
		ep := &endpoint{r: rg, ledgers: ledgers, start: now, pace: *pace}
		p := fmt.Sprintf("/r/%d-%d", rg.First, rg.Last)
		mux.Handle(p, ep)
		list = append(list, p)
		if rg.Last-rg.First > longest.Last-longest.First {
			longest = rg
		}
	}
	mux.Handle("/", &endpoint{r: longest, ledgers: ledgers, start: now, pace: *pace})
	mux.HandleFunc("/ranges", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(list)
	})
	log.Printf("%d ledgers in %d ranges; / serves %d-%d; endpoints: %s", len(ledgers), len(ranges), longest.First, longest.Last, strings.Join(list, " "))
	log.Fatal(http.ListenAndServe(*addr, mux))
}
