#!/usr/bin/env bash
# test_own_mutants.sh — builder-authored §1.1 mutants of the REAL engine. Each mutant names the suite it must
# break (core = test_core.sh, r2 = test_round2.sh, r3 = test_round3.sh, r4..r8 = test_round4.sh..test_round8.sh, r11 = test_round11.sh); it is KILLED when that suite reports a failure.
# One mutant at a time (host load). A mutant may carry several old/new pairs (applied in order).
# Env: DEC_MUTANTS_ROUND=r2|r3|r4|r5|r6|r7|r8 limits the set (r2 also runs N only); DEC_MUTANTS_ONLY=<ERE> runs only matching names;
# DEC_MUTANTS_APPLY_ONLY=1 only checks that each mutant still applies to the engine (no suite run).
# A mutant whose search text is gone (a stale anchor after an engine change) is NOT-APPLIED: listed by name and the run FAILS.
set -u
here="$(cd "$(dirname "$0")" && pwd)"; repo="$(cd "$here/../.." && pwd)"
. "$repo/scripts/lib/safe_rm.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/dec_own_mut.XXXXXX")" || exit 1
trap 'safe_rm_rf "${tmp:?}"' EXIT
killed=0; survived=0; applied=0; not_applied=0; not_applied_names=""
mutant() { # name suite old new [old new]...
  local name="$1" suite="$2"; shift 2
  # DEC_MUTANTS_ONLY: optional extended regex; mutants whose name does not match are not run (and not counted)
  if [ -n "${DEC_MUTANTS_ONLY:-}" ] && ! grep -Eq -- "$DEC_MUTANTS_ONLY" <<<"$name"; then return; fi
  local m="$tmp/$name"; mkdir -p "$m"; cp "$repo/scripts/decisions/constitution_decisions.sh" "$repo/scripts/decisions/decisions_engine.py" "$m/"
  if ! python3 -I - "$m/decisions_engine.py" "$@" <<'PY'
import sys; p = sys.argv[1]; pairs = sys.argv[2:]; s = open(p).read()
for old, new in zip(pairs[0::2], pairs[1::2]):
    if old not in s: sys.exit(1)
    s = s.replace(old, new, 1)
open(p, "w").write(s)
PY
  then echo "  NOT-APPLIED $name (its search text is no longer in the engine: a stale anchor; update the mutant)"
       not_applied=$((not_applied+1)); not_applied_names="$not_applied_names $name"; return; fi
  applied=$((applied+1))
  if [ -n "${DEC_MUTANTS_APPLY_ONLY:-}" ]; then echo "  applies $name"; return; fi
  local f="$here/test_core.sh"; [ "$suite" = r2 ] && f="$here/test_round2.sh"; [ "$suite" = r3 ] && f="$here/test_round3.sh"; [ "$suite" = r4 ] && f="$here/test_round4.sh"; [ "$suite" = r5 ] && f="$here/test_round5.sh"; [ "$suite" = r6 ] && f="$here/test_round6.sh"; [ "$suite" = r7 ] && f="$here/test_round7.sh"; [ "$suite" = r8 ] && f="$here/test_round8.sh"; [ "$suite" = r11 ] && f="$here/test_round11.sh"
  # cwd is the mutant's own sandbox, never the caller's (the real repo): a mutant that writes cwd-relative
  # (P19 did: it leaked .decisions-backup/ into the repo root) must stay inside $m.
  mkdir -p "$m/cwd"
  (cd "$m/cwd" && DECISIONS_CLI="$m/constitution_decisions.sh" bash "$f") >"$m/out" 2>&1
  local line; line="$(tail -1 "$m/out")"
  if grep -q 'fail=0$' <<<"$line"; then survived=$((survived+1)); echo "  SURVIVED $name ($line)"
  else killed=$((killed+1)); echo "  killed  $name ($line; first: $(grep -m1 '  FAIL' "$m/out" | sed 's/^ *//'))"; fi
}
if [ "${DEC_MUTANTS_ROUND:-all}" != r2 ]; then
mutant MT1_no_contradiction_check core 'def check_contradictions(eff):' 'def check_contradictions(eff):
    return'
