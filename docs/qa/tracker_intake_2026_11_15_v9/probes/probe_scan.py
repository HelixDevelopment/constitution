import importlib.util, sys
src = open(sys.argv[2]).read()
start = src.index('V = "FAKE'); end = src.index("def hits")
ns = {}; exec(src[start:end], ns)
spec = importlib.util.spec_from_file_location("ls", sys.argv[1]); S = importlib.util.module_from_spec(spec); spec.loader.exec_module(S)
miss=[];fp=[]
for i,t in ns["POS"]:
    k=[a for a,_ in S.scan_line(t)]
    if not k: miss.append(i)
for i,t in ns["NEG"]:
    k=[a for a,_ in S.scan_line(t)]
    if k: fp.append(i)
print("LEAKSCAN pos=%d miss=%d neg=%d leads=%d"%(len(ns["POS"]),len(miss),len(ns["NEG"]),len(fp)))
print("MISSED"," ".join(miss)); print("LEADS"," ".join(fp))
