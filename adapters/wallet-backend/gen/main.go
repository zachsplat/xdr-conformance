// Command xdrc-gen produces the corpus entries that pubnet history does not
// conveniently hold, by running real transactions on a local, offline
// stellar-core (stellar/quickstart --local, docker --network none) and
// capturing the LedgerCloseMeta core wrote for them.
//
// It is copied into a wallet-backend checkout as cmd/xdrc-gen only to reuse
// that module's go-stellar-sdk; it does not import wallet-backend.
//
// Cases:
//
//	sac-trust-creates-trustline   CAP-73: an account calls trust(self) on a
//	                              Stellar Asset Contract; core creates the
//	                              trustline and emits no contract event
//	soroban-muxed-source          a Soroban operation (ExtendFootprintTTL)
//	                              whose transaction source is an M... address
//	invoke-muxed-source           the same for InvokeHostFunction (core is
//	                              expected to refuse it; recorded either way)
//	sac-native-transfer-creates-account
//	                              CAP-73: a native-asset contract transfer to a
//	                              G... address that does not exist creates the
//	                              account, with no CreateAccount operation
//
// -cases picks which to run (default all). Each run starts from a fresh local
// network, so ledger numbers and hashes differ between runs.
//
// Keys are derived from fixed strings so every run builds the same accounts.
// They exist only on the local network.
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/stellar/go-stellar-sdk/keypair"
	"github.com/stellar/go-stellar-sdk/network"
	"github.com/stellar/go-stellar-sdk/strkey"
	"github.com/stellar/go-stellar-sdk/support/compressxdr"
	"github.com/stellar/go-stellar-sdk/xdr"
)

const pass = "Standalone Network ; February 2017"

var base = flag.String("base", "http://localhost:8000", "quickstart base URL")
var outDir = flag.String("out", "/out", "output directory")
var cases = flag.String("cases", "trust,muxed,native-transfer", "comma-separated cases to run")

func want(c string) bool {
	for _, x := range strings.Split(*cases, ",") {
		if x == c {
			return true
		}
	}
	return false
}

func main() {
	flag.Parse()
	issuer := key("xdr-conformance local issuer")
	holder := key("xdr-conformance local holder")
	for _, kp := range []*keypair.Full{issuer, holder} {
		fund(kp.Address())
	}
	asset := xdr.MustNewCreditAsset("XDRC", issuer.Address())
	cid, err := asset.ContractID(pass)
	check(err)
	contract := xdr.ContractId(cid)
	csk, _ := strkey.Encode(strkey.VersionByteContract, cid[:])
	fmt.Fprintln(os.Stderr, "asset contract", csk)

	// 1. Deploy the asset contract (issuer pays).
	deploy := xdr.HostFunction{
		Type: xdr.HostFunctionTypeHostFunctionTypeCreateContract,
		CreateContract: &xdr.CreateContractArgs{
			ContractIdPreimage: xdr.ContractIdPreimage{Type: xdr.ContractIdPreimageTypeContractIdPreimageFromAsset, FromAsset: &asset},
			Executable:         xdr.ContractExecutable{Type: xdr.ContractExecutableTypeContractExecutableStellarAsset},
		},
	}
	if want("native-transfer") {
		nativeTransfer(holder)
	}
	if !want("trust") && !want("muxed") {
		return
	}
	res := soroban(issuer, issuer.Address(), invokeOp(deploy))
	report("deploy-asset-contract", res)

	// 2. CAP-73: the holder calls trust(holder) on the asset contract.
	holderAddr := scAccount(holder.Address())
	trust := xdr.HostFunction{
		Type: xdr.HostFunctionTypeHostFunctionTypeInvokeContract,
		InvokeContract: &xdr.InvokeContractArgs{
			ContractAddress: xdr.ScAddress{Type: xdr.ScAddressTypeScAddressTypeContract, ContractId: &contract},
			FunctionName:    "trust",
			Args:            []xdr.ScVal{{Type: xdr.ScValTypeScvAddress, Address: &holderAddr}},
		},
	}
	if want("trust") {
		res = soroban(holder, holder.Address(), invokeOp(trust))
		save("sac-trust-creates-trustline", res)
	}
	if !want("muxed") {
		return
	}

	// 3. A Soroban operation with an M... transaction source: extend the TTL
	// of the asset contract instance.
	muxed := muxedOf(holder.Address(), 1234567890)
	extend := xdr.Operation{Body: xdr.OperationBody{
		Type:                 xdr.OperationTypeExtendFootprintTtl,
		ExtendFootprintTtlOp: &xdr.ExtendFootprintTtlOp{ExtendTo: 500_000},
	}}
	instance := xdr.LedgerKey{Type: xdr.LedgerEntryTypeContractData, ContractData: &xdr.LedgerKeyContractData{
		Contract:   xdr.ScAddress{Type: xdr.ScAddressTypeScAddressTypeContract, ContractId: &contract},
		Key:        xdr.ScVal{Type: xdr.ScValTypeScvLedgerKeyContractInstance},
		Durability: xdr.ContractDataDurabilityPersistent,
	}}
	res = soroban(holder, muxed, extend, instance)
	save("soroban-muxed-source", res)

	// 4. InvokeHostFunction with an M... transaction source (core is
	// expected to refuse it).
	res = soroban(holder, muxed, invokeOp(trust))
	save("invoke-muxed-source", res)
}

