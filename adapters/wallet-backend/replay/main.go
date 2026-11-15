// Command xdrc-replay is the wallet-backend replay adapter of xdr-conformance.
//
// It is copied into a wallet-backend checkout (any commit) as cmd/xdrc-replay
// and run there, so it drives that commit's own indexer: indexer.ProcessLedger
// fills an IndexerBuffer exactly as live ingestion does, and every address the
// buffer would write to a BYTEA column goes through that commit's own
// driver.Valuer (the encode the COPY path runs) and sql.Scanner (the read the
// API runs).
//
// Independently of wallet-backend, the adapter derives facts from the ledger
// XDR itself (accounts created, trustlines created, signers added) and checks
// that the indexer recorded a state change for each one.
//
// Inputs:
//
//	-lcm FILE      a Galexie object: zstd LedgerCloseMetaBatch (*.xdr.zst);
//	               FILE#TXHASH reports only that transaction (the whole
//	               ledger is still processed)
//	-entry DIR     a corpus entry (envelope.xdr + meta.xdr); the transaction is
//	               wrapped in a one-transaction LedgerCloseMeta using the
//	               ledger number, protocol and close time from -manifest
//
// Output: one JSON object per input on stdout.
//
// The calls into wallet-backend go through reflect so that one source file
// builds on every commit even though NewIndexer and ProcessLedger changed
// arity over time.
package main

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"time"

	"github.com/alitto/pond/v2"
	"github.com/stellar/go-stellar-sdk/ingest"
	"github.com/stellar/go-stellar-sdk/network"
	"github.com/stellar/go-stellar-sdk/strkey"
	"github.com/stellar/go-stellar-sdk/support/compressxdr"
	"github.com/stellar/go-stellar-sdk/xdr"

	"github.com/stellar/wallet-backend/internal/indexer"
	"github.com/stellar/wallet-backend/internal/indexer/types"
)

type addrCheck struct {
	Where    string `json:"where"`
	Type     string `json:"type"`
	In       string `json:"in"`
	Stored   int    `json:"stored_bytes,omitempty"`
	Out      string `json:"out,omitempty"`
	Verdict  string `json:"verdict"`
	Error    string `json:"error,omitempty"`
	ToID     int64  `json:"to_id,omitempty"`
	TxHash   string `json:"tx_hash,omitempty"`
	OpIndex  int    `json:"op_index,omitempty"`
	Category string `json:"category,omitempty"`
}

type fact struct {
	Kind     string `json:"kind"`
	TxHash   string `json:"tx_hash"`
	OpIndex  int    `json:"op_index"`
	OpType   string `json:"op_type"`
	Account  string `json:"account"`
	Detail   string `json:"detail"`
	Found    bool   `json:"recorded"`
	Recorded string `json:"recorded_as,omitempty"`
}

type report struct {
	Adapter          string         `json:"adapter"`
	Commit           string         `json:"wallet_backend_commit"`
	Input            string         `json:"input"`
	Ledger           uint32         `json:"ledger"`
	TxFilter         string         `json:"tx_filter,omitempty"`
	Transactions     int            `json:"transactions"`
	StateChanges     int            `json:"state_changes"`
	AddressesChecked int            `json:"addresses_checked"`
	VerdictCounts    map[string]int `json:"address_verdicts"`
	Anomalies        []addrCheck    `json:"address_anomalies"`
	Facts            []fact         `json:"facts"`
	Result           string         `json:"result"`
	Why              []string       `json:"why,omitempty"`
	Error            string         `json:"error,omitempty"`
}

type multi []string

func (m *multi) String() string     { return strings.Join(*m, ",") }
func (m *multi) Set(v string) error { *m = append(*m, v); return nil }

