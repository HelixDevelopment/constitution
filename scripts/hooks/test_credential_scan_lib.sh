#!/usr/bin/env bash
# =============================================================================
# test_credential_scan_lib.sh — self-validating fixtures for the project-agnostic
# credential-scan library (credential_scan_lib.sh). §11.4.201 / §11.4.107(10):
# a guard that false-POSITIVEs is a FAIL-bluff exactly as a false-NEGATIVE pass
# is a PASS-bluff — so this suite pins BOTH directions with golden fixtures.
#
# GOLDEN-GOOD (MUST all be CLEAN — no false positive on a legitimate carrier):
#   (a) a git@github.com:org/repo SSH remote line,
#   (b) a `user@1000.service was SIGKILLed (status=9/KILL)` §12 forensic note,
#   (c) an Android `clientId=...AudioManager@...AudioManager$$Synthetic...@hex`
#       logcat object reference,
#   (d) a BINARY `*.db` blob embedding an email + a password-shaped token
#       (proves the .db binary-skip prevents the detector-2 false positive),
#   (i) a `PASSWORD=CHANGE_ME` / `api_key=PLACEHOLDER` config-template line
#       (carrier-strip #8a placeholder-value allowlist),
#   (j) a `SECRET=…must_not_leak…` test-fixture sentinel (carrier-strip #8a),
#   (k) a `data:image/png;base64,<blob>` whose base64 image bytes randomly
#       contain an AKIA-shaped run (carrier-strip #8b base64-image data-URI).
# GOLDEN-BAD (MUST all be CAUGHT — real leaks):
#   (1) `user@company.com : S3cretPass99`  (email+password adjacency, lc TLD),
#   (2) `api_key=AKIA...`                    (known-token + keyword-assignment),
#   (3) `password: hunter2hunter2`           (keyword-anchored assignment),
#   (4) `-----BEGIN OPENSSH PRIVATE KEY-----`(private-key marker),
#   (5) `AIza<35 chars>`                     (Google-API-key format).
#
# A golden-bad that is NOT caught means the library WEAKENED the gate (a release
# blocker); a golden-good that IS caught means a §11.4.201 false-positive.
#
# Usage:        bash constitution/scripts/hooks/test_credential_scan_lib.sh
# Inputs:       none (builds fixtures in a mktemp dir; touches nothing tracked).
# Outputs:      one PASS/FAIL line per case; exit 0 iff EVERY case passes.
# Side-effects: creates + removes a mktemp dir (trap … EXIT).
# Dependencies: bash, grep, awk.
# Cross-refs:   credential_scan_lib.sh (system under test); §11.4.10 / §11.4.201 /
#               §11.4.107(10) / §1.1.
#
# SECURITY: uses ONLY SYNTHETIC fake credentials. NO real leaked value appears.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
LIB="$HERE/credential_scan_lib.sh"
if [ ! -f "$LIB" ]; then
    echo "FATAL: library under test not found: $LIB" >&2
    exit 2
fi
# §11.4.201(4) / §11.4.1 PARSE guard — an UNLOADABLE library must exit 2
# (harness-broken), NEVER 1 (a real fixture FAIL). A syntactically-broken
# library that sources anyway carries on and reports every golden-bad as
# MISSED — a §11.4.1 FAIL-bluff (the 2026-07-17 apostrophe-in-awk incident).
# bash -n BEFORE sourcing.
if ! bash -n "$LIB" 2>/dev/null; then
    echo "FATAL: library under test does not parse (bash -n): $LIB" >&2
    exit 2
fi
# shellcheck source=/dev/null
. "$LIB"
# §11.4.201(4) LOAD guard — both detectors MUST be non-empty after sourcing
# (a library that parsed but defined no HELIX_CRED_VALUE_PATTERN /
# HELIX_CRED_ADJACENCY_AWK is harness-broken, not a fixture regression).
# exit 2, NEVER 1.
if [ -z "${HELIX_CRED_VALUE_PATTERN:-}" ] || [ -z "${HELIX_CRED_ADJACENCY_AWK:-}" ]; then
    echo "FATAL: credential detectors empty after sourcing (HELIX_CRED_VALUE_PATTERN / HELIX_CRED_ADJACENCY_AWK): $LIB" >&2
    exit 2
fi

