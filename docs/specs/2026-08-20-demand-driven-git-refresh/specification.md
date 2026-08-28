# Demand-Driven Repository Fact Refresh Specification

Requirements: [Demand-Driven Repository Fact Refresh Requirements](requirements.md)

## Observable problem and desired difference

Agent Studio currently performs recurring in-process local Git work after the sidebar projection has settled, uses several independently constructed status-capacity registries, and pays a second full-worktree line-count diff inside every status request. The retained exact-debug marker aligns one-second local status settlements with repeated 50–111% process CPU samples. A current-head real-root run with 121 repositories and 148 worktrees completed 208 periodic local Git reads with 63.5 seconds of physical duty before another forty-worktree ready wave prevented positive settlement. Current GitHub refresh has a three-minute freshness gate and per-repository single-flight, but no global CLI capacity, generic failures can retry faster than the documented floor, and one demanded branch still fetches repository-wide open PR pages before local filtering.

The required difference is a cache-first system in which consumers immediately read accepted keyed facts, source work begins only when the cache, qualifying local activity, and demand contract require it, the cheapest authoritative source and smallest safe query are selected, physical work is bounded across consumers, and only complete current changed facts publish. A finite local freshness checkpoint may renew a previously exact-clean warm result without another Git traversal only when uninterrupted, loss-aware observation proves that the exact Git identity and every relevant dependency remained unchanged; any uncertainty must use the existing exact Git path. A repository becomes locally inactive only after continuous evidence proves no qualifying local repository/worktree activity for sixty days and no associated pane is open. Unknown or gapped activity evidence remains unclassified, never falsely inactive.

## Normative obligations

### S1 — Real-scale idle CPU

After fixture preparation and settlement, the isolated debug Agent Studio process MUST measure below 10% CPU at p99 during a continuous idle population. Idle means zero debug-owned PTYs, no agent/terminal workload, no proof actions, unchanged rendered state, and no trace-export backlog. Bounded warm local correctness self-heal MAY continue; hidden or locally inactive scheduled source work MUST remain stopped.

### S2 — Real-scale interaction CPU

Sidebar search, grouping changes, sidebar hide/show, and tab switching MUST measure below 20% process CPU at p95. Search, grouping, scrolling, and row materialization MUST NOT change repository-fact demand. Each action MUST reach its expected visible/read-back state without stale publication, duplicates, focus loss, or source work caused solely by rendering or attention changes while accepted facts remain fresh.

### S3 — Real fixture identity

Acceptance MUST add the complete `/Users/shravansunder/Documents/dev/open-source` and `/Users/shravansunder/Documents/dev/project-dev` roots through production watched-folder owners. Every population MUST record positive repository/worktree counts, exactly five tabs and twenty pane models, a matching deterministic topology fingerprint, and the expected zero-or-one debug-owned PTY lifecycle. Pane count MUST NOT imply PTY count.

### S4 — Cache-first consumer contract

UI and derived-state consumers MUST read keyed accepted atoms and MUST NOT call local Git, remote Git, GitHub CLI, or source adapters from body/render/materialization paths. A cache hit that satisfies the consumer's identity and freshness contract MUST result in zero source work. Content-equal writes MUST preserve keyed revision and unaffected-key identity.

### S5 — Honest cache states

Each cached fact MUST retain source identity, owning entity identity, accepted generation, and freshness/invalidation state sufficient to distinguish fresh, stale-but-usable, unknown, unavailable, and wrong-identity values. Stale-but-usable or unavailable refresh MUST preserve the last facts confirmed for the current identity. Locally inactive presentation MUST NOT describe retained runtime facts as current: it hides ordinary Git and PR chips and presents only the specified inactivity status and update control. Origin, branch, worktree, or repository replacement MUST reject facts belonging to the old identity.

### S6 — Cheapest sufficient source

Workspace membership MUST come from canonical topology atoms; working-tree, branch, local remote-tracking, and line-count truth MUST originate from local Git; server-current remote refs MUST come from demanded remote fetch; PR/check/review/mergeability truth MUST come from Forge/GitHub. Loss-aware local observation MAY prove that a previously accepted exact-clean local Git result remains current, but it MUST NOT originate a Git fact or turn a non-clean or uncertain result into clean. The system MUST NOT invoke a stronger or remote source when accepted weaker-source facts satisfy the consumer's promise.

