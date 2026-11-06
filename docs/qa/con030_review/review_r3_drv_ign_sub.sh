#!/usr/bin/env bash
# A suite writes an IGNORED file during the run: $1 runner, $2 fixture dir (new), $3 where: sub|root.
# sub: the submodule `lib` ignores out/ and the suite writes lib/out/x. root: the root ignores out/, the suite writes out/x.
set -u
RUN="${1:?runner}"; F="${2:?fixture}"; W="${3:?where}"; [ ! -e "$F" ] || exit 2
gitc(){ git -C "$1" -c user.email=a@b -c user.name=t "${@:2}"; }
mkdir -p "$F"; git init -q "$F/lib"; printf 'out/\n' > "$F/lib/.gitignore"; gitc "$F/lib" add .gitignore; gitc "$F/lib" commit -q -m i
mkdir -p "$F/root/tests/a"; git init -q "$F/root"; printf 'out/\n' > "$F/root/.gitignore"; gitc "$F/root" add .gitignore; gitc "$F/root" commit -q -m init
if [ "$W" = sub ]; then tgt='lib/out/x'; else tgt='out/x'; fi
printf '#!/usr/bin/env bash\ncd "$(dirname "$0")/../.."\nmkdir -p "$(dirname %s)"; date +%%s%%N > %s\necho "passed=1 failed=0"\n' "$tgt" "$tgt" > "$F/root/tests/a/test_x.sh"
git -C "$F/root" -c protocol.file.allow=always submodule add -q "$F/lib" lib >/dev/null 2>&1 || echo "add refused"
bash "$RUN" --root "$F/root" --generate-manifest --write >/dev/null 2>&1
gitc "$F/root" add -A; gitc "$F/root" commit -q -m s
git -C "$F/root" status --porcelain --ignore-submodules=none | head -3
bash "$RUN" --root "$F/root" --out "$F/out" --include-heavy > "$F/run.log" 2>&1; echo "rc=$?"
ls -la "$F/root/$tgt" 2>&1 | cut -c1-120
grep -E '^(RESULT|TREE|IDENTITY|DIRTY)' "$F/run.log" | cut -c1-200
