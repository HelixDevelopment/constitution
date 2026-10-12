package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
	"unicode/utf8"
)

func rawCtl(dir string, args ...string) (int, string, string) {
	var o, e bytes.Buffer
	rc := run(append([]string{"--dir", dir}, args...), &o, &e)
	return rc, o.String(), e.String()
}

func dangerousOut(s string) bool {
	for _, r := range s {
		if (r < 0x20 && r != '\n' && r != '\t') || r == 0x7f || (r >= 0x80 && r <= 0x9f) || r == utf8.RuneError ||
			(r >= 0x202a && r <= 0x202e) || (r >= 0x2066 && r <= 0x2069) {
			return true
		}
	}
	return !utf8.ValidString(s)
}

// Finding 2: every text output path is terminal-safe, whatever the input.
func TestTextOutputsNeverCarryTerminalControls(t *testing.T) {
	for _, loc := range []string{"C", "C.UTF-8"} {
		t.Run(loc, func(t *testing.T) {
			t.Setenv("LC_ALL", loc)
			d := t.TempDir()
			hostile := "x\x1b]0;PWNED\x07\x1b]52;c;aGk=\x07\x1b[2J\u009d0;C1\u009c\x9d\x00‮evil⁦y" + strings.Repeat("z", 5000)
			outs := []string{}
			add := func(rc int, o, e string) { outs = append(outs, o, e) }
			add(rawCtl(d, "switch-alias", "--alias", "c"+hostile, "--model", hostile, "--effort", hostile))
			add(rawCtl(d, "register", "--id", "e1", "--kind", "shell", "--track", "1", "--branch", hostile,
				"--alias", hostile, "--model", hostile, "--effort", hostile, "--source", hostile, "--cwd", "/"+hostile, "--follow-active", "false"))
			add(rawCtl(d, "get", "--id", "e1"))
			add(rawCtl(d, "get", "--id", "e1", "--json"))
			add(rawCtl(d, "list", "--text"))
			add(rawCtl(d, "list", "--json"))
			add(rawCtl(d, "label", "e1"))
			add(rawCtl(d, "snapshot"))
			add(rawCtl(d, "update", "--id", "e1", "--branch", hostile))
			add(rawCtl(d, "watch", "--since", "0", "--text", "--max", "2"))
			add(rawCtl(d, "watch", "--since", "0", "--max", "2"))
			// error paths that echo input
			add(rawCtl(d, "get", "--id", hostile))
			add(rawCtl(d, "label", hostile))
			add(rawCtl(d, "register", "--id", "e2", "--kind", hostile))
			add(rawCtl(d, hostile))
			for i, o := range outs {
				if dangerousOut(o) {
					t.Fatalf("output #%d carries control/bidi/invalid bytes: %q", i, o)
				}
			}
			rc, lab, _ := rawCtl(d, "label", "e1")
			if rc != 0 || utf8.RuneCountInString(lab) > 600 {
				t.Fatalf("label rc=%d len=%d (fields must be capped)", rc, utf8.RuneCountInString(lab))
			}
		})
	}
}

// Finding 2: ids outside ^[A-Za-z0-9._:@/-]{1,160}$ are rejected with rc 1.
func TestInvalidIDsRejectedRC1(t *testing.T) {
	d := t.TempDir()
	for _, id := range []string{"a b", "id\x1b[2J", "ü", strings.Repeat("a", 161), "semi;colon"} {
		for _, args := range [][]string{
			{"register", "--id", id, "--kind", "shell"},
			{"update", "--id", id, "--branch", "b"},
			{"heartbeat", "--id", id},
			{"unregister", "--id", id},
			{"get", "--id", id},
			{"label", id},
		} {
			if rc, _, _ := rawCtl(d, args...); rc != 1 {
				t.Errorf("%v: rc=%d want 1", args, rc)
			}
		}
	}
	if rc, _, e := rawCtl(d, "register", "--id", "session:abc-123_X.y@h/1", "--kind", "session"); rc != 0 {
		t.Fatalf("valid id refused: %s", e)
	}
	if rc, _, _ := rawCtl(d, "register", "--id", "ok2", "--kind", "agent", "--parent", "bad parent"); rc != 1 {
		t.Fatalf("bad --parent accepted rc=%d", rc)
	}
}

// Hook-review finding 9: --lock-timeout bounds the wait; timeout is rc 2.
func TestLockTimeoutFlagRC2(t *testing.T) {
	d := t.TempDir()
	if rc, _, e := rawCtl(d, "register", "--id", "a", "--kind", "shell"); rc != 0 {
		t.Fatal(e)
	}
	f, err := os.OpenFile(filepath.Join(d, "lock"), os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		t.Fatal(err)
	}
	t0 := time.Now()
	var o, e bytes.Buffer
	rc := run([]string{"--dir", d, "--lock-timeout", "200ms", "heartbeat", "--id", "a"}, &o, &e)
	if el := time.Since(t0); rc != 2 || el > 2*time.Second || !strings.Contains(e.String(), "state lock busy") {
		t.Fatalf("rc=%d after %v: %s", rc, el, e.String())
	}
	t.Setenv("LABEL_SYNC_LOCK_TIMEOUT", "100ms")
	if rc, _, _ := rawCtl(d, "heartbeat", "--id", "a"); rc != 2 {
		t.Fatalf("env timeout rc=%d", rc)
	}
	// reads never take the lock
	if rc, _, _ := rawCtl(d, "label", "a"); rc != 0 {
		t.Fatal("reads must not wait for the writer lock")
	}
}

