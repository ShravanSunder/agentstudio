# Terminal Title Cadence And Pane Observation Proportionality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute this plan task-by-task. Tests are written and observed RED before production edits. Subagents may research, review, or run bounded proof, but the parent integrates and verifies every result.

**Goal:** Deliver fixed non-sliding one-second terminal title publication and proportional pane observation, prove both slices, complete one dual-review remediation cycle, and prepare one review-ready pull request without merging or releasing.

> Repo Explorer note (2026-08-09): the visibility-mode presentation references
> in this cross-cutting historical plan predate the favorites-first cutover.
> Those passages are non-executable; use the current
> [favorites-first Specification](../../2026-08-08-repo-sidebar-favorites-first/2026-08-08-repo-sidebar-favorites-first-specification.md)
> for Repo Explorer behavior.

**Architecture:** Hard-cut the terminal accumulator and scheduler to independent immediate/title lanes with accumulator-owned absolute deadlines. Hard-cut pane storage to one canonical keyed entity map plus one equality-gated structural projection, explicit snapshots, a persistence revision, per-tab observation, title-insensitive fleet consumers, and an App-owned batched command-presentation observer. Keep current runtime events, persistence schema, command execution authority, and UI behavior.

**Tech Stack:** Swift 6, Swift Observation, Swift Testing, SwiftPM, AppKit/SwiftUI, repo-owned architecture lint, Agent Studio trace runtime, OTLP/Victoria.

## Global Constraints

- Title publication deadline is fixed at 1,000 ms from the first pending title admission and never slides.
- Cursor, scrollbar/activity, and search presentation remain immediate and cannot publish or reschedule title work.
- Exact non-title facts/controls remain the sole early title barrier.
- Preserve independent latest semantic title and latest `setTitle` host value, sequence/replay/EventBus/IPC/readiness, and surface-lifetime rejection.
- Keep one canonical pane owner; do not add an actor, store, event bus, schema, migration, atom per field, cached execution authority, or compatibility path.
- Hot reads use keyed membership/canonical/structural interfaces; deliberate cold or execution-time fleet work uses explicitly named snapshots.
- Repo Explorer presentation is advisory; every click still routes through current authoritative dispatch validation.
- Telemetry remains aggregate/content-safe and owns no correctness state.
- Do not use wall-clock sleeps in tests. Use injected time/scheduling seams and bounded event/state waits.
- Preserve unrelated work and stage only files owned by this plan.

---

### Task 1: Independent terminal lanes and absolute title deadlines

**Files:**

- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/TerminalLocalActionAccumulator.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/TerminalLocalActionDrainScheduler.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter+LocalActions.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/TerminalLocalActionAccumulatorTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterLocalDrainTests.swift`
- Adapt only if required: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift`
- Adapt only if required: `Tests/AgentStudioTests/App/Terminal/GhosttyActionRouterMixedPressureTests.swift`

**Interfaces:**

```swift
enum TerminalLocalActionLane: Hashable, Sendable {
    case immediate
    case title
}

struct TerminalLocalDrainRequest: Equatable, Sendable {
    let lane: TerminalLocalActionLane
    let absoluteDeadlineNanoseconds: UInt64?
}

// Accumulator-owned time and lane-specific lifecycle.
init(
    scheduleDrain: @escaping @Sendable (UUID, TerminalLocalDrainRequest) -> Void,
    scheduleFollowUpDrain: (@Sendable (UUID, TerminalLocalDrainRequest) -> Void)? = nil,
    cancelScheduledTitleDrain: @escaping @Sendable (UUID) -> Void = { _ in },
    nowNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
)

func beginDrain(for surfaceID: UUID, lane: TerminalLocalActionLane, ...) -> TerminalLocalActionBatch?
func finishDrain(for surfaceID: UUID, lane: TerminalLocalActionLane) -> TerminalLocalAccumulatorDrainCompletion
```

The first title records `firstAdmission + 1_000_000_000` exactly. Initial and follow-up scheduling callbacks carry that same absolute value. Scheduler claims are keyed by `(surfaceID, lane)` and its injected title seam receives `(absoluteDeadlineNanoseconds, DispatchWorkItem)`. Retirement cancels both claims; exact barriers cancel only title.

