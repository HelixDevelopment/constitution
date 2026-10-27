# opencode decision-layer coverage gaps (honest record, §11.4.280(C))

The opencode plugin hook (`tool.execute.before`) intercepts direct tool calls only.
It does NOT intercept:
- MCP-tool calls invoked through other MCP servers
- subagent/task calls spawned inside a session

Those call classes bypass the decision-layer gate on this platform. Claiming full
coverage would be a §7.1 bluff.