func main() {
	var lcms, entries, manifests multi
	flag.Var(&lcms, "lcm", "Galexie zstd LedgerCloseMetaBatch file, optionally FILE#TXHASH (repeatable)")
	flag.Var(&entries, "entry", "corpus entry directory (repeatable)")
	flag.Var(&manifests, "manifest", "corpus manifest (for -entry; repeatable)")
	netFlag := flag.String("network", "pubnet", "pubnet, testnet or standalone (for -lcm)")
	commit := flag.String("commit", "unknown", "wallet-backend commit under test, echoed in the output")
	flag.Parse()

	out := json.NewEncoder(os.Stdout)
	for _, arg := range lcms {
		p, txFilter, _ := strings.Cut(arg, "#")
		pass := network.PublicNetworkPassphrase
		switch *netFlag {
		case "testnet":
			pass = network.TestNetworkPassphrase
		case "standalone":
			pass = "Standalone Network ; February 2017" // stellar/quickstart --local
		}
		r := report{Input: *netFlag + ":" + filepath.Base(p), TxFilter: txFilter}
		var batch xdr.LedgerCloseMetaBatch
		f, err := os.Open(p)
		if err == nil {
			_, err = compressxdr.NewXDRDecoder(compressxdr.DefaultCompressor, &batch).ReadFrom(f)
			f.Close()
		}
		if err != nil {
			r.Result, r.Error = "error", "reading ledger: "+err.Error()
		} else {
			for _, lcm := range batch.LedgerCloseMetas {
				r = replay(pass, lcm, r)
			}
		}
		finish(&r, *commit)
		must(out.Encode(r))
	}
	if len(entries) > 0 {
		man := map[string]manEntry{}
		for _, p := range manifests {
			for id, e := range loadManifest(p) {
				man[id] = e
			}
		}
		for _, dir := range entries {
			id := filepath.Base(filepath.Clean(dir))
			r := report{Input: "corpus:" + id}
			e, ok := man[id]
			if !ok {
				r.Result, r.Error = "error", "entry not in manifest"
				finish(&r, *commit)
				must(out.Encode(r))
				continue
			}
			lcm, err := wrapEntry(dir, e)
			if err != nil {
				r.Result, r.Error = "error", err.Error()
			} else {
				r.TxFilter = e.Expected.TxHash
				r = replay(e.Passphrase, lcm, r)
			}
			finish(&r, *commit)
			must(out.Encode(r))
		}
	}
}

func must(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
}

// ---- corpus entries ----

type manEntry struct {
	ID         string `json:"id"`
	Passphrase string `json:"network_passphrase"`
	Protocol   uint32 `json:"protocol_version"`
	Source     struct {
		Ledger   uint32 `json:"ledger"`
		ClosedAt string `json:"closed_at"`
	} `json:"source"`
	Expected struct {
		TxHash string `json:"tx_hash"`
	} `json:"expected"`
	Files struct {
		Meta struct {
			XDRType string `json:"xdr_type"`
		} `json:"meta"`
	} `json:"files"`
}

func loadManifest(path string) map[string]manEntry {
	b, err := os.ReadFile(path)
	must(err)
	var m struct {
		Entries []manEntry `json:"entries"`
	}
	must(json.Unmarshal(b, &m))
	out := map[string]manEntry{}
	for _, e := range m.Entries {
		out[e.ID] = e
	}
	return out
}

