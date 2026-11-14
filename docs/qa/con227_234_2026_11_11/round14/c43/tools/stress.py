# stress.py N SECONDS: N busy processes for SECONDS (controlled CPU load for the C43 reproduction)
import multiprocessing as m, sys, time
def spin(t):
    e = time.time() + t
    while time.time() < e:
        pass
if __name__ == "__main__":
    n, t = int(sys.argv[1]), float(sys.argv[2])
    ps = [m.Process(target=spin, args=(t,)) for _ in range(n)]
    [p.start() for p in ps]; [p.join() for p in ps]
