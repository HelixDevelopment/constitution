package main

// Second-review fixes: finding 4 (an explicit alias pins, CONTRACT §4.2: only
// alias-less roots follow) and finding 12 (negative / out-of-range pids).

import (
	"strings"
	"testing"
)

func TestExplicitAliasPinsLikeContract42(t *testing.T) {
	d := t.TempDir()
	rawCtl(d, "switch-alias", "--alias", "claude1", "--model", "sonnet", "--effort", "low")
	rc, out, e := rawCtl(d, "register", "--id", "x", "--kind", "agent", "--track", "2", "--branch", "b",
		"--alias", "claude2", "--model", "opus", "--effort", "high")
	if rc != 0 || strings.TrimSpace(out) != "(T2/b - claude2 - opus - high)" {
		t.Fatalf("register with an explicit alias rc=%d out=%q err=%q (explicit triple ignored)", rc, out, e)
	}
	rawCtl(d, "switch-alias", "--alias", "claude3")
	if _, out, _ := rawCtl(d, "label", "x"); strings.TrimSpace(out) != "(T2/b - claude2 - opus - high)" {
		t.Fatalf("explicit alias followed the active context: %q", out)
	}
	// alias-less root still follows
	rawCtl(d, "register", "--id", "f", "--kind", "agent", "--track", "2", "--branch", "b")
	if _, out, _ := rawCtl(d, "label", "f"); !strings.Contains(out, "claude3") {
		t.Fatalf("alias-less root does not follow: %q", out)
	}
	// an explicit --follow-active true still wins over the default
	rawCtl(d, "register", "--id", "g", "--kind", "agent", "--alias", "claude9", "--follow-active", "true")
	if _, out, _ := rawCtl(d, "label", "g"); !strings.Contains(out, "claude3") {
		t.Fatalf("explicit --follow-active true ignored: %q", out)
	}
	// update --alias on a follower pins it too (CONTRACT §4.3)
	rawCtl(d, "update", "--id", "f", "--alias", "claude5")
	rawCtl(d, "switch-alias", "--alias", "claude6")
	if _, out, _ := rawCtl(d, "label", "f"); !strings.Contains(out, "claude5") {
		t.Fatalf("update --alias did not pin: %q", out)
	}
}

func TestBadPidsRejectedRC1(t *testing.T) {
	d := t.TempDir()
	for _, p := range []string{"-1", "-99", "4194305", "abc"} {
		if rc, _, e := rawCtl(d, "register", "--id", "p", "--kind", "shell", "--pid", p); rc != 1 {
			t.Fatalf("register --pid %s rc=%d (%s), want 1", p, rc, e)
		}
	}
	rawCtl(d, "register", "--id", "ok", "--kind", "shell", "--pid", "42")
	for _, p := range []string{"-1", "4194305"} {
		if rc, _, e := rawCtl(d, "update", "--id", "ok", "--pid", p); rc != 1 {
			t.Fatalf("update --pid %s rc=%d (%s), want 1", p, rc, e)
		}
	}
}
