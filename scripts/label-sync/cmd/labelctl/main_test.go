package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
)

func ctl(t *testing.T, dir string, args ...string) (int, string, string) {
	t.Helper()
	var o, e bytes.Buffer
	rc := run(append([]string{"--dir", dir}, args...), &o, &e)
	return rc, strings.TrimSpace(o.String()), strings.TrimSpace(e.String())
}

func TestRegisterSwitchListVerify(t *testing.T) {
	d := t.TempDir()
	if rc, _, e := ctl(t, d, "switch-alias", "--alias", "claude1", "--model", "opus", "--effort", "high"); rc != 0 {
		t.Fatalf("switch rc=%d %s", rc, e)
	}
	rc, lab, e := ctl(t, d, "register", "--id", "sh1", "--kind", "shell", "--track", "2", "--branch", "feature/x", "--pid", "1")
	if rc != 0 || lab != "(T2/feature/x - claude1 - opus - high)" {
		t.Fatalf("register rc=%d out=%q err=%q", rc, lab, e)
	}
	if rc, _, _ := ctl(t, d, "switch-alias", "--alias", "claude2", "--model", "sonnet", "--effort", "xhigh"); rc != 0 {
		t.Fatal("switch")
	}
	if rc, out, _ := ctl(t, d, "label", "sh1"); rc != 0 || out != "(T2/feature/x - claude2 - sonnet - xhigh)" {
		t.Fatalf("label after switch: rc=%d %q", rc, out)
	}
	rc, out, _ := ctl(t, d, "list", "--json")
	var snap model.Snapshot
	if rc != 0 || json.Unmarshal([]byte(out), &snap) != nil || len(snap.Entities) != 1 || snap.Active.Alias != "claude2" {
		t.Fatalf("list --json rc=%d %s", rc, out)
	}
	if rc, out, _ := ctl(t, d, "list", "--text"); rc != 0 || !strings.Contains(out, "(T2/feature/x - claude2 - sonnet - xhigh)") {
		t.Fatalf("list text: %q", out)
	}
	if rc, out, e := ctl(t, d, "verify"); rc != 0 || !strings.Contains(out, "OK") {
		t.Fatalf("verify rc=%d %s %s", rc, out, e)
	}
}

func TestExitCodes(t *testing.T) {
	d := t.TempDir()
	cases := []struct {
		name string
		args []string
		want int
	}{
		{"no command", nil, 2},
		{"unknown command", []string{"frobnicate"}, 2},
		{"register without id", []string{"register", "--kind", "shell"}, 2},
		{"register bad kind", []string{"register", "--id", "x", "--kind", "nope"}, 1},
		{"get unknown", []string{"get", "--id", "ghost"}, 1},
		{"label unknown", []string{"label", "ghost"}, 1},
		{"heartbeat unknown", []string{"heartbeat", "--id", "ghost"}, 1},
		{"update nothing", []string{"update", "--id", "x"}, 2},
		{"switch no alias", []string{"switch-alias"}, 1},
		{"bad watch since", []string{"watch", "--since", "abc"}, 2},
		{"bad flag", []string{"register", "--bogus"}, 2},
		{"verify empty ok", []string{"verify"}, 0},
	}
	for _, c := range cases {
		var o, e bytes.Buffer
		if got := run(append([]string{"--dir", d}, c.args...), &o, &e); got != c.want {
			t.Errorf("%s: rc=%d want %d (%s)", c.name, got, c.want, e.String())
		}
	}
}

func TestUpdateOnlyChangesGivenFields(t *testing.T) {
	d := t.TempDir()
	ctl(t, d, "register", "--id", "a", "--kind", "agent", "--track", "1", "--branch", "b", "--alias", "claude7", "--model", "haiku", "--effort", "low", "--follow-active", "false")
	if rc, _, e := ctl(t, d, "update", "--id", "a", "--model", "opus"); rc != 0 {
		t.Fatalf("update rc=%d %s", rc, e)
	}
	_, out, _ := ctl(t, d, "label", "a")
	if out != "(T1/b - claude7 - opus - low)" {
		t.Fatalf("got %q", out)
	}
	ctl(t, d, "unregister", "--id", "a")
	_, out, _ = ctl(t, d, "get", "--id", "a", "--json")
	if !strings.Contains(out, `"state":"done"`) {
		t.Fatalf("got %s", out)
	}
}

func TestDeriveDelegatesToLabeler(t *testing.T) {
	d := t.TempDir()
	script := filepath.Join(t.TempDir(), "lab.sh")
	os.WriteFile(script, []byte("#!/usr/bin/env bash\necho \"(T4/derived-branch - ${CLAUDE_CONFIG_DIR##*.claude-} - opus - max)\"\n"), 0o755)
	t.Setenv("LABEL_SYNC_LABELER", script)
	rc, lab, e := ctl(t, d, "register", "--id", "s", "--kind", "session", "--derive", "--config-dir", "/h/.claude-claude8", "--pid", "1")
	if rc != 0 || lab != "(T4/derived-branch - claude8 - opus - max)" {
		t.Fatalf("rc=%d %q %s", rc, lab, e)
	}
	// session derived under its own alias must NOT follow the active context
	ctl(t, d, "switch-alias", "--alias", "claude1", "--model", "m", "--effort", "e")
	if _, out, _ := ctl(t, d, "label", "s"); !strings.Contains(out, "claude8") {
		t.Fatalf("own-alias session followed active: %q", out)
	}
	// explicit flag overrides derived value
	_, lab, _ = ctl(t, d, "register", "--id", "s2", "--kind", "agent", "--derive", "--config-dir", "/h/.claude-claude8", "--model", "sonnet", "--pid", "1")
	if !strings.Contains(lab, "sonnet") {
		t.Fatalf("explicit --model must win: %q", lab)
	}
	t.Setenv("LABEL_SYNC_LABELER", "/nonexistent.sh")
	if rc, _, _ := ctl(t, d, "register", "--id", "s3", "--kind", "agent", "--derive"); rc != 2 {
		t.Fatalf("failed derive must be rc 2, got %d", rc)
	}
}

func TestWatchMaxStreamsEvents(t *testing.T) {
	d := t.TempDir()
	ctl(t, d, "switch-alias", "--alias", "a", "--model", "m", "--effort", "e")
	rc, out, _ := ctl(t, d, "watch", "--since", "0", "--max", "1", "--interval-ms", "20")
	if rc != 0 || !strings.Contains(out, `"type":"alias_switch"`) {
		t.Fatalf("rc=%d %s", rc, out)
	}
}