mutant MT2_endpoint_order_ignored core 'if [x for x in ENDPOINT_ORDER if x in v] != v or "local" not in v:' 'if "local" not in v:'
mutant MT3_duplicate_set_allowed core 'raise Usage("decision key given twice with --set")' 'pass'
mutant MT4_symlink_followed r3 'if os.path.islink(p) and not allow_link:' 'if False:'
mutant MT5_env_agents_ignored core 'out["agents.%s.wiring" % a] = "consent"' 'pass'
mutant MT6_duplicate_markers_accepted r3 'if len(b) != 1 or len(e) != 1 or e[0] < b[0]:' 'if not b or not e:'
mutant MT7_no_backup core 'dest = backup(proj, to_backup)' 'dest = proj.root'
mutant MT8_reset_ignored core '    if a.reset:
        target = {}' '    if a.reset:
        pass'
fi
# round-2 mutants (review B1-B4, I1-I8, minors)
mutant N01_regex_dollar_class r2 'KEY_SHAPE_RE = re.compile(r"[a-z][a-z0-9_]{0,39}(?:\.[a-z][a-z0-9_]{0,39}){1,3}")' 'KEY_SHAPE_RE = re.compile(r"[a-z][a-z0-9_]{0,39}(?:\.[a-z][a-z0-9_]{0,39}){1,3}$")' \
  'not KEY_SHAPE_RE.fullmatch(key):' 'not KEY_SHAPE_RE.match(key):' \
  '    m = DYN_QTYPE.fullmatch(key)
    if m:
        t = m.group(1)' '    m = re.match(DYN_QTYPE.pattern + "$", key)
    if m:
        t = m.group(1)' \
  '    if back != decisions or' '    if False and back != decisions or' \
  '            if not KEY_SHAPE_RE.fullmatch(k) or' '            if not KEY_SHAPE_RE.match(k) or'
