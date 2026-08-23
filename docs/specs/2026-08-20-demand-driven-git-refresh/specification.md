# Demand-Driven Git Refresh Specification

Requirements: [Demand-Driven Git Refresh Requirements](requirements.md)

## Observable problem and desired difference

Agent Studio currently performs local Git status work after the sidebar projection has settled. In the retained exact-debug marker, one-second Git caller timeouts align with repeated 50–111% process CPU samples. Because the underlying in-process status read can continue after the caller returns, the current timeout is not a physical CPU bound. Capacity contention is also reported through the repository-failure backoff path.

The required difference is an application that preserves eventual Git correctness and foreground freshness while keeping physical Git work inside the owner's strict idle and interaction CPU budgets. Consumers must continue to see the same current Git facts; the repair changes when and how refresh work is admitted, accounted for, and recovered.

## Normative obligations

### S1 — Real-scale idle CPU

After fixture preparation and the specified warmup/settlement condition, the isolated debug Agent Studio process MUST measure below 10% CPU at p99 during a continuous idle population. Idle means zero debug-owned PTYs, no agent or terminal workload, no proof actions, unchanged rendered sidebar state, and no trace-export backlog. Bounded correctness self-heal MAY continue during this population.

Traces: U-GIT-IDLE-CPU-1, U-GIT-PROOF-1.

### S2 — Real-scale interaction CPU

For sidebar search, grouping changes, sidebar hide/show, and tab switching performed as bounded ordinary actions after settlement, the isolated debug process MUST measure below 20% CPU at p95. Each action MUST reach its expected final visible/read-back state without stale results, duplicates, focus loss, or additional fleet-wide Git admission caused solely by the presentation action.

Traces: U-GIT-ACTION-CPU-1, U-GIT-CURRENTNESS-1, U-GIT-PROOF-1.

### S3 — Fixture identity

The acceptance fixture MUST add the complete `/Users/shravansunder/Documents/dev/open-source` and `/Users/shravansunder/Documents/dev/project-dev` watched roots through production watched-folder owners. It MUST produce exactly five tabs and twenty pane models, record positive repository and worktree counts plus a deterministic topology fingerprint, and require those facts to match across populations. Pane count MUST NOT imply PTY count.

Traces: U-GIT-PROOF-1.

### S4 — Eventual self-heal without an idle fiction

Every registered, available background worktree MUST remain eligible for eventual refresh when ordinary filesystem or visibility events are absent. Equal results MAY lengthen the next eligibility interval; changed results MUST restore the prompt policy interval. Quarantined, unregistered, replaced, or failure-backed-off worktrees MAY defer refresh according to their declared state. The verifier MUST NOT require future eligibility or all logical debt to disappear permanently.

Traces: U-GIT-SELF-HEAL-1, U-GIT-ADMISSION-1.

### S5 — Foreground non-starvation

When background work is eligible or executing, an active-pane refresh MUST be admitted within one foreground slot turnaround. Visible-sidebar, open-pane, and explicit demand MUST retain their declared priority and MUST NOT wait behind an unbounded background queue. A background worktree's slow read, timeout, capacity wait, or backoff MUST NOT consume every foreground-capable slot.

Traces: U-GIT-FOREGROUND-1, U-GIT-ADMISSION-1.

### S6 — Physical-work accounting

For each local Git status attempt, the system MUST distinguish caller-visible settlement from physical native completion. If the provider cannot interrupt the native operation, caller timeout or cancellation MUST NOT release same-root exclusion, physical concurrency accounting, or shutdown accounting before true completion. The system MUST NOT start a retry that can overlap the same root's abandoned native read.

Traces: U-GIT-PHYSICAL-BOUND-1, U-GIT-CURRENTNESS-1.

### S7 — Capacity is not repository failure

If a status attempt is rejected because global capacity is occupied or the same root is already physically in flight, the worktree MUST retain one coalesced pending invalidation and retry through bounded capacity admission. That outcome MUST NOT increment repository-failure state or open/advance the exponential repository circuit breaker. Only a genuine provider failure assigned to that worktree MAY advance failure backoff.

Traces: U-GIT-ADMISSION-1, U-GIT-CURRENTNESS-1.

### S8 — No retry multiplication after a soft deadline

If a caller deadline expires while native work continues, the system MUST preserve at most one physical read for that root and at most one bounded follow-up intent. Repeated cadence ticks, visibility changes, file events, or explicit requests MAY merge scope or raise priority, but MUST NOT create overlapping native reads or an unbounded retry sequence.

Traces: U-GIT-PHYSICAL-BOUND-1, U-GIT-CURRENTNESS-1.

### S9 — Scope and publication currentness

Pending work MUST retain the union of affected paths and the freshest ordering context required by the accepted worktree identity. Before publication, the result MUST still match the current worktree/root identity and refresh generation. Obsolete, unregistered, replaced, or shutdown results MUST NOT publish. An equal current result MAY suppress publication only when sequence-end state remains equivalent to the ungated reference.