// nativeTransfer deploys the native asset contract if it is missing, then has
// the holder transfer 20 XLM through it to an account that does not exist.
func nativeTransfer(holder *keypair.Full) {
	native := xdr.MustNewNativeAsset()
	cid, err := native.ContractID(pass)
	check(err)
	contract := xdr.ContractId(cid)
	deploy := xdr.HostFunction{
		Type: xdr.HostFunctionTypeHostFunctionTypeCreateContract,
		CreateContract: &xdr.CreateContractArgs{
			ContractIdPreimage: xdr.ContractIdPreimage{Type: xdr.ContractIdPreimageTypeContractIdPreimageFromAsset, FromAsset: &native},
			Executable:         xdr.ContractExecutable{Type: xdr.ContractExecutableTypeContractExecutableStellarAsset},
		},
	}
	res := soroban(holder, holder.Address(), invokeOp(deploy))
	fmt.Fprintf(os.Stderr, "deploy-native-contract %s %s (an existing contract is fine)\n", res.Status, res.Error)

	fresh := key("xdr-conformance local new account")
	from, to := scAccount(holder.Address()), scAccount(fresh.Address())
	amount := xdr.Int128Parts{Hi: 0, Lo: 20_0000000}
	transfer := xdr.HostFunction{
		Type: xdr.HostFunctionTypeHostFunctionTypeInvokeContract,
		InvokeContract: &xdr.InvokeContractArgs{
			ContractAddress: xdr.ScAddress{Type: xdr.ScAddressTypeScAddressTypeContract, ContractId: &contract},
			FunctionName:    "transfer",
			Args: []xdr.ScVal{
				{Type: xdr.ScValTypeScvAddress, Address: &from},
				{Type: xdr.ScValTypeScvAddress, Address: &to},
				{Type: xdr.ScValTypeScvI128, I128: &amount},
			},
		},
	}
	res = soroban(holder, holder.Address(), invokeOp(transfer))
	save("sac-native-transfer-creates-account", res)
}

func key(s string) *keypair.Full {
	seed := sha256.Sum256([]byte(s))
	kp, err := keypair.FromRawSeed(seed)
	check(err)
	return kp
}

func muxedOf(g string, id uint64) string {
	mx, err := xdr.MuxedAccountFromAccountId(g, id)
	check(err)
	return mx.Address()
}

func scAccount(g string) xdr.ScAddress {
	a := xdr.MustAddress(g)
	return xdr.ScAddress{Type: xdr.ScAddressTypeScAddressTypeAccount, AccountId: &a}
}

func invokeOp(hf xdr.HostFunction) xdr.Operation {
	return xdr.Operation{Body: xdr.OperationBody{
		Type:                 xdr.OperationTypeInvokeHostFunction,
		InvokeHostFunctionOp: &xdr.InvokeHostFunctionOp{HostFunction: hf},
	}}
}

// ---- transactions ----

type result struct {
	Hash     string `json:"tx_hash"`
	Status   string `json:"status"`
	Ledger   uint32 `json:"ledger,omitempty"`
	Error    string `json:"error,omitempty"`
	Source   string `json:"tx_source"`
	envelope xdr.TransactionEnvelope
	closedAt string
	protocol uint32
	lcm      *xdr.LedgerCloseMeta
}