pass=0
fail=0
ok()  { echo "PASS: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/credscan_lib_test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# assert_clean <name> <path> : helix_cred_scan_file MUST return 1 (clean).
assert_clean() {
    if helix_cred_scan_file "$2"; then
        bad "$1 — FALSE POSITIVE (reported credential; expected clean)"
    else
        ok  "$1 — clean (no false positive)"
    fi
}
# assert_caught <name> <path> : helix_cred_scan_file MUST return 0 (found).
assert_caught() {
    if helix_cred_scan_file "$2"; then
        ok  "$1 — caught (real leak detected)"
    else
        bad "$1 — MISSED (expected credential caught; gate WEAKENED)"
    fi
}

echo "== credential_scan_lib.sh — self-validating golden fixtures =="
echo "   (throwaway dir: $WORK)"
echo ""

# --- GOLDEN-GOOD ------------------------------------------------------------
cat > "$WORK/good_a_git_remote.txt" <<'EOF'
# Git remotes
- github / upstream: git@github.com:ATMOSphere1234321/ATMOSphere-Android-15.git
- origin: git@github.com:vasic-digital/Android-15-AOSP.git
EOF
assert_clean "(a) git SSH remote URLs" "$WORK/good_a_git_remote.txt"

cat > "$WORK/good_b_systemd.txt" <<'EOF'
# Host-session safety incident
The developer's user@1000.service was again SIGKILLed (status=9/KILL) while a
Phase 17 AOSP rebuild was in flight. No kernel OOM kill in dmesg for this boot.
EOF
assert_clean "(b) systemd user@N.service forensic note" "$WORK/good_b_systemd.txt"

cat > "$WORK/good_c_java_ref.txt" <<'EOF'
07-16 10:30:00.123  MediaFocusControl: clientId=android.media.AudioManager@android.media.AudioManager$$ExternalSyntheticLambda13@a1b2c3 requested focus
EOF
assert_clean "(c) Android object reference @pkg.CamelCaseClass" "$WORK/good_c_java_ref.txt"

# (d) BINARY .db blob: embed an email adjacent to a password-shaped token AND
# real NUL bytes so the file is genuinely binary. If detector-2 ran on this as
# TEXT it WOULD fire — the .db binary-skip is what makes it clean, so this
# fixture proves the skip is load-bearing (§11.4.201).
printf 'SQLite format 3\000\000admin@example.com S3cretDbToken99\000\000rows\000' > "$WORK/good_d_binary.db"
assert_clean "(d) binary .db with embedded email+token (binary-skip)" "$WORK/good_d_binary.db"

# (e) §11.4.201 carrier-strip #5: a Markdown-emphasized plain WORD adjacent to an
# email in bug-report prose is emphasis, not a password. Forensic FP:
# docs/Issues.md:3794 "abkmusic64@gmail.com ... **BROWSERS**".
cat > "$WORK/good_e_markdown_word.txt" <<'EOF'
- **Bug 12** (`abkmusic64@gmail.com`) now logs in on **ALL BROWSERS** but *fails* on `code`.
EOF
assert_clean "(e) markdown-emphasized word near email (**BROWSERS**)" "$WORK/good_e_markdown_word.txt"

# (f) §11.4.201 carrier-strip #6: a long PROSE line where an email co-occurs with
# DISTANT technical tokens (config keys, code identifiers, product names) is not a
# credential — the password of a real email:pass leak is IMMEDIATELY adjacent.
# Forensic FP: docs/Issues.md:3794 attestation discussion.
cat > "$WORK/good_f_distant_tokens.txt" <<'EOF'
Tester abkmusic64@gmail.com now logs in on all browsers but still fails on D3; MYSOC1 verified_boot_state=UNVERIFIED device_locked=false DRM-L3 Handset-8 persist.myvendor.attest.device_keybox=true remains the blocker.
EOF
assert_clean "(f) email + distant technical tokens (proximity window)" "$WORK/good_f_distant_tokens.txt"

# (g) detector-1 carrier-strip: a recognised secret KEYWORD followed by a
# separator whose VALUE is an XML/localization PLACEHOLDER (starts with '<' or
# '%') is a UI label, not a secret. Forensic FP: AOSP Settings
# "Wi-Fi password: <xliff:g id="password">%1$s</xliff:g>".
cat > "$WORK/good_g_xliff_placeholder.xml" <<'EOF'
    <string name="wifi_dpp_wifi_password">Wi-Fi password: <xliff:g id="password" example="my password">%1$s</xliff:g></string>
EOF
assert_clean "(g) keyword: <xliff placeholder> (UI label, not a secret)" "$WORK/good_g_xliff_placeholder.xml"

# (h) detector-1 carrier-strip: a recognised secret KEYWORD followed by a
# separator whose VALUE is a shell/jq VARIABLE REFERENCE (starts with '$') is a
# reference, never a literal secret. Forensic FP: docs prose quoting
# "password=$SMB_PASS" / "api_key:$ENV.CMA_TOK".
cat > "$WORK/good_h_var_ref.txt" <<'EOF'
SMB mount uses password=$SMB_PASS and the jq writer emits api_key:$ENV.CMA_TOK for the provider.
EOF
assert_clean "(h) keyword=\$VAR / keyword:\$ENV.x (variable reference, not a secret)" "$WORK/good_h_var_ref.txt"

# (i) §11.4.201 carrier-strip #8a: a recognised secret KEYWORD whose VALUE is a
# config-template placeholder (CHANGE_ME / PLACEHOLDER) is a template token, not a
# secret. Origin carrier: CONFIG_TEMPLATES.md "PASSWORD=CHANGE_ME".
cat > "$WORK/good_i_placeholder.env" <<'EOF'
# config template — fill these in per deployment
PASSWORD=CHANGE_ME
JWT_SECRET=CHANGE_ME
api_key=PLACEHOLDER
DB_PASSWORD=changeme
EOF
assert_clean "(i) keyword=CHANGE_ME / PLACEHOLDER (config-template placeholder)" "$WORK/good_i_placeholder.env"

# (j) §11.4.201 carrier-strip #8a: a test-fixture marker value (…must_not_leak…) is
# never a real secret. Origin carrier: test_helix_code_phase1_unit.sh "must_not_leak".
cat > "$WORK/good_j_must_not_leak.txt" <<'EOF'
# unit-test fixtures — synthetic sentinel values, never real credentials
SECRET=supersecret_must_not_leak
password: must_not_leak_dummy_value
EOF
assert_clean "(j) keyword=...must_not_leak... (test-fixture sentinel marker)" "$WORK/good_j_must_not_leak.txt"

# (k) §11.4.201 carrier-strip #8b: a base64 image data-URI blob RANDOMLY contains a
# token-shaped substring (here an AKIA[0-9A-Z]{16} run embedded in the base64 image
# bytes). Without the data-URI strip detector-1 WOULD flag it — the strip is what
# makes it clean, so this fixture proves the strip is load-bearing (§11.4.201).
# Origin carrier: DEEP_HELIXOTA base64 avatar/image data-URI. The blob is built
# deterministically so the embedded AKIA token is exactly the right shape.
{ printf 'avatar_data: data:image/png;base64,'
  printf 'iVBORw0KGgoAAAANSUhEUg'      # ordinary base64 image-header bytes
  printf 'AKIA0123456789ABCDEF'        # AKIA + 16 [0-9A-Z] chars, embedded in blob
  printf 'moreImageBytesHere+/=='      # trailing base64 image bytes
  printf '\n'
} > "$WORK/good_k_base64_image.txt"
assert_clean "(k) data:image/png;base64,<blob with token-shaped substring> (image data)" "$WORK/good_k_base64_image.txt"

# (m) §11.4.201 carrier-strip #9: the `sk-` OpenAI-key sub-pattern is only TWO
# letters + a hyphen, so WITHOUT a left token boundary it matches the TAIL of any
# identifier ending in "sk" that is followed by '-' and 20+ alphanumerics. Forensic
# FP: an Android `pm path` capture line
# ".../com.example.mediakiosk-<install-token>==/base.apk" — the "sk" is the tail
# of the package name "mediakio[sk]" and the base64url install-token supplies the
# 20+ chars. Any package ending in "…sk" (kiosk, disk, task, desk) trips it. The
# left-boundary `(^|[^0-9A-Za-z])` is what makes this clean, so this fixture proves
# the boundary is load-bearing (§11.4.201(7)(a) carrier-vs-thing).
cat > "$WORK/good_m_pkgpath_sk.txt" <<'EOF'
package:/data/app/~~U4OsJn3zzcMyh-sRkefkGQ==/com.example.mediakiosk-qz5gs3AbCdEfGhIjKlMnOp==/base.apk
package:/data/app/~~U4OsJn3zzcMyh-sRkefkGQ==/com.example.clouddisk-Zx9WvUt7SrQpOnMlKjIh==/split_config.en.apk
EOF
assert_clean "(m) Android pm-path '…mediakiosk-<token>' (sk- left-boundary carrier)" "$WORK/good_m_pkgpath_sk.txt"

# §11.4.201 carrier-strip #8a-ELLIPSIS. A `# Usage` comment documenting how to
# invoke a script with a token — `ANTHROPIC_API_KEY=sk-ant-... <cmd>` — is a
# DOC PLACEHOLDER whose secret characters are LITERALLY ABSENT (replaced by an
# ellipsis), never a real secret. Forensic FP (2026-08-19): this exact line in a
# tracked extension script REFUSED every commit repo-wide. The strip requires a
# `[_-]` separator immediately before the dots, so the no-separator forms in
# golden-bad (9)/(9a) below still SURVIVE and are still flagged — the fixture
# pair proves the strip is TIGHT, not a blanket ellipsis exemption.
cat > "$WORK/good_n_doc_ellipsis.sh" <<'EOF'
#!/usr/bin/env bash
# Environment
#   ANTHROPIC_API_KEY     required (unless E2E_DRY_RUN=1)
#
# Usage
#   ANTHROPIC_API_KEY=sk-ant-... bash scripts/e2e-agent-claude.sh
#
  if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -n "${CI:-}" ]; then
    printf 'ANTHROPIC_API_KEY not set in CI environment.\n'; exit 1
  fi
api_key=sk-...
access_token=ghp_...
EOF
assert_clean "(n) doc-ellipsis placeholder 'API_KEY=sk-ant-...' (truncated-prefix carrier)" "$WORK/good_n_doc_ellipsis.sh"

