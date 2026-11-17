"""D23/D24: does `git fetch` honour remote.<name>.uploadpack from the repository config (file:// transport),
and does `-c protocol.file.allow` matter? Real git, scratch sandbox; prints one TSV row per experiment."""
import os, subprocess, sys, tempfile, shutil
d = tempfile.mkdtemp(prefix="gt_up.", dir=sys.argv[1])
env = {"PATH": "/usr/bin:/bin", "HOME": d, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.path.join(d, "gc")}
def g(*a, cwd=None, check=True):
    return subprocess.run(["git"] + list(a), cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=check)
bare = os.path.join(d, "b.git"); work = os.path.join(d, "w")
g("init", "-q", "--bare", bare); g("clone", "-q", bare, work)
g("-C", work, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "x")
g("-C", work, "push", "-q", "origin", "HEAD:refs/heads/main")
mark = os.path.join(d, "UPLOADPACK_RAN")
prog = os.path.join(d, "up.sh")
with open(prog, "w") as f:
    f.write("#!/bin/sh\ntouch %s\nexec git-upload-pack \"$@\"\n" % mark)
os.chmod(prog, 0o700)
g("-C", work, "config", "remote.origin.uploadpack", prog)
r = g("-C", work, "fetch", "--no-tags", "origin", "+refs/heads/*:refs/remotes/origin/*", check=False)
print("D23\tremote.<n>.uploadpack in repo config runs on a file:// fetch (exact engine refspec)\t%s\trc=%d" % (os.path.exists(mark), r.returncode))
os.unlink(mark) if os.path.exists(mark) else None
r = g("-C", work, "-c", "remote.origin.uploadpack=git-upload-pack", "fetch", "--no-tags", "origin", "+refs/heads/*:refs/remotes/origin/*", check=False)
print("D24\twith -c remote.origin.uploadpack=git-upload-pack the repo-config program still runs (the -c pair does not override it)\t%s\trc=%d" % (os.path.exists(mark), r.returncode))
shutil.rmtree(d)