// wrapEntry builds the smallest LedgerCloseMeta that carries one corpus
// transaction: its envelope in a one-phase tx set and its result meta as the
// only processing entry (LedgerCloseMetaV2 for TransactionResultMetaV1, V1 for
// TransactionResultMeta, as the manifest records). Ledger number, protocol and
// close time come from the manifest. Nothing else in the ledger is read by the
// transaction reader.
func wrapEntry(dir string, e manEntry) (xdr.LedgerCloseMeta, error) {
	var env xdr.TransactionEnvelope
	if err := readXDR(filepath.Join(dir, "envelope.xdr"), &env); err != nil {
		return xdr.LedgerCloseMeta{}, err
	}
	closeTime := int64(0)
	if e.Source.ClosedAt != "" {
		if t, err := time.Parse(time.RFC3339, e.Source.ClosedAt); err == nil {
			closeTime = t.Unix()
		}
	}
	comps := []xdr.TxSetComponent{{
		Type:                  xdr.TxSetComponentTypeTxsetCompTxsMaybeDiscountedFee,
		TxsMaybeDiscountedFee: &xdr.TxSetComponentTxsMaybeDiscountedFee{Txs: []xdr.TransactionEnvelope{env}},
	}}
	header := xdr.LedgerHeaderHistoryEntry{Header: xdr.LedgerHeader{
		LedgerVersion: xdr.Uint32(e.Protocol),
		LedgerSeq:     xdr.Uint32(e.Source.Ledger),
		ScpValue:      xdr.StellarValue{CloseTime: xdr.TimePoint(closeTime)},
	}}
	txSet := xdr.GeneralizedTransactionSet{V: 1, V1TxSet: &xdr.TransactionSetV1{
		Phases: []xdr.TransactionPhase{{V: 0, V0Components: &comps}},
	}}
	switch e.Files.Meta.XDRType {
	case "TransactionResultMetaV1", "":
		var meta xdr.TransactionResultMetaV1
		if err := readXDR(filepath.Join(dir, "meta.xdr"), &meta); err != nil {
			return xdr.LedgerCloseMeta{}, err
		}
		return xdr.LedgerCloseMeta{V: 2, V2: &xdr.LedgerCloseMetaV2{
			LedgerHeader: header, TxSet: txSet, TxProcessing: []xdr.TransactionResultMetaV1{meta},
		}}, nil
	case "TransactionResultMeta":
		var meta xdr.TransactionResultMeta
		if err := readXDR(filepath.Join(dir, "meta.xdr"), &meta); err != nil {
			return xdr.LedgerCloseMeta{}, err
		}
		return xdr.LedgerCloseMeta{V: 1, V1: &xdr.LedgerCloseMetaV1{
			LedgerHeader: header, TxSet: txSet, TxProcessing: []xdr.TransactionResultMeta{meta},
		}}, nil
	}
	return xdr.LedgerCloseMeta{}, fmt.Errorf("meta type %q not supported", e.Files.Meta.XDRType)
}

func readXDR(path string, v interface{}) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if err := xdr.SafeUnmarshal(b, v); err != nil {
		return fmt.Errorf("%s: %w", filepath.Base(path), err)
	}
	return nil
}

// ---- replay ----

func replay(pass string, lcm xdr.LedgerCloseMeta, r report) report {
	ctx := context.Background()
	r.Ledger = lcm.LedgerSequence()

	idx, err := newIndexer(pass)
	if err != nil {
		r.Result, r.Error = "error", "NewIndexer: "+err.Error()
		return r
	}
	buf := indexer.NewIndexerBuffer()
	if err := processLedger(ctx, pass, lcm, idx, buf); err != nil {
		// ProcessLedger failing means live ingestion cannot get past this ledger.
		r.Result, r.Error = "halts", "ProcessLedger: "+err.Error()
		return r
	}

	txs, err := ledgerTransactions(pass, lcm)
	if err != nil {
		r.Result, r.Error = "error", "reading transactions: "+err.Error()
		return r
	}
	seq := int64(lcm.LedgerSequence())
	hashByToID := map[int64]string{}
	want := map[int64]bool{}
	for _, tx := range txs {
		toid := seq<<32 | int64(tx.Index)<<12
		h := hex.EncodeToString(tx.Hash[:])
		hashByToID[toid] = h
		if r.TxFilter == "" || r.TxFilter == h {
			want[toid] = true
			r.Transactions++
		}
	}
	keep := func(id int64) bool { return want[id&^0xFFF] }

	if r.VerdictCounts == nil {
		r.VerdictCounts = map[string]int{}
	}
	record := func(c addrCheck, id int64) {
		c.ToID = id
		c.TxHash = hashByToID[id&^0xFFF]
		c.OpIndex = int(id & 0xFFF)
		r.AddressesChecked++
		r.VerdictCounts[c.Verdict]++
		if c.Verdict != "exact" {
			r.Anomalies = append(r.Anomalies, c)
		}
	}

	for _, part := range []struct {
		where string
		m     map[int64]map[string]struct{}
	}{
		{"transactions_accounts.account_id", buf.GetTransactionsParticipants()},
		{"operations_accounts.account_id", buf.GetOperationsParticipants()},
	} {
		for _, id := range sortedKeys(part.m) {
			if !keep(id) {
				continue
			}
			for _, a := range sortedStrings(part.m[id]) {
				c := roundTrip(reflect.ValueOf(types.AddressBytea(a)))
				c.Where = part.where
				record(c, id)
			}
		}
	}

	changes := buf.GetStateChanges()
	for _, sc := range changes {
		if !keep(sc.ToID) {
			continue
		}
		r.StateChanges++
		v := reflect.ValueOf(sc)
		t := v.Type()
		for i := 0; i < t.NumField(); i++ {
			if !isAddressColumn(t.Field(i).Type) {
				continue
			}
			c := roundTrip(v.Field(i))
			if c.Verdict == "" {
				continue
			}
			col := t.Field(i).Tag.Get("db")
			c.Where = "state_changes." + col
			c.Category = string(sc.StateChangeCategory) + "/" + string(sc.StateChangeReason)
			id := sc.OperationID
			if id == 0 {
				id = sc.ToID
			}
			record(c, id)
		}
	}

	for _, tx := range txs {
		h := hex.EncodeToString(tx.Hash[:])
		if !want[seq<<32|int64(tx.Index)<<12] || !tx.Successful() {
			continue
		}
		r.Facts = append(r.Facts, factsFor(pass, tx, h, seq, changes)...)
	}
	return r
}

