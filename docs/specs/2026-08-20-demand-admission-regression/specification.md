# Demand Admission Regression — Specification

Requirements: [requirements.md](requirements.md)

## Observable Contract

### Classification And Admission

**S1.** Every affected input lane MUST be explicitly classified as an ordered fact, latest-state projection, burst of samples, expensive refresh, or future eligibility deadline, including any composition of those classes. Its selected suppression, coalescing, aggregation, admission, execution, and deadline mechanisms MUST preserve the corresponding obligation from the governing demand-driven contract. [U-ADMISSION-1, U-BOUNDS-1]

**S2.** Repo Explorer MUST observe only the smallest keyed inputs that can change rows rendered by the current grouping and current sidebar demand. By Repository MUST NOT observe pane activity, pane message, focus, drawer, or recency facts that cannot change its rendered rows. A hidden sidebar surface MAY retain its last materialized result but MUST NOT continue an often/heavy capture lane merely to remain warm. [U-ADMISSION-1, U-CURRENTNESS-1]

**S3.** Equality and demand admission MUST occur before construction of a full Repo Explorer projection request. A source change that cannot alter the demanded rendered meaning MUST NOT walk all repositories, worktrees, tabs, or panes and MUST NOT schedule the projection worker. [U-PERF-1, U-ADMISSION-1]

**S4.** An admitted MainActor capture MUST read already-materialized keyed values and produce one immutable bounded request or delta. It MUST NOT resolve symlinks, canonicalize filesystem paths, perform Git/SQLite/network/process work, or recreate stable repository/worktree identity from paths. [U-ISOLATION-1]

**S5.** Latest-state pane-row facts MUST use per-key distinct-until-changed and latest-value coalescing. When a changed value is temporarily ineligible, the lane MUST retain at most one latest pending invalidation and deliver it by the first demanded checkpoint. It MUST NOT discard a changed value through an unrearmed leading-edge rate limit. [U-CURRENTNESS-1, U-BOUNDS-1]

### Terminal Activity And Metadata

**S6.** Raw Ghostty callback cadence MUST NOT define Repo Explorer, MainActor, EventBus, or OTLP cadence. Title, CWD, pane activity, and terminal-derived sidebar content MUST pass through their typed source admission and publish only changed compact semantic facts required by current consumers. Exact ordered facts MUST retain ordered delivery. [U-ADMISSION-1, U-CURRENTNESS-1]

An exact `commandFinished` fact required to settle a pane MUST NOT cross a lossy subscriber or any boundary that can silently discard it. Diagnostic trace admission MUST occur after the normative typed disposition and MUST obey that disposition's volume class. [U-CURRENTNESS-1, U-OBSERVABILITY-1]

**S7.** Terminal-derived sidebar content MUST preserve the latest demanded changed line without reading or copying an unbounded viewport on every raw output event. Any settle-time Ghostty read MUST be explicitly bounded, measured, and admitted before further MainActor or publication work; unchanged content MUST be suppressed at the earliest owner capable of proving equality. [U-PERF-1, U-CURRENTNESS-1, U-ISOLATION-1]

**S8.** Known future recency transitions MUST be scheduled from the earliest demanded row deadline. The app MUST NOT periodically rebuild the complete Repo Explorer fleet to discover whether a displayed recency tier changed. [U-ADMISSION-1, U-BOUNDS-1]

### Pull-Request Loading And Forge

**S9.** Pull-request loading is a latest-state repository presentation fact. Start, stop, cancellation, invalidation, and result completion MUST converge through one repository-keyed current state. Duplicate or superseded lifecycle signals MUST NOT create multiple MainActor mutations, work-intent backlog, or whole-sidebar captures. A successful current completion MUST materialize loading completion and its confirmed facts as one consumer-visible transition; consumers MUST NOT observe an intermediate not-loading state before the corresponding confirmed result. [U-ADMISSION-1, U-CURRENTNESS-1, U-BOUNDS-1]

**S10.** Honest PR presentation MUST continue to distinguish unknown, loading, unavailable, confirmed empty, and confirmed facts. Coalescing or suppression MUST NOT erase the last confirmed current-origin facts, publish an obsolete origin/generation, or strand a repository in loading after cancellation, removal, failure, or supersession. A completion MUST pass current origin, generation, live membership, and publication-scope validation before it mutates successful-freshness or last-published equality state. A rejected completion MUST NOT become the baseline that suppresses a later valid result. Demand loss alone MUST NOT invalidate facts for a branch that retains live membership. [U-CURRENTNESS-1]

**S11.** Forge MUST retain at most one active provider request and one latest pending follow-up per repository, current demand/origin/generation validation, one reschedulable freshness deadline, and repository-batched provider execution. The repair MUST NOT add polling, per-branch provider calls, or a second refresh owner. [U-PRESERVATION-1, U-BOUNDS-1]

**S12.** Repo Explorer MUST observe a repository's loading fact once per repository key when that fact affects the current rendered grouping. It MUST NOT repeat the same repository loading read once per worktree or capture the whole loading map/set on the hot path. [U-ADMISSION-1, U-ISOLATION-1]

