# Demand-Driven Repository Fact Refresh Specification

Requirements: [Demand-Driven Repository Fact Refresh Requirements](requirements.md)

## Observable problem and desired difference

Agent Studio currently performs recurring in-process local Git work after the sidebar projection has settled, uses several independently constructed status-capacity registries, and pays a second full-worktree line-count diff inside every status request. The retained exact-debug marker aligns one-second local status settlements with repeated 50–111% process CPU samples. Current GitHub refresh has a three-minute freshness gate and per-repository single-flight, but no global CLI capacity, generic failures can retry faster than the documented floor, and one demanded branch still fetches repository-wide open PR pages before local filtering.

The required difference is a cache-first system in which consumers immediately read accepted keyed facts, source work begins only when the cache and demand contract require it, the cheapest authoritative source and smallest safe query are selected, physical work is bounded across consumers, and only complete current changed facts publish.

## Normative obligations

### S1 — Real-scale idle CPU

After fixture preparation and settlement, the isolated debug Agent Studio process MUST measure below 10% CPU at p99 during a continuous idle population. Idle means zero debug-owned PTYs, no agent/terminal workload, no proof actions, unchanged rendered state, and no trace-export backlog. Bounded local correctness self-heal MAY continue; hidden remote work MUST remain stopped.

### S2 — Real-scale interaction CPU

Sidebar search, grouping changes, sidebar hide/show, and tab switching MUST measure below 20% process CPU at p95. Search, grouping, scrolling, and row materialization MUST NOT change repository-fact demand. Each action MUST reach its expected visible/read-back state without stale publication, duplicates, focus loss, or source work caused solely by rendering or attention changes while accepted facts remain fresh.

### S3 — Real fixture identity

Acceptance MUST add the complete `/Users/shravansunder/Documents/dev/open-source` and `/Users/shravansunder/Documents/dev/project-dev` roots through production watched-folder owners. Every population MUST record positive repository/worktree counts, exactly five tabs and twenty pane models, a matching deterministic topology fingerprint, and the expected zero-or-one debug-owned PTY lifecycle. Pane count MUST NOT imply PTY count.

### S4 — Cache-first consumer contract

UI and derived-state consumers MUST read keyed accepted atoms and MUST NOT call local Git, remote Git, GitHub CLI, or source adapters from body/render/materialization paths. A cache hit that satisfies the consumer's identity and freshness contract MUST result in zero source work. Content-equal writes MUST preserve keyed revision and unaffected-key identity.

### S5 — Honest cache states

Each cached fact MUST retain source identity, owning entity identity, accepted generation, and freshness/invalidation state sufficient to distinguish fresh, stale-but-usable, unknown, unavailable, and wrong-identity values. Stale-but-usable or unavailable refresh MUST preserve the last facts confirmed for the current identity. Origin, branch, worktree, or repository replacement MUST reject facts belonging to the old identity.

### S6 — Cheapest sufficient source

Workspace membership MUST come from canonical topology atoms; working-tree, branch, local remote-tracking, and line-count truth MUST come from local Git; server-current remote refs MUST come from demanded remote fetch; PR/check/review/mergeability truth MUST come from Forge/GitHub. The system MUST NOT invoke a stronger or remote source when accepted weaker-source facts satisfy the consumer's promise.

### S7 — Contract input before admission

Filesystem bursts MUST coalesce by worktree while preserving affected-path union and maximum flush latency. Visibility/demand bursts MUST contract to the newest complete identity set. Contraction MUST precede cache/freshness admission, and neither debounce nor cancellation may count as equality. Every source key MUST retain at most one active operation and one bounded scope-preserving follow-up intent.

### S8 — Local self-heal and priority

Every registered available worktree MUST retain a finite local refresh deadline. Active, visible, open, explicit, and background classes MUST preserve that priority order and finite class-specific freshness bounds. Equal results MAY lengthen the next deadline within the declared maximum; changed results MUST restore prompt eligibility. A background queue MUST NOT starve active or visible work.

### S9 — Efficient local query shape

