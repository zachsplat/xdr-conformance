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
	"sync"
	"time"

	protocol "github.com/stellar/go-stellar-sdk/protocols/rpc"

	"xdrconf-mockrpc/internal/lake"
)

const passphrase = "Public Global Stellar Network ; September 2015"

const help = "xdr-conformance mock Stellar RPC: POST JSON-RPC 2.0 (getHealth, getLatestLedger, getNetwork, getVersionInfo, getLedgers).\n" +
	"Real pubnet ledgers from the public Galexie data lake; /ranges lists the endpoints. Source: https://github.com/zachsplat/xdr-conformance/tree/master/mockrpc\n"

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
	ratePerMin = flag.Int("rate-per-min", 0, "requests per minute per client IP (CF-Connecting-IP, else the peer address); 0 disables")
	maxPages   = flag.Int("max-concurrent", 4, "getLedgers requests served at once; the rest wait")
	pageSem    chan struct{}
	limMu      sync.Mutex
	limits     = map[string]*bucket{}
)

type bucket struct {
	tokens float64
	last   time.Time
}

// allow is a token bucket per client: ratePerMin tokens a minute, bursts up to the same number.
func allow(r *http.Request) bool {
	if *ratePerMin <= 0 {
		return true
	}
	ip := r.Header.Get("CF-Connecting-IP")
	if ip == "" {
		ip, _, _ = strings.Cut(r.RemoteAddr, ":")
	}
	now := time.Now()
	limMu.Lock()
	defer limMu.Unlock()
	if len(limits) > 10000 {
		limits = map[string]*bucket{}
	}
	b, ok := limits[ip]
	if !ok {
		b = &bucket{tokens: float64(*ratePerMin), last: now}
		limits[ip] = b
	}
	b.tokens += now.Sub(b.last).Minutes() * float64(*ratePerMin)
	if b.tokens > float64(*ratePerMin) {
		b.tokens = float64(*ratePerMin)
	}
	b.last = now
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
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
		pageSem <- struct{}{}
		defer func() { <-pageSem }()
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
			meta, err := l.Meta()
			if err != nil {
				return nil, &rpcErr{-32603, err.Error()}
			}
			resp.Ledgers = append(resp.Ledgers, protocol.LedgerInfo{Hash: l.Hash, Sequence: l.Seq, LedgerCloseTime: l.CloseTime,
				LedgerHeader: base64.StdEncoding.EncodeToString(l.Header), LedgerMetadata: base64.StdEncoding.EncodeToString(meta)})
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
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method == http.MethodGet || r.Method == http.MethodHead {
		// a person opening the URL in a browser gets a short page; JSON-RPC clients always POST
		if r.URL.Path != "/" && !strings.HasPrefix(r.URL.Path, "/r/") {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(page(e, baseURL(r))))
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, help, http.StatusMethodNotAllowed)
		return
	}
	if !allow(r) {
		w.Header().Set("Retry-After", "10")
		http.Error(w, "rate limited", http.StatusTooManyRequests)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
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

var endpointList []string

func baseURL(r *http.Request) string {
	scheme := "http"
	if r.TLS != nil || r.Header.Get("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	return scheme + "://" + r.Host
}

func page(e *endpoint, base string) string {
	var rows strings.Builder
	for _, p := range endpointList {
		fmt.Fprintf(&rows, "<li><code>%s</code></li>", p)
	}
	limits := fmt.Sprintf("Up to %d ledgers per getLedgers page (default %d), %d page requests at a time", *maxLimit, *defLimit, *maxPages)
	if *ratePerMin > 0 {
		limits += fmt.Sprintf(", %d requests a minute per client", *ratePerMin)
	}
	return fmt.Sprintf(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mock Stellar RPC</title><style>body{font:16px/1.55 system-ui,sans-serif;max-width:46rem;margin:2rem auto;padding:0 16px;color:#1b1f24;background:#fff}
code,pre{font:14px ui-monospace,monospace;background:#f2f4f7;border-radius:4px}code{padding:1px 4px}pre{padding:12px;overflow-x:auto}
@media (prefers-color-scheme:dark){body{color:#e6e9ee;background:#0f131a}code,pre{background:#1a202b}a{color:#7cc4ff}}</style></head><body>
<h1>Mock Stellar RPC</h1>
<p>A Stellar RPC that serves real pubnet ledgers from the public Galexie data lake, for testing indexers and SDKs. Point an indexer that reads ledgers through <code>getLedgers</code> at it and it ingests them with no code changes. Every ledger is served byte for byte as Galexie stored it.</p>
<p>It answers JSON-RPC 2.0 over POST: <code>getHealth</code>, <code>getLatestLedger</code>, <code>getNetwork</code>, <code>getVersionInfo</code> and <code>getLedgers</code> (base64 XDR, <code>startLedger</code> or <code>cursor</code> paging). This URL serves ledgers %d to %d.</p>
<pre>curl -s -X POST %s -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"getLedgers","params":{"startLedger":%d,"pagination":{"limit":2}}}'</pre>
<p>Each run of consecutive ledgers is its own endpoint (<a href="/ranges">/ranges</a>):</p><ul>%s</ul>
<p>Limits: %s. It is a test fixture holding only these ledgers, not a general RPC. The server writes no per-request logs; client addresses are held in memory only for the rate limit.</p>
<p>Source, tests and the byte-for-byte check: <a href="https://github.com/zachsplat/xdr-conformance/tree/master/mockrpc">github.com/zachsplat/xdr-conformance</a>.</p>
</body></html>`, e.r.First, e.r.Last, base+pathFor(e), e.r.First, rows.String(), limits)
}

var longestRange lake.Range

func pathFor(e *endpoint) string {
	if e.r == longestRange {
		return "/"
	}
	return fmt.Sprintf("/r/%d-%d", e.r.First, e.r.Last)
}

func main() {
	dir := flag.String("lake", "", "directory of <seq>.xdr.zst Galexie files")
	addr := flag.String("addr", "127.0.0.1:8000", "listen address")
	pace := flag.Duration("pace", 0, "advance one ledger per interval (0: every ledger available at once)")
	flag.Parse()
	pageSem = make(chan struct{}, *maxPages)
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
	endpointList = list
	longestRange = longest
	mux.Handle("/", &endpoint{r: longest, ledgers: ledgers, start: now, pace: *pace})
	mux.HandleFunc("/ranges", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(list)
	})
	log.Printf("%d ledgers in %d ranges; / serves %d-%d; endpoints: %s", len(ledgers), len(ranges), longest.First, longest.Last, strings.Join(list, " "))
	srv := &http.Server{Addr: *addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second,
		WriteTimeout: 60 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16 << 10}
	log.Fatal(srv.ListenAndServe())
}