### S7 — Contract input before admission

Filesystem bursts MUST coalesce by worktree while preserving affected-path union and maximum flush latency. Visibility/demand bursts MUST contract to the newest complete identity set. Contraction MUST precede cache/freshness admission, and neither debounce nor cancellation may count as equality. Every source key MUST retain at most one active operation and one bounded scope-preserving follow-up intent.

### S8 — Warm local self-heal and priority

Every warm registered available worktree MUST retain a finite local freshness checkpoint. Active, visible, open, explicit, and warm-background classes MUST preserve that priority order and finite class-specific freshness bounds. At a warm checkpoint, a current exact-clean result MAY renew through verified continuity without physical Git; every other result MUST remain eligible for the exact local Git backstop. Equal or continuity-renewed results MAY lengthen the next checkpoint within the declared maximum; changed, uncertain, or identity-invalid results MUST restore exact-refresh eligibility. A warm background queue MUST NOT starve active or visible work. Locally inactive worktrees MUST NOT retain periodic status or detail deadlines. A relevant filesystem mutation or explicit update MUST still retain one scope-preserving local intent and run through ordinary local admission.

### S8B — Sixty-day locally inactive admission and update control

A repository MUST be locally inactive only when it has no associated open pane and continuously covered evidence proves that neither the repository nor any current worktree had qualifying local activity at or after the sixty-day cutoff. Qualifying activity MUST include non-ignored projected worktree mutations and external local Git mutations affecting worktree content, local HEAD/branch/index state, or remote-reference state. One qualifying event in any current worktree MUST warm the canonical repository. Opening, viewing, searching, grouping, scrolling, or rendering MUST NOT persist activity; an associated open pane is an ephemeral warm/priority override only.

Before persisted activity and FSEvents coverage hydrate and replay, the repository MUST remain unclassified. Missing rows, bootstrap absence, cursor gaps/wraps, replay unavailability, scope replacement, persistence failure, or future/suspect timestamps MUST remain unknown and MUST NOT produce a locally inactive claim. Unknown repositories remain eligible for the bounded warm correctness path until continuous coverage can prove the full sixty-day negative interval. Bounded Git/reflog/current-dirty bootstrap MAY contribute positive activity evidence but absence MUST NOT prove inactivity, and bootstrap MUST NOT recursively scan repository trees.

Canonical watched-folder, repository, worktree, ordering, grouping, search, and collapse membership MUST remain unchanged by local inactivity. While locally inactive, the repository MUST contribute no periodic local Git deadline and no automatic remote-reference or Forge demand, even when the attended sidebar contains it. Classification MUST occur from complete canonical membership, open-pane association, repository-keyed activity evidence, and coverage authority before search, grouping, scrolling, disclosure, viewport, or materialization; those presentation operations MUST have zero classification or source-call effect.

The locally inactive repository header MUST hide ordinary local Git and PR/check chips and show one compact `memorychip` status icon with tooltip/accessibility copy `Locally inactive`. Activating that status MUST reveal one compact `Refresh` chip for thirty seconds without moving the row. While refresh is admitted, the header MUST show only a compact circular progress indicator with tooltip/accessibility copy `Updating repo`. These states MUST use the existing trailing control slot and MUST NOT add a row or change header height.

The status and revealed Refresh chip MUST appear only where the selected grouping exposes a unique repository header. By Tab and By Pane MUST suppress ordinary cold Git/PR chip content without repeating repository update controls on pane or worktree rows. Changing grouping MUST NOT alter activity classification, source demand, or accepted update progress; returning to By Repo MUST expose the same repository-targeted control.

Activating Refresh MUST issue one explicit canonical-repository remote-reference fetch. It MUST NOT persist qualifying activity merely because Agent Studio initiated the action, and MUST NOT pull, merge, checkout, update the checked-out local branch, or fast-forward `HEAD`. The fetch MAY bypass successful-result freshness but MUST NOT bypass repository/origin identity, currentness validation, repository-keyed single-flight, process capacity, backoff, or child-process custody. A current successful promotion MUST trigger targeted local ahead/behind/status recomputation for every represented worktree and the visible progress lifetime MUST remain unsettled until that recomputation settles. The action MUST NOT explicitly refresh Forge/GitHub facts. Failure MUST preserve prior current-identity remote/local facts, and a repository whose qualifying activity remains old MUST return to the memorychip state after settlement.