echo ""
# --- GOLDEN-BAD -------------------------------------------------------------
cat > "$WORK/bad_1_email_pw.txt" <<'EOF'
Service login for the AVR test account:
  user@company.com : S3cretPass99
EOF
assert_caught "(1) email+password adjacency (lowercase TLD)" "$WORK/bad_1_email_pw.txt"

cat > "$WORK/bad_2_akia.txt" <<'EOF'
export api_key=AKIA1234567890ABCDEF
EOF
assert_caught "(2) AKIA + api_key= assignment" "$WORK/bad_2_akia.txt"

cat > "$WORK/bad_3_password.txt" <<'EOF'
db:
  password: hunter2hunter2
EOF
assert_caught "(3) keyword-anchored password: assignment" "$WORK/bad_3_password.txt"

cat > "$WORK/bad_4_privkey.txt" <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAAB
-----END OPENSSH PRIVATE KEY-----
EOF
assert_caught "(4) OPENSSH PRIVATE KEY marker" "$WORK/bad_4_privkey.txt"

# Build the Google-API-key fixture: AIza + exactly 35 chars (39 total) so it
# matches AIza[0-9A-Za-z_-]{35}. Hand-typed literals risk an off-by-one that
# would silently WEAKEN the gate, so generate the 35-char run deterministically.
{ printf 'gmaps_key=AIza'; printf 'x%.0s' {1..35}; printf '\n'; } > "$WORK/bad_5_aiza.txt"
assert_caught "(5) AIza Google-API-key format (39 chars)" "$WORK/bad_5_aiza.txt"

# (6) proximity-window MUST NOT over-narrow: a real password IMMEDIATELY adjacent
# to an email (within the §11.4.201 carrier-strip #6 window) MUST still be caught.
# This pins that carrier-strip #6 tightened the scan WITHOUT weakening real-leak
# detection — the paired §1.1 mutation (widening the window to scan whole prose
# lines re-introduces the FP; narrowing it below the compact leak form fails THIS).
cat > "$WORK/bad_6_adjacent_pw.txt" <<'EOF'
AVR account: tester@company.com / Tr0ub4dor3Special!
EOF
assert_caught "(6) real password adjacent to email (window not over-narrow)" "$WORK/bad_6_adjacent_pw.txt"

# (l) §11.4.201(1) MID-LINE placeholder (the raw-grep-bypass forensic, 2026-07-28):
# a recognised secret KEYWORD=PLACEHOLDER appearing MID-LINE inside a doc / JSONL
# registry / tracker-item that QUOTES it as the example (a self-referential
# carrier — the credscan-fix tracker item quotes `PASSWORD=CHANGE_ME`). detector-1
# uses `grep -Eio`, so the EXTRACTED MATCH is `PASSWORD=CHANGE_ME` (not the whole
# line) and #8a strips it — MUST be CLEAN. A raw `grep -Eiq value_pattern` in a
# consumer bypasses #8a and false-positive-REFUSES this; every stream consumer is
# therefore required to route through helix_cred_detector1_real_hit_stream.
cat > "$WORK/good_l_midline_placeholder.txt" <<'EOF'
{"ts":"2026-07-27T21:50:46Z","event":"complete","label":"(T1/main - claude4) credscan false-positive on legit PASSWORD=CHANGE_ME example"}
The task quotes the placeholder api_key=PLACEHOLDER in prose to describe the fix.
EOF
assert_clean "(l) MID-LINE keyword=PLACEHOLDER in doc/registry prose (self-referential carrier)" "$WORK/good_l_midline_placeholder.txt"

echo ""
# (7) FALSE-NEGATIVE GUARD (§11.4.201(2)): a line carrying BOTH a real secret AND a
# placeholder MUST still be CAUGHT — the mid-line #8a strip removes ONLY the
# placeholder match; the real-secret match survives. If this ever MISSES, the fix
# WEAKENED the gate (a release blocker). This is the paired guard for (l).
cat > "$WORK/bad_7_real_plus_placeholder.txt" <<'EOF'
db: password: hunter2hunter2realleak  note: fill PASSWORD=CHANGE_ME in prod
EOF
assert_caught "(7) real secret + placeholder on ONE line (mid-line strip must not leak the real one)" "$WORK/bad_7_real_plus_placeholder.txt"

# (8) FALSE-NEGATIVE GUARD for carrier-strip #9 (§11.4.201(2)): a REAL `sk-` key
# ALWAYS stands at a token boundary — the character immediately before `sk-` is
# NON-ALPHANUMERIC (or the key is at line start). The shipped left-boundary is the
# CLASS `(^|[^0-9A-Za-z])`, so this guard pins the CLASS BY CONSTRUCTION rather
# than by a hand-picked sample: the fixture set is PROGRAMMATICALLY ENUMERATED
# over EVERY printable-ASCII non-alphanumeric byte (0x20..0x7E minus [0-9A-Za-z]
# = space + the 32 punctuation/symbol characters), plus line-start, plus a literal
# TAB, plus a control character and a high-byte (UTF-8 «) form. A hand-typed list
# could only ever be a SAMPLE, and a mutation narrowing the shipped class to
# exactly the sampled characters would survive it — the precise regression this
# guard exists to catch (§11.4.115(F): the fixtures must catch the boundary's own
# negation, not merely agree with it). Because the ASCII sweep is generated, ANY
# narrowing of the printable-ASCII class now fails BY CONSTRUCTION — the reviewer's
# M-R1 `(^|[ ="_])`, M-F1 `(^|[<TAB> ="'_:/,(.;>-])` (the exact prior fixture list)
# and M-F2 `(^|[[:punct:][:space:]])` mutations ALL make this suite FAIL.
# HONEST BOUNDARY (§11.4.6): the sweep is exhaustive over PRINTABLE ASCII only.
# The non-printable + high-byte domain is NOT exhaustively enumerated (it is
# unbounded and locale-dependent); it is covered by the two REPRESENTATIVE forms
# below — a C0 control byte (neither [:punct:] nor [:space:] in ANY locale, so it
# is the universal M-F2 killer) and a UTF-8 high-byte guillemet (which additionally
# escapes `[[:punct:]]` under LC_ALL=C). Every form MUST still be CAUGHT. If any
# MISSES, the left-boundary WEAKENED the gate (a release blocker). This is the
# paired guard for (m); a fix that makes (m) clean by dropping the `sk-`
# alternative entirely dies HERE.
_SK_KEY='sk-qz5gs3AbCdEfGhIjKlMnOp'
: > "$WORK/bad_8_sk_boundary.txt"
# form 1 — line start (the `^` branch of the shipped alternation).
printf '%s\n' "$_SK_KEY" >> "$WORK/bad_8_sk_boundary.txt"
# forms 2..34 — EVERY printable-ASCII non-alphanumeric byte, generated. The
# alphanumeric skip-set is spelled out CHARACTER BY CHARACTER (never the ranges
# `[0-9A-Za-z]`) because a bracket RANGE in a case-glob is collation-dependent in
# a UTF-8 locale and could silently skip a punctuation byte — a locale-dependent
# hole in the very sweep that proves the class (§11.4.201(7)(c): the path is part
# of the instrument).
_sk_c=32
while [ "$_sk_c" -le 126 ]; do
    _sk_ch=$(printf "\\$(printf '%03o' "$_sk_c")")
    case "$_sk_ch" in
        [0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz])
            _sk_c=$((_sk_c + 1)); continue ;;
    esac
    printf '%s%s\n' "$_sk_ch" "$_SK_KEY" >> "$WORK/bad_8_sk_boundary.txt"
    _sk_c=$((_sk_c + 1))