- [ ] Add deterministic failing tests for first-title deadline, replacement without deadline movement, and a title admitted during an earlier title drain retaining its own `admission + 1s` follow-up deadline.
- [ ] Run `mise run test:swift -- --filter "Terminal local action accumulator"`; confirm RED failures describe the missing lane/deadline behavior.
- [ ] Add failing interleaving tests proving immediate drain leaves pending title untouched, both admitted lanes can execute in either order once, exact barrier preserves immediate work, and retirement invalidates both captured claims.
- [ ] Run the same focused suite and confirm the new interleaving assertions fail for the current shared phase/claim behavior.
- [ ] Implement independent accumulator pending/phase state, lane-specific detachment/completion, lane-keyed scheduler claims, absolute deadline transport, and router lane wiring. Preserve the existing exact-barrier and downstream title publication bodies.
- [ ] Add/adjust router integration assertions for `setTitle("window")` then `setTabTitle("tab")`: host title is exactly `"window"`, exactly one semantic `tabTitleChanged("tab")` is emitted, and immediate work does not publish either early.
- [ ] Run `mise run test:swift -- --filter "Terminal local action accumulator"` and the focused local-drain/router suites; confirm GREEN with zero retained claims/state debt.
- [ ] Run `mise run format`, inspect the task diff, and commit only this slice as `fix(terminal): isolate title publication cadence`.

---

### Task 2: Atomic keyed pane owner and hot-consumer cutover

**Files:**

- Modify: `Sources/AgentStudio/Infrastructure/AtomLib/AtomEntityMap.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AtomLib/AtomPerformanceTelemetry.swift`
- Modify: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneStructuralFacts.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneGraphAtom.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneDerived.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteSaveCoordinator.swift`
- Modify: `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceLookupDerived.swift`
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+ProjectionHelpers.swift`
- Modify: `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgePaneActivity.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`
- Modify only as needed: command-bar and filesystem observation consumers that currently observe a rich fleet
- Modify: explicit cold/execution snapshot callers found by `rg 'paneAtom\.panes|workspacePane\.panes|\.paneStates\b' Sources/AgentStudio`
- Test: `Tests/AgentStudioTests/Infrastructure/AtomLib/AtomEntityMapObservationTests.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspacePaneBoundaryTests.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift`
- Test: `Tests/AgentStudioTests/App/Panes/TabBarAdapterTests.swift`
- Test: `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerPaneProjectionTests.swift`
- Test: relevant Bridge/Inbox/CommandBar integration suites
- Test: existing OTLP projection tests selected by source ownership

**Interfaces:**

```swift
package init(
    telemetryLabel: String,
    isContentEqual: @escaping (Value, Value) -> Bool
)

package struct PaneStructuralFacts: Equatable, Sendable {
    // Only durable CWD/topology input, content kind/Bridge eligibility,
    // residency, drawer parent/ownership, and placement facts.
    // Excludes title, note, payload text, and derived repo/worktree identity.
}

package func paneState(_ id: UUID) -> PaneGraphState?
package func paneStructuralFacts(_ id: UUID) -> PaneStructuralFacts?
package var paneIDs: Set<UUID> { get }
package func paneStateSnapshot() -> [UUID: PaneGraphState]
package var paneAcceptedCommitRevision: Int { get }

package func pane(_ id: UUID) -> Pane?
package func paneSnapshot() -> [UUID: Pane]
```

`WorkspacePaneGraphAtom` owns one `AtomMutationContext` per accepted operation. It copy-transforms canonical state, commits canonical and structural maps plus drawer index/membership invariants, then bumps one aggregate persistence revision. Equality-suppressed writes and nil-slot pruning do not bump it. Storage labels are controlled, product-agnostic strings supplied by Core; OTLP allowlists the label but never IDs or values.

`TabBarAdapter` retains global tab identity/order and active selection, then owns one observation registration plus cached `TabBarItem` per live tab. Each registration reads only its tab/arrangement/presentation, referenced pane IDs, keyed pane state, and keyed enrichment. Reconciliation cancels removed registrations before removing cached items; equality suppresses unchanged item publication.