Known bounded changed paths MUST use path-scoped status when rename, Git-internal, identity, or scope safety does not require a full status. Status facts and exact full-worktree line-count detail MUST be separate physical capabilities. Known content changes, changed status facts, missing detail, explicit complete refresh, or an expired finite detail deadline MUST demand exact line counts. Equal automatic facts with fresh accepted detail MUST reuse the cached exact counts and MUST NOT run the second full diff.

### S10 — Complete local publication

A local result MUST publish only as one complete worktree candidate containing mutually current status facts and exact line-count detail. A detail failure after fact success MUST retain the prior complete candidate and one complete pending intent; it MUST NOT publish a mixed old/new result. Publication MUST validate worktree/root identity, request generation, and shutdown state.

### S11 — Ahead/behind source and remote-ref refresh

Ahead/behind MUST be immediately computed from accepted local remote-tracking refs and MUST communicate that last-fetched meaning. Active or visible demand MAY admit one repository-batched noninteractive remote fetch only after its successful-fetch freshness floor; explicit refresh MAY bypass freshness but MUST obey capacity and backoff. Hidden repositories MUST retain cached counts without automatic fetch. Successful fetch MUST trigger targeted local-ref/status recomputation; failure MUST retain prior counts.

### S12 — Demanded Forge facts

PR, check, review, mergeability, and merge-state facts MUST remain keyed by exact repository, non-empty branch, and current origin. Automatic demand MUST be the union of sidebar-attended worktrees and visible panes in the active tab. While the sidebar is attended, sidebar-attended worktrees MUST be its semantic worktree membership before search, grouping, scrolling, or row materialization. Hiding, minimizing, occluding, or closing the sidebar/window MUST remove sidebar attention without deleting accepted facts. A demanded repository with no accepted result MUST refresh immediately; after success it MUST NOT automatically refresh again before three minutes. Losing demand MUST stop future automatic work without deleting current-origin facts.

### S13 — Efficient, bounded, and atomic GitHub query

One admitted Forge refresh MUST issue one bounded GraphQL request plan for the current repository and complete demanded-branch set. Where the provider supports branch filtering, the request MUST use demanded `headRefName` scopes, batching multiple branches with bounded aliases rather than retrieving unrelated repository-wide PR pages. Every aliased connection MUST be completely paginated within the plan's declared connection, node, and result bounds. The repository-scoped result MUST publish atomically only when every demanded branch connection is complete and current; if any batch or connection fails, truncates, rate-limits, or remains incomplete, no branch from that plan may update and prior or unknown facts MUST remain unchanged.

### S14 — Forge concurrency and recovery

Forge MUST maintain one active request and one latest complete follow-up per repository plus a bounded process-wide GitHub CLI capacity across repositories. Capacity deferral MUST preserve intent without changing repository health. Automatic failure, truncation, and rate-limit retry MUST respect the three-minute automatic floor; authoritative `Retry-After` MUST extend it. After three consecutive unsuccessful attempts, presentation MAY become unavailable while preserving current-origin confirmed facts and continuing bounded recovery.

### S15 — Honest physical lifecycle

Non-cancellable in-process local reads MUST retain same-root exclusion and physical capacity until true native completion. A slow threshold MAY report that the caller is waiting but MUST NOT release capacity, create failure, or start a retry. Killable fetch and GitHub CLI child processes MUST retain capacity until exit and MUST be cancelled/reaped on demand loss, identity invalidation, or shutdown according to their owner contract. Separate consumers MUST share the physical gate for the same status source class.

### S16 — Capacity is not source failure

Global capacity exhaustion or same-root/same-repository work already in flight MUST retain one coalesced pending intent and retry through completion wake or a bounded capacity deadline. It MUST NOT increment repository failure state or open/advance the exponential source-failure breaker. Only a genuine source failure after physical settlement may advance failure backoff.

### S17 — Currentness and changed-only publication

Every active operation MUST capture source identity, repository/worktree/branch scope, and refresh generation. Before publication, the owner MUST validate those values against current membership and demand. Obsolete results MUST NOT publish or advance freshness/equality baselines. Complete equal results MAY suppress publication only when sequence-end state equals the ungated reference.

### S18 — Bounded observability

