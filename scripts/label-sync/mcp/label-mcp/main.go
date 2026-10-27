// scripts/label-sync/mcp/label-mcp/main.go
//
// Purpose : Entry point of the label-sync MCP server (see server.go).
// Usage   : label-mcp          (stdio JSON-RPC 2.0; one document per line)
// Inputs  : env LABEL_SYNC_DIR / LABEL_SYNC_TTL / LABEL_SYNC_DONE_RETENTION.
// Outputs : JSON-RPC responses on stdout only.
// Exit    : 0 clean stdin EOF; 2 stdout write failure.
// Side-effects: see server.go. Deps: Go stdlib only.
// Cross-refs: §11.4.182, §11.4.18. Classification: universal (§11.4.17).
package main

import (
	"fmt"
	"os"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/state"
)

func main() {
	s := newServer(state.OptionsFromEnv())
	if err := s.Serve(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "label-mcp: %v\n", err)
		os.Exit(2)
	}
}
