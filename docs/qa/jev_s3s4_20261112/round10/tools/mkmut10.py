#!/usr/bin/env python3
"""Round-10 mutants (reviewer set re-anchored + own) of scripts/jev/jev-place.sh. Same frame as the fixer's mkmut9.py: a T_START-frozen
base (T_START/T_MONO_T/T_MONO_TOK = clocks at process start), every substitution asserted to match exactly once, each
mutant a FULL copy of scripts/jev. usage: mkmut_rev.py <producer> <out>"""
import os, sys, hashlib, shutil
src, out = sys.argv[1], sys.argv[2]
base = open(src).read()
ANCHOR = 'clock_refresh\nfor n in "$RTMO"'
assert base.count(ANCHOR) == 1
base_t = base.replace(ANCHOR, 'clock_refresh\nT_START="$NOW"; T_MONO_T="$MONO_T"; T_MONO_TOK="$MONO_TOK"\nfor n in "$RTMO"', 1)

def sub(text, old, new, hint):
    n = text.count(old)
    assert n == 1, (hint, n)
    return text.replace(old, new, 1)

M = {}
M['CTRL'] = ('CONTROL: frozen base, no change', lambda t: t)
# --- reviewer mutants of the round-9 review, re-anchored on the round-10 producer where the code moved ---
M['R9-01'] = ('leases_save ACQ_REFRESH stamps heartbeat with the process-start clocks',
  lambda t: sub(t, '--arg rf "${ACQ_REFRESH:-0}" --argjson now "$NOW" --arg mo "$MONO_TOK"',
                   '--arg rf "${ACQ_REFRESH:-0}" --argjson now "$T_START" --arg mo "$T_MONO_TOK"', 'refresh clock'))
M['R9-02'] = ('reap_locked: the holder of a CLEARED mark also suspends lease TTLs',
  lambda t: sub(t, '    elif [ -n "$mh" ] && [ "$mh" != null ]; then live_h+="$mh "',
                   '    fi; if [ -n "$mh" ] && [ "$mh" != null ]; then live_h+="$mh "', 'live_h'))
M['R9-03'] = ('set_view: ownership by pid only (pid_start ignored) [re-anchored: finish_stop now uses set_view]',
  lambda t: sub(t, '((($k.pid_start // null) | tostring) == (if $pst == "" then "null" else $pst end))', 'true', 'ours pst'))
M['R9-04'] = ('arm_stop_locked: no reap before the re-judgement',
  lambda t: sub(t, '  local p="$1" kind="$2" cur why\n  reap_locked\n', '  local p="$1" kind="$2" cur why\n', 'arm reap'))
M['R9-05'] = ('age_of: a record from another boot is judged on wall time [re-anchored]',
  lambda t: sub(t, '    if [ "$b" != "$MONO_BOOT" ]; then echo "$AGE_EXPIRED"; return 0; fi\n', '', 'other boot'))
M['R9-06'] = ('MARK_TTL without the record waits',
  lambda t: sub(t, 'MARK_TTL=$(( STMO + 2 + RETRIES * LOCK_TMO + 30 ))', 'MARK_TTL=$(( STMO + 2 + 30 ))', 'mark ttl'))
M['R9-07'] = ("finish_stop_locked rc 0: deleted with another stopper's mark [re-anchored: finish_stop's rule_sole ignores the other mark]",
  lambda t: sub(t, '    if rule_sole "$claim" "$others" "$omark"; then', '    if rule_sole "$claim" "$others" 0; then', 'foreign delete'))
M['R9-08'] = ('mark_start_locked: a stopping mark elsewhere no longer refuses a start mark',
  lambda t: sub(t, "if jq -e 'any(.sets[]?; (.starting // null) != null or (.stopping // null) != null)' <<<\"$cur\" >/dev/null; then return 1; fi",
                   "if jq -e 'any(.sets[]?; (.starting // null) != null)' <<<\"$cur\" >/dev/null; then return 1; fi", 'start refuse stop'))
M['R9-09'] = ('arm_stop_locked: the stopping mark mono is the process-start monotonic clock',
  lambda t: sub(t, '  cur="$(jq -c --arg p "$p" --argjson m "$(me_mark)" \'.sets[$p].stopping = $m\' <<<"$cur")"',
                   '  cur="$(jq -c --arg p "$p" --argjson m "$(MONO_TOK="$T_MONO_TOK"; me_mark)" \'.sets[$p].stopping = $m\' <<<"$cur")"', 'arm mono'))
M['R9-10'] = ('reap_locked: ANY live mark suspends EVERY lease TTL',
  lambda t: sub(t, '        case "$live_h" in *" $h "*)', '        case "$live_h" in *" "?*)', 'any holder'))
M['R9-11'] = ('finish_stop_locked kept set: health not set pending (stays routable)',
  lambda t: sub(t, "\n       | .sets[$p].health = {state:\"pending\", reason:\"stopped (llmctl stop rc 0) while it held \\($n) lease(s); not observed since\", seq:$f, at:$now}' <<<\"$cur\")\"",
                   "' <<<\"$cur\")\"", 'kept health'))
M['R9-12'] = ('lease_json: pid_start not recorded',
  lambda t: sub(t, "heartbeat_at:$now,\n      heartbeat_mono:", "heartbeat_at:$now, pid_start:null,\n      heartbeat_mono:", 'lj pst'))