// Finding 11: update can CLEAR a field.
func TestUpdateClear(t *testing.T) {
	d := t.TempDir()
	rawCtl(d, "register", "--id", "a", "--kind", "shell", "--track", "4", "--branch", "b", "--alias", "x", "--model", "m", "--effort", "e", "--follow-active", "false")
	if rc, out, e := rawCtl(d, "update", "--id", "a", "--clear", "branch,model"); rc != 0 || strings.TrimSpace(out) != "(T4/? - x - ? - e)" {
		t.Fatalf("clear: rc=%d out=%q err=%q", rc, out, e)
	}
	if rc, _, _ := rawCtl(d, "update", "--id", "a", "--clear", "kind"); rc != 1 {
		t.Fatal("clearing a required field must be refused")
	}
	if rc, _, _ := rawCtl(d, "update", "--id", "a", "--clear", "nonsense"); rc != 1 {
		t.Fatal("unknown --clear key must be refused")
	}
}

// Finding 1: register --derive under a CLAUDE_CONFIG_DIR alias PINS the
// entity (process-bound truth) with no read of the active alias; two
// terminals on two aliases each keep their own alias through switches.
func TestDeriveUnderConfigDirPins(t *testing.T) {
	d := t.TempDir()
	script := filepath.Join(t.TempDir(), "lab.sh")
	if err := os.WriteFile(script, []byte("#!/bin/bash\na=\"${CLAUDE_CONFIG_DIR##*/.claude-}\"; [ \"$a\" = \"$CLAUDE_CONFIG_DIR\" ] && a='?'\n[ -z \"$CLAUDE_CONFIG_DIR\" ] && a='?'\necho \"(T1/main - $a - opus - high)\"\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("LABEL_SYNC_LABELER", script)
	rawCtl(d, "switch-alias", "--alias", "claude1", "--model", "opus", "--effort", "high")
	t.Setenv("CLAUDE_CONFIG_DIR", "/home/u/.claude-claude2")
	if rc, out, e := rawCtl(d, "register", "--id", "termA", "--kind", "shell", "--derive"); rc != 0 || !strings.Contains(out, "claude2") {
		t.Fatalf("A: rc=%d %q %q", rc, out, e)
	}
	t.Setenv("CLAUDE_CONFIG_DIR", "/home/u/.claude-claude3")
	rawCtl(d, "register", "--id", "termB", "--kind", "shell", "--derive")
	rawCtl(d, "register", "--id", "cmdA", "--kind", "command", "--parent", "termA")
	t.Setenv("CLAUDE_CONFIG_DIR", "")
	if rc, out, _ := rawCtl(d, "register", "--id", "plain", "--kind", "shell", "--derive"); rc != 0 || !strings.Contains(out, "claude1") {
		t.Fatalf("alias-less root must follow active: %q", out)
	}
	for _, a := range []string{"claude4", "claude5", "claude1"} {
		rawCtl(d, "switch-alias", "--alias", a, "--model", "m", "--effort", "e")
		for id, want := range map[string]string{"termA": "claude2", "termB": "claude3", "cmdA": "claude2", "plain": a} {
			if _, out, _ := rawCtl(d, "label", id); !strings.Contains(out, " - "+want+" - ") {
				t.Fatalf("after switch to %s: %s shows %q, want %s", a, id, out, want)
			}
		}
	}
}

// Defence in depth: a LEGACY log written before sanitisation existed (raw
// ESC / bidi in fields and ids) must still print safely.
func TestLegacyLogOutputsSanitised(t *testing.T) {
	d := t.TempDir()
	legacy := "{\"seq\":1,\"ts\":\"2026-10-12T10:00:00Z\",\"type\":\"register\",\"entity\":{\"id\":\"leg\\u001b]0;X\\u0007\",\"kind\":\"shell\",\"branch\":\"b‮evil\\u001b[2J\",\"alias\":\"a⁦z\",\"follow_active\":false,\"state\":\"running\",\"started_at\":\"2026-10-12T10:00:00Z\",\"updated_at\":\"2026-10-12T10:00:00Z\"}}\n"
	if err := os.WriteFile(filepath.Join(d, "events.jsonl"), []byte(legacy), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, args := range [][]string{{"list", "--text"}, {"list", "--json"}, {"snapshot"}, {"watch", "--since", "0", "--max", "1"}, {"watch", "--since", "0", "--max", "1", "--text"}} {
		type res struct {
			rc   int
			o, e string
		}
		done := make(chan res, 1)
		go func() { rc, o, e := rawCtl(d, args...); done <- res{rc, o, e} }()
		var got res
		select {
		case got = <-done:
		case <-time.After(10 * time.Second):
			t.Fatalf("%v hung: a seq-less legacy log must still be watchable", args)
		}
		rc, o, e := got.rc, got.o, got.e
		if dangerousOut(o) || dangerousOut(e) {
			t.Fatalf("%v rc=%d leaks controls: %q %q", args, rc, o, e)
		}
	}
}