done
# form 35 — literal TAB, emitted via printf (NEVER a heredoc) so the separator
# stays a REAL tab: an editor that re-indents a fixture file silently converts an
# in-heredoc tab into spaces, degrading this form into the already-covered space
# form — a silent class-coverage loss the suite could not see (§11.4.201(6)).
printf '\t%s\n' "$_SK_KEY" >> "$WORK/bad_8_sk_boundary.txt"
# form 36 — C0 control byte (0x01). Non-printable, so outside the generated sweep;
# it is neither [:punct:] nor [:space:] in ANY locale, making it the form that
# kills a `[[:punct:][:space:]]` narrowing everywhere.
printf '\001%s\n' "$_SK_KEY" >> "$WORK/bad_8_sk_boundary.txt"
# form 37 — high-byte UTF-8 guillemet « (0xC2 0xAB). Outside the ASCII sweep; under
# LC_ALL=C its lead byte is not [:punct:] either, so it kills the same narrowing
# in the C locale even where the UTF-8 locale would classify « as punctuation.
printf '\302\253%s\n' "$_SK_KEY" >> "$WORK/bad_8_sk_boundary.txt"
assert_caught "(8) real sk- key at token boundary, non-alphanumeric CLASS spread (boundary must not weaken)" "$WORK/bad_8_sk_boundary.txt"
# Per-form guard: assert_caught passes if ANY line hits, so pin EACH form
# individually — a boundary that only catches 1 of N must not read as GREEN.
# (8b) pins the FILE-level contract (helix_cred_scan_file = detector-1 OR
# detector-2); (8c) pins the SAME forms at the DETECTOR-1 layer, where the
# left-boundary actually lives — without (8c) a future broadening of detector-2
# (email-adjacency) could start catching these lines for an unrelated reason and
# silently mask a detector-1 boundary regression (§11.4.115(F) unvalidated
# instrumentation: the assertion must remain load-bearing on the thing it names).
_sk_form_n=0; _sk_form_miss=0; _sk_d1_miss=0
while IFS= read -r _sk_line; do
    _sk_form_n=$((_sk_form_n + 1))
    printf '%s\n' "$_sk_line" > "$WORK/bad_8_form_$_sk_form_n.txt"
    helix_cred_scan_file "$WORK/bad_8_form_$_sk_form_n.txt" || _sk_form_miss=$((_sk_form_miss + 1))
    printf '%s\n' "$_sk_line" | helix_cred_detector1_real_hit_stream || _sk_d1_miss=$((_sk_d1_miss + 1))
done < "$WORK/bad_8_sk_boundary.txt"
# (8a) GENERATOR SELF-CHECK (§11.4.201(6) false-null guard). (8b)/(8c) below
# assert "zero MISSES", which a generator emitting ZERO forms would satisfy
# VACUOUSLY — a blind instrument returning the same quiet zero as a healthy one.
# Pin the exact expected form count so a silently-empty or silently-truncated
# sweep FAILS here instead of passing everything downstream:
#   1 line-start
# + 33 printable-ASCII non-alphanumeric (0x20..0x7E is 95 chars, minus the 62
#      alphanumerics = 33: the space plus the 32 punctuation/symbol characters)
# + 1 TAB + 1 C0 control byte + 1 high-byte UTF-8 guillemet
# = 37 forms.
_sk_form_expected=37
if [ "$_sk_form_n" -eq "$_sk_form_expected" ]; then
    ok  "(8a) boundary-form generator emitted all $_sk_form_expected forms (sweep not empty/truncated)"
else
    bad "(8a) boundary-form generator emitted $_sk_form_n forms, expected $_sk_form_expected (sweep BROKEN — (8b)/(8c) below would pass vacuously)"
fi
if [ "$_sk_form_miss" -eq 0 ]; then
    ok  "(8b) each of the $_sk_form_n real sk- boundary forms caught individually (file scanner)"
else
    bad "(8b) $_sk_form_miss/$_sk_form_n real sk- boundary forms MISSED (gate WEAKENED)"
fi
if [ "$_sk_d1_miss" -eq 0 ]; then
    ok  "(8c) each of the $_sk_form_n real sk- boundary forms caught by DETECTOR-1 (left-boundary class)"
else
    bad "(8c) $_sk_d1_miss/$_sk_form_n real sk- boundary forms MISSED by detector-1 (left-boundary WEAKENED)"
fi

echo ""
# §11.4.201(2) TIGHTENING GUARD for carrier-strip #8a-ELLIPSIS. The strip admits
# ONLY the truncated-PREFIX idiom (`<stub><_->...`). A value whose ellipsis is NOT
# preceded by a `_`/`-` separator is an AMBIGUOUS shape and MUST stay flagged
# (fail-closed). These two fixtures prove the ellipsis strip cannot be widened
# into a blanket "anything ending in dots is a placeholder" exemption.
cat > "$WORK/bad_9_ellipsis_no_sep.txt" <<'EOF'
password=hunter2hunter2...
EOF
assert_caught "(9) real-looking secret with trailing dots, NO separator (ellipsis strip must not fire)" "$WORK/bad_9_ellipsis_no_sep.txt"

cat > "$WORK/bad_9a_ellipsis_alnum_sep.txt" <<'EOF'
api_key=abc123def456...
EOF
assert_caught "(9a) alnum value with trailing dots, NO separator (ellipsis strip must not fire)" "$WORK/bad_9a_ellipsis_alnum_sep.txt"

# --- STREAM DETECTOR CONTRACT (the entry point every STREAM consumer calls) ----
# helix_cred_detector1_real_hit_stream reads STDIN. Exit 1 = clean, 0 = hit. The
# file scanner delegates to it; a consumer that scans a STREAM (a `git show` in a
# commit hook, a captured evidence stream) calls it directly — pin its contract
# here so a regression in either path is caught.
# CONSUMER FACTS (§11.4.6, measured in THIS checkout 2026-09-08): the seams that
# actually source this library are constitution/scripts/gates/lib/execution_record.sh
# (`_xr_redact`, the §11.4.268 evidence-stream redactor) and a second checkout at
# submodules/claude-toolkit/constitution/ (which needs a LOCKSTEP bump). The parent
# project's scripts/git_hooks/pre-commit and commit_all.sh do NOT source it — the
# pre-commit credential step is a FILENAME-class check plus scripts/secret_scan.sh,
# whose patterns are known TOKEN FORMATS only. The library is project-agnostic
# (§11.4.28), so a consuming project MAY wire it into its own commit seam; the
# pipefail / binary-stream contracts below are pinned for any such consumer, not
# because a hook in this repo happens to call it.
if printf 'note PASSWORD=CHANGE_ME in a captured prompt\n' | helix_cred_detector1_real_hit_stream; then
    bad "(stream-good) mid-line PASSWORD=CHANGE_ME — FALSE POSITIVE (stream reported credential; expected clean)"
else
    ok "(stream-good) mid-line PASSWORD=CHANGE_ME stream — clean"