Debug telemetry MUST expose bounded outcomes for cache hit/miss/stale, source selection, contraction, freshness admission, active coalescing, capacity deferral, physical start/slow/settlement/completion, query scope, failure backoff, currentness rejection, publication, and pending/physical debt. Acceptance populations MUST report zero required trace/runtime/collector loss and retain existing source scrubbing.

### S19 — Exact debug-only lifecycle

The proof harness MUST bind launch, workload, sampling, telemetry, retirement, zmx inventory, and data-root reset to the exact isolated debug identity. Identity mismatch, process reuse, missing completion, unexpected PTY, or retirement timeout MUST fail closed without inspecting or signaling beta or production.

### S20 — Proof completeness

Acceptance MUST combine deterministic cache/admission/currentness tests, local and remote physical-lifecycle tests, `agentstudio-git` compatibility and efficiency proof, integration through production local/remote owners, marker-scoped outcomes/loss telemetry, exact-PID CPU populations, and native interaction/read-back proof. Instantaneous zero debt, a stale marker, unit-only evidence, an unauthorized JSONL fallback, or host process-name checks MUST NOT substitute for the required boundary evidence.

## Failure and partial-success contract

- Cache freshness expiry preserves current-identity accepted facts while demanded refresh proceeds.
- Local fact success followed by detail failure publishes nothing partial.
- Remote fetch or Forge failure preserves current-origin accepted facts and enters only its bounded recovery class.
- A partially successful multi-batch Forge plan publishes no branch facts; recovery retries the complete latest repository plan.
- Capacity deferral changes neither cache truth nor source health.
- Demand or identity changes may cancel interest; late physical completion still requires lifecycle accounting and cannot publish obsolete facts.
- A disallowed host-pressure state invalidates the performance population; unrelated processes are not stopped to manufacture acceptance.

## Negative space

- Hidden repositories are not promised continuous server-current remote refs or PR/check facts.
- Ahead/behind remains explicitly last-fetched until a demanded fetch succeeds.
- An in-process libgit2 operation is not promised hard cancellation when its public API exposes no interruption seam.
- A demanded-branch Forge request need not use branch filtering when GitHub cannot express the required complete bounded query, but the fallback must remain bounded and observable.
- No persistence, generic scheduling framework, beta/production instrumentation, or broad helper-process architecture is implied.

## Requirement-to-proof coverage

| Requirement | Observable contract | Evidence modality |
| --- | --- | --- |
| U-GIT-IDLE-CPU-1 | S1, S8-S16 | exact-PID performance measurement plus marker-scoped source telemetry |
| U-GIT-ACTION-CPU-1 | S2, S4 | native interaction/read-back plus exact-PID performance measurement |
| U-GIT-CACHE-FIRST-1 | S4-S5 | keyed cache behavior, source-call absence, and projection revision evidence |
| U-GIT-SOURCE-SUFFICIENCY-1 | S6, S11-S13 | source-selection behavior and local/remote integration evidence |
| U-GIT-SELF-HEAL-1 | S8-S12 | injected-deadline behavior and longitudinal demanded-checkpoint proof |
| U-GIT-FOREGROUND-1 | S8, S14-S16 | deterministic capacity/priority interleavings and stressed runtime actions |
| U-GIT-ADMISSION-1 | S7-S8, S12-S16 | outcome-accounted contraction/admission tests and marker ratios |
| U-GIT-LOCAL-EFFICIENCY-1 | S9-S10 | package/app query-shape, detail-demand, currentness, and timing evidence |
| U-GIT-REMOTE-REF-1 | S11 | remote-fetch cache/freshness/failure integration and read-back evidence |
| U-GIT-FORGE-1 | S12-S14 | branch-scoped provider, cache, concurrency, rate-limit, and UI agreement evidence |
| U-GIT-CURRENTNESS-1 | S5, S10-S17 | generation/identity interleavings and complete publication evidence |
| U-GIT-PHYSICAL-BOUND-1 | S14-S16 | non-cooperative native and child-process lifecycle evidence |
| U-GIT-OBSERVABILITY-1 | S18 | bounded aggregation and zero-loss marker evidence |
| U-GIT-PROOF-1 | S3, S18-S20 | complete real-root exact-debug proof chain |
