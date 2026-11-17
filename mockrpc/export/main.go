// export lays the lake out the way Galexie writes the public data lake (same object keys, same
// .config.json), so go-stellar-sdk's BufferedStorageBackend and anything else that reads a
// Galexie datastore (filesystem, or S3 after a sync) works on it unchanged.
package main

import (
	"flag"
	"log"
	"os"
	"path/filepath"

	"github.com/stellar/go-stellar-sdk/support/datastore"

	"xdrconf-mockrpc/internal/lake"
)

const manifest = `{"networkPassphrase":"Public Global Stellar Network ; September 2015","version":"1.0","compression":"zstd","ledgersPerBatch":1,"batchesPerPartition":64000}`

func main() {
	src := flag.String("lake", "", "directory of <seq>.xdr.zst files")
	dst := flag.String("out", "", "datastore root to write")
	flag.Parse()
	ledgers, ranges, err := lake.Load(*src)
	if err != nil {
		log.Fatal(err)
	}
	schema := datastore.DataStoreSchema{LedgersPerFile: 1, FilesPerPartition: 64000, FileExtension: "zst"}
	for _, l := range ledgers {
		p := filepath.Join(*dst, schema.GetObjectKeyFromSequenceNumber(l.Seq))
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			log.Fatal(err)
		}
		if err := os.WriteFile(p, l.Raw, 0o644); err != nil {
			log.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(*dst, ".config.json"), []byte(manifest), 0o644); err != nil {
		log.Fatal(err)
	}
	log.Printf("wrote %d ledgers in %d ranges to %s", len(ledgers), len(ranges), *dst)
}