// ledgerTransactions reads the ledger with the SDK's own reader, not through
// wallet-backend, so the facts below do not depend on the code under test.
func ledgerTransactions(pass string, lcm xdr.LedgerCloseMeta) ([]ingest.LedgerTransaction, error) {
	rd, err := ingest.NewLedgerTransactionReaderFromLedgerCloseMeta(pass, lcm)
	if err != nil {
		return nil, err
	}
	defer rd.Close()
	var txs []ingest.LedgerTransaction
	for {
		tx, err := rd.Read()
		if errors.Is(err, io.EOF) {
			return txs, nil
		}
		if err != nil {
			return nil, err
		}
		txs = append(txs, tx)
	}
}

func newIndexer(pass string) (*indexer.Indexer, error) {
	fn := reflect.ValueOf(indexer.NewIndexer)
	ft := fn.Type()
	args := []reflect.Value{reflect.ValueOf(pass), reflect.ValueOf(pond.NewPool(4))}
	for i := 2; i < ft.NumIn(); i++ {
		if ft.In(i).Kind() == reflect.Bool {
			args = append(args, reflect.ValueOf(true)) // collect everything live ingestion collects
		} else {
			args = append(args, reflect.Zero(ft.In(i))) // metrics: nil, as the indexer's own tests pass
		}
	}
	out := fn.Call(args)
	if e := out[len(out)-1]; !e.IsNil() {
		return nil, e.Interface().(error)
	}
	return out[0].Interface().(*indexer.Indexer), nil
}

func processLedger(ctx context.Context, pass string, lcm xdr.LedgerCloseMeta, idx *indexer.Indexer, buf *indexer.IndexerBuffer) error {
	out := reflect.ValueOf(indexer.ProcessLedger).Call([]reflect.Value{
		reflect.ValueOf(ctx), reflect.ValueOf(pass), reflect.ValueOf(lcm), reflect.ValueOf(idx), reflect.ValueOf(buf),
	})
	if e := out[len(out)-1]; !e.IsNil() {
		return e.Interface().(error)
	}
	return nil
}

// ---- address round trip ----

var (
	valuerT  = reflect.TypeOf((*driver.Valuer)(nil)).Elem()
	scannerT = reflect.TypeOf((*sql.Scanner)(nil)).Elem()
)

