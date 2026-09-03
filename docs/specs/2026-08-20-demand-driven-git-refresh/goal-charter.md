# Agent Studio Repository-Fact Performance Goal Charter

## Status and authority

This charter is the detailed authority behind the active performance-goal tracker. It defines the outcome, boundaries, workload, proof standard, and decisions that must be settled before implementation.

The goal is not merely to make one profiler trace look better or to reduce one periodic Git call. The goal is to make Agent Studio an efficient companion to coding agents at the user's real workspace scale. When Agent Studio is settled and no agents or terminals are doing work, the app must preserve nearly all machine capacity for the user's next task. When the user performs ordinary navigation or sidebar presentation actions, the app must respond without turning those actions into fleet-scale Git, GitHub, projection, or MainActor work.

The current [Demand-Driven Repository Fact Refresh Requirements](requirements.md) remains the artifact to revise after research. [Demand-Driven Derived-State Refresh](../../architecture/state/demand_driven_derived_state_refresh.md) owns generic mechanism vocabulary. This charter establishes the shared product and proof outcome; concrete owners retain workspace topology, source facts, caches, UI, and observability.

## Objective

Bring Agent Studio below 10% product-process CPU at p99 during settled, real-size idle operation and below 20% product-process CPU at p95 for ordinary sidebar search, sidebar grouping changes, sidebar visibility switching, and tab switching when no agents or terminal workloads are active. Preserve the current repository-status user experience, correctness, freshness meaning, focus behavior, and supported real workspace topology. Achieve the result by eliminating work that is not useful for current product demand, contracting bursty invalidations before expensive boundaries, answering consumers from accepted keyed caches, selecting the cheapest authoritative source capable of satisfying each fact, bounding physical work, performing expensive derivation and I/O off MainActor, and publishing only changed current semantic outcomes.

The CPU limits are product-process limits. Whole-machine CPU, unrelated host processes, process-name inventories, and the presence of Codex, Claude, Gemini, crash handlers, or app servers are not the measurement target and must not be used to veto or manufacture a result. Beta and production are protected: the proof harness must not inspect, stop, reset, sample, or mutate them. The measured product boundary is the exact isolated debug identity and any debug-owned helper processes whose work would otherwise relocate Agent Studio's cost outside the app PID. The final proof design must state explicitly how helper cost and physical custody are accounted for without reaching into unrelated applications.

## Why this matters

Agent Studio runs beside coding agents, terminals, compilers, tests, browsers, and development services. Idle CPU consumed by repository inventory is unavailable to those workloads. Redundant projection, list reconciliation, cache misses, and source calls create jank and compete with agents. Resource sparsity is part of correctness.

At the same time, low CPU cannot be obtained by silently making repository facts wrong, indefinitely stale, or incomplete. The sidebar presents one composed repository-status experience assembled from facts with different authorities and freshness needs: local working-tree state, local remote-tracking ahead/behind, server-current remote references, and GitHub pull-request/check/review state. The user must be able to understand whether a value is accepted, refreshing, stale but usable, unavailable, unknown, or last-fetched. The visible refresh animation or loading state must represent real admitted work and must not flicker because rendering caused another refresh.

The central tradeoff is trustworthy, responsive status with no recurring work that cannot improve the relevant demanded checkpoint. It must be explicit per fact and consumer, not hidden in one polling interval.

## Acceptance workload

Acceptance uses the isolated debug app with the complete real watched workspace. Both `/Users/shravansunder/Documents/dev/open-source` and `/Users/shravansunder/Documents/dev/project-dev` must be added through the same production watched-folder owners used by the product. The workload must positively verify repository and worktree counts rather than assuming directory presence is enough. It must construct exactly five tabs and twenty pane models, which is the representative pressure fixture selected by the product owner.

Pane models do not imply terminal processes. The idle population owns zero debug PTYs and no active agents or terminal commands. A separate terminal-interaction proof, if required by an accepted design, may own at most one debug PTY and must prove its exact cleanup. The existing debug PTY inventory helper must be used so the proof cannot leak pseudo-terminals or exhaust the host. Fixture construction, sampling, UI actions, telemetry queries, retirement, and reset must remain bound to an exact state-file-derived debug PID, bundle identity, data root, marker, and isolated zmx root.

The watched roots and tab/pane fixture are not tunable. Acceptance must not remove repositories, reduce topology, replace production discovery with fakes, or change watched membership to hide a defect. Slow, large, dirty, nested, or unavailable repositories must be isolated through admission and capacity rather than defined away.

## Settled idle contract

