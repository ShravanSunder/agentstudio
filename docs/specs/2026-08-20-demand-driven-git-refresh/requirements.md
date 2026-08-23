# Demand-Driven Git Refresh Requirements

## Authority and boundary

These requirements capture the product owner's settled performance and correctness outcomes for Agent Studio's local Git enrichment at the complete real workspace scale. They are a fresh Requirements identity in the previously intended dated home; they do not claim to recover a missing historical document.

The affected people are developers using Agent Studio alongside coding agents. Agent Studio must leave CPU capacity available for those agents while keeping repository facts trustworthy and interactions responsive.

The permitted change surface is Agent Studio's local Git refresh, admission, derived-state publication, and debug proof path. Stable and beta applications are protected. Security expansion, unrelated cleanup, the separate By Tab membership defect, remote forge behavior, persistence schema changes, and terminal-agent workload are outside this boundary.

All rows below are priority P0, assigned by the product owner in the active performance goal.

## Authorized needs

### U-GIT-IDLE-CPU-1 — Idle capacity belongs to the user's work

With the complete real watched workspace loaded and no terminal or agent workload running, settled Agent Studio must use less than 10% process CPU at p99. A correctness self-heal may continue, but it must fit inside that budget rather than redefining the application as non-idle.

Evidence basis: the product owner's explicit `<10% p99` idle target and exact-PID diagnostic samples showing p99 above 100% during recurring local Git work.

### U-GIT-ACTION-CPU-1 — Ordinary navigation stays inexpensive

Sidebar search, grouping changes, sidebar hide/show, and tab switching must remain below 20% process CPU at p95 when no agents or terminals are running. Background Git work must not turn those ordinary actions into fleet-scale work or MainActor contention.

Evidence basis: the product owner's explicit `<20% p95` target for minor UX actions.

### U-GIT-SELF-HEAL-1 — Dropped events do not permanently stale Git facts

Every registered, available worktree must retain an eventual local Git refresh backstop even when filesystem or visibility events are lost. The backstop may adapt its cadence from stable results and measured cost. It must not be removed merely to make idle CPU green.

Evidence basis: the owner-approved historical self-heal contract in `docs/specs/git-enrichment-at-scale.md` and the current workspace architecture's local Git materialization responsibility.

### U-GIT-FOREGROUND-1 — Current work is fresher than background inventory

The active pane, visible sidebar rows, open panes, and explicit refreshes must retain their priority over background self-heal. A slow or unhealthy background worktree must not block refresh of the worktree the user is actively inspecting.

Evidence basis: existing tier semantics and the foreground non-starvation contract in `docs/specs/git-enrichment-at-scale.md`.

### U-GIT-ADMISSION-1 — Work crosses the expensive boundary only when useful

Git refresh admission must distinguish current consumer attention, correctness backstop eligibility, explicit refresh, capacity contention, repository failure, and obsolete scope before physical status work begins. Debounce, cadence, equality, timeout, or retry mechanisms must not silently convert one class into another.

Evidence basis: the current demand-driven derived-state classification and the live regression's repeated periodic full-status work.

### U-GIT-CURRENTNESS-1 — Performance repair does not trade away truth

The last published Git state for each worktree must remain current with the accepted worktree identity and refresh generation. Pending invalidations must preserve affected scope. Unregistration, root replacement, shutdown, failure, timeout, or delayed completion must not publish facts for an obsolete worktree or lose a required follow-up.

Evidence basis: existing workspace currentness and pending-scope contracts.

### U-GIT-PHYSICAL-BOUND-1 — A timeout must describe an enforceable boundary

The system must not claim that a physical Git operation stopped merely because its caller stopped waiting. Work that cannot be interrupted must remain accounted for in concurrency, CPU attribution, recovery, and shutdown behavior until its true completion. Repeated retry must not multiply abandoned native work.

Evidence basis: current libgit2 status has no supported in-progress cancellation boundary, while retained telemetry shows one-second caller timeouts aligned with 50–111% app CPU samples.

### U-GIT-OBSERVABILITY-1 — The expensive lane explains itself cheaply

Debug performance telemetry must distinguish eligibility, admission, physical start, caller timeout, true completion, capacity deferral, failure backoff, stale rejection, publication, and retained debt using bounded dimensions. Measurement must not create material work, and exported telemetry must retain the existing source-scrubbing boundary.

Evidence basis: the project's Performance Lane Directive and the need to distinguish a timed-out caller from an actually completed native read.

### U-GIT-PROOF-1 — Acceptance uses the real workspace without harming other channels

Performance acceptance must exercise both complete watched roots through production owners with exactly five tabs and twenty pane models. Idle proof uses zero debug-owned PTYs. A terminal interaction proof may use at most one debug-owned PTY and must prove cleanup. All process discovery, sampling, retirement, and root reset must remain bound to the isolated debug identity; beta and production are never inspected, stopped, or mutated.

Evidence basis: the product owner's explicit fixture and safety constraints.

## Accepted outcomes and limits

- O1: settled idle p99 process CPU is below 10% on the complete real-root 5/20 fixture.
- O2: ordinary sidebar and tab interactions remain below 20% process CPU at p95 on the same fixture.
- O3: background self-heal remains eventual, paced, and subordinate to foreground demand.
- O4: physical status work has honest lifecycle accounting; timeout, capacity, and repository failure are distinct.
- O5: no stale or lost Git publication is introduced.
- O6: exact-marker telemetry and exact-debug identity make the performance verdict reproducible.

## Explicit non-goals

- Do not disable Git enrichment or remove complete watched roots to satisfy CPU targets.
- Do not move cost into beta, production, unrelated host processes, or hidden unbounded helper work.
- Do not add persistence, a remote service, a generic scheduler framework, or a second Git truth owner unless a smaller design is proven insufficient.
- Do not change remote forge refresh, repository topology ownership, watched-folder discovery, or sidebar product behavior.
- Do not make zero logical Git debt the definition of settled idle; future self-heal eligibility is expected.

## Open evidence, not owner decisions

- Normal host memory pressure may reduce status duration relative to the retained warning-pressure marker. Final acceptance still requires a fresh normal-pressure run.
- The smallest physical-work mechanism that satisfies the percentile targets remains a structural design choice. It must be selected against current source and runtime proof rather than embedded here as a requirement.
