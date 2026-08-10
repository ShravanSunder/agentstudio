# Terminal and Ghostty hotspot

## Source and admission

Ghostty actions enter `GhosttyActionRouter`, where high-volume action tags are selectively excluded from tracing but retained actions still create attributes and enqueue trace records. Replaceable local terminal state is accumulated by surface/pane and drained through `TerminalLocalActionDrainScheduler`.

## Production evidence

The full production capture recorded:

- 13,660 offered terminal facts;
- 12,114 replacements (88.7% removed before MainActor work);
- 1,527 scheduled drains and 19 follow-up drains;
- 1,545 MainActor tasks.

In the trailing two-minute window, 2,421 offers became 266 MainActor tasks. Titles normally wait near their one-second deadline by design: average queue age was about 940 ms. That elapsed age is scheduler delay, not 940 ms of CPU or MainActor execution.

Steady immediate admission was about 2.9 ms average and 4.4 ms p95. Startup immediate admission reached 812 ms, which is real startup contention. Compact apply averaged about 0.12 ms in steady state and maxed near 1 ms.

## Interpretation

`accepted` — terminal source volume is high but the local accumulator is doing the intended work. PR #251’s local title/pane invalidation path is proportional in the observed production window. It is not the leading remaining CPU hotspot.

`accepted` — startup has a separate admission/delivery burst; it should not be conflated with steady title debounce.

`unresolved` — the exact retained Ghostty action tags responsible for the roughly 22 actions/second of tracing volume need a fresh per-tag count if diagnostic overhead is to be reduced. Current aggregate telemetry reports the `ghostty.action.received` body but not a safe action-tag histogram.