// isAddressColumn picks the wallet-backend column types that hold a strkey as
// BYTEA (AddressBytea, NullAddressBytea and, after #729, SignerKeyBytea).
func isAddressColumn(t reflect.Type) bool {
	n := t.Name()
	if !strings.HasSuffix(n, "Bytea") || !(strings.Contains(n, "Address") || strings.Contains(n, "Signer")) {
		return false
	}
	return t.Implements(valuerT) && reflect.PointerTo(t).Implements(scannerT)
}

// strOf returns the strkey held by an address column value, and false for a
// NULL one.
func strOf(v reflect.Value) (string, bool) {
	if v.Kind() == reflect.String {
		return v.String(), v.String() != ""
	}
	if v.Kind() == reflect.Struct {
		if valid := v.FieldByName("Valid"); valid.IsValid() && valid.Kind() == reflect.Bool && !valid.Bool() {
			return "", false
		}
		for i := 0; i < v.NumField(); i++ {
			if v.Field(i).Kind() == reflect.String {
				return v.Field(i).String(), v.Field(i).String() != ""
			}
		}
	}
	return "", false
}

// roundTrip runs the column type's Value (what the COPY path stores) and Scan
// (what a read returns) and classifies the result:
//
//	exact         read back unchanged
//	reduced       an M... read back as its own G... base account (wallet-backend's documented choice since #693)
//	truncated     read back as a different strkey (information lost silently)
//	undecodable   read back as a string that is not a valid strkey (information lost silently)
//	scan_error    stored bytes cannot be read back at all
//	encode_error  Value() refuses it: the persist transaction fails and ingestion retries this ledger
func roundTrip(v reflect.Value) addrCheck {
	c := addrCheck{Type: v.Type().Name()}
	in, ok := strOf(v)
	if !ok {
		return addrCheck{}
	}
	c.In = in
	dv, err := v.Interface().(driver.Valuer).Value()
	if err != nil {
		c.Verdict, c.Error = "encode_error", err.Error()
		return c
	}
	if b, ok := dv.([]byte); ok {
		c.Stored = len(b)
	}
	back := reflect.New(v.Type())
	if err := back.Interface().(sql.Scanner).Scan(dv); err != nil {
		c.Verdict, c.Error = "scan_error", err.Error()
		return c
	}
	c.Out, _ = strOf(back.Elem())
	switch {
	case c.Out == in:
		c.Verdict = "exact"
	case strings.HasPrefix(in, "M") && c.Out == baseOfMuxed(in):
		c.Verdict = "reduced"
	default:
		if _, _, err := strkey.DecodeAny(c.Out); err != nil {
			c.Verdict, c.Error = "undecodable", err.Error()
		} else {
			c.Verdict = "truncated"
		}
	}
	return c
}

func baseOfMuxed(m string) string {
	var mx xdr.MuxedAccount
	if err := mx.SetAddress(m); err != nil {
		return ""
	}
	a := mx.ToAccountId()
	return a.Address()
}

// ---- facts from the ledger XDR ----

