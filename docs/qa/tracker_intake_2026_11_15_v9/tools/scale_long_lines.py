"""Time of secret_hits on a long repeated key line (token: and password=) at four lengths, for each lint
path given; growth is linear when each doubling about doubles the time. Gate-logic only (section 11.4.289)."""
import importlib.util, sys, time
def load(p, n):
    s = importlib.util.spec_from_file_location(n, p); m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
for path in sys.argv[1:]:
    il = load(path, "il" + str(abs(hash(path))))
    for unit, name in (("token:", "colon"), ("password=", "eq")):
        row = []
        for n in (5000, 10000, 20000, 40000):
            t = unit * n; t0 = time.perf_counter(); list(il.secret_hits(t)); row.append("%d:%.2fs" % (n, time.perf_counter() - t0))
        print(path.split("/")[-1], name, " ".join(row))
