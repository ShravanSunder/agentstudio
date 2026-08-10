# Bug packet

## Symptom

AgentStudio `0.0.74` is materially better than the prior beta, but production still shows bursty CPU around 15% in Activity Monitor. The investigation must identify all recurring hotspots and distinguish product work from diagnostic overhead.

## Expected

Normal interactive work should not spend sustained CPU on unrelated global invalidations, repeated unchanged Git scans, broad atom reads, or diagnostic export. MainActor work should be bounded to the affected surface and entity, and startup terminal creation must not leave the main thread synchronously blocked in native filesystem setup.

## Scope

- Stable production `0.0.74`.
- A fresh worktree debug observability run from the current checkout.
- A local beta diagnostic only if a current artifact can be produced safely.
- Git/FSEvents, terminal/Ghostty, Repo Explorer, coordinators, MainActor application, atom reads/derived values, rendering proxies, EventBus delivery, and OTLP.

## Non-goals

- No product-code edits, configuration changes, preference changes, release changes, or fixes in this investigation.
- No claim that OTLP blocks MainActor; OTLP is measured as a possible overhead source only.
- No claim that elapsed duration equals CPU time.

## Runtime anchors

- Stable process previously observed: PID `95537`, version `0.0.74`, build `115`, stable channel.
- Worktree HEAD: `3960f3b22`.
- Installed beta is stale: `0.0.73-beta.10`; it does not contain PR #251.
- Shared collector/Victoria services are healthy at investigation start.

## Acceptance bar for a hotspot

Each hotspot needs:

1. a source path and actor/ownership boundary;
2. a fresh rate or stack/cost measurement;
3. the downstream MainActor or presentation edge, if any;
4. an atom/invalidation interpretation, or an explicit statement that no atom edge is established;
5. confidence and the smallest next proof when evidence is incomplete.