fi
if printf 'password: hunter2hunter2realleak\n' | helix_cred_detector1_real_hit_stream; then
    ok "(stream-bad) real secret stream — caught"
else
    bad "(stream-bad) real secret stream — MISSED (stream detector WEAKENED)"
fi
# (stream-bad-B1 §11.4.115/§11.4.201(2), Fable-review 2026-07-28): a LARGE dump of
# real secrets (>~64 KB of matches) under `set -o pipefail` — the pre-fix verdict
# `printf … | grep -Eiv CARRIER | grep -q '[^space]'` short-circuited at the first
# survivor, SIGPIPE-killed the upstream grep, and the pipeline exited 141 → wrongly
# CLEAN (a credential DUMP is the highest-value leak). A stream consumer typically
# runs under `set -o pipefail` (execution_record.sh's caller does), so reproduce
# under pipefail exactly as such a seam does. The fix captures survivors
# into a variable (no pipe short-circuit) + a case-glob non-whitespace test.
if ( set -o pipefail
     awk 'BEGIN{for (i = 0; i < 60000; i++) print "password: hunter2hunter2realleak"}' \
       | helix_cred_detector1_real_hit_stream ); then
    ok "(stream-bad-B1) 60k-line real-secret dump under pipefail — caught"
else
    bad "(stream-bad-B1) 60k-line dump under pipefail — MISSED (pipefail SIGPIPE false negative)"
fi
# (stream-bad-B2 §11.4.115/§11.4.201(2), Fable-review 2026-07-28): a BINARY stream
# (NUL bytes) carrying a plaintext secret — the pre-fix `grep -Eio` (no `-a`) on
# binary emits "binary file matches" to STDERR with EMPTY stdout → extracted
# nothing → wrongly CLEAN at any stream seam (`git show | stream_fn` / a captured
# evidence stream, NULs intact), where a raw `grep -Eiq` had caught it. The fix adds `-a` to the
# extraction so a .db/.so/.apk with an embedded plaintext secret is still caught.
if printf 'BIN\000\001\002 password: hunter2hunter2realsecret \000\377 more\n' \
     | helix_cred_detector1_real_hit_stream; then
    ok "(stream-bad-B2) binary stream with plaintext secret — caught"
else
    bad "(stream-bad-B2) binary stream with plaintext secret — MISSED (binary -o false negative)"
fi

# =============================================================================
# (19) SELF-DEFINITION EXEMPTION — carrier-strip #19, BOTH directions.
# §11.4.201(7)(a) carrier-vs-thing applied to the exemption itself: the two
# canonical files MUST stay exempt (a §11.4.201(1) false-positive refusal blocks
# this library's own maintenance — FORENSIC 2026-08-20), while a file merely
# RENAMED to one of those basenames and merely MENTIONING the tokens in prose
# MUST be scanned normally (FORENSIC 2026-08-25: the pre-fix
# `grep -q A || grep -q B` exempted exactly that carrier, and a naive `&&`
# de-exempts this very suite — 0 occurrences of the pattern-assignment token).
# Every fixture secret below is ASSEMBLED AT RUNTIME so this file never carries
# a new literal credential-shaped token.
# =============================================================================
_x19_secret="$(printf 'api%s=%s%s' '_key' 'AKIA' 'Q7X2M4B8N1V5C3Z9')"
_x19_fn="$(printf 'helix%s' '_cred_scan_file')"
_x19_pat="$(printf 'HELIX%s=' '_CRED_VALUE_PATTERN')"
mkdir -p "$WORK/x19a" "$WORK/x19b" "$WORK/x19c" "$WORK/x19d"

# golden-GOOD: the two canonical files themselves stay exempt.
assert_clean "(19-good-1) canonical credential_scan_lib.sh stays exempt" "$LIB"
assert_clean "(19-good-2) canonical test_credential_scan_lib.sh stays exempt" \
             "$HERE/test_credential_scan_lib.sh"

# golden-BAD 1: renamed to the library basename, tokens only in a COMMENT.
{ echo '#!/bin/sh'
  printf '# doc: %s is assigned by the library and %s() is its entry point\n' "$_x19_pat" "$_x19_fn"
  printf '%s\n' "$_x19_secret"; } > "$WORK/x19a/credential_scan_lib.sh"
assert_caught "(19-bad-1) renamed to lib basename, tokens in comments only" \
              "$WORK/x19a/credential_scan_lib.sh"

# golden-BAD 2: renamed to the suite basename, every required token in a COMMENT.
{ echo '#!/bin/sh'
  printf '# doc: the suite defines assert_clean() / assert_caught() and calls %s\n' "$_x19_fn"
  printf '%s\n' "$_x19_secret"; } > "$WORK/x19b/test_credential_scan_lib.sh"
assert_caught "(19-bad-2) renamed to suite basename, tokens in comments only" \
              "$WORK/x19b/test_credential_scan_lib.sh"

# golden-BAD 3: PARTIAL forgery — assigns the pattern but defines no scanner.
{ echo '#!/bin/sh'; printf "%s'x'\n" "$_x19_pat"; printf '%s\n' "$_x19_secret"; } \
  > "$WORK/x19c/credential_scan_lib.sh"
assert_caught "(19-bad-3) lib basename, pattern assigned but no scanner defined" \
              "$WORK/x19c/credential_scan_lib.sh"

# golden-BAD 4: PARTIAL forgery — one oracle defined, the other missing.
{ echo '#!/bin/sh'; echo 'assert_clean() { :; }'
  printf '  %s "$1"\n' "$_x19_fn"; printf '%s\n' "$_x19_secret"; } \
  > "$WORK/x19d/test_credential_scan_lib.sh"
assert_caught "(19-bad-4) suite basename, assert_caught definition missing" \
              "$WORK/x19d/test_credential_scan_lib.sh"

# --- carrier-strips #20/#21/#22/#23 (2026-08-26) ----------------------------
# Three FALSE-POSITIVE carrier shapes, each with a golden-GOOD (carrier is
# clean) AND a golden-BAD (a REAL secret in the SAME shape is still caught).

# (20) SHAPE A — secret keyword assigned from an ENV-LOOKUP CALL.
cat > "$WORK/good_20_env_lookup.kts" <<'EOF'
signingConfigs {
    create("release") {
        storePassword = System.getenv("ATMO_STORE_PASSWORD") ?: ""
        keyAlias      = System.getenv("ATMO_KEY_ALIAS") ?: "atmosphere-release"
        keyPassword   = System.getenv("ATMO_KEY_PASSWORD") ?: ""
    }
}
val goSide   = os.Getenv("API_TOKEN")
val nodeSide = process.env.CLIENT_SECRET
EOF
assert_clean "(20) keyword = System.getenv( / os.Getenv( (env-lookup call value)" \
             "$WORK/good_20_env_lookup.kts"

cat > "$WORK/bad_20_env_lookup_literal.kts" <<'EOF'
signingConfigs {
    create("release") {
        keyPassword = "Hunter2Hunter2Xy"
    }
}
EOF
assert_caught "(20-bad) LITERAL keyPassword in the same signing block (env-strip must not leak it)" \
              "$WORK/bad_20_env_lookup_literal.kts"