`WorkspaceLookupDerived` enumerates `paneIDs` and reads `paneStructuralFacts(_:)`, combining durable CWD with current topology. Repo Explorer, Bridge activity, Inbox surface correlation, and other observation-driven fleet consumers use membership plus keyed structural facts. Consumers with an existing non-observation trigger use explicit snapshots.

- [ ] Add failing primitive tests proving two maps emit distinct controlled labels while IDs/values never reach JSONL/OTLP; update every existing map construction to supply a label.
- [ ] Run focused AtomLib and OTLP projection tests; confirm RED on the missing label interface/projection.
- [ ] Add failing pane-oracle tests that observe canonical A/B, structural A/B, membership, and accepted revision across title-only, structural, equal, insert, remove, replacement, restore, and pruning operations.
- [ ] Confirm RED: current dictionary observation wakes broadly and exposes no structural/revision interfaces.
- [ ] Implement `PaneStructuralFacts`, canonical/structural `AtomEntityMap` storage, one copy-transform-commit boundary for every existing mutation, graph-owned pruning after membership/lifecycle cleanup, and explicit keyed/membership/snapshot/revision reads.
- [ ] Add failing tab tests for one-pane title mutation publishing only the dependent tab item, overridden labels publishing nothing, and tab insertion/removal owning exactly one observer lifetime.
- [ ] Add failing projection/coordinator tests proving title-only mutation causes zero Repo Explorer/Bridge/Inbox work while residency/content/CWD/drawer or membership changes refresh affected outputs.
- [ ] Implement per-tab registrations/cache/reconciliation and structural lookup, then migrate the named hot fleet consumers without changing rendered `TabBarItem` semantics or adding a second projection store/event lane.
- [ ] Replace every remaining ambiguous `panes`/`paneStates` call in the same compile-time cutover: keyed reads where the caller owns one identity; explicit `paneSnapshot()`/`paneStateSnapshot()` for cold, event, diagnostic, persistence, or one-shot execution work. Do not retain a compatibility property between commits.
- [ ] Change `WorkspaceStore.startObserving()` to observe `paneAcceptedCommitRevision`; preserve dirty state, sudden-termination protection, debounce, initial-composition suppression, and save failure behavior. Add RED/GREEN autosave tests for accepted title change, equal write, pruning, and replacement.
- [ ] Run focused AtomLib, pane-boundary, persistence, tab, Repo Explorer, Bridge, Inbox, CommandBar, and OTLP tests until GREEN; run `rg` again and verify no ambiguous production `paneAtom.panes`, `workspacePane.panes`, or observed `paneStates` access remains.
- [ ] Run `mise run format`, inspect the task diff, and commit the atomic cutover as `refactor(state): key pane observation`.

---

### Task 3: App-owned batched command presentation, structural lint, and proof

**Files:**

- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerCommandPresentation.swift`
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- Modify: `Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift`
- Create or modify one narrowly App-owned command-presentation batch owner adjacent to `SidebarSurfaceHost`
- Modify: relevant Agent Studio performance trace/metrics projection only for approved aggregate counters
- Add: one SwiftSyntax architecture rule and fixtures parallel to `RepoCacheKeyedReadsRule.swift`
- Test: `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerCommandPresentationTests.swift`
- Test: `Tests/AgentStudioTests/Architecture/RepoExplorerHotPathArchitectureTests.swift`
- Test: App integration tests for real command owners and presentation invalidation

**Interfaces:**

```swift
package enum RepoExplorerCommandPresentationArguments: Hashable, Sendable {
    case noArguments
    case repoSidebarSortOrder(RepoExplorerSortOrder)
}

package struct RepoExplorerCommandPresentationRequest: Hashable, Sendable {
    let command: AppCommand
    let surface: AppCommandSurface
    let target: UUID?
    let targetType: SearchItemType?
    let arguments: RepoExplorerCommandPresentationArguments
}