When an authoritative warm repository crosses the sixty-day boundary, the transition MUST suppress only future automatic deadlines and demand. Work already physically admitted retains its existing custody through native return or child exit, and any late result still passes ordinary identity, generation, and changed-only publication validation. A coverage gap MUST transition activity to unknown rather than inactive. Neither transition may erase accepted current-identity facts or convert cancellation/capacity state into source failure.

### S9 — Efficient local query shape

Known bounded changed paths MUST use path-scoped status when rename, Git-internal, identity, or scope safety does not require a full status. Status facts and exact full-worktree line-count detail MUST be separate physical capabilities. Known content changes, changed or non-clean status facts, missing detail without an exact-clean proof, explicit complete refresh, or an expired finite detail deadline without verified clean continuity MUST demand exact line counts. A full exact status result that proves no staged, tracked-worktree, conflicted, renamed, type-changed, unreadable, or recursively discovered untracked entry MUST imply exact empty status and exact `0/0` line detail without executing the second full diff. Equal automatic facts with fresh accepted detail MUST reuse the cached exact counts and MUST NOT run the second full diff.

### S9A — Verified exact-clean continuity

Only a successful full exact local Git result for the current repository, worktree, root, per-worktree Git directory and index, HEAD, branch, origin/configuration, ignore dependencies, and refresh generation MAY establish an exact-clean baseline. Observation coverage MUST begin before that baseline is accepted and MUST remain continuous through a freshness-checkpoint barrier. A checkpoint MAY renew the exact empty facts and exact `0/0` detail without physical Git only when the observer proves the same identity and epoch, no relevant mutation, no dropped or wrapped events, no rescan requirement, no registration or sleep gap, and no unsupported observation state. Known mutation, explicit refresh, dirty or incomplete baseline, identity drift, observation loss, or any ambiguity MUST return to the existing exact Git path. Continuity renewal MUST NOT delete finite checkpoints or suppress a pending known invalidation.

### S10 — Complete local publication

A local result MUST publish only as one complete worktree candidate containing mutually current status facts and exact line-count detail. A continuity-renewed candidate MUST carry the exact-clean baseline identity plus the observation epoch and checkpoint barrier that justified renewal. A detail failure after fact success MUST retain the prior complete candidate and one complete pending intent; it MUST NOT publish a mixed old/new result. Publication MUST validate worktree/root identity, request generation, exact-clean/observation generation when applicable, and shutdown state.

### S11 — Ahead/behind source and remote-ref refresh

Ahead/behind MUST be immediately computed from accepted local remote-tracking refs and MUST communicate that last-fetched meaning. Active or warm visible demand MAY admit one repository-batched noninteractive remote fetch only after its successful-fetch freshness floor; explicit update MAY bypass freshness but MUST obey capacity and backoff. Hidden or locally inactive repositories MUST retain current-identity runtime counts without automatic fetch. Successful fetch MUST trigger targeted local-ref/status recomputation; failure MUST retain prior counts.

### S12 — Demanded Forge facts

PR, check, review, mergeability, and merge-state facts MUST remain keyed by exact repository, non-empty branch, and current origin. Automatic demand MUST be the union of warm sidebar-attended worktrees and visible panes in the active tab. While the sidebar is attended, its complete semantic worktree membership MUST be captured before inactivity admission and before search, grouping, scrolling, or row materialization. Hiding, minimizing, occluding, closing, or classifying a repository locally inactive MUST remove its automatic Forge attention without deleting current-origin runtime facts. A demanded warm repository with no accepted result MUST refresh immediately; after success it MUST NOT automatically refresh again before three minutes. Losing demand MUST stop future automatic work without deleting current-origin facts.

### S13 — Efficient, bounded, and atomic GitHub query

One admitted Forge refresh MUST issue one bounded GraphQL request plan for the current repository and complete demanded-branch set. Where the provider supports branch filtering, the request MUST use demanded `headRefName` scopes, batching multiple branches with bounded aliases rather than retrieving unrelated repository-wide PR pages. Every aliased connection MUST be completely paginated within the plan's declared connection, node, and result bounds. The repository-scoped result MUST publish atomically only when every demanded branch connection is complete and current; if any batch or connection fails, truncates, rate-limits, or remains incomplete, no branch from that plan may update and prior or unknown facts MUST remain unchanged.

### S14 — Forge concurrency and recovery