# (21) SHAPE B — secret keyword whose value is a PascalCase TYPE NAME.
cat > "$WORK/good_21_symbol_ref.md" <<'EOF'
The sibling seam is
`OptionCPairingTransport.pair(host, pairingPort, secret: OptionCPairingSecret, ourPublicKey)`
and the box mirror carries `token: RemoteSessionToken)`.
EOF
assert_clean "(21) keyword: PascalCaseTypeName (symbol reference, not a secret)" \
             "$WORK/good_21_symbol_ref.md"

cat > "$WORK/bad_21_symbol_digit.md" <<'EOF'
secret: Hunter2Secret
EOF
assert_caught "(21-bad-1) CamelCase value carrying a DIGIT (letters-only rule must hold)" \
              "$WORK/bad_21_symbol_digit.md"

cat > "$WORK/bad_21_one_hump.md" <<'EOF'
secret = SuperSecret
EOF
assert_caught "(21-bad-2) one-hump letters-only value (two-hump floor must hold)" \
              "$WORK/bad_21_one_hump.md"

cat > "$WORK/bad_21_short_hump.md" <<'EOF'
secret: MySecret
EOF
assert_caught "(21-bad-3) short one-hump letters-only value (two-hump floor must hold)" \
              "$WORK/bad_21_short_hump.md"

# (22) SHAPE C-i — git SSH remote split by an exporter mailto autolink.
cat > "$WORK/good_22_markup_git_remote.html" <<'EOF'
<p>then add as submodule the forked repo:
<a href="mailto:git@github.com">git@github.com</a>:MyOrg1234/Some-Repo.git.</p>
EOF
assert_clean "(22) markup-SPLIT git remote (autolinked <a>…</a> between host and :)" \
             "$WORK/good_22_markup_git_remote.html"

# (23) SHAPE C-ii — mailto autolink duplicating the address into a markup-wrapped token.
cat > "$WORK/good_23_mailto_autolink.html" <<'EOF'
<p>Maintainer contact:
<a href="mailto:ops85team@example.com">ops85team@example.com</a> for access requests.</p>
EOF
assert_clean "(23) mailto autolink duplicate DIGIT-BEARING address (markup-wrapped email self-ref)" \
             "$WORK/good_23_mailto_autolink.html"

cat > "$WORK/bad_23_mailto_plus_password.html" <<'EOF'
<p>login <a href="mailto:ops85team@example.com">ops85team@example.com</a> / Hunter2Hunter2! now</p>
EOF
assert_caught "(23-bad) REAL password adjacent to a mailto-autolinked email (markup strip must not leak it)" \
              "$WORK/bad_23_mailto_plus_password.html"

# (24) The elvis/or FALLBACK literal — the catch that carrier-strip #20 must not
# cost. MEASURED 2026-08-26: with #20 present but no fallback alternative, a real
# secret in `= System.getenv("X") ?: "<secret>"` went HIT -> CLEAN, a catch
# REGRESSION. These pin both directions.
cat > "$WORK/bad_24_elvis_real.kts" <<'EOF'
storePassword = System.getenv("ATMO_PW") ?: "Hunter2Hunter2Xy"
EOF
assert_caught "(24-bad-1) REAL secret in an elvis fallback beside an env lookup" \
              "$WORK/bad_24_elvis_real.kts"

cat > "$WORK/bad_24_or_real.go" <<'EOF'
apiKey := os.Getenv("K")
api_key = os.Getenv("K") || "Hunter2Hunter2Xy"
EOF
assert_caught "(24-bad-2) REAL secret in an or-fallback beside an env lookup" \
              "$WORK/bad_24_or_real.go"

cat > "$WORK/good_26_sed_at_delim.sh" <<'EOF'
sed -e 's@MessageDigest.isEqual(a, b)@true@' "$src" > "$mut2"
EOF
assert_clean "(26) sed s@PATTERN@REPL@ delimiters (pseudo-email shape) — clean (no false positive)" \
              "$WORK/good_26_sed_at_delim.sh"

cat > "$WORK/bad_26_real_email_beside_sed.sh" <<'EOF'
sed -e 's@Foo.bar@true@' x
admin@company.com : hunter2RealPassword
EOF
assert_caught "(26-bad) REAL email+password on a line beside a sed s@..@..@ (blank must not leak it)" \
              "$WORK/bad_26_real_email_beside_sed.sh"

cat > "$WORK/good_25_accessor_call.kt" <<'EOF'
val password: String = "",
val token: String = "",
password = obj.optString("password", ""),
token    = obj.optString("token", ""),
EOF
assert_clean "(25) accessor/method CALL in value position (obj.optString) — clean (no false positive)" \
              "$WORK/good_25_accessor_call.kt"

cat > "$WORK/bad_25_quoted_lookalike.kt" <<'EOF'
password = "objDotOptStringLooksLikeACall"
EOF
assert_caught "(25-bad-1) quoted literal that merely LOOKS like a call (strip must be \$-anchored past the quote)" \
              "$WORK/bad_25_quoted_lookalike.kt"

cat > "$WORK/bad_25_real_literal.kt" <<'EOF'
password = obj.optString("password", "")
api_key  = "AKIAIOSFODNN7EXAMPLE"
EOF
assert_caught "(25-bad-2) REAL secret on a line beside an accessor-call carrier (strip must not blanket the file)" \
              "$WORK/bad_25_real_literal.kt"

cat > "$WORK/good_24_elvis_placeholder.kts" <<'EOF'
storePassword = System.getenv("ATMO_PW") ?: ""
keyPassword   = System.getenv("ATMO_KP") ?: "CHANGE_ME"
keyAlias      = System.getenv("ATMO_ALIAS") ?: "atmosphere-release"
EOF
assert_clean "(24) empty / CHANGE_ME elvis fallback + non-keyword keyAlias fallback" \
             "$WORK/good_24_elvis_placeholder.kts"