package struct RepoExplorerCommandPresentationSnapshot: Equatable, Sendable {
    let generation: UInt64
    let results: [RepoExplorerCommandPresentationRequest: Bool]
}
```

The App owner observes the exact capability facts used by current validators and the bounded visible request set. It captures one coherent context and publishes one immutable equality-gated snapshot per accepted capability change, independent of sidebar projection generation. This is a Repo Explorer-specific presentation snapshot adjacent to `SidebarSurfaceHost`, not a generic atom, reusable command cache, persistence owner, or execution authority. The request arguments distinguish parameterized visibility and sort choices; the App owner maps them to the existing `AppCommandExecutionArguments` only while resolving presentation. Repo Explorer body reads the snapshot and never calls `dispatcher.canDispatch`. Clicks still invoke `AppCommandDispatcher` and revalidate live state. If reusing one `ActionStateSnapshot` requires extracting an existing validator helper, move that helper to its current App/Core owner rather than copying command switches.

- [ ] Add failing behavior tests for one visible-row request batch, distinct visibility/sort argument choices, independent refresh after management/zoom/tab/topology changes, zero refresh after title-only mutation, and stale presentation followed by live dispatch rejection.
- [ ] Confirm RED: current body performs commands × rows live capability reads and lacks an independent generation.
- [ ] Implement the narrow App owner and inject the immutable snapshot through `SidebarSurfaceHost`; remove body-time `dispatcher.canDispatch` calls.
- [ ] Add the SwiftSyntax rule rejecting explicit bulk pane snapshots in the designated hot tab/sidebar/command-presentation contexts, with good/bad fixtures and rule inventory coverage.
- [ ] Run focused Repo Explorer, App integration, architecture-tool, and telemetry tests until GREEN.
- [ ] Run `mise run format`, `mise run lint`, and `mise run build`; correct only failures inside this plan's code path.
- [ ] Run the complete local PR gate: `mise run test`. Record command, pass/fail counts when available, duration, and exit code.
- [ ] Run shared-stack proof: `mise run observability:up`, `mise run run-debug-observability -- --detach`, `mise run verify-debug-observability`, and the smallest marker-scoped title/pane workload verifier supported by the repo. Do not use stale JSONL as fallback.
- [ ] Perform bounded native manual proof against the debug app: typing, cursor, search, scroll, focus, tab, sidebar, ordinary title delay, and capability refresh. Use Peekaboo with PID targeting when visual interaction is required.
- [ ] Commit the complete proof/lint slice as `test(perf): prove proportional title and pane work`.

---

### Task 4: Dual implementation review, one remediation cycle, and PR readiness

**Review packet:** exact Requirements, Specification, Program Design, this plan, base/head SHAs, complete diff, focused/full proof receipts, observability/manual evidence, constraints, and review question. Reviewers receive no parent conversation history and read-only workspace access. Findings are candidate-only until parent reduction.

- [ ] Dispatch exact `claude-opus-5` at high reasoning and exact `gpt-5.6-sol` at high reasoning in parallel for independent whole-implementation review.
- [ ] Parent-verify every finding against current source, requirement, failure path, and proof. Merge duplicates and classify `accepted | rejected | contested | unverified`.
- [ ] Perform exactly one bounded remediation implementation cycle for all verified in-scope Critical/Important findings. Do not expand scope for unrelated suggestions; record unresolved load-bearing findings as blockers.
- [ ] Dispatch one scoped read-only re-review to both model lineages covering only accepted findings and the remediation diff; no second remediation cycle.
- [ ] Re-run every proof gate affected by remediation, then `mise run lint`, `mise run build`, and `mise run test` on current HEAD.
- [ ] Load PR-wrapup references, inspect branch/diff/staged scope, sanitize public text, commit scoped changes, push, and open or update a PR against `main`.
- [ ] Watch checks with `gh pr checks <pr> --watch --interval 120`; inspect comments, reviews, paginated unresolved threads, mergeability, and PR head SHA. Resolve only verified in-scope feedback. Do not merge.
- [ ] Report the PR as ready only when local HEAD equals PR head, all required checks pass, no actionable unresolved thread remains, mergeability is clear, and the final quiet re-fetch is clean.

## Plan Self-Review

- U1-U3 map to Task 1 and Task 3 runtime proof.
- U4 maps to Tasks 2-3: keyed owner, structural facts, per-tab/fleet consumers, and command batch.
- U5 maps to Task 2 attribution/equivalence/autosave and Task 3 Victoria proof.
- No task adds a forbidden owner, public API, persistence schema, compatibility path, or correctness dependency on telemetry.
- Review and remediation cardinality is explicit: two independent final reviewers, one remediation cycle, one scoped re-review, then stop or proceed to PR readiness.