// soroban simulates a one-operation Soroban transaction with the signer's
// G... address as source (as a wallet would), then assembles it with the
// requested source (G... or M...), signs, submits and waits for it to close.
// readOnly pre-fills the footprint for operations simulation cannot infer it
// for (ExtendFootprintTTL).
func soroban(signer *keypair.Full, source string, op xdr.Operation, readOnly ...xdr.LedgerKey) result {
	src, err := xdr.AddressToMuxedAccount(source)
	check(err)
	g := xdr.MustMuxedAddress(signer.Address())
	seq := sequence(signer.Address()) + 1
	var pre *xdr.SorobanTransactionData
	if len(readOnly) > 0 {
		pre = &xdr.SorobanTransactionData{Resources: xdr.SorobanResources{Footprint: xdr.LedgerFootprint{ReadOnly: readOnly}}}
	}
	env := build(g, seq, 100, op, pre)

	var sim struct {
		TransactionData string `json:"transactionData"`
		MinResourceFee  string `json:"minResourceFee"`
		Error           string `json:"error"`
		Results         []struct {
			Auth []string `json:"auth"`
		} `json:"results"`
	}
	rpc("simulateTransaction", map[string]any{"transaction": b64(env)}, &sim)
	r := result{Source: source}
	if sim.Error != "" {
		r.Status, r.Error = "SIMULATION_FAILED", sim.Error
		return r
	}
	var data xdr.SorobanTransactionData
	check(xdr.SafeUnmarshalBase64(sim.TransactionData, &data))
	if op.Body.Type == xdr.OperationTypeInvokeHostFunction && len(sim.Results) > 0 {
		var auth []xdr.SorobanAuthorizationEntry
		for _, a := range sim.Results[0].Auth {
			var e xdr.SorobanAuthorizationEntry
			check(xdr.SafeUnmarshalBase64(a, &e))
			auth = append(auth, e)
		}
		op.Body.InvokeHostFunctionOp.Auth = auth
	}
	minFee, _ := strconv.ParseInt(sim.MinResourceFee, 10, 64)
	data.ResourceFee = xdr.Int64(minFee*2 + 10_000)
	env = build(src, seq, uint32(minFee*2+10_100), op, &data)
	return submit(signer, env, r)
}

func build(src xdr.MuxedAccount, seq int64, fee uint32, op xdr.Operation, data *xdr.SorobanTransactionData) xdr.TransactionEnvelope {
	tx := xdr.Transaction{
		SourceAccount: src,
		Fee:           xdr.Uint32(fee),
		SeqNum:        xdr.SequenceNumber(seq),
		Cond:          xdr.Preconditions{Type: xdr.PreconditionTypePrecondNone},
		Operations:    []xdr.Operation{op},
	}
	if data != nil {
		tx.Ext = xdr.TransactionExt{V: 1, SorobanData: data}
	}
	return xdr.TransactionEnvelope{Type: xdr.EnvelopeTypeEnvelopeTypeTx, V1: &xdr.TransactionV1Envelope{Tx: tx}}
}

func submit(signer *keypair.Full, env xdr.TransactionEnvelope, r result) result {
	h, err := network.HashTransactionInEnvelope(env, pass)
	check(err)
	sig, err := signer.SignDecorated(h[:])
	check(err)
	env.V1.Signatures = []xdr.DecoratedSignature{sig}
	r.Hash = hex.EncodeToString(h[:])
	r.envelope = env

	var sent struct {
		Status         string `json:"status"`
		ErrorResultXdr string `json:"errorResultXdr"`
	}
	rpc("sendTransaction", map[string]any{"transaction": b64(env)}, &sent)
	if sent.Status != "PENDING" && sent.Status != "DUPLICATE" {
		r.Status = "REJECTED_" + sent.Status
		var tr xdr.TransactionResult
		if sent.ErrorResultXdr != "" && xdr.SafeUnmarshalBase64(sent.ErrorResultXdr, &tr) == nil {
			r.Error = tr.Result.Code.String()
		}
		return r
	}
	for i := 0; i < 60; i++ {
		time.Sleep(time.Second)
		var got struct {
			Status string `json:"status"`
			Ledger uint32 `json:"ledger"`
		}
		rpc("getTransaction", map[string]any{"hash": r.Hash}, &got)
		if got.Status == "NOT_FOUND" {
			continue
		}
		r.Status, r.Ledger = got.Status, got.Ledger
		r.lcm, r.closedAt, r.protocol = ledgerMeta(got.Ledger)
		return r
	}
	r.Status = "TIMEOUT"
	return r
}

