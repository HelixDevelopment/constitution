import sys
p=sys.argv[1]
s=open(p,encoding='utf-8').read()
old="""#   vcs, proxy, serverOption, promisor ...) is refused. The remaining gap is the time
#   between that check and git reading its config for the operation itself.
"""
new="""#   vcs, proxy, serverOption, promisor ...) is refused. The remaining gap is the time
#   between that check and git reading its config for the operation itself.
#   A refusal in the middle of the push loop names the remotes this run already
#   pushed the checked main to; no further remote is pushed after it.
"""
assert s.count(old)==1
s=s.replace(old,new)
open(p,'w',encoding='utf-8').write(s)
