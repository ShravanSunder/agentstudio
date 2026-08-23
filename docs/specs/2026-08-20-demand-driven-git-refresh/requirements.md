# Demand-Driven Repository Fact Refresh Requirements

## Authority and boundary

These requirements capture the product owner's settled performance and correctness outcomes for repository facts at the complete real workspace scale. They are a fresh Requirements identity in the previously intended dated home; they do not claim to recover a missing historical document.

The affected people are developers using Agent Studio alongside coding agents. Agent Studio must leave CPU, process, network, and GitHub API capacity available for those agents while keeping the repository facts a user can see trustworthy and responsive.

The permitted change surface is Agent Studio's repository-fact caches, demand projection, local Git refresh, demanded remote-reference refresh, GitHub PR/check/review refresh, source-side execution in `agentstudio-git`, changed-only materialization, and debug proof path. `agentstudio-git` is owner-controlled and may change through a deliberate hard contract cutover.

The existing [Repository-Branch Pull Request Facts](../2026-08-10-repo-branch-pr-facts/requirements.md) requirements remain authoritative for repository-branch identity, exact URL behavior, unknown versus confirmed-empty presentation, and toolbar/sidebar agreement. This artifact owns the holistic cache, source-selection, efficiency, capacity, freshness, and performance contract around those facts.

Stable and beta applications are protected. Security/authentication expansion, the separate By Tab membership defect, persistence schema changes, general Bridge review/diff workloads, repository topology ownership, watched-folder discovery semantics, and terminal-agent workload are outside this boundary.

All rows below are priority P0, assigned by the product owner in the active performance goal.

## Authorized needs

### U-GIT-IDLE-CPU-1 — Idle capacity belongs to the user's work

With the complete real watched workspace loaded and no terminal or agent workload running, settled Agent Studio must use less than 10% process CPU at p99. Correctness self-heal may continue, but it must fit inside that budget rather than redefining the application as non-idle.

### U-GIT-ACTION-CPU-1 — Ordinary navigation stays inexpensive

Sidebar search, grouping changes, sidebar hide/show, and tab switching must remain below 20% process CPU at p95 when no agents or terminals are running. Presentation actions must not turn cached repository facts into local Git, network, GitHub CLI, or fleet-scale projection work.

### U-GIT-CACHE-FIRST-1 — Accepted atoms answer before sources

Repository facts already accepted for the current identity must be the first answer to UI and derived-state consumers. A source call is justified only when the owning cache can prove that the fact is missing, invalidated, too old for current demand, or explicitly requested. Cache state must distinguish fresh, stale-but-usable, unknown, unavailable, and wrong-identity facts.

### U-GIT-SOURCE-SUFFICIENCY-1 — Use the cheapest authoritative source

Each fact must come from the cheapest source capable of satisfying its promise: canonical atoms for workspace membership, local Git for working-tree and local-ref truth, demanded remote fetch for server-current remote-tracking refs, and Forge/GitHub for live PR/check/review truth. A stronger source must not be called when a weaker accepted source is good enough.

### U-GIT-SELF-HEAL-1 — Lost events do not permanently stale facts

Every registered, available worktree must retain an eventual local Git backstop even when filesystem or visibility events are lost. Exact line counts must refresh promptly after known content changes and retain a finite slower self-heal deadline. Remote facts may stop automatic work without demand but must refresh at the first demanded checkpoint when their accepted cache is too old.

### U-GIT-FOREGROUND-1 — Current work outranks background inventory

The active pane, visible sidebar rows, visible panes in the active tab, and explicit refreshes must retain priority over background correctness work. A slow or unhealthy background worktree, remote fetch, or GitHub request must not block the repository facts the user is actively inspecting.

### U-GIT-ADMISSION-1 — Debounce contracts bursts; admission decides usefulness

Refresh admission must distinguish input contraction, cache freshness, current demand, explicit intent, self-heal eligibility, source capacity, source failure, and obsolete scope before expensive work begins. Debounce, equality, timeout, retry, or cache reuse must not silently convert one class into another.

### U-GIT-LOCAL-EFFICIENCY-1 — Local Git performs the smallest complete work