func factsFor(pass string, tx ingest.LedgerTransaction, h string, seq int64, changes []types.StateChange) []fact {
	var facts []fact
	ops := tx.Envelope.Operations()
	for i := range ops {
		opID := seq<<32 | int64(tx.Index)<<12 | int64(i+1)
		opType := ops[i].Body.Type.String()
		lec, err := tx.GetOperationChanges(uint32(i))
		if err != nil {
			continue
		}
		for _, ch := range lec {
			switch {
			case ch.Type == xdr.LedgerEntryTypeTrustline && ch.Pre == nil && ch.Post != nil:
				tl := ch.Post.Data.MustTrustLine()
				if tl.Asset.Type == xdr.AssetTypeAssetTypePoolShare {
					continue
				}
				acct := tl.AccountId.Address()
				asset := tl.Asset.ToAsset()
				token := ""
				if cid, err := asset.ContractID(pass); err == nil {
					token, _ = strkey.Encode(strkey.VersionByteContract, cid[:])
				}
				f := fact{Kind: "trustline_created", TxHash: h, OpIndex: i + 1, OpType: opType, Account: acct,
					Detail: asset.StringCanonical() + " token " + token}
				for _, sc := range changes {
					if sc.OperationID == opID && string(sc.StateChangeCategory) == "TRUSTLINE" &&
						string(sc.StateChangeReason) == "ADD" && string(sc.AccountID) == acct {
						f.Found = true
						f.Recorded = "TRUSTLINE/ADD"
					}
				}
				facts = append(facts, f)
			case ch.Type == xdr.LedgerEntryTypeAccount && ch.Post != nil:
				post := ch.Post.Data.MustAccount()
				if ch.Pre == nil {
					acct := post.AccountId.Address()
					f := fact{Kind: "account_created", TxHash: h, OpIndex: i + 1, OpType: opType, Account: acct,
						Detail: fmt.Sprintf("starting balance %d stroops", post.Balance)}
					for _, sc := range changes {
						if sc.OperationID == opID && string(sc.StateChangeCategory) == "ACCOUNT" &&
							string(sc.StateChangeReason) == "CREATE" && string(sc.AccountID) == acct {
							f.Found = true
							f.Recorded = "ACCOUNT/CREATE"
						}
					}
					facts = append(facts, f)
				}
				before := map[string]bool{}
				if ch.Pre != nil {
					for _, s := range ch.Pre.Data.MustAccount().Signers {
						k, _ := s.Key.GetAddress()
						before[k] = true
					}
				}
				for _, s := range post.Signers {
					k, err := s.Key.GetAddress()
					if err != nil || before[k] {
						continue
					}
					acct := post.AccountId.Address()
					f := fact{Kind: "signer_added", TxHash: h, OpIndex: i + 1, OpType: opType, Account: acct,
						Detail: fmt.Sprintf("%s weight %d", k, s.Weight)}
					for _, sc := range changes {
						if sc.OperationID != opID || string(sc.StateChangeCategory) != "SIGNER" {
							continue
						}
						v := reflect.ValueOf(sc).FieldByName("SignerAccountID")
						if got, ok := strOf(v); ok && got == k {
							f.Found = true
							f.Recorded = "SIGNER/" + string(sc.StateChangeReason)
						}
					}
					facts = append(facts, f)
				}
			}
		}
	}
	return facts
}

// ---- verdict ----

func finish(r *report, commit string) {
	r.Adapter = "xdrc-replay wallet-backend 0.1"
	r.Commit = commit
	if r.VerdictCounts == nil {
		r.VerdictCounts = map[string]int{}
	}
	if r.Anomalies == nil {
		r.Anomalies = []addrCheck{}
	}
	if r.Facts == nil {
		r.Facts = []fact{}
	}
	if r.Result != "" {
		return
	}
	halts, lost, missing := 0, 0, 0
	for _, a := range r.Anomalies {
		switch a.Verdict {
		case "encode_error":
			halts++
		case "truncated", "undecodable", "scan_error":
			lost++
		}
	}
	for _, f := range r.Facts {
		if !f.Found {
			missing++
		}
	}
	switch {
	case halts > 0:
		r.Result = "halts"
		r.Why = append(r.Why, fmt.Sprintf("%d address(es) refused by the column encoder; the persist transaction fails and ingestion retries this ledger", halts))
	case lost > 0 || missing > 0:
		r.Result = "mishandled"
	default:
		r.Result = "pass"
	}
	if lost > 0 {
		r.Why = append(r.Why, fmt.Sprintf("%d address(es) stored lossily (read back different or undecodable)", lost))
	}
	if missing > 0 {
		r.Why = append(r.Why, fmt.Sprintf("%d ledger fact(s) with no state change", missing))
	}
}

func sortedKeys(m map[int64]map[string]struct{}) []int64 {
	ks := make([]int64, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	sort.Slice(ks, func(i, j int) bool { return ks[i] < ks[j] })
	return ks
}

func sortedStrings(m map[string]struct{}) []string {
	ss := make([]string, 0, len(m))
	for s := range m {
		ss = append(ss, s)
	}
	sort.Strings(ss)
	return ss
}
