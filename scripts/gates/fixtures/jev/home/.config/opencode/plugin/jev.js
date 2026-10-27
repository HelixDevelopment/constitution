// jev decision-layer gate plugin (fixture copy) — intercepts tool calls in opencode.
export const JevGate = async () => ({
  "tool.execute.before": async (input, output) => {
    // consults the decide gateway before allowing the tool call
  },
})
