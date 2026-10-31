#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# test_mutations.sh — paired §1.1 mutation tests for every security rule of the extension engine.
#
# For each rule: copy scripts/constitution_ext (+ scripts/lib/safe_rm.sh) into the sandbox, apply the
# mutation that reverts the rule (each replacement must match its anchor EXACTLY ONCE, otherwise the
# mutation is reported BROKEN — a mutation that silently applies nowhere would prove nothing,
# §11.4.273), run the suites that guard the rule against the mutated copy, and require at least one of
# them to FAIL (KILLED). A mutation whose suites all pass SURVIVED and fails this test.
# Control: the UNMUTATED copy must pass the same suites (otherwise failures could come from the copy).
# Rules with two independent enforcement layers are mutated in both layers at once (noted per row).
# Usage: bash tests/extensions/test_mutations.sh [MUTATION_NAME...]
T_NAME=mutations
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
HERE="$REPO/tests/extensions"

mk_copy() { # dir — copy of the engine laid out as <dir>/scripts/{constitution_ext,lib}
  mkdir -p "$1/scripts/constitution_ext" "$1/scripts/lib"
  cp "$REPO"/scripts/constitution_ext/*.sh "$REPO"/scripts/constitution_ext/*.py "$1/scripts/constitution_ext/"
  cp "$REPO/scripts/lib/safe_rm.sh" "$REPO/scripts/lib/protected_paths.list" "$1/scripts/lib/"
}
run_suites() { # copy_dir suites... — prints the failing suite names (empty = all passed)
  local d="$1"; shift; local s bad=""
  for s in "$@"; do
    [ -n "$bad" ] && [ "${MUT_ALL_SUITES:-0}" != 1 ] && break  # one failing suite already kills the mutant
    if [ "$s" = unit ]; then
      CONSTITUTION_EXT_DIR="$d/scripts/constitution_ext" python3 -I "$HERE/test_unit.py" >/dev/null 2>&1 || bad="$bad $s"
    else
      CONSTITUTION_EXT_ENGINE="$d/scripts/constitution_ext/constitution_ext.sh" bash "$HERE/test_$s.sh" >/dev/null 2>&1 || bad="$bad $s"
    fi
  done
  printf '%s' "$bad"
}

# name‖suites‖file‖old‖new; continuation rows '+‖‖file‖old‖new'; blocks separated by '@@'; \n = newline
MUTS="$SB/muts.txt"
cat >"$MUTS" <<'EOF'
R2-symlink (check_tree + copy layer)‖security‖ext_engine.py‖            if stat.S_ISLNK(st.st_mode):  # RULE:R2-symlink‖            if False:  # RULE:R2-symlink
+‖‖ext_engine.py‖            st = os.lstat(e.path)‖            st = os.stat(e.path)
+‖‖ext_engine.py‖            st = os.lstat(sp)‖            st = os.stat(sp)
+‖‖ext_engine.py‖        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)  # RULE:M4-open-nonblock‖        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)  # RULE:M4-open-nonblock
@@
R2-dotdot (manifest + tree_problems layer)‖unit security‖ext_engine.py‖    if any(s in ("", ".", "..") for s in segs):  # RULE:R2-dotdot‖    if False:  # RULE:R2-dotdot
+‖‖ext_engine.py‖            if not full.startswith(rt + os.sep):‖            if False:
@@
R2-abs-path (manifest + tree_problems layer)‖unit security‖ext_engine.py‖    if p.startswith("/") or p.startswith("~") or "\\" in p:  # RULE:R2-abs-path‖    if False:  # RULE:R2-abs-path
+‖‖ext_engine.py‖            if not full.startswith(rt + os.sep):‖            if False:
@@
R2-control-chars (RM2)‖unit‖ext_engine.py‖    if bad_chars(p):  # RULE:R2-control-chars‖    if False:  # RULE:R2-control-chars
@@
R2-setuid‖unit security‖ext_engine.py‖                if st.st_mode & (stat.S_ISUID | stat.S_ISGID | stat.S_ISVTX):  # RULE:R2-setuid‖                if False:  # RULE:R2-setuid
@@
R2-file-size‖security‖ext_engine.py‖                if st.st_size > MAX_FILE_BYTES:  # RULE:R2-file-size‖                if False:  # RULE:R2-file-size
@@
R2-leading-dash (RM7)‖unit attacks‖ext_engine.py‖            if not NAME_OK_RE.match(e.name) or e.name.startswith("-"):‖            if not NAME_OK_RE.match(e.name):
@@
R3-unknown-key‖unit security‖ext_engine.py‖            if k not in fields:  # RULE:R3-unknown-key‖            if False:  # RULE:R3-unknown-key
@@
R3-duplicate-key‖unit security‖ext_yaml.py‖            if key in out:‖            if False:
@@
R3-depth-limit‖unit‖ext_yaml.py‖        if depth > MAX_DEPTH:‖        if False:
@@
R3-size-limit (parser layer)‖unit‖ext_yaml.py‖        if len(text.encode("utf-8", "surrogatepass")) > max_bytes:‖        if False:
@@
R3-int-cap‖unit attacks‖ext_yaml.py‖        if len(s.lstrip("-")) > MAX_INT_DIGITS:‖        if False:
@@
R3-yaml11-scalar‖unit attacks‖ext_yaml.py‖    if YAML11_RE.fullmatch(s):‖    if False:
@@
R3-yaml11-key‖unit‖ext_yaml.py‖    if YAML11_RE.fullmatch(key):‖    if False:
@@
R3-bad-chars (bidi/format)‖unit attacks‖ext_engine.py‖        elif bad_chars(v):  # RULE:R3-bad-chars‖        elif False:  # RULE:R3-bad-chars
@@
R3-trust-tier‖attacks‖ext_engine.py‖    if ext.get("trust_tier") not in (None, "community"):  # RULE:R3-trust-tier‖    if False:  # RULE:R3-trust-tier
@@
R3-id-regex‖unit security‖ext_engine.py‖ID_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,62}\Z")‖ID_RE = re.compile(r"(?s).+\Z")
@@
R4-git-pin‖integration‖ext_engine.py‖        if kind == "git" and not sha and not waiver:  # RULE:R4-git-pin‖        if False:  # RULE:R4-git-pin
@@
R4-dir-pin‖security‖ext_engine.py‖        if kind == "dir" and not sha256 and not waiver:  # RULE:R4-dir-pin‖        if False:  # RULE:R4-dir-pin
@@
R4-sha256‖integration‖ext_engine.py‖        if sha256 and sha256 != digest:  # RULE:R4-sha256‖        if False:  # RULE:R4-sha256
@@
R5-consent‖security e2e‖ext_engine.py‖        if self.o["yes"]:‖        if True:
@@
R5-consent-no-tty (RM6)‖attacks‖ext_engine.py‖            tty = open(os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY), "r+b", buffering=0)\n        except OSError:\n            raise EngineError(EXIT_REFUSED, "consent required: pass --yes or run interactively")‖            tty = open(os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY), "r+b", buffering=0)\n        except OSError:\n            return "notty"
@@
R5-default-disabled‖security‖ext_engine.py‖"consent": {"capabilities": caps, "mode": mode},\n                 "components": self._components(m, False)}‖"consent": {"capabilities": caps, "mode": mode},\n                 "components": self._components(m, True)}
@@
R5-components-consistent‖security unit‖ext_engine.py‖        if (e.get("components") or {}) != want:  # RULE:R5-components-consistent‖        if False:  # RULE:R5-components-consistent
@@
R6-secret-patterns‖unit security‖ext_engine.py‖    for r in _SECRET_RES:  # RULE:R6-secret-patterns‖    for r in []:  # RULE:R6-secret-patterns
@@
R6-secret-scan‖unit security‖ext_engine.py‖        if looks_secret(s):  # RULE:R6-secret-scan‖        if False:  # RULE:R6-secret-scan
@@
R1-no-exec (inject hook execution)‖security e2e‖ext_engine.py‖        self.audit("add", eid, ‖        [subprocess.run(["bash", os.path.join(final, h["command"])]) for h in (m.get("provides") or {}).get("hooks") or []]\n        self.audit("add", eid,
@@
R7-rollback‖chaos‖ext_engine.py‖            if eid not in lock:  # RULE:R7-rollback‖            if False:  # RULE:R7-rollback
@@
R7-source-checksums‖security‖ext_engine.py‖            if parse_checksums(_read_nofollow(os.path.join(srcdir, CHECKSUMS), MAX_FILE_BYTES, CHECKSUMS)) != hashes:  # RULE:R7-source-checksums‖            if False:  # RULE:R7-source-checksums
@@
R7-staged-verify (RM3)‖unit‖ext_engine.py‖        if tree_digest(staged) != digest:  # RULE:R7-staged-verify‖        if False:  # RULE:R7-staged-verify
@@
R7-verify-after-install (RM8)‖unit‖ext_engine.py‖        if tree_digest(final) != digest:  # RULE:R7-verify-after-install (§11.4.200)‖        if False:  # RULE:R7-verify-after-install
@@
R7-verify (digest + per-file layer)‖security‖ext_engine.py‖        if digest != e.get("sha256"):  # RULE:R7-verify-digest‖        if False:  # RULE:R7-verify-digest
+‖‖ext_engine.py‖                for r in sorted(set(recorded) | set(hashes)):‖                for r in []:
@@
R7-lock-no-launder‖security attacks‖ext_engine.py‖            elif tree is None or tree_digest(tree) != e.get("sha256"):  # RULE:R7-lock-no-launder‖            elif False:  # RULE:R7-lock-no-launder
@@
R8-safe-rm (bypass safe_rm_rf)‖security‖ext_engine.py‖        if not os.path.isfile(self.safe_rm):‖        shutil.rmtree(path); return\n        if not os.path.isfile(self.safe_rm):
@@
R9-revocation‖security‖ext_engine.py‖        for r in cat.get("revoked") or []:  # RULE:R9-revocation‖        for r in []:  # RULE:R9-revocation
@@
R9-keep-revocations‖attacks‖ext_engine.py‖        if prev and not self.o.get("replace"):  # RULE:R9-keep-revocations‖        if False:  # RULE:R9-keep-revocations
@@
R10-binding‖security‖ext_engine.py‖        for b in (m.get("provides") or {}).get("tools_bindings") or []:  # RULE:R10-binding‖        for b in []:  # RULE:R10-binding
@@
R11-shim-path (B1)‖attacks‖ext_engine.py‖        if path != self._shim_rel(a, root, cmd):  # RULE:R11-shim-path‖        if False:  # RULE:R11-shim-path
@@
R11-contained (B1)‖attacks‖ext_engine.py‖        if not _inside(os.path.realpath(os.path.dirname(self._wabs(path))), proj):  # RULE:R11-contained‖        if False:  # RULE:R11-contained
@@
R11-link-target (B1)‖attacks‖ext_engine.py‖            if w["kind"] != "symlink" or w["target"] not in self._link_texts(eid, cmd, path, dig):  # RULE:R11-link-target‖            if False:  # RULE:R11-link-target
@@
R11-target-inside (wire --target; all three containment layers)‖attacks‖ext_engine.py‖        if not _inside(os.path.realpath(target), proj):  # RULE:R11-target-inside‖        if False:  # RULE:R11-target-inside
+‖‖ext_engine.py‖                    if not _inside(os.path.realpath(self._deep_existing(os.path.dirname(path))), proj):‖                    if False:
+‖‖ext_engine.py‖            if not _inside(os.path.realpath(os.path.dirname(p)), proj):‖            if False:
@@
R11-no-overwrite-edited (wire)‖attacks‖ext_engine.py‖                if h == w["sha256"] or (same and h == rec.get("sha256")):  # RULE:R11-no-overwrite-edited‖                if True:  # RULE:R11-no-overwrite-edited
@@
R12-final-bound (B2)‖unit attacks‖ext_engine.py‖        if j.get("final") != os.path.join(self.inst_dir, eid):  # RULE:R12-final-bound‖        if False:  # RULE:R12-final-bound
@@
R12-aux-bound (B2)‖unit attacks‖ext_engine.py‖            if not isinstance(aux, str) or os.path.dirname(aux) != self.inst_dir \\n                    or not TRASH_RE.match(os.path.basename(aux)):  # RULE:R12-aux-bound‖            if False:  # RULE:R12-aux-bound
@@
R13-lock (B3)‖attacks‖ext_engine.py‖                fcntl.flock(fd, fcntl.LOCK_EX)  # RULE:R13-lock‖                pass  # RULE:R13-lock
@@
R14-dotgit (check_tree + copy layer, B4)‖unit attacks‖ext_engine.py‖            if e.name.lower() == ".git":  # RULE:R14-dotgit‖            if False:  # RULE:R14-dotgit
+‖‖ext_engine.py‖        if any(x.lower() == ".git" for x in dns + fns):‖        if False:
@@
R14-bare-repo (B4)‖attacks‖ext_engine.py‖        if "head" in low and "config" in low and "objects" in low:  # RULE:R14-bare-repo‖        if False:  # RULE:R14-bare-repo
@@
R14-hardlink (check_tree + copy layer)‖unit attacks‖ext_engine.py‖                if st.st_nlink > 1:  # RULE:R14-hardlink‖                if False:  # RULE:R14-hardlink
+‖‖ext_engine.py‖            if not stat.S_ISREG(st.st_mode) or st.st_nlink > 1:‖            if not stat.S_ISREG(st.st_mode):
@@
R14-dir-count‖attacks‖ext_engine.py‖        if state["dirs"] > MAX_DIRS:  # RULE:R14-dir-count‖        if False:  # RULE:R14-dir-count
@@
R15-env-scrub (I2)‖unit attacks‖ext_engine.py‖    env = {k: os.environ[k] for k in _GIT_KEEP_ENV if k in os.environ}  # RULE:R15-env-scrub‖    env = dict(os.environ)  # RULE:R15-env-scrub
@@
R15-git-config (all -c)‖unit attacks‖ext_engine.py‖    cmd = cmd + args  # RULE:R15-git-config‖    cmd = ["git"] + args  # RULE:R15-git-config
@@
R15-hooksPath (RM5)‖unit‖ext_engine.py‖_GIT_CONFIG = ("core.hooksPath=/dev/null", ‖_GIT_CONFIG = (
@@
R15-no-symlinks‖unit‖ext_engine.py‖"core.symlinks=false", ‖"core.symlinks=true", 
@@
R15-attributes (I2 filter)‖unit attacks‖ext_engine.py‖        f.write(GIT_ATTRIBUTES)  # RULE:R15-attributes‖        f.write("")  # RULE:R15-attributes
@@
R15-git-symlink‖unit‖ext_engine.py‖        if mode == "120000":  # RULE:R15-git-symlink‖        if False:  # RULE:R15-git-symlink
@@
R16-transport-helper (RM1)‖unit attacks‖ext_engine.py‖    if "::" in u:  # RULE:R16-transport-helper‖    if False:  # RULE:R16-transport-helper
@@
R16-userinfo (I1)‖unit attacks‖ext_engine.py‖    if m and "@" in m.group(2):  # RULE:R16-userinfo‖    if False:  # RULE:R16-userinfo
@@
R16-secret-url (I1)‖unit‖ext_engine.py‖    if looks_secret(u):  # RULE:R16-secret-url‖    if False:  # RULE:R16-secret-url
@@
R17-mac (I3)‖attacks‖ext_engine.py‖            and hmac.compare_digest(rec["mac"], self._mac(key, rec["id"], rec["entry"]))  # RULE:R17-mac‖            and True  # RULE:R17-mac
@@
R17-compare (I3)‖attacks‖ext_engine.py‖        for k in sorted(set(entry) | set(rec["entry"])):  # RULE:R17-compare‖        for k in []:  # RULE:R17-compare
@@
R17-enable-check (I3)‖attacks‖ext_engine.py‖        if rp and not missing:  # RULE:R17-enable-check‖        if False:  # RULE:R17-enable-check
@@
R17-wire-check (I3)‖attacks‖ext_engine.py‖            if rp:  # RULE:R17-wire-check‖            if False:  # RULE:R17-wire-check
@@
R17-lock-check (I3)‖attacks‖ext_engine.py‖                if rp:  # RULE:R17-lock-check‖                if False:  # RULE:R17-lock-check
@@
R18-nofollow (read + write + up-front layer)‖attacks‖ext_engine.py‖        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)  # never blocks on a FIFO‖        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)  # never blocks on a FIFO
+‖‖ext_engine.py‖        if os.path.lexists(path) and not stat.S_ISREG(os.lstat(path).st_mode):‖        if False:
+‖‖ext_engine.py‖        fd = os.open(self.p("extensions.audit.log"), os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o644)‖        fd = os.open(self.p("extensions.audit.log"), os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
+‖‖ext_engine.py‖                if os.path.lexists(f) and not stat.S_ISREG(os.lstat(f).st_mode):  # RULE:R18-upfront‖                if False:  # RULE:R18-upfront
@@
R18-state-dir‖attacks‖ext_engine.py‖            if not stat.S_ISDIR(st.st_mode):\n                raise EngineError(EXIT_REFUSED, "%s is not a real directory (a symlink or a file); refusing to use it" % self.state)‖            pass
@@
R19-kill-guard‖attacks‖ext_engine.py‖    if _HARNESS["ok"] and os.environ.get("CONSTITUTION_EXT_TEST_MODE") == "1"‖    if os.environ.get("CONSTITUTION_EXT_TEST_MODE") == "1"
@@
R19-version-guard‖attacks‖ext_engine.py‖and not _HARNESS["ok"]:  # RULE:R19-version-guard‖and False:  # RULE:R19-version-guard
@@
W1-no-overwrite-unmanaged‖e2e‖ext_engine.py‖            raise EngineError(EXIT_REFUSED, "%s exists and is not managed by this extension; refusing to overwrite" % p)‖            pass
@@
W2-unwire-only-unchanged‖e2e‖ext_engine.py‖                if _sha_file(p) == w["sha256"]:‖                if True:
@@
M01 _inside prefix-only (reviewer)‖provenance attacks‖ext_engine.py‖return path == parent or path.startswith(parent.rstrip(os.sep) + os.sep)‖return path.startswith(parent)
@@
M03 nonce file perm check dropped (reviewer)‖provenance attacks‖ext_engine.py‖st.st_uid != os.geteuid() or st.st_mode & 0o077 or‖False or
@@
M12 disable launders tampered entry (reviewer)‖provenance attacks‖ext_engine.py‖            if clean:\n                self.commit(lock, [eid], stage="disable:locked")‖            if True:\n                self.commit(lock, [eid], stage="disable:locked")
@@
M13 key mode check dropped (reviewer)‖provenance attacks‖ext_engine.py‖if not stat.S_ISREG(st.st_mode) or st.st_mode & 0o077:‖if not stat.S_ISREG(st.st_mode):
@@
M15 enable ignores revocation (reviewer)‖provenance security‖ext_engine.py‖        if why:  # RULE:R9-enable-revocation‖        if False:  # RULE:R9-enable-revocation
@@
M16 installed may shadow bundled id (reviewer)‖provenance security‖ext_engine.py‖        if borigin == "bundled":\n            raise EngineError(EXIT_REFUSED, "%s is a bundled extension; use enable/disable" % eid)‖        if False:\n            raise EngineError(EXIT_REFUSED, "x")
@@
M17 catalog install_allowed ignored (reviewer)‖provenance security‖ext_engine.py‖        if not (cat.get("catalog") or {}).get("install_allowed"):‖        if False:
@@
M20 copy keeps setuid/odd modes (reviewer)‖provenance security‖ext_engine.py‖            os.chmod(dp2, 0o755 if st.st_mode & 0o111 else 0o644)‖            os.chmod(dp2, st.st_mode & 0o7777)
@@
M24 gitlink not refused (reviewer)‖provenance attacks‖ext_engine.py‖        elif mode == "160000":‖        elif False:
@@
M26 caps-changed-since-consent dropped (reviewer)‖provenance security‖ext_engine.py‖        if e.get("enabled") and (e.get("consent") or {}).get("capabilities") != now:‖        if False:
@@
R20-marker (marker accepted for any file)‖provenance‖ext_engine.py‖        return any(ln.strip() == mark for ln in head)  # RULE:R20-marker‖        return True  # RULE:R20-marker
@@
R20-mac (forged signed record accepted)‖provenance‖ext_engine.py‖ or not hmac.compare_digest(rec["mac"], self._wmac(key, rec["entries"])):  # RULE:R20-mac‖ or False:  # RULE:R20-mac
@@
R20-signed (every entry treated as bound)‖provenance‖ext_engine.py‖        if self._wkey(w) in self._wsigned or w["kind"] == "symlink":  # RULE:R20-signed‖        if True:  # RULE:R20-signed
@@
R20-refuse (unbound entries acted on)‖provenance‖ext_engine.py‖            if self._unbound(w):  # RULE:R20-refuse‖            if False:  # RULE:R20-refuse
@@
R9-wire-revocation‖provenance‖ext_engine.py‖            if why:  # RULE:R9-wire-revocation‖            if False:  # RULE:R9-wire-revocation
@@
R5-wire-consent‖unit provenance‖ext_engine.py‖            if (e.get("consent") or {}).get("capabilities") != capabilities_of(m, stage):  # RULE:R5-wire-consent‖            if False:  # RULE:R5-wire-consent
@@
R21-shell detection‖provenance‖ext_engine.py‖    if any(r.search(text) for r in AGENT_SHELL_RES):  # RULE:R21-shell‖    if False:  # RULE:R21-shell
@@
R21-allowed-tools detection (front matter parsed, I1)‖unit security provenance‖ext_engine.py‖    if fm is not None and _fm_keys(fm, set()) & FM_SHELL_KEYS:  # RULE:R21-allowed-tools‖    if False:  # RULE:R21-allowed-tools
@@
R21-files detection‖provenance‖ext_engine.py‖    if any(r.search(text) for r in AGENT_FILES_RES):  # RULE:R21-files‖    if False:  # RULE:R21-files
@@
R21-declared (declaration not compared)‖provenance‖ext_engine.py‖        if name not in decl[cls]:  # RULE:R21-declared‖        if False:  # RULE:R21-declared
@@
R21-enable‖provenance‖ext_engine.py‖        if cerr:  # RULE:R21-enable‖        if False:  # RULE:R21-enable
@@
R21-wire‖unit provenance‖ext_engine.py‖            if cerr:  # RULE:R21-wire‖            if False:  # RULE:R21-wire
@@
R16-query-token‖provenance‖ext_engine.py‖            if CRED_PARAM_RE.match(part.split("=", 1)[0]):  # RULE:R16-query-token‖            if False:  # RULE:R16-query-token
@@
R16-redact (messages not redacted)‖provenance‖ext_engine.py‖    for r, rep in _REDACT_RES:‖    for r, rep in []:
@@
R16-waiver-secret‖provenance‖ext_engine.py‖        if opts.get("waiver_id") and secret_shaped_id(opts["waiver_id"]):  # RULE:R16-waiver-secret‖        if False:  # RULE:R16-waiver-secret
@@
R4-git-content-pin‖provenance‖ext_engine.py‖        if kind == "git" and sha and not sha256 and not waiver:  # RULE:R4-git-content-pin‖        if False:  # RULE:R4-git-content-pin
@@
R5-consent-visible (--json hides the list)‖provenance‖ext_engine.py‖            print(ln, file=sys.stderr)  # RULE:R5-consent-visible‖            if not self.o.get("json"):\n                print(ln, file=sys.stderr)  # RULE:R5-consent-visible
@@
R18-upfront‖provenance‖ext_engine.py‖                if os.path.lexists(f) and not stat.S_ISREG(os.lstat(f).st_mode):  # RULE:R18-upfront‖                if False:  # RULE:R18-upfront
@@
R11-relative (absolute wiring entries accepted)‖provenance attacks‖ext_engine.py‖        if not _rel_ok(root):  # RULE:R11-relative‖        if False:  # RULE:R11-relative
@@
R11-link-relative (absolute legacy link text)‖unit provenance‖ext_engine.py‖        return tuple(os.path.relpath(os.path.realpath(os.path.join(b, eid, "commands", cmd)), d)‖        return tuple(os.path.realpath(os.path.join(b, eid, "commands", cmd))
@@
R13-root-lock (extensions/ lock only)‖provenance‖ext_engine.py‖            for d in (self.project, self.root):  # the root always exists (extensions/ may not yet)‖            for d in (self.project,):
@@
B1 unscannable file treated as clean‖unit security‖ext_engine.py‖        return ["%s cannot be scanned (%s); files exposed to an agent must be UTF-8 text" % (rel, ex.msg)]‖        return []
@@
B1 only SKILL.md of a command dir scanned (m5)‖unit security‖ext_engine.py‖                out.append((c["name"], rel + "/" + n))‖                out.append((c["name"], rel + "/" + n)) if n == "SKILL.md" else None
@@
B1 symlinked directory in a command dir not scanned‖unit‖ext_engine.py‖            for n in sorted(fns) + [d for d in dns if os.path.islink(os.path.join(dp, d))]:‖            for n in sorted(fns):
@@
B1 FIFO read blocks (no O_NONBLOCK)‖unit‖ext_engine.py‖        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)  # never blocks on a FIFO‖        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)  # never blocks on a FIFO
@@
B1 unreadable directory skipped by the hash walk‖unit‖ext_engine.py‖    for dp, dns, fns in os.walk(root, onerror=_walk_error):‖    for dp, dns, fns in os.walk(root):
@@
I1 unparsable front matter treated as none‖unit security‖ext_engine.py‖                raise ValueError("front matter is not in the accepted YAML subset (%s)" % ex)‖                return None, text
@@
I1 byte-order mark treated as no front matter‖unit security‖ext_engine.py‖        raise ValueError("starts with a byte-order mark")‖        return None, text
@@
I1 loose opener treated as no front matter‖unit‖ext_engine.py‖        raise ValueError(_FM_OPEN_MSG)  # RULE:R21-fm-open‖        return None, text  # RULE:R21-fm-open
@@
I1 carriage return inside front matter accepted‖unit‖ext_engine.py‖                raise ValueError("carriage return inside the front matter")‖                pass
@@
I1 unterminated front matter treated as none‖unit‖ext_engine.py‖    raise ValueError("unterminated front matter (no closing '---' line)")‖    return None, text
@@
I1 delimiter with trailing characters accepted‖unit‖ext_engine.py‖            raise ValueError("front matter delimiter line with extra characters (%r)" % disp(ln[:20]))‖            continue
@@
I1 hooks key not a shell key‖unit‖ext_engine.py‖FM_SHELL_KEYS = frozenset(("allowedtools", "hooks"))‖FM_SHELL_KEYS = frozenset(("allowedtools",))
@@
I1 key spelling not normalised‖unit‖ext_engine.py‖            out.add(re.sub(r"[-_]", "", str(k).lower()))‖            out.add(str(k))
@@
R22 command form unchecked‖unit‖ext_engine.py‖    if not (TOOL_RE.match(cmd) or relpath_ok(cmd)) or cmd.startswith("-"):  # RULE:R22-command-form‖    if False:  # RULE:R22-command-form
@@
R22 option-shaped command accepted‖unit‖ext_engine.py‖    if not (TOOL_RE.match(cmd) or relpath_ok(cmd)) or cmd.startswith("-"):  # RULE:R22-command-form‖    if not (TOOL_RE.match(cmd) or relpath_ok(cmd)):  # RULE:R22-command-form
@@
R22 non-JSON MCP file accepted‖unit‖ext_engine.py‖            errs.append("%s: not a readable JSON MCP file (%s)" % (s["file"], str(ex)[:120]))‖            pass
@@
R22 MCP file extension unchecked‖unit‖ext_engine.py‖        raise ValueError("MCP server files must be JSON (*.json)")‖        pass
@@
R22 unknown capabilities.shell name accepted‖unit‖ext_engine.py‖        errs.append("capabilities.shell: %s is not an MCP server of this extension" % n)‖        pass
@@
I2 consent hides the MCP command‖unit security‖ext_engine.py‖            caps.add("mcp-command:%s=%s" % (s["name"], _argv_text(s["command"], s.get("args"))))‖            pass
@@
I2 consent hides commands in the MCP file‖unit‖ext_engine.py‖                caps.add("mcp-command:%s/%s=%s" % (s["name"], where, _argv_text(d.get("command"), d.get("args"))))‖                pass
@@
I2 consent hides env names in the MCP file‖unit‖ext_engine.py‖                        caps.add("env:%s" % _redact_item(k))‖                        pass
@@
I2 consent hides the shell capability‖security‖ext_engine.py‖        caps.add("shell:" + n)‖        pass
@@
I3 consent does not bind content‖unit security‖ext_engine.py‖            caps.add("sha256:%s=%s" % (r, _sha_or_unreadable(os.path.join(tree, r))))‖            pass
@@
I3 risky command dirs not bound‖unit‖ext_engine.py‖    risky = set(caps.get("agent_shell") or []) | set(caps.get("reads_files") or [])‖    risky = set()
@@
I3 lock launders widened bundled content‖security‖ext_engine.py‖                if e.get("enabled") and (cerr or (e.get("consent") or {}).get("capabilities") != caps):  # RULE:R5-lock-reconsent‖                if False:  # RULE:R5-lock-reconsent
@@
m3 consent hides the trust tier‖security‖ext_engine.py‖"  trust tier: %s" % disp(tier or "community")‖"  trust tier: (hidden)"
@@
m3 consent hides the waiver id‖security‖ext_engine.py‖"  waiver id: %s" % disp(waiver or "none")‖"  waiver id: (hidden)"
@@
m1 project == root accepted‖security‖ext_engine.py‖        if self.project and os.path.realpath(self.project) == os.path.realpath(self.root):  # RULE:M1-project-not-root‖        if False:  # RULE:M1-project-not-root
@@
m2 catalog latest unchecked‖unit security‖ext_engine.py‖            if "latest" in ent and (not is_semver(ent["latest"]) or ent["latest"] not in rels):  # RULE:M2-latest‖            if False:  # RULE:M2-latest
@@
m4 wire temporary files never cleaned‖unit security‖ext_engine.py‖                if ok:  # RULE:M4-tmp-cleanup‖                if False:  # RULE:M4-tmp-cleanup
@@
m4 cleanup ignores the owner‖unit‖ext_engine.py‖                if os.geteuid() != st.st_uid:  # RULE:M4-owner‖                if False:  # RULE:M4-owner
@@
m4 cleanup ignores the marker‖unit‖ext_engine.py‖                    ok = stat.S_ISREG(st.st_mode) and self._marker_ok(w, full)‖                    ok = stat.S_ISREG(st.st_mode)
@@
m4 wire journal not validated‖unit‖ext_engine.py‖                    or len(ents) > 5000 or any(self._wiring_problem(w) for w in ents):  # RULE:R12-wire-journal‖                    or len(ents) > 5000:  # RULE:R12-wire-journal
@@
catalog: unreadable previous catalog silently dropped‖security‖ext_engine.py‖            if not self.o.get("replace"):\n                raise EngineError(EXIT_VERIFY, "the previous catalog cannot be read‖            if False:\n                raise EngineError(EXIT_VERIFY, "the previous catalog cannot be read
@@
m4 cleanup ignores a live wire owner‖unit‖ext_engine.py‖        if _alive(pid) or pid == os.getpid():  # RULE:M4-live-owner‖        if False:  # RULE:M4-live-owner
@@
B1 @ at a token start not file injection (old narrow rule)‖unit provenance‖ext_engine.py‖re.compile(r"(?<!\w)@(?=\S)"))  # RULE:R21-at-token‖re.compile(r"(?:^|\s)@[\w./~-]*/[\w./~-]"))  # RULE:R21-at-token
@@
B1 @ after punctuation missed (lookbehind widened)‖unit‖ext_engine.py‖re.compile(r"(?<!\w)@(?=\S)"))  # RULE:R21-at-token‖re.compile(r"(?<![^\s])@(?=\S)"))  # RULE:R21-at-token
@@
R22 code-bearing environment variable accepted‖unit‖ext_engine.py‖        elif not env_inert(k):  # RULE:R22-code-env‖        elif False:  # RULE:R22-code-env
+‖‖ext_engine.py‖                     for n in s.get("env_vars") or [] if not env_inert(n)]  # RULE:R22-env-vars‖                     for n in s.get("env_vars") or [] if False]  # RULE:R22-env-vars
@@
R22 consent hides code-bearing env (both layers)‖unit‖ext_engine.py‖            if not env_inert(ev):\n                caps.add("env-code:" + ev)‖            if False:\n                caps.add("env-code:" + ev)
+‖‖ext_engine.py‖                        if not env_inert(k):\n                            caps.add("env-code:%s" % _redact_item(k))‖                        if False:\n                            caps.add("env-code:%s" % _redact_item(k))
@@
M1 output sink does not escape terminal controls‖unit‖ext_engine.py‖        return self._raw.write(term_safe(s))  # RULE:M1-sink‖        return self._raw.write(s)  # RULE:M1-sink
@@
M2 rendered gemini/qwen shim not rescanned‖unit‖ext_engine.py‖                        if rerr:  # RULE:M2-rendered-rescan‖                        if False:  # RULE:M2-rendered-rescan
@@
M3 partial lock reported as written‖provenance‖ext_engine.py‖            self.say("lock PARTIALLY written: %s (%d entr%s refreshed; NOT refreshed, consent needed: %s)"‖            self.say("lock written: %s (%d entr%s refreshed; NOT refreshed, consent needed: %s)"
@@
M4 copy open blocks on a FIFO (no O_NONBLOCK)‖unit‖ext_engine.py‖        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)  # RULE:M4-open-nonblock‖        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)  # RULE:M4-open-nonblock
@@
M4 copy accepts a non-regular file at open time‖unit‖ext_engine.py‖    if not stat.S_ISREG(st.st_mode):  # RULE:M4-open-regular‖    if False:  # RULE:M4-open-regular
@@
M5 deep JSON nesting crashes (RecursionError not caught)‖unit‖ext_engine.py‖        return json.loads(text, object_pairs_hook=pairs)\n    except RecursionError:‖        return json.loads(text, object_pairs_hook=pairs)\n    except ZeroDivisionError:
@@
I3 read-only command recovers and deletes‖unit security chaos‖ext_engine.py‖        if not mutating:  # RULE:I3-read-only-no-recovery‖        if False:  # RULE:I3-read-only-no-recovery
@@
I3 garbage collection runs beside an invalid journal‖unit‖ext_engine.py‖        if self._journal_bad:  # RULE:I3-no-gc-with-bad-journal‖        if False:  # RULE:I3-no-gc-with-bad-journal
@@
I3 trash not named by our journal deleted‖chaos‖ext_engine.py‖                    if m.group(1) == "trash":  # RULE:I3-trash-kept‖                    if False:  # RULE:I3-trash-kept
@@
I2 changed snapshot reused‖unit provenance‖ext_engine.py‖            if os.path.islink(snap) or not os.path.isdir(snap) or command_digest(snap) != w["sha256"]:  # RULE:I2-snap-intact‖            if False:  # RULE:I2-snap-intact
@@
I2 unused snapshots never removed‖unit provenance‖ext_engine.py‖                            and os.path.isdir(sd):  # RULE:I2-snap-gc‖                            and False:  # RULE:I2-snap-gc
@@
I2 changed snapshot not reported by verify‖unit provenance‖ext_engine.py‖            if not good:  # RULE:I2-snap-verify‖            if False:  # RULE:I2-snap-verify
@@
I2 old-format live link not reported by verify‖unit provenance‖ext_engine.py‖            if w.get("sha256") is None:  # RULE:I2-legacy-link‖            if False:  # RULE:I2-legacy-link
@@
I2 interrupted snapshot temp never cleaned‖unit chaos‖ext_engine.py‖                if spat.match(n) and stat.S_ISDIR(st.st_mode) and st.st_uid == os.geteuid():  # RULE:I2-snap-tmp‖                if False:  # RULE:I2-snap-tmp
@@
I2 shim linked to the live tree (no snapshot)‖unit provenance‖ext_engine.py‖                        link = self._link_texts(i, c["name"], rel, dig)[0]‖                        link = self._link_texts(i, c["name"], rel)[0]
@@
I2 snapshot never made‖unit provenance‖ext_engine.py‖                self._ensure_snapshot(w)‖                pass
@@
R11-link-relative (absolute snapshot link text)‖unit provenance‖ext_engine.py‖            return (os.path.relpath(os.path.realpath(self._snap(eid, cmd, digest)), d),)‖            return (os.path.realpath(self._snap(eid, cmd, digest)),)
@@
R22 allow-list not enforced (any program)‖unit security‖ext_engine.py‖        if opts is None:  # RULE:R22-allow-list‖        if False:  # RULE:R22-allow-list
@@
R22 interpreter option allow-list dropped‖unit‖ext_engine.py‖                if args[i] not in opts:  # RULE:R22-interp-option‖                if False:  # RULE:R22-interp-option
@@
R22 interpreter operand not required in-tree‖unit‖ext_engine.py‖                if i >= len(args) or not _intree_file(tree, args[i]):  # RULE:R22-interp-operand‖                if False:  # RULE:R22-interp-operand
@@
R22 executable not required in-tree‖unit‖ext_engine.py‖        if not _intree_file(tree, cmd):  # RULE:R22-intree-exec‖        if False:  # RULE:R22-intree-exec
@@
R22 arguments not plain tokens (both layers)‖unit‖ext_engine.py‖\n                if why:  # RULE:R22-args‖\n                if False:  # RULE:R22-args
+‖‖ext_engine.py‖\n                        if why:  # RULE:R22-args‖\n                        if False:  # RULE:R22-args
@@
R22 environment names not allow-listed‖unit‖ext_engine.py‖        elif k not in (env_vars or ()):  # RULE:R22-env-allow‖        elif False:  # RULE:R22-env-allow
@@
R22 launch-mapping keys not allow-listed‖unit‖ext_engine.py‖        elif not declared and k not in MCP_KEYS:  # RULE:R22-keys‖        elif False:  # RULE:R22-keys
@@
R22 cwd / env file not confined‖unit‖ext_engine.py‖            if not relpath_ok(v):  # RULE:R22-dir-key‖            if False:  # RULE:R22-dir-key
@@
R22 secrets in MCP files accepted‖unit‖ext_engine.py‖        errs += ["%s %s" % (s["file"], x) for x in sec[:20]]  # RULE:R22-secret-walk‖        pass  # RULE:R22-secret-walk
@@
R22 launcher count / size bound dropped‖unit‖ext_engine.py‖        if len(launchers) > MAX_LAUNCHERS or _argv_size(launchers) > MAX_ARGV_BYTES:  # RULE:R22-bounds‖        if False:  # RULE:R22-bounds
@@
R22 launch mappings of the MCP file unchecked‖unit security‖ext_engine.py‖            errs += mcp_launch_problems("%s %s" % (s["file"], where), d, declared, tree, s.get("env_vars"))‖            pass
@@
R22 manifest MCP command unchecked (allow-list layer)‖unit security‖ext_engine.py‖            errs += mcp_command_problems("provides.mcp %s" % s["name"], s["command"], s.get("args"), declared,\n                                         None, tree, s.get("env_vars"))‖            pass
@@
I3 whole tree not part of the consent‖unit security‖ext_engine.py‖        if p.get("hooks") or p.get("mcp") or c.get("executes"):  # RULE:I3-tree-digest‖        if False:  # RULE:I3-tree-digest
@@
I2 wire copy not compared with the lock‖unit‖ext_engine.py‖        if digest_of_hashes(hashes) != e.get("sha256"):  # RULE:I2-copy-matches-lock‖        if False:  # RULE:I2-copy-matches-lock
@@
I2 wire checks run on the live tree (TOCTOU)‖unit‖ext_engine.py‖            cerr = content_problems(stage, m)‖            cerr = content_problems(tree, m)
@@
I2 snapshot is a copy of the live tree (TOCTOU)‖unit‖ext_engine.py‖                cdir = os.path.join(stage, "commands", c["name"])‖                cdir = os.path.join(tree, "commands", c["name"])
@@
I2 verify trusts the stored wiring digest‖unit‖ext_engine.py‖            if w["sha256"] != want:  # RULE:I2-wiring-digest-derived‖            if False:  # RULE:I2-wiring-digest-derived
@@
I2 verify trusts the stored link text‖unit‖ext_engine.py‖            if not os.path.islink(p) or os.readlink(p) != want_link:  # RULE:I2-link-derived‖            if os.path.islink(p) and False:  # RULE:I2-link-derived
@@
I2 verify trusts the stored shim digest‖unit‖ext_engine.py‖        if _sha_file(p) != want_sha:  # RULE:I2-shim-rerender‖        if False:  # RULE:I2-shim-rerender
@@
I2 verify skips the rendered-shim rescan‖unit‖ext_engine.py‖            rerr = self._rendered_problems(m, w["agent"], cmd, _read_nofollow(p, MAX_FILE_BYTES, p))‖            rerr = None
@@
R9 revocation compares versions as strings‖unit‖ext_engine.py‖                hit = r.get("version") == "*" or core(r.get("version")) == core(version)  # RULE:R9-semver‖                hit = r.get("version") == "*" or r.get("version") == version  # RULE:R9-semver
@@
R9 revocation by content digest ignored‖unit‖ext_engine.py‖                hit = digest is not None and r["sha256"] == digest‖                hit = False
@@
R12 rollback removes a tree the journal did not create‖unit‖ext_engine.py‖                    if j.get("ident") is not None and _ident_of(final) == j["ident"]:‖                    if True:
@@
M1 temp-looking directory crashes recovery‖unit‖ext_engine.py‖                    if (stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode)) and st.st_uid == os.geteuid():‖                    if True:
@@
M1 temp file of a live process deleted‖unit‖ext_engine.py‖                if m and int(m.group(1)) <= 4194304 and not _alive(int(m.group(1))):\n                    full‖                if m and int(m.group(1)) <= 4194304:\n                    full
@@
R18 snapshots directory not checked before use‖unit‖ext_engine.py‖            if os.path.lexists(top) and not stat.S_ISDIR(os.lstat(top).st_mode):  # RULE:R18-snapshots-dir‖            if False:  # RULE:R18-snapshots-dir
+‖‖ext_engine.py‖            for dd in (sd, self.p(SNAP_DIR)):  # RULE:R18-snapshots-dir‖            for dd in (sd,):  # RULE:R18-snapshots-dir
@@
Y lone CR accepted by the YAML subset‖unit‖ext_yaml.py‖        if re.search(r"\r(?!‖        if False and re.search(r"\r(?!
@@
I2 stale stage directories never swept‖unit‖ext_engine.py‖                if stat.S_ISDIR(st.st_mode) and st.st_uid == os.geteuid():\n                    self.rm_tree(full, top)‖                if False:\n                    self.rm_tree(full, top)
@@
R7 RM1 in-tree check follows symlinks‖unit‖ext_engine.py‖    mode = os.lstat(cur).st_mode‖    mode = os.stat(cur).st_mode
@@
R7 RM2 --opt=/abs accepted‖unit‖ext_engine.py‖    for part in a.split("="):  # RULE:R22-opt-value‖    for part in a.split("=")[:1]:  # RULE:R22-opt-value
@@
R7 RM3 secret-looking JSON key accepted‖unit‖ext_engine.py‖            if looks_secret(str(k)):\n                out.append(‖            if False:\n                out.append(
@@
R7 RM4 env value path check dropped‖unit‖ext_engine.py‖                                                          or _env_value_ok(k, v)):  # RULE:R22-env-value‖                                                          or True):  # RULE:R22-env-value
@@
R7 RM5 in-tree leaf type unchecked‖unit‖ext_engine.py‖        if last and not (stat.S_ISDIR(mode) if want_dir else stat.S_ISREG(mode)):‖        if False:
@@
R7 env name deny-list instead of allow-list‖unit‖ext_engine.py‖        elif not env_inert(k):  # RULE:R22-code-env‖        elif code_env(k):  # RULE:R22-code-env
+‖‖ext_engine.py‖                     for n in s.get("env_vars") or [] if not env_inert(n)]  # RULE:R22-env-vars‖                     for n in s.get("env_vars") or [] if code_env(n)]  # RULE:R22-env-vars
@@
R7 manifest env_vars unchecked‖unit‖ext_engine.py‖                     for n in s.get("env_vars") or [] if not env_inert(n)]  # RULE:R22-env-vars‖                     for n in s.get("env_vars") or [] if False]  # RULE:R22-env-vars
@@
R7 consent hides env-code (manifest)‖unit‖ext_engine.py‖            if not env_inert(ev):‖            if False:
@@
R7 consent hides env-code (file)‖unit‖ext_engine.py‖                        if not env_inert(k):‖                        if False:
@@
R7 entry shapes unchecked‖unit‖ext_engine.py‖        errs += mcp_shape_problems(doc, s, m)  # RULE:R22-shape‖        pass
@@
R7 stdio entry may carry endpoint keys‖unit‖ext_engine.py‖            if _knorm(k) in _ENDPOINT_NORM and "command" in ent:  # RULE:R22-shape-stdio‖            if False:  # RULE:R22-shape-stdio
@@
R7 remote entry need not be declared‖unit‖ext_engine.py‖        if key != s["name"] or s.get("transport") != "http" or not srv_net:  # RULE:R22-shape-declared‖        if False:  # RULE:R22-shape-declared
@@
R7 remote url form unchecked‖unit‖ext_engine.py‖        if (u.scheme != "https" or "@" in u.netloc or u.query or u.fragment or not u.hostname  # RULE:R22-shape-url‖        if (False  # RULE:R22-shape-url
@@
R7 remote host need not be declared‖unit‖ext_engine.py‖        elif netloc not in {h.lower() for h in srv_net} or netloc not in {h.lower() for h in caps_net}:‖        elif False:
@@
R7 remote header values unchecked‖unit‖ext_engine.py‖            elif not mt or mt.group(1) not in env_vars:‖            elif False:
@@
R7 remote keys unchecked‖unit‖ext_engine.py‖            if k not in REMOTE_KEYS:  # RULE:R22-shape-keys‖            if False:  # RULE:R22-shape-keys
@@
R7 consent hides the endpoint‖unit‖ext_engine.py‖                    caps.add("mcp-endpoint:%s/%s=%s" % (s["name"], _redact_item(key), _redact_item(ent.get("url"))))‖                    pass
@@
R7 consent hides the server key‖unit‖ext_engine.py‖                caps.add("mcp-server:%s/%s" % (s["name"], _redact_item(key)))‖                pass
@@
R7 implicit root walks up from the cwd‖unit‖ext_engine.py‖    cand = os.path.dirname(os.path.dirname(here))\n    if os.path.basename(here)‖    cand = os.path.dirname(os.path.dirname(here))\n    cur = os.getcwd()\n    while cur != "/":\n        for rel in ("constitution", "submodules/constitution"):\n            if _has_constitution(os.path.join(cur, rel)):\n                return os.path.join(cur, rel)\n        cur = os.path.dirname(cur)\n    if os.path.basename(here)
@@
R7 engine location shape unchecked‖unit‖ext_engine.py‖    if os.path.basename(here) == "constitution_ext" and os.path.basename(os.path.dirname(here)) == "scripts" \‖    if True or os.path.basename(here) == "constitution_ext" and os.path.basename(os.path.dirname(here)) == "scripts" \
@@
R7 project not compared with the cwd top level‖unit integration‖ext_engine.py‖    if top is None or top != os.path.realpath(project):  # RULE:R23-project-is-cwd‖    if False:  # RULE:R23-project-is-cwd
@@
R7 cwd check not wired into acquire‖integration‖ext_engine.py‖            if mutating:\n                _check_project_is_cwd_toplevel‖            if False:\n                _check_project_is_cwd_toplevel
@@
R7 duplicate JSON keys accepted‖unit‖ext_engine.py‖            if k in out:  # RULE:R22-dup-key‖            if False:  # RULE:R22-dup-key
@@
R7 catalog revoked version unchecked‖unit‖ext_engine.py‖not (r.get("version") == "*" or is_semver(r.get("version")))‖not isinstance(r.get("version"), str)
@@
R7 copy follows symlinked directories‖unit‖ext_engine.py‖            if stat.S_ISLNK(os.lstat(os.path.join(dp, d)).st_mode):  # RULE:R2-copy-symlink-dir‖            if False:  # RULE:R2-copy-symlink-dir
@@
R7 copy file bounds dropped‖unit‖ext_engine.py‖            if n_files > MAX_FILES or n_bytes > MAX_TREE_BYTES or st.st_size > MAX_FILE_BYTES:‖            if False:
@@
R7 copy depth bound dropped‖unit‖ext_engine.py‖        if rel != "." and rel.count(os.sep) + 1 > MAX_TREE_DEPTH:  # RULE:R2-copy-bounds‖        if False:  # RULE:R2-copy-bounds
@@
R7 copy dir bound dropped‖unit‖ext_engine.py‖        if n_dirs > MAX_DIRS:‖        if False:
@@
E1r1 CH1 enable shortcut ignores the consent list‖reviewfix‖ext_engine.py‖        if e.get("enabled") and (e.get("consent") or {}).get("capabilities") == caps and not rp \\n‖        if e.get("enabled") and True and not rp \\n
@@
E1r1 RJ2 commit-journal recovery deletes records of ids still in the lock‖reviewfix‖ext_engine.py‖                if i not in lock:\n                    self.delete_record(i)‖                if True:\n                    self.delete_record(i)
@@
E1r1 PC2 aux dirname arm dropped (journal check + rename bound)‖unit reviewfix‖ext_engine.py‖if not isinstance(aux, str) or os.path.dirname(aux) != self.inst_dir \\n‖if not isinstance(aux, str) or False \\n
+‖‖ext_engine.py‖                    if os.path.dirname(aux) == self.inst_dir and os.path.dirname(final) == self.inst_dir \\n‖                    if True \\n
@@
E1r1 PC3 recovery rename accepts a link / foreign owner‖unit reviewfix‖ext_engine.py‖                        ok_aux = stat.S_ISDIR(st.st_mode) and st.st_uid == os.geteuid()‖                        ok_aux = True
@@
E1r1 EA2 http(s) value allowed in any env name‖unit‖ext_engine.py‖    if isinstance(name, str) and ENV_URLISH_RE.fullmatch(name) and v.startswith(("http://", "https://")):‖    if isinstance(name, str) and v.startswith(("http://", "https://")):
@@
E1r1 PC1 _rel_ok drops the .. arms‖unit‖ext_engine.py‖        and r != ".." and not r.startswith("../") and not bad_chars(r)‖        and not bad_chars(r)
@@
E1r1 F6a copy reads a growing file past the per-file cap‖unit‖ext_engine.py‖                    if got > MAX_FILE_BYTES or n_bytes - st.st_size + got > MAX_TREE_BYTES:‖                    if got > MAX_FILE_BYTES * 0 + 10**12 or n_bytes - st.st_size + got > MAX_TREE_BYTES:
@@
E1r1 F6b copy reads a growing file past the tree cap‖unit‖ext_engine.py‖                    if got > MAX_FILE_BYTES or n_bytes - st.st_size + got > MAX_TREE_BYTES:‖                    if got > MAX_FILE_BYTES or n_bytes - st.st_size + got > 10**12:
@@
E1r8 S1 remove-journal identity not compared‖unit round9‖ext_engine.py‖        return isinstance(ident, list) and _ident_of(aux) == ident‖        return True
@@
E1r8 S1 remove journal records no identity‖unit round9‖ext_engine.py‖        if os.path.lexists(final) and _ident_of(final) is not None:  # RULE:S1-ident‖        if False and _ident_of(final) is not None:  # RULE:S1-ident
@@
E1r8 M1 aux rename drops the trash-name check‖unit‖ext_engine.py‖                or not TRASH_RE.match(os.path.basename(aux)):\n            return False‖                or False:\n            return False
@@
E1r8 M3 aux rename drops the final-in-installed check‖unit‖ext_engine.py‖        if os.path.dirname(aux) != self.inst_dir or os.path.dirname(final) != self.inst_dir \‖        if os.path.dirname(aux) != self.inst_dir \
@@
E1r8 S1 staging sweep drops the owner check‖unit‖ext_engine.py‖ and os.lstat(full).st_uid == os.geteuid():  # RULE:S1-sweep-owner‖:  # RULE:S1-sweep-owner
@@
E1r8 M4a per-file cap off by one (copy loop)‖unit‖ext_engine.py‖                    if got > MAX_FILE_BYTES or n_bytes‖                    if got >= MAX_FILE_BYTES or n_bytes
@@
E1r8 M4b per-file cap off by one (size check)‖unit‖ext_engine.py‖            if n_files > MAX_FILES or n_bytes > MAX_TREE_BYTES or st.st_size > MAX_FILE_BYTES:‖            if n_files > MAX_FILES or n_bytes > MAX_TREE_BYTES or st.st_size >= MAX_FILE_BYTES:
@@
E1r8 M5 growing file counted twice against the tree cap‖unit‖ext_engine.py‖n_bytes - st.st_size + got > MAX_TREE_BYTES:‖n_bytes + got > MAX_TREE_BYTES:
@@
E1r8 M6 copy loop drops both hard-link checks (lstat + fstat)‖unit‖ext_engine.py‖            if not stat.S_ISREG(st.st_mode) or st.st_nlink > 1:\n                raise EngineError(EXIT_REFUSED, "%s: not a single-link‖            if not stat.S_ISREG(st.st_mode):\n                raise EngineError(EXIT_REFUSED, "%s: not a single-link
+‖‖ext_engine.py‖fst.st_nlink > 1 \‖False \
@@
E1r8 S2 opened file need not be the one lstat described‖unit‖ext_engine.py‖                    or (fst.st_dev, fst.st_ino) != (st.st_dev, st.st_ino):‖                    or False:
@@
E1r8 M8 enable shortcut ignores a missing local record‖unit‖ext_engine.py‖get("capabilities") == caps and not rp \‖get("capabilities") == caps \
EOF

apply_mut() { # copy_dir name — applies every replacement of mutation NAME; returns 1 if an anchor is not unique
  python3 -I - "$MUTS" "$1" "$2" <<'PY'
import sys
muts, d, name = sys.argv[1:4]
blocks = open(muts).read().split("\n@@\n")
for b in blocks:
    rows = [r for r in b.strip("\n").split("\n") if r]
    if not rows or rows[0].split("\u2016")[0] != name:
        continue
    for r in rows:
        f = r.split("\u2016")
        fname, old, new = f[2], f[3].replace("\\n", "\n"), f[4].replace("\\n", "\n")
        p = "%s/scripts/constitution_ext/%s" % (d, fname)
        s = open(p).read()
        if s.count(old) != 1:
            print("anchor matched %d times in %s: %r" % (s.count(old), fname, old[:80])); sys.exit(1)
        open(p, "w").write(s.replace(old, new))
    sys.exit(0)
print("no such mutation " + name); sys.exit(1)
PY
}

names="$(python3 -I -c 'import sys; [print(b.strip().split("\n")[0].split("\u2016")[0]) for b in open(sys.argv[1]).read().split("\n@@\n") if b.strip()]' "$MUTS")"
want=("$@")

# control: the unmutated copy passes every suite any mutation uses
mk_copy "$SB/control"
bad="$(run_suites "$SB/control" unit security e2e chaos integration attacks provenance reviewfix)"
eq "control: unmutated copy passes unit security e2e chaos integration attacks provenance reviewfix" "" "$bad"

killed=0; survived=0; broken=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if [ "${#want[@]}" -gt 0 ]; then case " ${want[*]} " in *" $name "*) ;; *) continue;; esac; fi
  suites="$(python3 -I -c 'import sys
for b in open(sys.argv[1]).read().split("\n@@\n"):
    r = b.strip().split("\n")[0].split("\u2016")
    if r[0] == sys.argv[2]: print(r[1])' "$MUTS" "$name")"
  d="$SB/m$((killed+survived+broken))"; mk_copy "$d"
  if ! msg="$(apply_mut "$d" "$name")"; then broken=$((broken+1)); nok "BROKEN mutation [$name]: $msg"; continue; fi
  # shellcheck disable=SC2086
  bad="$(run_suites "$d" $suites)"
  if [ -n "$bad" ]; then killed=$((killed+1)); ok "KILLED [$name] by:$bad"
  else survived=$((survived+1)); nok "SURVIVED [$name] (suites: $suites)"; fi
  chmod -R u+w "${d:?}" 2>/dev/null; safe_rm_rf "${d:?}"
done <<<"$names"
echo "mutations: killed $killed survived $survived broken $broken"
finish
