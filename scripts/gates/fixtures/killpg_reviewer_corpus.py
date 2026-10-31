#!/usr/bin/env python3
"""Regression corpus for CM-KILLPG-PGID-GUARD (anchor 11.4.263), review round 3 -> round 4.

Provenance: the 188 single-file shapes an independent Opus reviewer generated against commit 2315d04
(round-3 review, NO-GO). Every shape is INERT TEXT written to disk for the gate's scanner to read; nothing
here is ever executed. Almost every shape is a real way to reach a process-group signal that the
anchor forbids to leave unguarded; the ids in KNOWN_GAP are the few INDIRECT name-flow shapes
(variable assigned a string then run, computed attribute names, aliasing through a function value, exec
wrappers) that no static text scanner can see - they are recorded, NOT asserted.

Usage: python3 killpg_reviewer_corpus.py <outdir>      writes <outdir>/<id>/mod_<id>.<ext>
       python3 killpg_reviewer_corpus.py --known-gap   prints the KNOWN_GAP ids, one per line
"""
import os
import sys

C = {}
C['p01.py']='import os\nos.killpg(os.getpgid(p.pid), 9)\n'
C['p02.py']='import os\nos.killpg(1, 9)\n'
C['p03.py']='import os, subprocess\nsubprocess.run("kill -9 -1", shell=True)\n'
C['p04.py']='import os\nos.system("kill -9 -1")\n'
C['p05.py']='import subprocess\nsubprocess.run(["kill","-9","-1"])\n'
C['p06.py']='import subprocess\nsubprocess.run(["bash","-c","kill -9 -1"])\n'
C['p07.py']='import os\nf"{os.killpg(pg, 9)}"\n'
C['p08.py']='from os import killpg as k\nk(pg, 9)\n'
C['p09.py']='import os\nk = getattr(os, "killpg")\nk(pg, 9)\n'
C['p10.py']='import os\nk, j = os.killpg, 1\nk(pg, 9)\n'
C['p11.py']='import os\nd = {"x": os.killpg}\nd["x"](pg, 9)\n'
C['p12.py']='import os\ndef f(k=os.killpg):\n    k(pg, 9)\n'
C['p13.py']='import os\nk = os.__dict__["killpg"]\nk(pg, 9)\n'
C['p14.py']='import os\nos.kill(-pg, 9)\n'
C['p15.py']='import os\nos.kill(0 - pg, 9)\n'
C['p16.py']='import os\nos.killpg(\n    pg, 9)\n'
C['p17.py']='import os\nx = "a"; os.killpg(pg, 9)\n'
C['p18.py']='import os\ns = """\ndoc\n"""\nos.killpg(pg, 9)\n'
C['p19.py']="import os\ns = '''x'''; os.killpg(pg,9)\n"
C['p20.py']='import os\r\nos.killpg(pg, 9)\r\n'
C['p21.py']='import os\n\tos.killpg(pg, 9)\n'
C['p22.py']='import os\nos.killpg (pg, 9)\n'
C['p23.py']='import os\ns = "\\\\"; os.killpg(pg, 9)\n'
C['p24.py']='import os\ns = r"\\"; os.killpg(pg, 9)\n'
C['p25.py']='import os\nos.kill(-1, 9)\n'
C['p26.py']='import os\ns = "x # y"; os.killpg(pg,9)\n'
C['p27.py']='import os\nimport subprocess as sp\nsp.check_call("kill -- -1", shell=True)\n'
C['p28.py']='import os\nsubprocess.Popen(f"kill -9 -{pg}", shell=True)\n'
C['p29.py']='import os\ncmd = "kill -9 -1"\nos.system(cmd)\n'
C['p30.py']='import os\nos.kill(-os.getpgid(p.pid), 9)\n'
C['p31.py']='import signal, os\nfrom os import *\nkillpg(pg, 9)\n'
C['p32.py']='import os\nk = vars(os)["kill"+"pg"]\nk(pg,9)\n'
C['p33.py']='import os\n# ok\nif pid > 1:\n    os.killpg(pg, 9)\n'
C['p34.py']='import os\nx = """a\'\'\' b"""; os.killpg(pg, 9)\n'
C['p35.py']='import os\nx = f"{\'}\'}"; os.killpg(pg, 9)\n'
C['p36.py']='import os\nx = "ü"; os.killpg(pg, 9)\n'
C['p37.py']='import os\nx = b"\\x00"; os.killpg(pg, 9)\n'
C['p38.py']='import os\nos.killpg(pg, 9) if True else None\n'
C['p39.py']='import os\nx = 1 \\\n  ; os.killpg(pg, 9)\n'
C['p40.py']='import os\npg = 1\nif pg >= 1:\n    os.killpg(pg, 9)\n'
C['s01.sh']='kill -9 -1\n'
C['s02.sh']='kill -- -1\n'
C['s03.sh']='kill -s KILL -"$pg"\n'
C['s04.sh']='kill -9 -"$pg"\n'
C['s05.sh']='kill -9 -- -"$pg"\n'
C['s06.sh']='pkill -g "$pg"\n'
C['s07.sh']='bash -c "kill -9 -1"\n'
C['s08.sh']="sh -c 'kill -9 -1'\n"
C['s09.sh']='eval "kill -9 -1"\n'
C['s10.sh']='ok "$(kill -9 -1)"\n'
C['s11.sh']='die "$(kill -9 -1)"\n'
C['s12.sh']='ok() { kill -9 -1; }\nok x\n'
C['s13.sh']='echo x | bash\nkill -9 -1\n'
C['s14.sh']='bash <<EOF\nkill -9 -1\nEOF\n'
C['s15.sh']='cat <<EOF | bash\nkill -9 -1\nEOF\n'
C['s16.sh']='cat <<EOF > /tmp/x.sh\nkill -9 -1\nEOF\nbash /tmp/x.sh\n'
C['s17.sh']="x='it'\\''s'; kill -9 -1\n"
C['s18.sh']='x="a\\"b"; kill -9 -1\n'
C['s19.sh']='kill \\\n  -9 -1\n'
C['s20.sh']='kill -9 -1\r\n'
C['s21.sh']='\tkill -9 -1\n'
C['s22.sh']='kill -KILL -1\n'
C['s23.sh']='kill -n 9 -1\n'
C['s24.sh']='kill -9 "-$pg"\n'
C['s25.sh']='kill -TERM -"${pg}"\n'
C['s26.sh']='/bin/kill -9 -1\n'
C['s27.sh']='command kill -9 -1\n'
C['s28.sh']='builtin kill -9 -1\n'
C['s29.sh']='echo "# x"; kill -9 -1\n'
C['s30.sh']='x=$(printf "%s" a)#; kill -9 -1\n'
C['s31.sh']='ok "$(eval kill -9 -1)"\n'
C['s32.sh']='die "`kill -9 -1`"\n'
C['s33.sh']="log 'x'; kill -9 -1\n"
C['s34.sh']='k=kill; $k -9 -1\n'
C['s35.sh']='printf "kill -9 -1" | sh\n'
C['s36.sh']='echo "kill -9 -1" | sudo bash\n'
C['s37.sh']="ok \"$(bash -c 'kill -9 -1')\"\n"
C['s38.sh']='timeout 5 kill -9 -1\n'
C['s39.sh']='xargs kill -9 <<<"-1"\n'
C['s40.sh']='read -r x <<EOF\nkill -9 -1\nEOF\nkill -9 -1\n'
C['s41.sh']="cat <<'EOF'\nfoo\nEOF\nkill -9 -1\n"
C['s42.sh']='x="$(cat <<EOF\nkill -9 -1\nEOF\n)"; eval "$x"\n'
C['s43.sh']='kill -9 -1 # x\n'
C['s44.sh']='ok "x" && kill -9 -1\n'
C['s45.sh']='[[ $x == "a" ]] && kill -9 -1\n'
C['s46.sh']='kill -9 -$pg\n'
C['s47.sh']='kill -9 -"$(cat pgfile)"\n'
C['s48.sh']="kill -9 -$'1'\n"
C['s49.sh']='trap "kill -9 -1" EXIT\n'
C['s50.sh']='ssh h "kill -9 -1"\n'
C['s51.sh']='if true; then kill -9 -1; fi\n'
C['s52.sh']='echo "${x:-"y"}"; kill -9 -1\n'
C['s53.sh']="echo '\"'; kill -9 -1\n"
C['s54.sh']='echo "$(echo ")")"; kill -9 -1\n'
C['s55.sh']='env kill -9 -1\n'
C['g01.go']='package m\nfunc f(){ syscall.Kill(-pg, 9) }\n'
C['g02.go']='package m\nfunc f(){ unix.Kill(-pg, 9) }\n'
C['g03.go']='package m\nfunc f(){ syscall.Kill(-1, 9) }\n'
C['g04.go']='package m\nvar s = `\nx\n`\nfunc f(){ syscall.Kill(-pg, 9) }\n'
C['g05.go']='package m\nfunc f(){ exec.Command("bash","-c","kill -9 -1").Run() }\n'
C['g06.go']='package m\nfunc f(){ exec.Command("kill","-9","-1").Run() }\n'
C['g07.go']='package m\nvar r = \'"\'\nfunc f(){ syscall.Kill(-pg, 9) }\n'
C['g08.go']='package m\nvar s = "/*"\nfunc f(){ syscall.Kill(-pg, 9) }\n'
C['g09.go']='package m\nfunc f(){ syscall.Kill(0-pg, 9) }\n'
C['g10.go']='package m\nfunc f(){ k := syscall.Kill; k(-pg, 9) }\n'
C['r01.rs']='fn f(){ kill(Pid::from_raw(-pg), Signal::SIGKILL); }\n'
C['r02.rs']='fn f(){ killpg(Pid::from_raw(pg), Signal::SIGKILL); }\n'
C['r03.rs']='fn f(){ let s = r#"\\"#; killpg(p, s); }\n'
C['r04.rs']="fn f<'a>(x:&'a str){ killpg(p, s); }\n"
C['r05.rs']='fn f(){ Command::new("sh").arg("-c").arg("kill -9 -1").spawn(); }\n'
C['c01.c']='void f(){ kill(-pg, 9); }\n'
C['c02.c']='void f(){ killpg(pg, 9); }\n'
C['c03.c']='void f(){ system("kill -9 -1"); }\n'
C['c04.c']='#define X "/*"\nvoid f(){ killpg(pg, 9); }\n'
C['c05.c']='void f(){ char c = \'"\'; killpg(pg, 9); }\n'
C['t01.sh']='ok() { eval "$1"; }\nok "kill -9 -1"\n'
C['t02.sh']='die() { bash -c "$*"; }\ndie "kill -9 -1"\n'
C['t03.sh']='alias ok=eval\nok "kill -9 -1"\n'
C['t04.sh']='printf "kill -9 -1" > /tmp/k; . /tmp/k\n'
C['t05.sh']='echo "kill -9 -1" > /tmp/k.sh; bash /tmp/k.sh\n'
C['t06.sh']='c="kill -9 -1"; $c\n'
C['t07.sh']='c="kill -9 -1"; eval "$c"\n'
C['t08.sh']='arr=(kill -9 -1); "${arr[@]}"\n'
C['t09.sh']='log "kill -9 -1" | sh\n'
C['t10.sh']='cat > /tmp/k <<EOF\nkill -9 -1\nEOF\nsource /tmp/k\n'
C['t11.sh']='tee /tmp/k >/dev/null <<EOF\nkill -9 -1\nEOF\n. /tmp/k\n'
C['t12.sh']='grep -q x f && kill -9 -1\n'
C['t13.sh']='set -- -9 -1; kill "$@"\n'
C['t14.sh']='kill -9 -1 &\n'
C['t15.sh']='{ kill -9 -1; }\n'
C['t16.sh']='( kill -9 -1 )\n'
C['t17.sh']='[ -n "$x" ] && kill -9 -1\n'
C['t18.sh']='echo "$(kill -9 -1)"\n'
C['t19.sh']="echo '$(kill -9 -1)'\n"
C['t20.sh']='x=$(kill -9 -1)\n'
C['t21.sh']='x=`kill -9 -1`\n'
C['t22.sh']='local x="$(kill -9 -1)"\n'
C['t23.sh']='printf -v x "%s" "$(kill -9 -1)"\n'
C['t24.sh']='case $x in a) kill -9 -1;; esac\n'
C['t25.sh']='for i in 1; do kill -9 -1; done\n'
C['t26.sh']='until false; do kill -9 -1; done\n'
C['t27.sh']='echo $(( 1 )) ; kill -9 -1\n'
C['t28.sh']='echo "${a#x}"; kill -9 -1\n'
C['t29.sh']='echo ${a#x}; kill -9 -1\n'
C['t30.sh']='echo $#; kill -9 -1\n'
C['t31.sh']='x=a#b; kill -9 -1\n'
C['q01.py']='import os\nsp.run(cmd := "kill -9 -1", shell=False)\n'
C['q02.py']='import subprocess\nsubprocess.run(\n    "kill -9 -1",\n    shell=True,\n)\n'
C['q03.py']='import subprocess\nsubprocess.run(\n    ["kill",\n     "-9",\n     "-1"])\n'
C['q04.py']='import subprocess\nCMD = ["kill", "-9", "-1"]\nsubprocess.run(CMD)\n'
C['q05.py']='import asyncio\nawait asyncio.create_subprocess_shell("kill -9 -1")\n'
C['q06.py']='import asyncio\nawait asyncio.create_subprocess_exec("kill", "-9", "-1")\n'
C['q07.py']='import pexpect\npexpect.spawn("kill -9 -1")\n'
C['q08.py']='import os\nos.execvp("kill", ["kill","-9","-1"])\n'
C['q09.py']='import os\nos.popen("kill -9 -1")\n'
C['q10.py']='import subprocess\nsubprocess.run("kill -9 -1".split())\n'
C['q11.py']='import fc_common\nfc_common.safe_killpg(pg, 9)\n'
C['q12.py']='import fc_common\nfc_common.safe_killpg(pg, 9); os.killpg(pg, 9)\n'
C['q13.py']='# import fc_common\nfrom fc_common import safe_killpg\nsafe_killpg(1, 9)\n'
C['q14.py']='import fc_common\nfc_common.safe_killpg = os.killpg\nfc_common.safe_killpg(pg,9)\n'
C['q15.py']='import fc_common\nsetattr(fc_common, "safe_killpg", os.killpg)\nfc_common.safe_killpg(pg,9)\n'
C['q16.py']='import fc_common\nimport os as fc\nfc.killpg(pg,9)\n'
C['q17.py']='import fc_common\nfc_common.__dict__["safe_killpg"] = os.killpg\nfc_common.safe_killpg(pg,9)\n'
C['q18.py']='import sys\nsys.modules["fc_common"] = os\nimport fc_common\nfc_common.safe_killpg(pg,9)\n'
C['q19.py']='"""\nimport fc_common\n"""\nfc_common.safe_killpg(pg, 9)\n'
C['q20.py']='def safe_killpg(p, s):\n    os.killpg(p, s)\nsafe_killpg(pg, 9)\n'
C['q21.py']='def safe_killpg(p, s): return 0\nos.killpg(pg,9)\n'
C['u01.sh']='. <(echo "kill -9 -1")\n'
C['u02.sh']='bash <(echo "kill -9 -1")\n'
C['u03.sh']='source /dev/stdin <<<"kill -9 -1"\n'
C['u04.sh']='mapfile -t a <<<"kill -9 -1"; "${a[@]}"\n'
C['u05.sh']='printf "%s\\n" "kill -9 -1" >> ~/.bashrc\n'
C['u06.sh']='(echo "kill -9 -1") | bash\n'
C['u07.sh']='echo "kill -9 -1" |\n  bash\n'
C['u08.sh']='crontab <<EOF\n* * * * * kill -9 -1\nEOF\n'
C['u09.sh']='at now <<EOF\nkill -9 -1\nEOF\n'
C['u10.sh']='systemd-run --user sh -c "kill -9 -1"\n'
C['u11.py']='import sh\nsh.kill("-9", "-1")\n'
C['u12.py']='c.sudo("kill -9 -1")\n'
C['u13.py']='import os\nos.spawnlp(os.P_WAIT, "kill", "kill", "-9", "-1")\n'
C['u14.py']='import subprocess\nsubprocess.run(args="kill -9 -1", shell=True)\n'
C['u15.py']='import subprocess\nsubprocess.run(\n    "kill -9 -1",\n    shell=True)\n'
C['u16.py']='import subprocess\nsubprocess.run(["sh", "-c",\n    "kill -9 -1"])\n'
C['u17.py']='import subprocess\nsubprocess.run(["sh",\n "-c", "kill -9 -1"])\n'
C['u18.py']='import os\nos.system(" ".join(["kill", "-9", "-1"]))\n'
C['u19.py']='import os\nos.system("kill -9 " + "-1")\n'
C['u20.py']='import os\nos.system("kill -9 -%d" % pg)\n'
C['u21.py']='import os\nos.system("kill -9 -{}".format(pg))\n'

# Indirect shapes no text scanner can see (verified unflagged by the pre-round-3 base gate as well).
KNOWN_GAP = {
    "g10", "p28", "p32", "q03", "q04", "s19", "s34", "s39", "s47", "s48",
    "t13", "u11", "u19", "u20", "u21",
}


# Sanctioned usage (the real fc_common wrapper behind its real import): the gate MUST PASS these.
BENIGN = {"q11"}


def main(argv):
    if len(argv) == 2 and argv[1] == "--benign":
        print("\n".join(sorted(BENIGN)))
        return 0
    if len(argv) == 2 and argv[1] == "--known-gap":
        print("\n".join(sorted(KNOWN_GAP)))
        return 0
    if len(argv) != 2:
        sys.stderr.write(__doc__)
        return 2
    out = argv[1]
    for name, text in C.items():
        d = os.path.join(out, name.split(".")[0])
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "mod_" + name), "w", encoding="utf-8", newline="") as fh:
            fh.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