Settled idle means the UI and repository-fact system have completed fixture preparation and all work that is immediately eligible, while retaining only correctly classified future eligibility. There are no debug-owned PTYs, agent executions, terminal commands, proof actions, sidebar interactions, tab changes, build or test processes launched by the proof, or unaccounted exporter backlog. The rendered state is unchanged. There is no ready, overdue, capacity-stranded, or unclassified repository-fact work pretending to be future debt.

Idle does not mean that the system has forgotten every future correctness obligation. Local repository facts require a finite self-heal path because filesystem events can be lost. A future deadline that is not yet eligible is legitimate state, not active debt and not proof failure. Hidden remote-reference and Forge work must stop without semantic demand; accepted cached facts remain available. The idle proof must span a policy-derived interval sufficient to observe the maximum local self-heal behavior and its true physical settlement rather than selecting a short quiet gap between bursts.

The authoritative idle metric is the p99 CPU distribution for the measured Agent Studio product boundary over the accepted continuous sample population. The requirements/specification revision must define sample cadence, minimum usable samples, warm-up, settlement entry, gap rejection, percentile calculation, and how debug-owned helper CPU is incorporated. A single average, Activity Monitor screenshot, host-wide total, short hand-selected interval, or population that ends before self-heal is not acceptance evidence.

## Ordinary-action contract

The ordinary action population consists of sidebar search edits, sidebar grouping changes, sidebar hide/show or equivalent visibility switching, and tab switching. The requirements revision must define a reproducible mix and repetition count for each action type, capture external issue-to-confirmed-read-back timing, and retain process CPU samples through semantic settlement rather than ending at the first visible pixel if delayed demand/admission work still belongs to the action.

Every ordinary action must meet all of the following conditions:

- process CPU is below 20% at p95 for its accepted population;
- the action reaches its expected native visible and programmatic read-back state;
- focus, selection, counts, ordering, expansion, search, and grouping behavior remain correct;
- no duplicate or stale row publication occurs;
- search, grouping, scrolling, and row materialization do not change repository-fact demand;
- an attention change that leaves the effective source demand and cache eligibility unchanged causes zero local Git, remote-fetch, or Forge source calls;
- fresh accepted keyed facts remain identity-stable and do not republish merely because presentation changed;
- delayed work caused by the action is included in the action settlement window or explicitly classified as independent future eligibility.

The target is not permission to defer work until after measurement. Close each action after its complete pipeline settles, while excluding legitimate future self-heal eligibility through owner state and settlement gauges rather than fixed sleeps.

## The composed repository-status experience

The sidebar and related repository presentation show one experience composed from several facts:

1. Local working-tree facts describe tracked, unstaged, staged, untracked, conflicted, branch, upstream, and locally known repository state.
2. Exact line-count detail may enrich that local state but is a separate expensive capability with its own currentness contract.
3. Ahead/behind is immediately derived from accepted local remote-tracking references and therefore means "relative to the last accepted fetch," not necessarily server-current.
4. A demanded remote-reference refresh may contact the remote, update accepted remote-tracking truth only after currentness validation, and trigger targeted local recomputation.
5. GitHub/Forge facts describe pull requests, checks, reviews, mergeability, and merge state for the exact current repository, origin, and branch scope.

Before Requirements change, research must trace this complete UI/code composition: cache, identity, freshness floor, explicit refresh, loading, stale/unavailable presentation, and physical source owner. One invented "Git status refresh" cadence cannot replace that map because authorities, costs, and latency needs differ.

The update animation must correspond to admitted work that can improve the fact. Cache hits and presentation-only actions must not create false loading. Failure preserves current-identity facts without presenting them as newly confirmed. Explicit refresh remains subject to capacity, currentness, authentication, and failure rules.

## Demand and visibility semantics

Demand is semantic product interest before source work begins. It is not equivalent to a SwiftUI row being instantiated, occupying a viewport pixel, surviving a search filter, or remaining expanded in a list. Rendering is a consumer of accepted facts, not the owner of source eligibility.

For the sidebar, semantic membership is the sidebar's repository/worktree membership before search, grouping, scrolling, disclosure, virtualization, or row materialization. While the sidebar is attended, that semantic membership may contribute demand according to the source-specific contract. Search and grouping only reorganize or filter presentation; they must not make Git or GitHub facts newly demanded or undemanded. Scrolling and virtualization must have zero repository-fact demand effect.

Other attention concepts are distinct and must not be casually merged:

- the active pane identifies the user's current work;
- visible panes in the active tab describe canonical pane visibility according to window, tab, drawer, zoom, occlusion, and minimization semantics owned by the pane/PR demand system;
- open worktrees describe supported local correctness membership even when not foregrounded;
- sidebar attention describes whether the semantic sidebar surface is currently attended;
- hidden, minimized, occluded, or closed surfaces may remove remote automatic demand without deleting accepted facts;
- background registration may retain finite local self-heal while not authorizing remote freshness work.

Research must verify which states feed local priority, remote-reference demand, and Forge branch demand. Requirements must name each meaning and transition precisely. "Visible" cannot remain overloaded; viewport visibility is excluded unless the product owner changes the contract.

## Cache, freshness, and source-selection contract

Accepted keyed atoms answer consumers before sources. Each accepted fact must be bound to the repository, worktree, origin, branch, source, and generation required to interpret it. The cache must distinguish at least fresh, stale-but-usable, unknown, unavailable, and wrong-identity. Equal writes must preserve keyed identity and revision. A renderer, projection adapter, or eager atom must never call Git, `gh`, or a remote source to fill a missing field.

Cache-first does not mean cache-forever. Source admission asks whether the accepted fact is sufficient for the current consumer promise. Source choice then uses the cheapest authority able to satisfy the missing promise:

- canonical atoms for membership and topology;
- local Git for working-tree, branch, local refs, and locally known ahead/behind;
- demanded remote fetch for server-current remote references;
- Forge/GitHub for server-current PR/check/review facts.

Requirements must state user-visible meaning and tolerated staleness per fact and demand class. Existing policy values are evidence, not automatically final. Successful-result floors, failure backoff, capacity recheck, self-heal, explicit refresh, and UI latency are distinct. A three-minute success floor is not polling; finite local self-heal is not fleet-wide simultaneous eligibility.

## Admission, contraction, scheduling, and physical work

The generic refresh loop is authoritative vocabulary:

```text
observe
  -> project
  -> distinct-until-changed
  -> latest-value coalescing
  -> admission control
  -> single-flight execute
  -> stale-result validation
  -> fact publication
  -> materialized read model
```

Each lane classifies inputs before mechanisms. Filesystem coalescing may replace obsolete ordering but retains affected-path union. Demand snapshots may contract intermediates but must deliver the latest complete identity set. Demand/cache admission precedes expensive execution. One reschedulable earliest deadline owns future eligibility instead of fleet-wide polling.

Per source key, at most one physical operation and one bounded latest scope-preserving follow-up intent may exist. Capacity deferral is not source failure. Cancellation of caller interest is not physical completion. Non-cancellable in-process Git work retains capacity until return. Killable `git` or `gh` children retain capacity until actual exit and pipe settlement. Repeated invalidations must not multiply abandoned work or allow separate consumers to bypass a shared physical gate.

Local Git must use the smallest safe complete query. Known safe path changes should use path scope. Status facts and exact line-count detail remain separate physical capabilities. Expensive detail is demanded by its own invalidation/currentness rules rather than hidden inside every status call. No proposed cheap probe or `agentstudio-git` API change is accepted until research proves that it can preserve all required tracked, staged, unstaged, untracked, rename, branch, upstream, and remote-tracking semantics.

## MainActor and UX performance boundary

MainActor owns AppKit/SwiftUI mutation and publication—not filesystem admission, scheduling, source execution, fleet grouping, path canonicalization, full projection, or expensive equality preparation. The intended shape is thin coherent keyed capture, off-main contraction/projection/execution, validation, and small changed-only publication.

Do not move mutable UI atoms wholesale off MainActor or remove coherent snapshots. Reduce work before expensive capture, preserve source semantics, and render from compact accepted read models. Measure MainActor occupancy, source pressure, publication pressure, and list reconciliation separately.

## Correctness and failure constraints

Performance repair must never publish a result for the wrong repository, worktree root, origin, branch, demand scope, or generation. Pending invalidation must preserve required scope. A local fact result without required exact detail must not create a mixed old/new candidate. Remote fetch must not mutate canonical accepted refs before currentness validation. An incomplete multi-branch Forge plan must not partially publish sibling branches as though the repository result were complete.

Stale-but-current-identity accepted facts remain presentable during refresh or failure. Demand loss may stop future remote work but does not delete accepted facts. Identity replacement invalidates old facts. Genuine source failure may enter bounded backoff; capacity exhaustion, same-key work already running, cancellation, timeout observation, or lost interest must not masquerade as source failure or equality suppression. Local event loss must not permanently disable finite self-heal.