Local Git refresh must use safe path scope before full-repository scope and status facts before expensive line-count detail. Known invalidations must preserve affected scope, and cached exact detail may be reused only while its own freshness/currentness contract remains satisfied.

### U-GIT-REMOTE-REF-1 — Ahead/behind is immediate and demand-refreshed

Ahead/behind must be immediately available from accepted local remote-tracking refs. Active or visible demand may refresh those refs from the remote after the cache freshness floor; explicit refresh may accelerate eligibility. Hidden repositories must not be fetched fleet-wide merely to keep server-current counts.

### U-GIT-FORGE-1 — Remote PR/check facts follow demanded branch scope

PR, check, review, mergeability, and merge-state facts must remain repository+branch facts shared by every matching worktree. Active and visible demanded branches refresh after the three-minute successful-result floor; hidden branches retain accepted facts without automatic GitHub work. Remote query shape and concurrency must remain bounded by demanded scope.

### U-GIT-CURRENTNESS-1 — Performance repair never trades away truth

The last published repository facts must match the accepted repository, worktree, branch, origin, source, and refresh generation. Pending invalidations preserve required scope. Demand loss, branch/origin change, unregistration, failure, timeout, cancellation, or delayed completion must not publish obsolete facts or erase current accepted facts.

### U-GIT-PHYSICAL-BOUND-1 — Physical work has honest lifecycle and capacity

The system must not claim that local or remote physical work stopped merely because a caller stopped waiting. Non-cancellable in-process work remains accounted for until true completion. Killable child processes remain accounted for until exit. Repeated retry must not multiply abandoned work, and separate consumers must not bypass the process-wide capacity assigned to the same expensive source class.

### U-GIT-OBSERVABILITY-1 — Expensive lanes explain themselves cheaply

Debug performance telemetry must distinguish cache hit/miss/stale, source selection, contraction, admission, physical start/settlement/completion, capacity deferral, failure backoff, stale rejection, publication, and retained debt using bounded dimensions. Measurement must not become material work or weaken source scrubbing.

### U-GIT-PROOF-1 — Acceptance uses the real workspace without harming other channels

Performance acceptance must exercise both complete watched roots through production owners with exactly five tabs and twenty pane models. Idle proof uses zero debug-owned PTYs. A terminal interaction proof may use at most one debug-owned PTY and must prove cleanup. All discovery, sampling, telemetry, retirement, and reset remain bound to the isolated debug identity; beta and production are never inspected, stopped, or mutated.

## Accepted outcomes and limits

- O1: settled idle p99 process CPU is below 10% on the complete real-root 5/20 fixture.
- O2: ordinary sidebar and tab interactions remain below 20% process CPU at p95 on the same fixture.
- O3: UI and derived projections read keyed accepted atoms and never call Git, GitHub, or remote sources from rendering.
- O4: local facts, server-current remote refs, and Forge facts have explicit source and freshness meaning.
- O5: local self-heal remains finite, while hidden remote work stops until demand.
- O6: physical work is paced and bounded across all consumers of the same source class.
- O7: no stale, partial, cross-origin, or lost publication is introduced.
- O8: exact-marker telemetry and exact-debug identity make the verdict reproducible.

## Explicit non-goals

- Do not disable enrichment, remove watched roots, or reduce supported topology to satisfy CPU targets.
- Do not make every hidden repository server-current through background fetch or GitHub polling.
- Do not move cost into beta, production, unrelated host processes, or unmeasured helper processes.
- Do not add persistence, a generic scheduler framework, a remote service, or a second owner for an existing fact.
- Do not broaden the shared physical status budget into general Bridge review/tree/content/diff policy without evidence from those lanes.
- Do not make zero future eligibility or zero aggregate Git debt the definition of settled idle.

## Open evidence, not owner decisions

- Normal host memory pressure may reduce local status duration relative to the retained warning-pressure marker. Final acceptance still requires a fresh normal-pressure run.
- Exact concurrency, automatic start spacing, and detail self-heal constants remain policy tunables selected and proven during implementation; they may not weaken the observable freshness and CPU contracts above.