# --- carrier gap #26: PLURAL credential keywords (2026-09-08, HXC-352) -------
# FORENSIC ANCHOR (§11.4.10 / §11.4.138). A dispatched agent inspecting a live
# server's environment printed two credential VALUES in full despite running a
# redaction filter: the filter recognised `KEY=` but not `KEYS=`. Measured on
# the affected host, exactly two variables ended in the plural form —
# HELIX_AUTH_API_KEYS and HELIX_WIRE_FACADE_API_KEYS — while nine variables
# ending in the SINGULAR `KEY=` were correctly redacted. The singular/plural
# split WAS the whole defect.
#
# UNCONFIRMED (§11.4.6) — WHICH filter leaked. The redaction filter named in the
# incident report is NOT present in the tracked corpus, so there is NO evidence
# that THIS library was the filter that leaked. What IS established, and is the
# whole justification for this change, is that this library exhibits the SAME
# defect class: it named the singular keyword and missed the plural. The
# incident is cited as the ORIGIN of the observation, never as proof of this
# library's involvement.
#
# BLAST RADIUS — the ACTUAL consumers (§11.4.6, measured 2026-09-08). This
# library is NOT wired into the parent project's commit seam: the parent
# `scripts/git_hooks/pre-commit` credential step is a FILENAME-class check
# (basename `.env` / `*.pem` / `id_rsa` …) plus a call to `scripts/secret_scan.sh`,
# whose pattern set is known TOKEN FORMATS (AKIA / ghp_ / sk-ant- / AIza …) plus
# one `AZURE_*(KEY|SECRET)` shape — it carries NO generic `<keyword>=<value>`
# pattern, so neither `API_KEY=<v>` NOR `API_KEYS=<v>` is caught there, before or
# after this change. The consumers that DO source this library are:
#   * constitution/scripts/gates/lib/execution_record.sh (`_xr_redact`) — the
#     §11.4.268 evidence-stream redactor; this IS the seam the plural gap left open;
#   * submodules/claude-toolkit/constitution/scripts/hooks/credential_scan_lib.sh —
#     a SECOND checkout of this same library, which still carries the pre-change
#     pattern (verified: the two files differ at the pattern line). It needs a
#     LOCKSTEP bump; until then the plural gap remains open in that checkout.
#
# The gap was never limited to `API_KEYS`: every keyword in the detector-1
# alternation was singular-only, so `PASSWORDS=`, `SECRETS=`, `ACCESS_TOKENS=`,
# `CLIENT_SECRETS=`, `AUTH_TOKENS=` and `PASSWDS=` all escaped identically.
# A pattern that names `password` and then misses `passwords` is the §11.4.201
# FALSE-NEGATIVE class: the scanner reports clean and the leak ships.
#
# THE FIX IS NARROW, AND EVERY STEP OF THE NARROWING IS MEASURED against the
# 644-file tracked corpus (evidence:
# docs/qa/hxc352_plural_credential_pattern_20260908T201833Z/
# remediation_20260908T204420Z/ (7d_corpus_delta_matrix.txt carries every count
# quoted here; 7b_falsification_matrix.log carries the per-mutation proof).).
#   * BLANKET form (`s?` on the generic `[[:space:]]*[:=]` alternative, i.e.
#     admitting the COLON too): 141 -> 152 flagged files, +11 false-positive
#     refusals, because a PLURAL keyword before a colon is how code names a
#     COLLECTION of keys — `APIKeys: map[string]string{`, `Secrets: HashiCorp …`.
#     REFUTED: trading false negatives for false-positive refusals is the
#     §11.4.201(1) FAIL-bluff, not a fix. Pinned by (26-neg-3) below.
#   * ASSIGNMENT-ONLY, no padding (`s=`): correct but too tight — it missed
#     `PASSWORDS = <secret>` and `passwords = "<secret>"`.
#   * ASSIGNMENT-ONLY WITH PADDING (`s[[:space:]]*=[[:space:]]*`) — SHIPPED.
#     Measured cost: 2 corpus false positives, BOTH `apiKeys = &APIKeys{}` Go
#     composite literals, cured by widening carrier-strip #21 to admit a `&Type{}`
#     value. FINAL corpus verdict: 141 -> 141 flagged files — zero new false
#     positives, zero lost catches — while closing the plural false-negative
#     class, the space-padded class and the elvis-fallback class.
#
# CARRIER-STRIPS #8a / #18 / #20 / #21 / #25 also admit the plural `s?`. The
# earlier rationale for that ("a strip can only ever REMOVE a false positive,
# never create one") was FALSE and has been withdrawn: a strip removes a detector
# HIT, and if the hit was a TRUE positive the strip manufactures a false
# NEGATIVE. The correct argument is SYMMETRY — every widened carrier is
# `^(<keyword>)s?<separator>…`, so the `s?` can consume only an `s` standing
# between the keyword and the separator, and the only extracts carrying such an
# `s` are the ones the plural alternative itself produces. The widened strip
# therefore fires on `<kw>s=<v>` exactly when the un-widened one fired on
# `<kw>=<v>`: the plural masking surface EQUALS the pre-existing singular one, so
# no new masking class is created. Probed 2026-09-08; no counter-example could be
# constructed. Each widened strip is pinned by its OWN falsifying fixture below.
#
# HONEST RESIDUALS (§11.4.6 — stated, not silently omitted):
#   (1) COLON config style (`api_keys: <secret>` in YAML) is still NOT caught;
#       catching it is exactly what produced the +11 false positives.
#   (2) `SECRET_KEY=<v>`, `DJANGO_SECRET_KEY=<v>` and `SECRET_KEYS=<v>` are NOT
#       caught, BEFORE and AFTER this change alike, because `secret` must be
#       followed DIRECTLY by a separator and an intervening `_KEY` defeats it.
#       A PRE-EXISTING gap of the same defect class — NOT introduced here, NOT
#       closed here, and deliberately out of scope (a separate work item). It is
#       recorded so the §11.4.146 STEP-3 fan-out is not silently claimed complete.
#   (3) one standing corpus false positive: a spec file whose prose quotes an
#       `APIKeys=` fixture value. It is genuinely credential-shaped; adding that
#       value to the placeholder vocabulary would be over-fitting, so it is
#       recorded rather than hidden. Consequence, stated precisely: any consumer
#       scanning that file treats it as a hit — the §11.4.268 evidence-stream
#       redactor would REDACT a captured stream containing it, and a commit seam
#       wired to this library (none in this checkout) would REFUSE the commit —
#       until the fixture value is made placeholder-shaped.
#
# These fixtures are the FALSIFYING tests for the fix (§11.4.115 / §11.4.224):
# each names the mutation it catches, and each was OBSERVED to FAIL with that
# mutation applied to a scratch copy of the library (§1.1 / §11.4.84 — never the
# live tree). Values are synthetic (§11.4.10).

cat > "$WORK/bad_26_api_keys_plural.env" <<'EOF'
HELIX_AUTH_API_KEYS=hunter2hunter2hunter2
EOF
assert_caught "(26-a) plural API_KEYS= assignment (the exact shape that escaped)" \
              "$WORK/bad_26_api_keys_plural.env"

cat > "$WORK/bad_26_passwords_plural.env" <<'EOF'
DB_PASSWORDS=hunter2hunter2hunter2
EOF
assert_caught "(26-b) plural PASSWORDS= assignment" "$WORK/bad_26_passwords_plural.env"

cat > "$WORK/bad_26_secrets_plural.env" <<'EOF'
APP_SECRETS=hunter2hunter2hunter2
EOF
assert_caught "(26-c) plural SECRETS= assignment" "$WORK/bad_26_secrets_plural.env"

cat > "$WORK/bad_26_access_tokens_plural.env" <<'EOF'
SERVICE_ACCESS_TOKENS=hunter2hunter2hunter2
EOF
assert_caught "(26-d) plural ACCESS_TOKENS= assignment" "$WORK/bad_26_access_tokens_plural.env"

cat > "$WORK/bad_26_client_secrets_plural.env" <<'EOF'
OAUTH_CLIENT_SECRETS=hunter2hunter2hunter2
EOF
assert_caught "(26-e) plural CLIENT_SECRETS= assignment" "$WORK/bad_26_client_secrets_plural.env"

cat > "$WORK/bad_26_auth_tokens_plural.env" <<'EOF'
GATEWAY_AUTH_TOKENS=hunter2hunter2hunter2
EOF
assert_caught "(26-f) plural AUTH_TOKENS= assignment" "$WORK/bad_26_auth_tokens_plural.env"

cat > "$WORK/bad_26_passwds_plural.env" <<'EOF'
SYSTEM_PASSWDS=hunter2hunter2hunter2
EOF
assert_caught "(26-g) plural PASSWDS= assignment" "$WORK/bad_26_passwds_plural.env"

