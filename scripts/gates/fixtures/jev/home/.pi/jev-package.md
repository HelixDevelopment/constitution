# pi decision-layer integration (documented fallback, §11.4.280)

pi has no PreToolUse hook mechanism verified for this host. Fallback: the pi
package `jev-decision-layer` is declared in pi's package manifest and the MCP
server `jev` is registered in pi's mcp config. Coverage gap: free-form tool
invocations are not gated.