### Projection, Publication, And MainActor

**S13.** Expensive grouping, row indexing, branch/status merging, and render comparison MUST remain off MainActor. Execution MUST be single-flight per owned projection key with at most one latest pending invalidation; cooperative cancellation MUST settle the predecessor before a successor begins execution for that key. Superseded identity, scope, or generation MUST be rejected before publication. [U-ISOLATION-1, U-PRESERVATION-1]

**S14.** MainActor publication MUST be one compact changed result or affected-key delta. Content-equal results MUST retain the current materialized value without SwiftUI invalidation. The equality contract MUST include every value capable of changing rendered output in the current grouping, including pane title/message/note, recency text/tier, real-attention state, drawer state, and branch presentation. Unaffected keyed rows MUST retain identity and MUST NOT be reconstructed solely because an unrelated key changed. [U-PERF-1, U-CURRENTNESS-1]

### Performance And Observability

**S15.** Under one recorded real-size workload representing the owner's affected workspace, settled stable operation MUST normally remain below 30% process CPU, MUST improve over `v0.0.89` and `v0.0.90`, and MUST be no worse than the recorded `v0.0.88` control for interaction latency, terminal projection round trip, and MainActor queue wait. No single synthetic fixture may substitute for this proof. [U-PERF-1]

**S16.** Every affected stage MUST emit bounded outcomes sufficient to calculate: input-to-semantic-fact contraction, semantic-fact-to-capture admission, capture-to-execution admission, execution-to-publication, and publication-to-materialization waste ratios. Equal, coalesced, deferred, capacity-limited, cancelled, superseded, stale, failed, and published outcomes MUST remain distinct. [U-OBSERVABILITY-1]

**S17.** Telemetry MUST use controlled bounded dimensions and MUST NOT export raw paths, UUIDs, terminal text, prompts, payloads, errors, or tool output. An often/heavy diagnostic lane MUST aggregate, sample, or source-admit before the trace queue. The performance proof MUST have zero app trace-queue drops and zero collector-side loss attributable to the measured lane. [U-OBSERVABILITY-1]

**S18.** The proof surface MUST attribute each test mutation to the affected admission stage without requiring high-volume atom logging in the primary benchmark. Dedicated diagnostic runs MAY enable narrower instrumentation if they demonstrate that instrumentation does not materially perturb the claimed workload. [U-OBSERVABILITY-1]

## Failure Contract

- Loss of demand cancels or defers future work without deleting current materialized facts.
- Cancellation, timeout, provider failure, or stale completion never counts as equality or suppression.
- Capacity limitation retains bounded latest required intent and exposes a capacity outcome; it never silently converts demand into unavailable product state.
- A missing or failed optional telemetry sink never blocks ordinary application startup, but a strict performance proof fails when required evidence is absent or dropped.
- If a compact fact cannot prove equality, the owning lane executes or retains one pending invalidation; it does not guess that the change is irrelevant.

## Proof Obligations

- **Deterministic source admission:** changed/equal title, activity, focus, recency, drawer, PR loading, and PR fact sequences prove exact suppression/coalescing/admission counts and final state.
- **R-INV reference equivalence:** every pane-row equality/suppression and deferred latest-value sequence is compared with an ungated reference through its sequence end or first demanded checkpoint; visibly changed row fields can never complete as equal.
- **Grouping demand:** each Repo Explorer grouping proves its exact observed input set; irrelevant pane facts produce zero capture in By Repository, and hidden-surface hot facts produce zero heavy capture.
- **MainActor boundary:** automated architecture checks and duration probes prove hot capture performs no filesystem/Git/SQLite/network/process work and publishes compact changed values only.
- **Concurrency/currentness:** burst and cancellation tests prove one active plus one latest pending work item, obsolete result rejection, latest changed fact delivery, and loading-state recovery.
- **Forge publication equivalence:** in-flight demand sequences including A → B → A prove that rejected completions leave freshness/publication baselines unchanged and that a later identical valid result still reaches the materialized cache; loading completion and facts appear atomically.
- **Exact terminal delivery:** bounded-pressure integration proves `commandFinished` cannot be lost before settle/status publication and that diagnostic routing cannot bypass typed source admission.
- **End-to-end tagged comparison:** the same real-size marker-scoped workload runs against the `v0.0.88` control, faulty `v0.0.89`/`v0.0.90` evidence, and repaired build; it records CPU, capture cadence, MainActor held/queue time, terminal round trip, projection waste, interaction behavior, and trace loss.
- **Native behavior:** By Pane/By Tab activity, focus, recency, Git/PR presentation, sidebar switching, and terminal interaction remain visibly current in the packaged debug app.
- **Telemetry safety:** OTLP projection tests and current-marker negative checks prove bounded dimensions and absence of sensitive values.

## Non-Goals

- No generic admission framework, new service, persistence schema, feature flag, compatibility route, or fleet-wide polling.
- No removal of intended sidebar activity or honest PR-loading behavior.
- No unrelated Git, Bridge, authentication, security, release, or visual redesign.