M['R9-13'] = ('holder_alive: a heartbeat exactly TTL old is expired (-lt)',
  lambda t: sub(t, '[ "$(age_of "$hb" "${5:-}")" -le "$ttl" ]', '[ "$(age_of "$hb" "${5:-}")" -lt "$ttl" ]', 'ttl edge'))
# --- own mutants of the round-10 rule ---
M['M10-01'] = ('rule_sole ignores other holders', lambda t: sub(t, '[ "$2" = 0 ] && [ "$3" = 0 ]; }', '[ "$3" = 0 ]; }', 'sole others'))
M['M10-02'] = ('rule_sole ignores a foreign mark', lambda t: sub(t, '[ "$2" = 0 ] && [ "$3" = 0 ]; }', '[ "$2" = 0 ]; }', 'sole omark'))
M['M10-03'] = ('rule_sole: a cleared mark (claim gone) is never sole', lambda t: sub(t, 'case "$1" in ours|gone) ;;', 'case "$1" in ours) ;;', 'sole gone'))
M['M10-04'] = ('finish_start: placed without checking this acquire still holds a lease',
  lambda t: sub(t, '[ "$claim" != noset ] && [ "$mine" = 1 ]; then', '[ "$claim" != noset ]; then', 'mine'))
M['M10-05'] = ('adoption guard removed: a profile this acquire tried to start can be adopted',
  lambda t: sub(t, '    case " $START_TRIED " in *" $p "*) log "candidate $p: this acquire tried to start it; it is not adopted as operator-started"; continue ;; esac\n', '', 'adopt'))
M['M10-06'] = ('age_of: a monotonic time ahead of the reader gives a negative age (pre-round-10)',
  lambda t: sub(t, '    if [ "$t" -le "$MONO_T" ]; then echo $(( MONO_T - t )); return 0; fi', '    echo $(( MONO_T - t )); return 0', 'mono ahead'))
M['M10-07'] = ('age_of: a future wall time gives a negative age', lambda t: sub(t, '  if [ "$at" -gt "$NOW" ]; then echo "$AGE_EXPIRED"; return 0; fi\n', '', 'wall ahead'))
_RB = '  jp="$(leases_token)"\n  reap_locked\n  if [ -n "$g0" ] && [ "$(leases_token)" != "$jp" ]; then log "the reap changed the registry after the capacity read; reading it again"; return 99; fi\n'
_GW = '  [ "$cur" = "$jp" ] || printf \'%s\\n\' "$cur" | leases_save\n  finalize_locked 0 0\n'
M['M10-08'] = ('plan_locked: the gateway write before the reap (pre-round-10 order)',
  lambda t: sub(sub(t, _RB, '', 'reap blk'), _GW, '  [ "$cur" = "$jp" ] || printf \'%s\\n\' "$cur" | leases_save\n' + _RB + '  finalize_locked 0 0\n', 'gw blk'))
M['M10-09'] = ('not-sole start result: no health pending (kept set stays routable)',
  lambda t: sub(t, '       | (if $n > 0 then .sets[$p].health = {state:"pending", reason:"llmctl start rc \\($src) recorded while \\($n) other lease(s) held the set; not observed since", seq:$f, at:$now} else . end)', '       | .', 'nsole health'))
M['M10-10'] = ('not-sole start result: every lease dropped (pre-round-10 leases:[])',
  lambda t: sub(t, '       | .sets[$p].leases = [(.sets[$p].leases // [])[] | select(.holder != $h)]', '       | .sets[$p].leases = []', 'nsole leases'))
M['M10-11'] = ('not-sole start result: a foreign mark is cleared too',
  lambda t: sub(t, "      '(if $c == \"ours\" then .sets[$p].starting = null else . end)\n       | .sets[$p].constitution_started = true", "      '(.sets[$p].starting = null | .sets[$p].stopping = null)\n       | .sets[$p].constitution_started = true", 'nsole mark'))
M['M10-12'] = ('not-sole rc 0 reported placed (handed -> placed)', lambda t: sub(t, '0) START_RES=handed ;;', '0) START_RES=placed ;;', 'handed'))
M['M10-13'] = ('not-sole failure reported failed: the caller runs a cleanup stop under the other holders', lambda t: sub(t, '*) START_RES=failed_kept ;;', '*) START_RES=failed ;;', 'failed kept'))
M['M10-14'] = ('not-sole start result: constitution_started not forced true',
  lambda t: sub(t, "\n       | .sets[$p].constitution_started = true\n", "\n       | .sets[$p].constitution_started = false\n", 'nsole cs'))
os.makedirs(out, exist_ok=True)
with open(os.path.join(out, 'index.tsv'), 'w') as idx:
    for k, (desc, f) in M.items():
        m = f(base_t)
        d = os.path.join(out, k, 'scripts', 'jev')
        if os.path.exists(d):
            raise SystemExit(f'exists: {d}')
        shutil.copytree(os.path.dirname(os.path.abspath(src)), d)
        p = os.path.join(d, 'jev-place.sh')
        open(p, 'w').write(m); os.chmod(p, 0o755)
        idx.write(f"{k}\t{desc}\t{hashlib.sha256(m.encode()).hexdigest()}\n")
print('ok', len(M))