func ledgerMeta(seq uint32) (*xdr.LedgerCloseMeta, string, uint32) {
	var lg struct {
		Ledgers []struct {
			MetadataXdr     string `json:"metadataXdr"`
			LedgerCloseTime string `json:"ledgerCloseTime"`
		} `json:"ledgers"`
	}
	rpc("getLedgers", map[string]any{"startLedger": seq, "pagination": map[string]any{"limit": 1}}, &lg)
	if len(lg.Ledgers) == 0 {
		check(fmt.Errorf("ledger %d not served", seq))
	}
	var lcm xdr.LedgerCloseMeta
	check(xdr.SafeUnmarshalBase64(lg.Ledgers[0].MetadataXdr, &lcm))
	ct, _ := strconv.ParseInt(lg.Ledgers[0].LedgerCloseTime, 10, 64)
	return &lcm, time.Unix(ct, 0).UTC().Format(time.RFC3339), uint32(lcm.ProtocolVersion())
}

// ---- outputs ----

func report(name string, r result) {
	b, _ := json.Marshal(r)
	fmt.Fprintf(os.Stderr, "%s %s\n", name, b)
	if r.Status != "SUCCESS" {
		check(fmt.Errorf("%s did not succeed: %s %s", name, r.Status, r.Error))
	}
}

// save writes the corpus entry files (envelope.xdr, meta.xdr), the whole
// ledger as a Galexie-style zstd LedgerCloseMetaBatch, and a JSON record.
func save(name string, r result) {
	dir := filepath.Join(*outDir, name)
	check(os.MkdirAll(dir, 0o755))
	rec := map[string]any{"case": name, "tx_hash": r.Hash, "status": r.Status, "error": r.Error,
		"tx_source": r.Source, "ledger": r.Ledger, "closed_at": r.closedAt, "protocol_version": r.protocol,
		"network_passphrase": pass}
	envB, err := r.envelope.MarshalBinary()
	check(err)
	check(os.WriteFile(filepath.Join(dir, "envelope.xdr"), envB, 0o644))
	if r.lcm != nil {
		meta := findMeta(r.lcm, r.Hash)
		if meta != nil {
			mb, err := meta.MarshalBinary()
			check(err)
			check(os.WriteFile(filepath.Join(dir, "meta.xdr"), mb, 0o644))
		}
		batch := xdr.LedgerCloseMetaBatch{StartSequence: xdr.Uint32(r.Ledger), EndSequence: xdr.Uint32(r.Ledger),
			LedgerCloseMetas: []xdr.LedgerCloseMeta{*r.lcm}}
		var buf bytes.Buffer
		_, err = compressxdr.NewXDREncoder(compressxdr.DefaultCompressor, &batch).WriteTo(&buf)
		check(err)
		check(os.WriteFile(filepath.Join(dir, fmt.Sprintf("ledger-%d.xdr.zst", r.Ledger)), buf.Bytes(), 0o644))
	}
	b, _ := json.MarshalIndent(rec, "", " ")
	check(os.WriteFile(filepath.Join(dir, "generated.json"), append(b, '\n'), 0o644))
	fmt.Fprintf(os.Stderr, "%s %s\n", name, b)
}

func findMeta(lcm *xdr.LedgerCloseMeta, hash string) *xdr.TransactionResultMetaV1 {
	if lcm.V != 2 {
		return nil
	}
	for i := range lcm.V2.TxProcessing {
		p := lcm.V2.TxProcessing[i]
		if hex.EncodeToString(p.Result.TransactionHash[:]) == hash {
			return &p
		}
	}
	return nil
}

// ---- network helpers ----

func fund(addr string) {
	resp, err := http.Get(*base + "/friendbot?addr=" + addr)
	check(err)
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
}

func sequence(addr string) int64 {
	resp, err := http.Get(*base + "/accounts/" + addr)
	check(err)
	defer resp.Body.Close()
	var a struct {
		Sequence string `json:"sequence"`
	}
	check(json.NewDecoder(resp.Body).Decode(&a))
	n, err := strconv.ParseInt(a.Sequence, 10, 64)
	check(err)
	return n
}

func rpc(method string, params any, out any) {
	body, _ := json.Marshal(map[string]any{"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
	resp, err := http.Post(*base+"/rpc", "application/json", bytes.NewReader(body))
	check(err)
	defer resp.Body.Close()
	var env struct {
		Result json.RawMessage `json:"result"`
		Error  *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	check(json.NewDecoder(resp.Body).Decode(&env))
	if env.Error != nil {
		// Surface simulation errors to the caller through the result shape.
		env.Result, _ = json.Marshal(map[string]string{"error": env.Error.Message})
	}
	check(json.Unmarshal(env.Result, out))
}

func b64(env xdr.TransactionEnvelope) string {
	s, err := xdr.MarshalBase64(env)
	check(err)
	return s
}

func check(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "xdrc-gen:", err)
		os.Exit(1)
	}
}
