# Start sequence of an acquire with the gated start process (diagram source)

This is the Mermaid source of `start_intent.svg`. It is kept as a fenced block in Markdown, the form the repository
uses for diagrams, because the git-env census accepts only a closed list of file types. The block below is
byte-identical to the file that mermaid-cli rendered (`mmdc.log`); its sha256 is `de55c98d7eae98eab1101b4c1f0d40e7117497c43bfd201b593dcb33de103cfc`.

```mermaid
sequenceDiagram
  autonumber
  participant A as Acquire A (starter)
  participant G as Start process (jev-start-gate.sh)
  participant R as Lease registry (under the lock)
  participant L as llmctl
  participant B as Acquire B
  A->>G: spawn, outside the lock, it waits on a fifo only A writes
  A->>R: one write: set + starting mark + start intent naming A and G (pid, start time)
  alt the mark is refused
    A->>G: no (G exits 79, llmctl never runs)
  else the mark is written
    A->>G: go
    G->>L: exec timeout llmctl start (process group id = G's pid)
    Note over A,G: A SIGKILLed here: G keeps running. A killed before go: G reads end-of-file, exits 79
    B->>R: ticket: which intents' start processes are provably gone now
    B->>L: capacity --json (read after the ticket)
    alt A dead and G (or its group) may still run, or was not gone at B's ticket
      B->>R: intent kept: no adoption, no second start
    else A dead and G gone at B's ticket
      B->>R: set exists -> constitution-started, no set and unit runs -> lease-less constitution-started set with an owed stop, unit absent -> intent removed
    end
    G-->>A: exit code (A alive): A records the result and removes its own intent
  end
```