# (26-h / 26-i) SPACE-PADDED plural assignment. FALSIFYING MUTATION: tighten the
# plural alternative back to `s=` (no padding) — both FAIL. These are the two
# false negatives that the padded form was adopted to close; the padding is the
# measured trade whose ONLY corpus cost was cured by (26-neg-8).
cat > "$WORK/bad_26_padded_passwords.conf" <<'EOF'
DB_PASSWORDS = hunter2hunter2hunter2
EOF
assert_caught "(26-h) plural PASSWORDS with spaces around = " \
              "$WORK/bad_26_padded_passwords.conf"

cat > "$WORK/bad_26_padded_quoted.kts" <<'EOF'
val passwords = "hunter2hunter2hunter2"
EOF
assert_caught "(26-i) plural passwords = \"<secret>\" quoted literal" \
              "$WORK/bad_26_padded_quoted.kts"

# (26-j) PLURAL ELVIS / OR-FALLBACK. The elvis alternative was singular-only, so
# a plural keyword with a hard-coded fallback secret escaped even after the
# assignment fix. FALSIFYING MUTATION: remove `s?` from the elvis alternative.
# The left-hand value is deliberately SHORT (under the 8-character value floor)
# so the plural ASSIGNMENT alternative cannot match it — MEASURED: with a longer
# left-hand value (`readKeys()`) this fixture passes via the assignment path and
# is NON-DISCRIMINATING for the elvis widening, which is exactly the decoration
# §1.1 forbids.
cat > "$WORK/bad_26_plural_elvis.kts" <<'EOF'
val passwords = env ?: "hunter2hunter2hunter2"
EOF
assert_caught "(26-j) plural keyword with an elvis fallback secret" \
              "$WORK/bad_26_plural_elvis.kts"

# --- NEGATIVE CONTROLS (§11.4.201 both-directions) --------------------------
# (26-neg-1) BLANKET control only, and it is NON-DISCRIMINATING for the plural
# alternative by construction: it contains no credential keyword at all, so it
# stays clean with or without this change. It is kept deliberately, as the
# blanket "the widening did not turn the detector into a match-any-plural
# identifier" assertion. Every DISCRIMINATING negative control is (26-neg-2)
# through (26-neg-8), each of which names the exact mutation it fails against.
cat > "$WORK/good_26_plural_noncred.env" <<'EOF'
HELIX_LOG_LEVELS=debugdebugdebugdebug
HELIX_ALLOWED_ORIGINS=localhostlocalhost
EOF
assert_clean "(26-neg-1) plural NON-credential identifiers stay clean (blanket control)" \
             "$WORK/good_26_plural_noncred.env"

# (26-neg-2) FALSIFYING MUTATION: remove `s?` from HELIX_CRED_PLACEHOLDER_CARRIER.
cat > "$WORK/good_26_plural_placeholder.env" <<'EOF'
HELIX_AUTH_API_KEYS=CHANGE_ME
OAUTH_CLIENT_SECRETS=PLACEHOLDER
EOF
assert_clean "(26-neg-2) plural keyword with placeholder value still hits the #8a strip" \
             "$WORK/good_26_plural_placeholder.env"

# (26-neg-3) THE LOAD-BEARING NARROWING. These are the COLLECTION-declaration
# shapes that the REFUTED blanket form (`s?` + `[:=]` + padding) wrongly refuses.
# FALSIFYING MUTATION: restore the blanket form — this fixture FAILS, which is
# the whole reason the shipped alternative is assignment-only.
cat > "$WORK/good_26_plural_collection.go" <<'EOF'
type Config struct {
	APIKeys: map[string]string{
	Secrets: HashiCorp Vault is the reference store
	api_keys: REFUSING to enumerate them here
}
EOF
assert_clean "(26-neg-3) plural keyword + COLON = a collection declaration, not a secret" \
             "$WORK/good_26_plural_collection.go"

# (26-neg-4) FALSIFYING MUTATION: remove `s?` from HELIX_CRED_ENV_LOOKUP_CARRIER.
# The value is deliberately a `process.env.X` form and NOT a call, so the
# accessor strip (#25) cannot mask the failure — this fixture discriminates the
# env-lookup strip alone.
cat > "$WORK/good_26_plural_envlookup.js" <<'EOF'
const HELIX_AUTH_API_KEYS=process.env.HELIX_AUTH_API_KEYS
EOF
assert_clean "(26-neg-4) plural keyword whose value is an env lookup (#20 strip)" \
             "$WORK/good_26_plural_envlookup.js"

# (26-neg-5) FALSIFYING MUTATION: remove `s?` from HELIX_CRED_ACCESSOR_CALL_CARRIER.
# The value is a call the env-lookup strip does NOT know, so it discriminates the
# accessor strip alone.
cat > "$WORK/good_26_plural_accessor.go" <<'EOF'
HELIX_AUTH_API_KEYS=vault.read(
EOF
assert_clean "(26-neg-5) plural keyword whose value is an accessor call (#25 strip)" \
             "$WORK/good_26_plural_accessor.go"

# (26-neg-6) FALSIFYING MUTATION: remove `s?` from
# HELIX_CRED_IDENTIFIER_REFERENCE_CARRIER. Without it, `passwords=passwords` is a
# HIT while the singular `password=password` is clean — a false-positive class the
# singular form explicitly exempts (§11.4.201(1)).
cat > "$WORK/good_26_plural_identref.go" <<'EOF'
passwords=passwords
api_keys=api_keys
EOF
assert_clean "(26-neg-6) plural value-equals-key is a variable reference (#18 strip)" \
             "$WORK/good_26_plural_identref.go"

# (26-neg-7) FALSIFYING MUTATION: remove `s?` from
# HELIX_CRED_SYMBOL_REFERENCE_CARRIER. Without it, `apiKeys=DefaultAPIKey` is a
# HIT while the singular `apiKey=DefaultAPIKey` is clean — same asymmetry.
cat > "$WORK/good_26_plural_symbolref.go" <<'EOF'
apiKeys=DefaultAPIKey
EOF
assert_clean "(26-neg-7) plural keyword whose value is a TYPE name (#21 strip)" \
             "$WORK/good_26_plural_symbolref.go"

# (26-neg-8) FALSIFYING MUTATION: remove the `&?` / `(\{\})?` composite-literal
# form from HELIX_CRED_SYMBOL_REFERENCE_CARRIER. This is the exact shape (2
# tracked files) that the space-padded plural alternative would otherwise refuse;
# it is the measured cost of (26-h)/(26-i), and this strip is its cure.
cat > "$WORK/good_26_plural_composite.go" <<'EOF'
apiKeys = &APIKeys{}
EOF
assert_clean "(26-neg-8) plural keyword whose value is a Go composite literal (#21 strip)" \
             "$WORK/good_26_plural_composite.go"

# (26-neg-9) The widened #21 strip must NOT swallow the weak-but-plausible real
# secrets its two-hump floor was chosen to keep. Re-measured after the widening.
cat > "$WORK/bad_26_symbol_floor.go" <<'EOF'
secret = SuperSecret
EOF
assert_caught "(26-neg-9) #21 two-hump floor survives the widening (still caught)" \
              "$WORK/bad_26_symbol_floor.go"

echo ""
echo "== RESULT: ${pass} passed, ${fail} failed =="
[ "$fail" -eq 0 ]