Forge MUST maintain one active request and one latest complete follow-up per repository plus a bounded process-wide GitHub CLI capacity across repositories. Capacity deferral MUST preserve intent without changing repository health. Automatic failure, truncation, and rate-limit retry MUST respect the three-minute automatic floor; authoritative `Retry-After` MUST extend it. After three consecutive unsuccessful attempts, presentation MAY become unavailable while preserving current-origin confirmed facts and continuing bounded recovery.

### S15 — Honest physical lifecycle

Non-cancellable in-process local reads MUST retain same-root exclusion and physical capacity until true native completion. A slow threshold MAY report that the caller is waiting but MUST NOT release capacity, create failure, or start a retry. Killable fetch and GitHub CLI child processes MUST retain capacity until exit and MUST be cancelled/reaped on demand loss, identity invalidation, or shutdown according to their owner contract. Separate consumers MUST share the physical gate for the same status source class.

### S16 — Capacity is not source failure

Global capacity exhaustion or same-root/same-repository work already in flight MUST retain one coalesced pending intent and retry through completion wake or a bounded capacity deadline. It MUST NOT increment repository failure state or open/advance the exponential source-failure breaker. Only a genuine source failure after physical settlement may advance failure backoff.

### S17 — Currentness and changed-only publication

Every active operation MUST capture source identity, repository/worktree/branch scope, and refresh generation. A clean-continuity renewal MUST additionally capture and validate the exact-clean baseline identity, observation epoch, checkpoint barrier, and uncertainty generation. Before publication, the owner MUST validate those values against current membership and demand. Obsolete or uncertain results MUST NOT publish or advance freshness/equality baselines. Complete equal results MAY suppress publication only when sequence-end state equals the ungated reference.

### S18 — Bounded observability

Debug telemetry MUST expose bounded outcomes for cache hit/miss/stale, warm/locally-inactive/unknown activity classification, qualifying versus excluded owned activity, coverage replay/gap/reset, inactivity suppression/reactivation, source selection, contraction, freshness admission, verified-clean renewal, mutation invalidation, observation uncertainty, exact fallback, active coalescing, capacity deferral, physical start/slow/settlement/completion, query scope, failure backoff, currentness rejection, publication, and pending/physical debt. Acceptance populations MUST report zero required trace/runtime/collector loss and retain existing source scrubbing.

### S19 — Exact debug-only lifecycle

The proof harness MUST bind launch, workload, sampling, telemetry, retirement, zmx inventory, and data-root reset to the exact isolated debug identity. Identity mismatch, process reuse, missing completion, unexpected PTY, or retirement timeout MUST fail closed without inspecting or signaling beta or production.

### S20 — Proof completeness

Acceptance MUST combine deterministic cache/admission/currentness tests, local and remote physical-lifecycle tests, `agentstudio-git` compatibility and efficiency proof, differential clean-continuity proof against an immediate exact Git reference, activity cursor replay/gap/provenance proof, observer loss/gap/identity/race proof, integration through production local/remote owners, marker-scoped outcomes/loss telemetry, exact-PID CPU populations, and native interaction/read-back proof. The verifier MUST exercise warm, unknown, and proven locally inactive repositories in the complete real topology. It MUST prove that an attended locally inactive repository retains canonical membership and stable row geometry while producing no periodic local Git, automatic remote-reference, or automatic Forge work; that qualifying edit/commit/pull/external-fetch activity in any worktree warms the repository; that Agent Studio-owned automatic fetch and presentation/cache operations do not warm it; that a relevant filesystem mutation still admits required local correctness work; and that Refresh performs exactly one repository fetch, moves no checked-out `HEAD`, excludes Forge, exposes one loading lifetime through represented-worktree recomputation, and preserves truthful failure state.

The verifier MUST inject controlled uncertainty before the timed idle interval, then begin the interval after the injection action ends but before its retained exact fallback settles. The timed real-root idle population therefore contains positive verified-clean renewals, at least one periodic warm local self-heal completion, and observable exact fallback work without containing a proof action. Instantaneous zero debt, a stale marker, unit-only evidence, an unauthorized JSONL fallback, or host process-name checks MUST NOT substitute for the required boundary evidence.

## Failure and partial-success contract

