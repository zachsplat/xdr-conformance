// Package lake loads Galexie LedgerCloseMetaBatch files (one ledger per file, zstd) from a flat
// directory of <seq>.xdr.zst files, as tools/fetch_galexie.py writes them.
package lake

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/klauspost/compress/zstd"
	"github.com/stellar/go-stellar-sdk/xdr"
)

type Ledger struct {
	Seq       uint32
	Hash      string
	CloseTime int64
	Protocol  uint32
	Header    []byte // LedgerHeaderHistoryEntry XDR
	Raw       []byte // the compressed file, byte for byte
}

var dec, _ = zstd.NewReader(nil, zstd.WithDecoderConcurrency(0))

// Meta returns the LedgerCloseMeta XDR exactly as stored in the batch. Only the compressed file
// is kept in memory; Load has already checked that these bytes decode and re-encode unchanged.
func (l *Ledger) Meta() ([]byte, error) {
	plain, err := dec.DecodeAll(l.Raw, nil)
	if err != nil {
		return nil, err
	}
	return plain[12:], nil
}

// Range is a run of consecutive ledgers.
type Range struct{ First, Last uint32 }

func Load(dir string) (map[uint32]*Ledger, []Range, error) {
	names, err := filepath.Glob(filepath.Join(dir, "*.xdr.zst"))
	if err != nil {
		return nil, nil, err
	}
	out := map[uint32]*Ledger{}
	var seqs []uint32
	for _, n := range names {
		s, err := strconv.ParseUint(strings.TrimSuffix(filepath.Base(n), ".xdr.zst"), 10, 32)
		if err != nil {
			continue
		}
		raw, err := os.ReadFile(n)
		if err != nil {
			return nil, nil, err
		}
		plain, err := dec.DecodeAll(raw, nil)
		if err != nil {
			return nil, nil, fmt.Errorf("%s: %w", n, err)
		}
		var batch xdr.LedgerCloseMetaBatch
		if err := batch.UnmarshalBinary(plain); err != nil {
			return nil, nil, fmt.Errorf("%s: %w", n, err)
		}
		if len(batch.LedgerCloseMetas) != 1 {
			return nil, nil, fmt.Errorf("%s: %d ledgers in batch, want 1", n, len(batch.LedgerCloseMetas))
		}
		lcm := batch.LedgerCloseMetas[0]
		meta, err := lcm.MarshalBinary()
		if err != nil {
			return nil, nil, err
		}
		// the batch is startSequence, endSequence, a 1-element array count, then the meta: serve
		// exactly the bytes Galexie stored, and stop if re-encoding would change anything
		if !bytes.Equal(meta, plain[12:]) {
			return nil, nil, fmt.Errorf("%s: re-encoded meta differs from the stored bytes", n)
		}
		hdr, err := lcm.LedgerHeaderHistoryEntry().MarshalBinary()
		if err != nil {
			return nil, nil, err
		}
		if uint32(s) != lcm.LedgerSequence() {
			return nil, nil, fmt.Errorf("%s holds ledger %d", n, lcm.LedgerSequence())
		}
		out[uint32(s)] = &Ledger{Seq: uint32(s), Hash: lcm.LedgerHash().HexString(), CloseTime: lcm.LedgerCloseTime(),
			Protocol: lcm.ProtocolVersion(), Header: hdr, Raw: raw}
		seqs = append(seqs, uint32(s))
	}
	sort.Slice(seqs, func(i, j int) bool { return seqs[i] < seqs[j] })
	var rs []Range
	for _, s := range seqs {
		if len(rs) > 0 && rs[len(rs)-1].Last+1 == s {
			rs[len(rs)-1].Last = s
		} else {
			rs = append(rs, Range{s, s})
		}
	}
	return out, rs, nil
}
