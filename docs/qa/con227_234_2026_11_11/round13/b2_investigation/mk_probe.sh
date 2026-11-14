L="$1"; K6="$2"
mkprobe() { # copied verbatim from tests/release/test_redact_cut.sh line 245
  printf '#!/usr/bin/env bash\n. %q\n%s\nrc_env_clean %q "$@"; r=$?\nprintf "rc=%%s\\n" "$r"\nprintf "a0=%%s\\n" "$(tr "\\0" "\\n" </proc/$$/cmdline | head -n 1)"\nprintf "envn=%%s\\n" "$(tr "\\0" "\\n" </proc/$$/environ | grep -c .)"\nprintf "child:%%s\\n" "$(env | cut -d= -f1 | sort | tr "\\n" " ")"\nprintf "zzread=%%s zzs=%%s\\n" "${ZZREAD-unset}" "${ZZS-unset}"\n[ -e /proc/$$/fd/9 ] && echo fd9=open || echo fd9=closed\n' "$L" "${3:-}" "$2" >"$1"; }
mkprobe "$K6/p5.sh" ZZREAD '_rc_env_state() { _RC_ENV_STATE=dirty; }'
