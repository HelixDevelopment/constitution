import sys
p = sys.argv[1]
s = open(p, encoding='utf-8', newline='').read()
old = """#   through `commit-tree -S` because commit-tree itself ignores that setting). So no inherited variable can select another repository, index, work
#   tree, object store, namespace, template, config injection, trace or replace ref.
#   CDPATH is removed. The script"""
new = """#   through `commit-tree -S` because commit-tree itself ignores that setting). So no
#   inherited variable can select another repository, index, work tree, object
#   store, namespace, template, config injection, trace, attribute source or replace
#   ref. CDPATH is removed. The script"""
assert s.count(old) == 1, 'old1'
s = s.replace(old, new)
old2 = """#   is, and it skips a trailing '#' comment paragraph.) `<KEY>-050` is a placeholder by default, and a value
#   matching --placeholder-re is never accepted as a real id (also not at publish):
#   a real item numbered 050 needs another --placeholder-re."""
new2 = """#   is, and it skips a trailing '#' comment paragraph.) `<KEY>-050` is a placeholder
#   by default, and a value matching --placeholder-re is never accepted as a real id
#   (not as the minted id, not as --item-id, not in any trailer check, also not at
#   publish): a real item numbered 050 needs another --placeholder-re."""
assert s.count(old2) == 1, 'old2'
s = s.replace(old2, new2)
open(p, 'w', encoding='utf-8', newline='').write(s)
print("ok")