- Cache freshness expiry preserves current-identity accepted facts while demanded refresh proceeds.
- Exact-clean continuity uncertainty preserves the accepted candidate, retains one exact fallback intent, and advances neither clean-proof nor freshness authority.
- Local fact success followed by detail failure publishes nothing partial.
- Remote fetch or Forge failure preserves current-origin accepted facts and enters only its bounded recovery class.
- A partially successful multi-batch Forge plan publishes no branch facts; recovery retries the complete latest repository plan.
- Capacity deferral changes neither cache truth nor source health.
- Demand or identity changes may cancel interest; late physical completion still requires lifecycle accounting and cannot publish obsolete facts.
- Crossing into local inactivity suppresses future automatic intent but does not abandon already-admitted physical work, erase accepted current-identity facts, or fabricate failure. Coverage loss transitions to unknown, not inactive.
- An explicit Refresh settles after its one remote fetch and represented-worktree recomputation; failure preserves prior current-identity facts and does not fabricate local activity.
- A disallowed host-pressure state invalidates the performance population; unrelated processes are not stopped to manufacture acceptance.

## Negative space

- Hidden repositories are not promised continuous server-current remote refs or PR/check facts.
- Ahead/behind remains explicitly last-fetched until a demanded fetch succeeds.
- An in-process libgit2 operation is not promised hard cancellation when its public API exposes no interruption seam.
- Verified clean continuity is not a cache-forever promise, a replacement source for Git facts, or permission to assume that silence means unchanged.
- A demanded-branch Forge request need not use branch filtering when GitHub cannot express the required complete bounded query, but the fallback must remain bounded and observable.
- A locally inactive row is not promised persisted local-status or PR/check facts after restart; it presents only the inline inactivity status and update chip until warmed.
- Refresh is deliberately fetch-only. It does not promise local branch mutation, pull/fast-forward, or an explicit Forge/GitHub update.
- By Tab and By Pane do not promise a repeated inactive/update control for every row; the unique repository-targeted control is presented by By Repo.
- Only dedicated repository-local-activity and FSEvents cursor/coverage persistence is implied; no generic scheduling framework, beta/production instrumentation, or broad helper-process architecture is implied. SQLite stores factual keys, timestamps, cursors, and booleans only; typed multi-state activity interpretation remains in application code.

## Requirement-to-proof coverage

| Requirement | Observable contract | Evidence modality |
| --- | --- | --- |
| U-GIT-IDLE-CPU-1 | S1, S8-S16 | exact-PID performance measurement plus marker-scoped source and clean-continuity telemetry |
| U-GIT-ACTION-CPU-1 | S2, S4 | native interaction/read-back plus exact-PID performance measurement |
| U-GIT-CACHE-FIRST-1 | S4-S5 | keyed cache behavior, source-call absence, and projection revision evidence |
| U-GIT-SOURCE-SUFFICIENCY-1 | S6, S11-S13 | source-selection behavior and local/remote integration evidence |
| U-GIT-SELF-HEAL-1 | S8-S12 | injected-deadline behavior, continuity uncertainty fallback, and longitudinal demanded-checkpoint proof |
| U-GIT-COLD-1 | S5, S8-S8B, S11-S12, S15-S20 | warm/cold classification, no-scheduled-work, mutation, complete-update, partial-failure, stable-row, transition, CPU, and marker evidence |
| U-GIT-FOREGROUND-1 | S8, S14-S16 | deterministic capacity/priority interleavings and stressed runtime actions |
| U-GIT-ADMISSION-1 | S7-S8, S12-S16 | outcome-accounted contraction/admission tests and marker ratios |
| U-GIT-LOCAL-EFFICIENCY-1 | S9-S10 | package/app query-shape, exact-clean implication, continuity differential, fallback, currentness, and timing evidence |
| U-GIT-REMOTE-REF-1 | S11 | remote-fetch cache/freshness/failure integration and read-back evidence |
| U-GIT-FORGE-1 | S12-S14 | branch-scoped provider, cache, concurrency, rate-limit, and UI agreement evidence |
| U-GIT-CURRENTNESS-1 | S5, S10-S17 | generation/identity interleavings and complete publication evidence |
| U-GIT-PHYSICAL-BOUND-1 | S14-S16 | non-cooperative native and child-process lifecycle evidence |
| U-GIT-OBSERVABILITY-1 | S18 | bounded aggregation and zero-loss marker evidence |
| U-GIT-PROOF-1 | S3, S18-S20 | complete real-root exact-debug proof chain |