The current sidebar search, grouping, focus, collapse/disclosure, counts, branch/Git/PR chip semantics, toolbar/sidebar agreement, and refresh feedback must remain intact. This goal does not authorize the separate By Tab unassociated-pane membership repair, Inbox redesign/removal, general Bridge optimization, or unrelated command-bar work.

## Proof model and anti-false-green rules

Acceptance combines deterministic tests, integration proof, package proof for `agentstudio-git` changes, marker telemetry, native read-back, and exact-debug CPU evidence. Unit tests do not prove the real workload; runtime traces do not replace currentness tests; green CPU does not prove work was not relocated or suppressed.

The proof must fail closed for debug identity mismatch, missing or reused PID, topology mismatch, wrong tab/pane count, unexpected debug PTY, debug-owned child leakage, incomplete action read-back, sampling gaps beyond the accepted bound, stale telemetry, required telemetry loss, overdue/ready/unclassified debt, or retirement/reset failure. It must not fail because an unrelated process name exists. It must never stop or mutate beta or production to obtain a quiet sample.

OTLP/Victoria is the authoritative marker-scoped performance evidence path. JSONL may aid diagnosis but cannot substitute for required exported evidence. The current ingestion freshness mismatch is an observability proof issue to diagnose, not permission to weaken the freshness gate or to declare the product CPU result. Telemetry must remain bounded, scrubbed, and cheap enough not to create the workload being measured.

Compare improvements on the same fixture and contract. Report commands, exact HEAD, samples, percentiles, action counts, topology, PTYs, source calls, settlement, telemetry loss, and exit codes, separating lower-layer proof from blocked runtime or release layers.

## Authorized work and explicit exclusions

Authorized after the design and plan gates are accepted: repository-fact demand projection; local Git cache/freshness/admission and scope selection; remote-reference demand and refresh; Forge/GitHub cache, demand, capacity, and query efficiency; `agentstudio-git` contract changes owned by the user; keyed changed-only materialization; source settlement telemetry; exact-debug fixture and verifier corrections; and narrowly required MainActor capture/projection improvements.

Not authorized by this charter: security/auth expansion; persistence schema changes; a generic scheduler framework; a new atom, store, EventBus case, or coordinator responsibility without explicit owner concurrence; removal of enrichment; reduced watched roots; viewport-demand invention; broad application feature removal; beta/production access; host-wide CPU policing; unrelated performance cleanup; or a compatibility shim retaining old and new refresh paths. Proof failures outside the agreed path do not authorize edits to unrelated infrastructure.

No cadence, cache probe, query API, or source change is selected merely because it sounds cheaper. Research establishes the consumer promise and source capability; design names tradeoffs and falsifiers; implementation follows a reviewed plan with red/green proof and checkpoint commits.

## Research, design, and delivery sequence

The first active phase is research-only. It must produce an evidence ledger and update the Requirements from current code and architecture, covering:

1. the composed local/remote/Forge status presentation and loading behavior;
2. semantic sidebar membership and every distinct active/visible/open/hidden state;
3. cache identity, freshness, invalidation, and source-call boundaries;
4. admission, contraction, deadline, single-flight, capacity, and currentness owners;
5. exact process CPU workload and proof semantics, including debug-owned helpers;
6. contradictions between current Requirements, Specification, Program Design, code, tests, and verifier.

After the owner and agent concur on the updated Requirements, the Specification and Program Design must be revised through the bounded design workflow and independently reviewed. Only then may a current implementation plan authorize source changes. Implementation must use coherent green checkpoint commits, preserve user-owned changes, run focused red/green tests before broad gates, perform native/manual proof, receive bounded independent implementation review, and finish at a PR-ready, unmerged state unless the user gives separate merge authority.

## Terminal condition

The goal is complete only when the current exact implementation satisfies the updated requirements, all scoped deterministic and integration tests pass, `mise run lint` and `mise run test` pass on the exact final HEAD, native behavior is manually verified, the complete real-root 5-tab/20-pane exact-debug workload proves settled idle below 10% process CPU at p99 and ordinary actions below 20% process CPU at p95, the marker-scoped observability and settlement gates pass without loss, beta and production remain untouched, an independent implementation review is ready, and the resulting PR is ready and unmerged.

If the research reveals that the current composed status UX, source authority, or demand ownership differs from this charter's assumptions, that is a mental-model break. Stop implementation, present the evidence and tradeoff, and revise this charter or the Requirements with the product owner before proceeding. Difficulty, a checkpoint, a passing focused test, or an incomplete proof population is not a terminal condition.