Traces: U-GIT-CURRENTNESS-1.

### S10 — Cost-aware background admission

Background self-heal MUST be admitted from bounded policy eligibility and measured physical-work state. It MUST NOT drain a fleet-sized queue as fast as native reads finish merely because many worktrees share a periodic trigger. The admitted background rate and concurrency MUST remain bounded under slow reads, fast reads, timeouts, capacity contention, and unchanged-result adaptation. Foreground and explicit demand remain governed by S5 and S8.

Traces: U-GIT-IDLE-CPU-1, U-GIT-ADMISSION-1, U-GIT-PHYSICAL-BOUND-1.

### S11 — Honest slow-read and failure state

A slow but eventually successful native read MUST be distinguishable from timeout settlement, capacity rejection, SDK failure, and cancellation. Its eventual current result MUST either publish normally or be rejected by currentness validation. Slow-read policy MAY lengthen later background eligibility, but MUST NOT falsely report repository failure or lose the current result solely because an advisory deadline elapsed.

Traces: U-GIT-PHYSICAL-BOUND-1, U-GIT-CURRENTNESS-1.

### S12 — Bounded observability

Debug performance telemetry MUST expose bounded counts and durations for eligibility, admission, physical start, caller settlement, true physical completion, capacity deferral, slow completion, failure backoff, retry/coalescing, stale rejection, publication, and physical/logical debt. Telemetry MUST preserve existing source scrubbing and MUST report zero required trace/runtime/collector loss in acceptance populations.

Traces: U-GIT-OBSERVABILITY-1, U-GIT-PROOF-1.

### S13 — Exact debug-only lifecycle

The proof harness MUST bind launch, workload, sampling, telemetry, retirement, zmx inventory, and data-root reset to the exact isolated debug identity. Zero-PTY populations MUST remain zero throughout. A permitted one-PTY population MUST prove the exact `0 -> 1 -> 0-or-1 -> 0` lifecycle. Identity mismatch, process reuse, missing completion, unexpected PTY, or retirement timeout MUST fail closed without inspecting or signaling beta or production.

Traces: U-GIT-PROOF-1.

### S14 — Proof completeness

Acceptance MUST combine deterministic admission/currentness tests, provider physical-lifecycle tests, integration proof through the production Git owner, marker-scoped Git outcome and loss telemetry, exact-PID CPU populations, and manual/native interaction proof. A current-source unit test, instantaneous zero-debt sample, stale marker, JSONL fallback not authorized by the test plan, or host-process name check MUST NOT substitute for the required boundary evidence.

Traces: every authorized requirement.

## Failure and partial-success contract

- If physical native work outlives caller settlement, the operation remains physically active and accounted for; the UI remains responsive and the last accepted facts remain visible.
- If capacity is unavailable, one coalesced intent remains pending without poisoning repository health.
- If a genuine provider failure occurs, the existing current facts remain visible and one bounded failure backoff owns recovery.
- If demand changes while work is active, the result is validated against current identity/generation and any required follow-up survives.
- If the host is under disallowed pressure, the performance population is invalid rather than green or red; unrelated processes are not stopped to manufacture acceptance.

## Negative space

- No guarantee that every background repository is always fresh within the active-pane cadence.
- No permission to remove untracked-file correctness, watched roots, or registered worktrees to reduce cost.
- No guarantee that an in-process libgit2 operation can be hard-cancelled when its public API offers no interruption seam.
- No migration, persistence, remote service, beta/production instrumentation, or broad helper-process architecture is implied by these obligations.

## Requirement-to-proof coverage

| Requirement | Observable contract | Evidence modality |
| --- | --- | --- |
| U-GIT-IDLE-CPU-1 | S1, S4, S10 | exact-PID performance measurement plus marker-scoped Git telemetry |
| U-GIT-ACTION-CPU-1 | S2 | native interaction/read-back plus exact-PID performance measurement |
| U-GIT-SELF-HEAL-1 | S4, S10 | deterministic deadline/admission behavior plus longitudinal runtime evidence |
| U-GIT-FOREGROUND-1 | S5 | deterministic concurrency/admission behavior and stressed integration evidence |
| U-GIT-ADMISSION-1 | S4, S5, S7, S10 | outcome-accounted unit/integration evidence and telemetry ratios |
| U-GIT-CURRENTNESS-1 | S6-S9, S11 | interleaving/currentness behavior and production-owner integration evidence |
| U-GIT-PHYSICAL-BOUND-1 | S6, S8, S10, S11 | provider physical-lifecycle evidence and exact-marker timeout/true-completion telemetry |
| U-GIT-OBSERVABILITY-1 | S12 | bounded telemetry behavior and zero-loss marker evidence |
| U-GIT-PROOF-1 | S3, S12-S14 | exact debug fixture/lifecycle/runtime proof |