mutant N02_export_into_git r2 'FORBIDDEN_TOP = (".git", ".constitution", ".constitution-install-backup")' 'FORBIDDEN_TOP = ()'
mutant N03_export_overwrites r2 '    if os.path.exists(p) and not a.force_export:' '    if False:'
mutant N04_yes_without_clone r2 '        if eff.get("llmctl.clone_consent"):
            args += ["--agent"' '        if True:
            args += ["--agent"'
mutant N05_claude_without_settings r2 'if a == "claude" and not eff.get("agents.settings_json_consent"):' 'if False:'
mutant N06_discovery_unlocked r2 '"keys.discovery_consent": ("bool", True, {"locked": True,' '"keys.discovery_consent": ("bool", True, {'
mutant N07_local_droppable r2 ' or "local" not in v:' ':'
mutant N08_enforce_default_allow r2 'if "qtype" in extra and v == "enforce" and extra["qtype"] not in ENFORCE_ELIGIBLE:' 'if False:'
mutant N09_verif_class_missing r2 '"verif", "verdict")' '"verdict")'
mutant N10_drift_ignored r2 '        if drift:' '        if False:'
mutant N11_env_consent_without_flag r2 '    if not accept:
        emit_err("note: ignored' '    if False:
        emit_err("note: ignored'
mutant N12_doc_non_markdown r2 'if not p.lower().endswith((".md", ".markdown")):' 'if False:'
mutant N13_lock_follows_symlink r2 '    if os.path.islink(lp):' '    if False:' 'os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW |' 'os.O_RDWR | os.O_CREAT |'
mutant N14_no_lock r2 '    fd = acquire_lock(lockdir)' '    fd = os.open(os.devnull, os.O_RDONLY)'
mutant N15_control_chars_narrow r2 '    return any(is_unsafe_char(c) for c in s)' '    return "\n" in s or "\r" in s'
mutant N16_crlf_lost r2 '    nl = "\r\n" if "\r\n" in text else "\n"' '    nl = "\n"'
mutant N17_schema_loose r2 'if type(sv) is not int or sv != 1:' 'if sv != 1:'
mutant N18_utf8_traceback r2 '    except UnicodeDecodeError:
        raise Refused' '    except KeyError:
        raise Refused'
mutant N19_key_echoed r3 '    raw = k if isinstance(k, str) else repr(k)' '    return str(k)'
mutant N20_export_no_backup r2 '                dest = backup(proj, [(p, rel)])' '                dest = proj.root'
mutant N21_user_no_backup r2 '    private_copy(ufile, dest)' '    pass'
# round-3 mutants (review B-1, I-1..I-8, minors); killed by test_round3.sh
if [ "${DEC_MUTANTS_ROUND:-all}" = all ] || [ "${DEC_MUTANTS_ROUND:-all}" = r3 ]; then
mutant P01_secret_key_accepted r3 '    if looks_secret(key):
        raise Refused("a decision key looks like key material' '    if False:
        raise Refused("a decision key looks like key material'
mutant P02_secret_qtype_label_verbatim r3 '        if m and not looks_secret(k):
            return k' '        if m:
            return k' '    if looks_secret(key):
        raise Refused("a decision key looks like key material' '    if False:
        raise Refused("a decision key looks like key material'
mutant P03_no_redact r4 '    for r in SECRET_RES:
        s = r.sub("[redacted]", s)' '    pass'
mutant P04_secret_path_accepted r3 '        if looks_secret(os.path.relpath(p, self.root)):' '        if False:'
mutant P05_dry_run_export_writes r3 '    if a.dry_run:  # review I-1' '    if False:  # review I-1'
mutant P06_orphan_block_ok r3 '        if orphan:' '        if False:'
mutant P07_fence_ignored r3 '            m = FENCE_OPEN_RE.fullmatch(t)' '            m = None'
mutant P08_marker_prefix_match r3 '        if BEGIN_RE.fullmatch(t):' '        if BEGIN_RE.match(t):' '        elif END_RE.fullmatch(t):' '        elif END_RE.match(t):'
mutant P09_locked_stored r3 '    return drop_locked(target)' '    return target'
mutant P10_dynamic_lock_bricks r3 '        if reading and k in DYNAMIC_LOCKS' '        if False and k in DYNAMIC_LOCKS'
mutant P11_no_lenient_recovery r3 '            if bad is None:
                raise' '            if True:
                raise'
mutant P12_no_env_unset r3 '    env = ["env"] + ["-u %s" % n for n in bootstrap_env_names()]' '    env = []'
mutant P13_doc_symlink_not_deduped r3 '            if os.path.exists(p) and p not in seen:' '            if os.path.exists(p):'
mutant P14_doc_symlink_escape r3 '            if not self.contains(real) or self.forbidden(real) or' '            if'
mutant P15_mode_without_accept r3 'CONSENT_ENV = ("JEV_BOOTSTRAP_MODE", ' 'CONSENT_ENV = (' '    if not present:
        return out' '    if env.get("JEV_BOOTSTRAP_MODE"):
        out["layer.mode"] = env["JEV_BOOTSTRAP_MODE"]
    if not present:
        return validate_map(out, "env")'
mutant P16_enforce_under_shadow r3 '            if mode != "enforce":' '            if False:'
mutant P17_hosted_contradiction r3 '    if not eff.get("hosted.allowed") and "hosted" in' '    if False and "hosted" in'
mutant P18_backup_unbounded r3 '    for _k, fp in ours[:max(0, len(ours) - backup_keep())]:' '    for _k, fp in []:'
mutant P19_user_backup_in_project r3 '    base = os.path.join(os.path.dirname(ufile), ".decisions-backup")' '    base = os.path.join(os.getcwd(), ".decisions-backup")'
mutant P20_export_missing_dir_traceback r3 '    if not os.path.isdir(os.path.dirname(p)):
        raise Precondition' '    if False:
        raise Precondition'
mutant P21_constitution_file_traceback r3 '        if os.path.exists(proj.cdir) and not os.path.isdir(proj.cdir):' '        if False:'
mutant P22_prelock_no_reread r3 '    test_delay("CONSTITUTION_DECISIONS_TEST_PRELOCK_DELAY")' '    st0 = State(proj, a.scope, lenient=recovery)
    test_delay("CONSTITUTION_DECISIONS_TEST_PRELOCK_DELAY")' '        st = State(proj, a.scope, lenient=recovery)  # re-read under the lock' '        st = st0'
fi
# round-4 mutants (review round 3: B-A fences, I-A env census, I-B OS errors, minors); killed by test_round4.sh
if [ "${DEC_MUTANTS_ROUND:-all}" = all ] || [ "${DEC_MUTANTS_ROUND:-all}" = r4 ]; then
mutant Q01_backtick_info_rule r4 'if m and not (m.group(2)[0] == "`" and "`" in m.group(3)):' 'if m:'
mutant Q02_append_into_open_fence r4 '        if open_fence is not None:' '        if False:'
mutant Q03_no_post_verify r4 '    if len(b2) != 1 or len(e2) != 1 or e2[0] < b2[0] or "".join(ol[b2[0]:e2[0] + 1]) != block:' '    if False:'
mutant Q04_close_any_char r4 'if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence):' 'if m and len(m.group(1)) >= len(fence):'
mutant Q05_close_shorter r4 'if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence):' 'if m and m.group(1)[0] == fence[0]:'
mutant Q06_fence_any_indent r4 'FENCE_OPEN_RE = re.compile(r"( {0,3})(' 'FENCE_OPEN_RE = re.compile(r"( *)('
mutant Q07_splitlines r4 '    return _MD_LINE.findall(text)' '    return text.splitlines(keepends=True)'
mutant Q08_static_census_incomplete r4 '    "JEV_BOOTSTRAP_NESTED", "JEV_BOOTSTRAP_HOME",' '    "JEV_BOOTSTRAP_HOME",'
mutant Q09_no_runtime_rescan r4 '    found = env_census(os.path.join(CONST_ROOT, "scripts", "jev")) or set()' '    found = set()'
mutant Q10_floor_not_explicit r4 '    env.append("JEV_CALIBRATE_FLOOR=%s" % eff["calibration.floor"])' '    pass'
mutant Q11_no_preflight r4 'def preflight(targets, rel):' 'def preflight(targets, rel):
    return'
mutant Q12_readonly_file_replaced r4 '            if not os.access(path, os.W_OK):' '            if False:'
mutant Q13_hardlink_split r4 '            if st.st_nlink > 1:' '            if False:'
mutant Q14_lost_update r4 '        if expect is not False and read_text(path) != expect:' '        if False:'
mutant Q15_umask_ignored r4 '    return base & ~um' '    return base & 0o644'
mutant Q16_toplevel_oserror_traceback r4 '    except (Usage, Precondition, Refused, OSError) as exc:' '    except (Usage, Precondition, Refused) as exc:'
mutant Q17_midrun_no_journal_message r4 '    except OSError as exc:
        raise Precondition("writing %s failed' '    except ZeroDivisionError as exc:
        raise Precondition("writing %s failed'
mutant Q18_redact_no_sanitise r4 '    return "".join(_uesc(c) if is_unsafe_char(c) and c not in "\n\t" else c for c in str(s))' '    return str(s)'
mutant Q19_has_control_c0_only r4 '    return unicodedata.category(c) in UNSAFE_CATEGORIES' '    o = ord(c)
    return o < 0x20 or o == 0x7F'
mutant Q20_argparse_echo r4 '        raise Usage(redact(m.group(1) + " (value not shown)" if m else message[:300]))' '        raise Usage(redact(message))'
mutant Q21_generic_secret_greedy r4 're.compile(r"(?=[A-Za-z0-9+/_=-]*[0-9])(?=[A-Za-z0-9+/_=-]*[A-Za-z])[A-Za-z0-9+/_=-]{32,}")' 're.compile(r"[A-Za-z0-9+/_=-]{32,}")'
mutant Q22_fifo_blocks r4 '        if os.path.exists(p) and not os.path.isdir(p) and not os.path.isfile(p):' '        if False:'
mutant Q23_no_size_limit r4 '    if len(t) > MAX_READ:' '    if False:'
mutant Q24_pass_list_ignored r4 'if n not in BOOTSTRAP_ENV and n not in BOOTSTRAP_PASS_ENV)' 'if n not in BOOTSTRAP_ENV)' '    env = ["env"] + ["-u %s" % n for n in bootstrap_env_names()]' '    env = ["env"] + ["-u %s" % n for n in bootstrap_env_names() + list(BOOTSTRAP_PASS_ENV)]'
# leak class: user-scope files must never land in the project tree
mutant R01_user_in_project_allowed r4 '    d = os.path.realpath(os.path.dirname(ufile))
    if proj.contains(d) and not proj.is_home_like():' '    d = os.path.realpath(os.path.dirname(ufile))
    if False:'
mutant R02_relative_user_file_allowed r4 '        if not os.path.isabs(f):' '        if False:'
mutant R03_user_location_not_resolved r4 '    d = os.path.realpath(os.path.dirname(ufile))' '    d = os.path.abspath(os.path.dirname(ufile))'
mutant R04_no_early_user_location_check r4 '    if a.scope == "user":
        check_user_location(proj, user_file())' '    if False:
        check_user_location(proj, user_file())'
fi
# round-5 mutants (round-4 review I-1..I-6 and minors); killed by test_round5.sh
if [ "${DEC_MUTANTS_ROUND:-all}" = all ] || [ "${DEC_MUTANTS_ROUND:-all}" = r5 ]; then
mutant S01_foreign_not_refused r5 '        if self.foreign(p):' '        if False:'
mutant S02_state_raises_contradiction r5 '        self.contradictions = check_contradictions(self.eff) or []' '        self.contradictions = check_contradictions(self.eff) or []
        if self.contradictions:
            raise Refused(self.contradictions[0])'
mutant S03_new_contradiction_allowed r5 '    if created:' '    if False:'
mutant S04_no_project_precondition r5 '        proj.require_inherited(a.inherits)' '        pass'
mutant S05_home_allowed r5 '        if self.root in home_dirs():' '        if False:'
mutant S06_backup_not_redacted r5 '        if text is not None and looks_secret(text):' '        if False:'
mutant S07_backup_world_readable r5 '    os.chmod(out, 0o600)' '    pass'
mutant S08_paths_redacted r5 '"project_root": proj.root' '"project_root": redact(proj.root)'
mutant S09_number_grammar_loose r5 '            if not (_INT_RE if kind in ("int", "nint") else _FLOAT_RE).fullmatch(v):' '            if False:'
mutant S10_prune_unguarded r5 'not os.path.isdir(base) or os.path.basename(base) not in BACKUP_BASES:' 'not os.path.isdir(base):' '    if os.path.basename(base) not in BACKUP_BASES or len(' '    if len('
mutant S11_default_foreign_doc_fails_run r5 '            except Foreign:' '            except ZeroDivisionError:'
mutant S12_root_inside_git_ok r5 '        if ".git" in self.root.split(os.sep):' '        if False:'
mutant S13_off_wording_dropped r5 '    if decisions.get("layer.mode") == "off":
        out +=' '    if False:
        out +='
mutant S14_gitmodules_ignored r5 '        roots = list(self.gitmodule_paths())' '        roots = []'
mutant S15_nested_repo_ignored r5 '        while d != self.root and self.contains(d):' '        while False:'
mutant S16_profile_charset_broadened r5 'PROFILE_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")' 'PROFILE_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/ -]{0,63}")'
mutant S17_inherited_path_not_protected r5 '        cands = ["submodules/constitution", "constitution"] + ([self.inh_override] if self.inh_override else [])' '        cands = []'
fi
if [ "${DEC_MUTANTS_ROUND:-all}" = all ] || [ "${DEC_MUTANTS_ROUND:-all}" = r6 ]; then
mutant R6S01_lowest_free_backup_name r6 '        slot = next_slot(bfd, BACKUP_DIR_RE)' '        slot = (_stamp(), 1)'
mutant R6S02_prune_deletes_newest r6 '    ours.sort()
    for _k, fp' '    ours.sort(reverse=True)
    for _k, fp'
mutant R6S03_clock_back_not_monotonic r6 '    return best[0], best[1] + 1' '    return now, 1'
mutant R6S04_newline_not_escaped r6 '        else _clean_line(str(text))' '        else "\n".join(_clean_line(x) for x in str(text).split("\n"))'
mutant R6S05_surrogates_unhandled r6 'UNSAFE_CATEGORIES = frozenset(("Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp"))' 'UNSAFE_CATEGORIES = frozenset(("Cc", "Cf", "Co", "Cn", "Zl", "Zp"))' '.encode(enc, "backslashreplace")' '.encode(enc, "strict")'
mutant R6S06_stdout_bypass r6 '    emit_out("exported: %s" % proj.rel(p))' '    sys.stdout.write("exported: %s\n" % proj.rel(p))'
mutant R6S07_print_bypass r6 '    emit_out("exported: %s" % proj.rel(p))' '    print("exported: %s" % proj.rel(p))'
mutant R6S08_gitmodules_key_case_sensitive r6 '            key = text[i:j].lower()' '            key = text[i:j]'
mutant R6S09_gitmodules_comment_kept r6 '        elif c in "#;":
            while j < n and text[j] != "\n":
                j += 1
            continue' '        elif False:
            pass'
mutant R6S10_gitmodules_strict_utf8 r6 'raw.decode("utf-8", "surrogateescape")' 'raw.decode("utf-8")'
mutant R6S11_recorded_inherits_ignored r6 '        rec = proj.recorded_inherits()' '        rec = None'
mutant R6S12_nonexistent_inherits_accepted r6 '        if not proj.inherits_dir_ok(a.inherits):' '        if False:'
# R6S13 retargeted in round 10: since the parent is held by a descriptor and compared by inode, a swapped parent is also caught WITHOUT the guard; the guard's remaining unique duty is the .git-appears-in-the-parent case (test_round7 R13).
mutant R6S13_no_last_moment_guard r7 '            guard(path)  # last path-based check before the rename (TOCTOU); raises Precondition' '            pass'
# R6S14 retargeted in round 11: test_round11 A (parent moved, symlink at the old name; inode unchanged).
mutant R6S14_parent_realpath_not_compared r11 '            if os.path.realpath(d) != d or not self.contains(d):' '            if not self.contains(d):'
mutant R6S15_check_ignores_intent r6 '    if os.path.lexists(proj.ifile):
        emit_err("check: .constitution/decisions.intent' '    if False:
        emit_err("check: .constitution/decisions.intent'
mutant R6S16_passwd_home_ignored r6 '        hs.add(os.path.realpath(pwd.getpwuid(os.getuid()).pw_dir))' '        pass'
mutant R6S17_home_abspath r6 '        hs.add(os.path.realpath(h))' '        hs.add(os.path.abspath(h))'
mutant R6S18_user_scope_needs_project r6 '    user_only = a.scope == "user" and not readonly' '    user_only = False'
mutant R6S19_backup_base_not_tightened r6 '        tighten_base(bfd, base)
        test_delay("CONSTITUTION_DECISIONS_TEST_BACKUP_SLOT_DELAY")
        slot = next_slot(bfd, BACKUP_DIR_RE)' '        test_delay("CONSTITUTION_DECISIONS_TEST_BACKUP_SLOT_DELAY")
        slot = next_slot(bfd, BACKUP_DIR_RE)'
mutant R6S20_user_base_not_tightened r6 '        tighten_base(bfd, base)
        test_delay("CONSTITUTION_DECISIONS_TEST_BACKUP_SLOT_DELAY")
        slot = next_slot(bfd, rx)' '        test_delay("CONSTITUTION_DECISIONS_TEST_BACKUP_SLOT_DELAY")
        slot = next_slot(bfd, rx)'
mutant R6S21_resolved_secret_shown r6 '            if looks_secret(os.path.relpath(real, self.root)):' '            if False:'
mutant R6S22_home_like_not_exempt r6 '    if proj.contains(d) and not proj.is_home_like():' '    if proj.contains(d):'
mutant R6S23_inherits_path_not_protected r6 '+ ([self.inh_override] if self.inh_override else [])' '+ []'
mutant R6S24_repo_check_dropped r6 '        if not in_repo:
            raise' '        if False:
            raise'
mutant R6S25_repo_check_root_only r6 '            nd = os.path.dirname(d)
            if nd == d:
                break
            d = nd
        if not in_repo' '            break
        if not in_repo'
mutant R6S26_dotgit_isdir_only_foreign r6 '            if os.path.lexists(os.path.join(d, ".git")):
                return True' '            if os.path.isdir(os.path.join(d, ".git")):
                return True'
mutant R6S27_dotgit_isdir_only_root r6 '            if os.path.lexists(os.path.join(d, ".git")):  # a directory, or a FILE (worktree / submodule checkout)' '            if os.path.isdir(os.path.join(d, ".git")):  # a directory, or a FILE (worktree / submodule checkout)'
mutant R6S28_export_dir_check_dropped r6 '    if os.path.isdir(p):
        raise Precondition("--export %s is a directory; refused" % rel)
' ''
mutant R6S29_precondition_redacted r6 '        emit_err("constitution_decisions: blocked: %s" % safe_text(exc))' '        emit_err("constitution_decisions: blocked: %s" % redact(exc))'
mutant R6S30_recorded_waives_repo_checks r6 '        self.inh_override = explicit or self.inh_override
        if explicit:' '        self.inh_override = explicit or self.inh_override
        if explicit or self.inh_recorded:'
fi
if [ "${DEC_MUTANTS_ROUND:-all}" = all ] || [ "${DEC_MUTANTS_ROUND:-all}" = r7 ]; then
# round 7: mutants for the round-6 review (I-1 catch-all/excepthook/TTY bytes, M-1 grammar, M-2 categories, M-3 tags,
# M-4 R13/R21, M-5 emitter for argparse, M-6 descriptors). Each must break test_round7.sh.
mutant R7M01_catchall_removed r7 '    except Exception as exc:  # the catch-all: UnicodeError, RecursionError, MemoryError, OverflowError, ValueError, KeyError...' '    except ZeroDivisionError as exc:'
mutant R7M02_excepthook_not_installed r7 '    install_excepthook()
    sys.exit(run_cli' '    sys.exit(run_cli'
mutant R7M03_tty_strict_utf8 r7 'tty_in = open("/dev/tty", "r", encoding="utf-8", errors="surrogateescape")' 'tty_in = open("/dev/tty", "r", encoding="utf-8")'
mutant R7M04_surrogate_answer_not_refused r7 '            if any(unicodedata.category(c) == "Cs" for c in ans):' '            if False:'
mutant R7M05_bom_not_stripped r7 '    if text.startswith("\ufeff"):' '    if False:'
mutant R7M06_legacy_dotted_section_ignored r7 '    in_sub = nm == "submodule" or nm.startswith("submodule.")' '    in_sub = nm == "submodule"'
mutant R7M07_eof_backslash_kept r7 '        if c == "\\" and j + 1 >= n:' '        if False:'
mutant R7M08_category_cf_dropped r7 'UNSAFE_CATEGORIES = frozenset(("Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp"))' 'UNSAFE_CATEGORIES = frozenset(("Cc", "Cs", "Co", "Cn", "Zl", "Zp"))'
mutant R7M09_category_co_dropped r7 'UNSAFE_CATEGORIES = frozenset(("Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp"))' 'UNSAFE_CATEGORIES = frozenset(("Cc", "Cf", "Cs", "Cn", "Zl", "Zp"))'
mutant R7M10_category_cn_dropped r7 'UNSAFE_CATEGORIES = frozenset(("Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp"))' 'UNSAFE_CATEGORIES = frozenset(("Cc", "Cf", "Cs", "Co", "Zl", "Zp"))'
mutant R7M11_category_zl_zp_dropped r7 'UNSAFE_CATEGORIES = frozenset(("Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp"))' 'UNSAFE_CATEGORIES = frozenset(("Cc", "Cf", "Cs", "Co", "Cn"))'
mutant R7M12_user_backup_tag_constant r7 '    return "%s_%s" % (safe, hashlib.sha256(os.fsencode(base)).hexdigest()[:8])' '    return "x"'
mutant R7M13_base_opened_following_links r7 'os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0))' 'os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_CLOEXEC", 0))'
mutant R7M14_no_identity_check_project_backup r7 '        same_dir(bfd, base)
' '        pass
' '        same_dir(bfd, base)
' '        pass
' '        same_dir(bfd, base)
' '        pass
'
mutant R7M15_no_identity_check_user_backup r7 '            same_dir(bfd, base)
            name = slot_name(slot, "@%s.yml" % tag)' '            name = slot_name(slot, "@%s.yml" % tag)' '        same_dir(bfd, base)
        private_copy(ufile, dest)
        same_dir(bfd, base)' '        private_copy(ufile, dest)'
mutant R7M16_help_bypasses_emitter r7 '            _emit(file, message, "", block=True)' '            file.write(message)'
mutant R7M17_brokenpipe_mapped_as_oserror r7 '                if isinstance(exc, BrokenPipeError):
                    raise
                rc = report_exception(exc)' '                rc = report_exception(exc)'
mutant R7M18_write_time_foreign_check_removed r7 '            if check_foreign:
                self.refuse_foreign(path, what)' '            pass'
mutant R7M19_rel_shows_key_shaped r7 '        return "<path hidden: key-shaped>" if looks_secret(r) else r' '        return r'
mutant R7M20_internal_error_shows_message r7 '        emit_err("constitution_decisions: internal error (%s)" % name)' '        emit_err("constitution_decisions: internal error (%s) %s" % (name, os.getcwd()))'
mutant R7M21_tighten_by_path r7 '        os.fchmod(fd, 0o700)' '        os.chmod(base, 0o700)'
fi
if [ "${DEC_MUTANTS_ROUND:-all}" = all ] || [ "${DEC_MUTANTS_ROUND:-all}" = r8 ]; then
# round 8: the round-7 review minors (m1-m4) and the round-8 review (B-2 flush on every path of run_cli, MINOR-2
# truthful intent message). Each must break test_round8.sh. The B-2 per-path mutants remove the final flush on ONE
# path at a time (they skip flush_outcome for one exit code, or on the SystemExit path).
mutant R8M01_no_flush_success_path r8 '    return flush_outcome(rc)' '    return rc if rc == 0 else flush_outcome(rc)'
mutant R8M02_no_flush_any_error_path r8 '    return flush_outcome(rc)' '    return flush_outcome(rc) if rc == 0 else rc'
mutant R8M03_no_flush_report_exception_path r8 '    return flush_outcome(rc)' '    return rc if rc == 3 else flush_outcome(rc)'
mutant R8M04_no_flush_report_internal_path r8 '    return flush_outcome(rc)' '    return rc if rc == 1 else flush_outcome(rc)'
mutant R8M05_no_flush_keyboardinterrupt_path r8 '    return flush_outcome(rc)' '    return rc if rc == 130 else flush_outcome(rc)'
mutant R8M06_no_flush_systemexit_path r8 '        frc = flush_outcome(0 if ok else 2)' '        frc = 0'
mutant R8M07_flush_masks_error_code r8 '        return report_exception(exc) if rc == 0 else rc' '        return report_exception(exc)'
mutant R8M08_pipe_flush_masks_error_code r8 '        return report_internal(type(exc).__name__) if rc == 0 else rc
    except OSError' '        return report_internal(type(exc).__name__)
    except OSError'
mutant R8M09_flush_no_silence r8 '            out.flush()
        except OSError:
            _silence_stdout()
            raise' '            out.flush()
        except OSError:
            raise'
mutant R8M10_flush_swallowed r8 '            out.flush()
        except OSError:
            _silence_stdout()
            raise' '            out.flush()
        except OSError:
            _silence_stdout()'
mutant R8M11_uesc_5digit r8 '    return "\\u%04x" % o if o <= 0xFFFF else "\\U%08x" % o' '    return "\\u%04x" % o'
mutant R8M12_no_nul_cut r8 '                val = val.split("\0", 1)[0]' '                val = val'
mutant R8M13_nul_keep_tail r8 '                val = val.split("\0", 1)[0]' '                val = val.split("\0", 1)[-1]'
mutant R8M14_same_dir_no_inode r8 '    if stat.S_ISLNK(a.st_mode) or (a.st_dev, a.st_ino) != (b.st_dev, b.st_ino):' '    if stat.S_ISLNK(a.st_mode):'
mutant R8M15_tag_no_hash r8 '    return "%s_%s" % (safe, hashlib.sha256(os.fsencode(base)).hexdigest()[:8])' '    return "%s_%s" % (safe, "00000000")'
mutant R8M16_intent_message_untruthful r8 '    if step == ".constitution/decisions.intent":
        return' '    if False:
        return'
mutant R8M17_intent_message_drops_backup_note r8 '+ ("; the backup this run took is kept" if backed_up else ""))' ')'
fi
# round-11 mutants (test_round11.sh): stale-temp prefix match, relative XDG / HOME honoured, BACKUP_KEEP=0 accepted
mutant R11B1_stale_temp_prefix_match r11 'if rx.fullmatch(e) and os.path.isfile(fp)' 'if e.startswith("." + name + ".tmp.") and os.path.isfile(fp)'
mutant R11B2_stale_temp_hex_loosened r11 'r"\.tmp\.[0-9a-f]{12}")' 'r"\.tmp\.[0-9a-f]{0,12}")'
mutant R11C1_relative_xdg_honoured r11 'if not base or not os.path.isabs(base):' 'if not base:'
mutant R11C2_relative_home_trusted r11 'if h and os.path.isabs(h):' 'if h:'
mutant R11E1_backup_keep_zero_accepted r11 'r"[1-9][0-9]{0,3}", v)' 'r"[0-9]{1,4}", v)'
echo "own mutants: applied=$applied killed=$killed survived=$survived not_applied=$not_applied"
if [ "$not_applied" -ne 0 ]; then
  echo "own mutants: FAIL - $not_applied mutant(s) did not apply (stale anchors):$not_applied_names"
fi
[ "$survived" -eq 0 ] && [ "$not_applied" -eq 0 ]
