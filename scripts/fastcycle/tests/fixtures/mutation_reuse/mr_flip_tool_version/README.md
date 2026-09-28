# mr_flip_tool_version (control needle: toolchain changed)

get asks with tool_versions.python3 = 3.12.0 instead of the put's 3.11.0 (bash unchanged). DEC-23 names 'tool versions' as one of the 4 key components explicitly -- a toolchain upgrade must force re-verification, since a mutation's KILLED verdict was only ever proven true under the OLD toolchain.

**Expected:** `MISS`
