import sys, os, importlib.util, time
repo, work = sys.argv[1], sys.argv[2]
sys.argv=[sys.argv[0]]
spec=importlib.util.spec_from_file_location("pm", os.path.join(repo,"tests/release/pvl_mutate.py")); M=importlib.util.module_from_spec(spec); spec.loader.exec_module(M)
box=os.path.join(work,"box"); w=os.path.join(work,"w"); os.makedirs(w, exist_ok=True)
M.sandbox(repo, box)
t=time.time()
try: print("api", M.api(box,w), round(time.time()-t,1), flush=True)
except Exception as e: print("api EXC", repr(e)[:300], flush=True)
for h in M.KILLERS:
    t=time.time(); print(h, M.run(box,w,h), round(time.time()-t,1), flush=True)
