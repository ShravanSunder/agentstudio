# Sidebar List Architecture

Status: Reviewed; ready for implementation planning
Date: 2026-07-16
Scope: Repo and Inbox sidebar list mechanics, projection boundaries, interaction semantics, and performance proof

## Product intent

AgentStudio's Repo and Inbox sidebars must remain responsive and behave like native macOS navigators as their data grows. A user must be able to search, group, sort, filter, expand, select, and activate rows without perceptible stalls, stale controls, lost focus, or container-specific behavioral drift.

The design preserves feature ownership while sharing the mechanics that should be identical across sidebar surfaces. It does not replace the existing sidebar header, toolbar, command, or persistence contracts.

## Success criteria

- Repo and Inbox share one typed sidebar-list interaction contract.
- Filtering, grouping, sorting, flattening, row indexing, and other proportional derivation execute outside the MainActor.
- Mutable row state is read from canonical keyed owners and can update without rebuilding unrelated rows or waiting for structural projection.
- Native keyboard, focus, selection, expansion, scrolling, and accessibility behavior remain correct through structural and nonstructural changes.
- Performance proof measures semantic intent through rendered, interaction-ready completion under deterministic fixtures.
- SwiftUI `List` remains an allowed backend only when it passes the acceptance gate in this spec. Failure requires the shared AppKit `NSOutlineView` backend; it does not permit a custom `LazyVStack` list system.

## Non-goals

- Redesigning sidebar header chrome, icons, menus, colors, or spacing.
- Unifying Repo and Inbox domain projections or canonical atoms.
- Moving product state into `SharedComponents`.
- Adding persistence for selection or focus.
- Replacing generic `command.execute` IPC with sidebar-specific command transports.
- Using `Table` for this single-column navigation surface.
- Building selection, accessibility, and keyboard navigation from scratch on `ScrollView + LazyVStack`.
- Defining implementation order, worker assignments, or exact validation commands.

## Current-state constraints

- Both sidebar roots are MainActor SwiftUI views.
- Repo and Inbox already use feature-owned actors and cancellable detached tasks for projection work.
- MainActor request construction still copies and compares broad snapshots.
- Both surfaces currently render SwiftUI `List` values.
- Repo projection output retains complete repo/worktree presentation values; Inbox projection output retains complete notification values.
- Existing `mainactor_apply` timing ends after cached-state assignment and excludes SwiftUI body recomputation, platform reconciliation, layout, display, accessibility exposure, and interaction readiness.
- Repo currently has no explicit row-selection model. Inbox owns feature-specific keyboard commands and row focus.
- Shared sidebar components accept direct values, bindings, callbacks, or explicit observable view models. They do not read atoms or global state.

## Requirements

### R1. Shared component independence

The shared sidebar list component must:

- live in `SharedComponents`;
- import neither `Core`, `Features`, nor `App`;
- receive immutable structures, direct values, bindings, callbacks, row builders, or explicitly passed observable interaction models;
- never read atoms, global stores, command routers, or persistence directly;
- keep SwiftUI/AppKit backend implementation types private to the shared component.

### R2. Feature ownership

Existing canonical owners remain authoritative:

- Core `RepositoryTopologyAtom` owns Repo topology and favorite mutation.
- Core `SidebarExpandedGroupAtom` plus `SidebarCacheStore` own persisted Repo expansion.
- Inbox feature atoms own notification state, Inbox preferences, and Inbox collapsed-group state.

The Core topology owner must expose canonical per-repo and per-worktree observable slots using the established `AtomEntityMap` pattern. Ordered topology references those canonical entities by typed ID. Keyed slot updates and topology membership/revision updates occur within the same owner mutation; a feature-maintained synchronized entity copy is not admissible.

Repo and Inbox feature adapters own:

- filtering, grouping, sorting, visibility, and search policy;
- immutable projection input construction;
- projection workers and generation admission;
- keyed reads and mutation intents against their named canonical owners;
- row content, context menus, activation meaning, and feature-specific shortcuts;
- selection-remapping policy when a structural change removes or duplicates an occurrence.

The shared component owns native interaction mechanics, not product meaning.

### R3. Identity model

The shared contract distinguishes four typed identity concepts:

- `GroupID`: semantic group identity used for expansion and group-row restoration.
- `EntityID`: canonical repo, worktree, or notification identity used for row state and actions.
- `OccurrenceID`: globally unique row occurrence identity used for duplicate placement, restoration, and diffing.
- `EntryID`: shared selection identity, with either `.group(GroupID)` or `.row(OccurrenceID)`.

`OccurrenceID` must remain stable across nonstructural row-state changes and sorting. It may change when grouping changes the semantic placement. A canonical entity may have multiple occurrences, including duplicate worktree occurrences in Tab mode. Group entries do not require an `EntityID`; row entries require `EntityID`, `OccurrenceID`, and `.row(OccurrenceID)` selection identity.

`GroupID` is namespaced by surface and grouping mode, so persisted expansion in Repo, Pane, Tab, Flat, or Inbox modes cannot collide. Inbox claim coalescence preserves the surviving notification `EntityID`.

Identity must not depend on transient favorite/read state, visible index, active styling, branch status, unread count, or localized display text.

### R4. Projection contract

Feature projection workers return one normalized immutable hierarchy containing:

- accepted generation/revision;
- ordered group nodes, including whether each header is visible in the current mode;
- ordered child occurrence IDs for every group node;
- entity IDs required for keyed resolution and action callbacks;
- immutable derived presentation facts that are expensive or unsafe to recompute on MainActor;
- optional content revisions for targeted row refresh.

Flat presentation uses one implicit group node whose header is hidden. Expansion is not baked into the hierarchy: the shared container derives visible `EntryID` order from the immutable hierarchy plus the feature-owned effective expansion binding. This representation drives both private backends; a backend does not request a second feature-specific tree shape.

Projection output must not retain complete mutable `RepoPresentationItem`, `Worktree`, or `InboxNotification` values as the canonical row source.

### R5. Canonical keyed row state

Each feature provides keyed, observable row-state access for canonical mutable values. Repo state includes favorite and mutable topology metadata; Inbox state includes read and dismissal state.

- A visible row observes only its entity slot and any explicitly required shared revision.
- A nonstructural mutation updates every visible occurrence of that entity without reconstructing list membership.
- A predicate-changing mutation may additionally request structural projection.
- A missing or deleted entity resolves safely and cannot activate a stale copied value.
- Repo adapters read the Core topology owner's canonical `AtomEntityMap` slots; they do not own a mirror.
- An unobserved dictionary or synchronized feature copy duplicated beside the canonical owner is not sufficient.

### R6. Concurrency and lifecycle

- Filtering, grouping, sorting, search normalization, flattening, row indexing, and proportional snapshot transformation must execute outside MainActor isolation.
- MainActor work is limited to capturing a bounded number of immutable `Sendable` copy-on-write source snapshots and revision tokens, admitting the latest generation, applying immutable results, and operating UI state. Capture cost is bounded by source-owner count, not entity or occurrence count.
- Retaining a projection input must not defer entity-proportional copy-on-write cost onto a later canonical MainActor mutation. Copy-on-write capture is admissible only when concurrent-mutation proof shows bounded mutation cost while the maximum-size snapshot is retained; otherwise projection input uses independently owned normalized storage or another storage strategy with bounded canonical mutation cost.
- Derived dictionaries, fingerprints, placement scans, full equality keys, search normalization, and other entity-proportional request assembly happen after immutable handoff and outside MainActor isolation.
- One admitted generation records the revision token from every contributing owner. A later mutation of any predicate-affecting owner invalidates that generation; mixed-revision structures are never applied.
- Projection is latest-wins. Stale generations never partially update structure or row state.
- Cancellation must be cooperative within proportional stages, not only before and after the complete projection.
- Each mounted surface has one projection lifecycle owner, at most one CPU-consuming projection, and at most one pending latest request. A newer request replaces the pending request, cancels the active projection, and starts only after active work acknowledges cancellation.
- Disappearing or replaced surfaces cancel owned work and cannot apply results or emit readiness afterward.
- The design must not use wall-clock sleeps or unsafe isolation escapes to coordinate completion.

### R7. Shared interaction contract

The shared container provides:

- one transient selected `EntryID`;
- first-responder acquisition and release;
- Up/Down movement across visible selectable rows;
- Left/Right collapse and expansion for groups;
- Return activation;
- scroll-to-selection and visibility preservation;
- selected and expanded accessibility state;
- stable accessibility identifiers and feature-provided labels/actions;
- one backend-neutral action-readiness receipt carrying proof marker, run-local sequence, action kind, affected `EntityID`/`EntryID` when applicable, expected observable state, and an optional structural revision;
- exactly one terminal readiness outcome per issued action: ready, timed out, wrong state, missing target, duplicate completion, canceled by teardown, or harness-invalid.

Group entries participate in Up/Down navigation. Left/Right and Return collapse or expand the selected group. Row Return invokes the feature activation callback. A pointer click first makes the entry current and then preserves current product behavior: group clicks toggle disclosure and row clicks invoke the existing feature activation. Inbox retains Space-to-toggle-read and its existing Option/Command navigation commands through feature callbacks. Repo activation and secondary actions remain feature-owned.

### R8. Selection and expansion repair

- Nonstructural refresh and sorting preserve the same `EntryID` selection.
- Grouping changes remap a selected row by canonical entity. Repo first prefers an occurrence with the same pane/tab placement identity, then the occurrence nearest the prior visible index, then the first occurrence in the new projected order. Inbox prefers the same notification occurrence, then the nearest prior visible index. Dictionary iteration order never participates.
- Grouping remap runs before disappearance repair. If the selected entry still has no target, selection moves to the next selectable entry in the prior visible order, then the previous entry; otherwise selection becomes nil while list focus remains valid.
- Filtering maintains a latent semantic selection. If a valid target returns when the filter clears, selection is restored using the same grouping-remap policy.
- Forced expansion used to reveal search results is transient and does not mutate persisted group expansion.
- Clearing search restores the persisted expansion set.
- Hidden descendants are neither selectable nor exposed as visible accessibility rows.

### R9. Stable row geometry

Sidebar row kinds use stable height categories. Mutable badges, labels, favorite/read state, and status updates do not change row height. Text truncates according to the existing sidebar style rather than wrapping into new list geometry.

If a future row kind requires variable height, it must declare explicit height invalidation and scroll-anchor behavior through the shared contract; implicit intrinsic-height churn is not allowed.

### R10. Backend admission

The public shared contract is backend-neutral. The backend is a private implementation choice with these rules:

- SwiftUI `List(selection:)` is admissible only after the model, identity, keyed observation, and end-to-end proof requirements in this spec are satisfied.
- A SwiftUI backend uses one flattened, structurally stable entry collection with cheap IDs and one row per collection element.
- SwiftUI `List` is admitted only when both clean deterministic runs pass every semantic and performance requirement. Any valid run failure rejects it and selects the shared AgentStudio-owned `NSOutlineView` bridge.
- The AppKit backend must use reusable views, semantic-ID selection/expansion restoration, bounded targeted insert/remove/move/reload operations, and coalesced full reloads.
- An AppKit wrapper that allocates every row, reloads the complete hierarchy for nonstructural changes, or reaches into feature/global state does not satisfy this spec.
- If the AppKit fallback also fails a required semantic or performance gate, the backend decision is blocked and both backend receipts are escalated to the owner. Budgets may change only through a reviewed spec revision, never by retrying or reclassifying a valid run.
- Repo and Inbox use one admitted production backend after the gate. Backend comparison may occur in an isolated proof harness, but production does not retain parallel List/AppKit paths or per-surface backend divergence. Backend details never escape into feature APIs.

### R11. Command and IPC behavior

- Sidebar product commands and domain mutations use typed `AppCommand` definitions and generic authenticated `command.execute` routing. Presentation-only focus/disclosure mechanics may remain local callbacks or `LocalActionSpec` values and are not represented as product commands.
- IPC validates command identity, specifiers, authorization, and semantic state readback. It does not prove rendering.
- Repo favorite mutation is a product command. It has a typed repo target/specifier, dispatches through the normal command system from UI and headless callers, appears automatically in the command catalog, and executes through generic IPC without a bespoke favorite transport.
- Favorite execution always requires an explicit repo target. A row action supplies its repo ID and a headless caller supplies the typed repo specifier; catalog discovery does not invent a target or open a picker. Missing, stale, or wrong-kind targets are rejected by normal command validation.
- UI-only pointer or accessibility actions must not be mislabeled as IPC command coverage.

### R12. Observability and privacy

Every measured action carries a fresh proof marker, safe surface/action dimensions, fixture dimensions, and a run-local sequence. Raw paths, repo names, notification text, prompts, UUIDs, and row labels must not enter OTLP.

The performance lifecycle is:

```text
semantic intent accepted
  -> immutable input ready
  -> worker admitted
  -> projection complete
  -> MainActor continuation resumed
  -> structural model applied
  -> container reconciliation observed
  -> matching row visible and interaction-ready
```

A nonstructural action follows a separate branch and does not synthesize structural work solely for proof:

```text
semantic intent accepted
  -> canonical keyed state changed
  -> every visible occurrence reflects expected state
  -> target occurrence remains interaction-ready
```

Diagnostic phase timings remain separate from:

- intent-to-visible-feedback;
- intent-to-reconciled-structure;
- intent-to-interaction-ready.

For an accepted revision, `container reconciliation observed` means an in-process, backend-neutral predicate confirms that the matching target entry is materialized with valid geometry and expected selection, expansion, and value state. A backend may additionally report a public platform-transaction completion signal, but that signal is not required when the framework exposes none and is never sufficient by itself. The proof harness validates the shared predicate against PID-targeted accessibility and native UI ground truth and must show that a receipt never precedes externally observable truth. `Interaction-ready` additionally means the expected target or deterministic replacement can accept the next semantic keyboard or activation action. Scheduling display, incrementing a host sequence, assigning SwiftUI state, or forcing layout without the matching entry predicate is not completion.

IPC/authentication/socket overhead, Peekaboo discovery/input/screenshot overhead, retries, and polling are reported separately and excluded from product latency.

### R13. Deterministic performance gate

The gate uses two recorded fixture classes rather than treating incompatible scales as one fixture.

The realistic large-workspace fixture contains at least:

- 118 repos, 163 worktrees, and 14 panes;
- declared favorites ratio, expanded-group count, visible occurrence count, and Pane/Tab duplicate distribution;
- exactly 1,000 Inbox notifications, matching but not exceeding the current retention cap, distributed across repo, pane, tab, and unassigned groups; fixture setup completes before measured actions so retention churn cannot contaminate samples.

The synthetic reconciliation-stress fixture contains at least:

- 1,000 visible row occurrences;
- 100 groups;
- Repo duplicates in Pane and Tab grouping modes;
- the same declared action dimensions as the realistic fixture.

Both fixtures are generated outside the user's workspace and record complete non-sensitive dimensions. A clean run starts from an idle, fully loaded isolated debug process, performs no concurrent fixture mutation or unrelated git refresh, and has no missing, duplicate, stale, or reordered lifecycle markers. Ineligible runs are reported and excluded rather than retried into a pass.

The admission matrix is keyed by backend, surface, fixture class, grouping/visibility mode, and action bucket. Each of two clean runs independently contains at least 100 issued samples per required bucket. Every issued action has one readiness receipt. Timeout, disappearance, wrong state, missing/duplicate readiness, stale completion, or failed follow-up interaction is a failed product sample and remains in the denominator; only a pre-intent harness-invalid attempt is excluded with a recorded reason. Semantic failures fail that run and cannot be retried away. Both clean runs must independently satisfy every semantic and latency requirement; pass/fail, fail/pass, and fail/fail all reject the backend.

Each fixture also retains its maximum-size projection input while favorite/read and predicate-changing mutations execute. Those actions must meet the same product budgets, and MainActor profiling must show no entity-proportional copy caused by retained projection storage.

Required product budgets:

- nonstructural visible feedback: p95 at or below 50 ms, maximum at or below 100 ms;
- structural filter, group, sort, collapse, favorite-only removal, and surface switch: p95 at or below 100 ms, maximum at or below 250 ms;
- zero selection, focus, keyboard, expansion, restoration, accessibility, stale-generation, or wrong-row activation failures.

The per-run maximums are intentional product contracts, not percentile estimates. Once semantic intent is accepted, scheduler or framework delay is user-visible latency and remains in the sample; it cannot make a run harness-ineligible. Only a recorded pre-intent violation of the clean-run contract may exclude an attempt. A backend rejected by these maxima may be reconsidered only after implementation improvement or a reviewed spec change.

A reviewer must be able to derive one joint backend verdict from the two run receipts without pooling samples across runs or choosing a per-surface fallback policy.

## Boundary and separability map

```text
Repo feature                         Inbox feature
adapts Core topology/expansion       owns notification/collapse atoms
owns repo projection policy          owns inbox projection policy
owns projection worker               owns projection worker
owns keyed row adapters              owns keyed row adapters
binds Core persisted expansion       binds feature persisted expansion
        |                                      |
        +------ immutable typed structure -----+
                               |
                               v
              SharedComponents/SidebarListContainer
              owns transient entry selection
              owns focus, keyboard, disclosure, AX
              owns reconciliation readiness signal
              owns private SwiftUI/AppKit backend
                               |
                  ID-only intents and bindings
                               |
        +----------------------+----------------------+
        v                                             v
Core topology canonical keyed state        Inbox canonical keyed state
```

Allowed dependencies:

- Features depend on shared contracts.
- Feature adapters pass direct values, bindings, callbacks, observables, and row builders.
- Shared container depends on SwiftUI/AppKit and domain-agnostic infrastructure only.

Forbidden dependencies:

- Shared container importing feature, core product, or app composition types.
- Shared container reading atoms, global stores, persistence, or command routers.
- Projection workers reading SwiftUI/AppKit or MainActor-owned mutable state.
- AppKit coordinators reaching into feature owners.
- Feature APIs exposing backend-specific SwiftUI/AppKit types.

## State and update examples

### Nonstructural favorite toggle in All mode

1. The typed favorite command changes canonical Repo state through the normal command owner.
2. Every visible occurrence observes the keyed repo slot and updates bookmark paint/accessibility immediately.
3. Structure remains unchanged; no structural snapshot is required solely for paint.
4. Persistence remains asynchronous and outside the interaction critical path.

### Favorite removal in Favorites Only mode

1. Canonical favorite state updates visible feedback.
2. The predicate-changing mutation requests a new structural projection.
3. Only the latest accepted generation removes the occurrence.
4. Grouping remap runs first; if no equivalent occurrence survives, selection repair chooses the deterministic next/previous entry fallback.
5. Readiness closes only when the removed row is absent and the replacement selection can accept input.

### Search and cancellation

1. Search input creates a new immutable request revision.
2. Older proportional work is canceled cooperatively and cannot apply.
3. Matching descendants use transient effective expansion.
4. Clearing search restores persisted expansion and any valid latent selection.

### Grouping with duplicate occurrences

1. Projection emits unique occurrence IDs for each placement.
2. Each occurrence resolves the same canonical entity slot for mutable row state.
3. Selection identifies one occurrence. Repo remapping prefers the same placement identity, then nearest prior visible index, then first projected occurrence.
4. Entity actions receive the canonical entity ID plus placement context where required.

## Alternatives considered

### Keep the current Lists without boundary repair

Rejected. It retains stale projected entity sources, broad invalidation, incomplete timing, and no common native interaction contract.

### Replace Lists immediately with custom LazyVStack scrolling

Rejected. It reduces control cost in one dimension while making AgentStudio own selection, keyboard navigation, disclosure, focus, accessibility, restoration, and scroll anchoring.

### Adopt NSOutlineView immediately without an admission gate

Not selected as the unconditional public design. AppKit is the accepted fallback and may ultimately win, but a wrapper alone does not guarantee targeted updates or good performance. The container-independent model and proof contracts are required either way.

### Use SwiftUI Table

Rejected. The surfaces are single-column navigators, not multi-column sortable tables, and no evidence shows Table resolves this reconciliation workload.

## Security and privacy context

This design introduces no new external trust boundary, filesystem access, network input, or authorization mechanism. Its security-sensitive surface is telemetry:

- OTLP exports only safe aggregate dimensions and deterministic hashes already allowed by observability policy.
- Accessibility and IPC proof must target the isolated worktree-specific debug process.
- IPC remains authenticated and command authorization remains centralized.

No separate threat model is required beyond these existing IPC and observability contracts.

## Proof expectations

- Schema and unit proof: identity uniqueness/stability, duplicate occurrences, selection remapping, expansion restoration, latest-generation admission, cancellation, and missing-entity behavior.
- Observation proof: nonstructural keyed mutation invalidates matching visible rows without invalidating unrelated rows or rebuilding structure.
- Integration proof: mounted container selection, responder focus, disclosure, scrolling, row reuse/targeted updates, teardown, and readiness lifecycle.
- Native UI proof: PID-targeted keyboard, pointer, accessibility, visual geometry, favorite/read feedback, and structural disappearance/restoration.
- Headless proof: authenticated generic command execution and semantic state readback, including explicit-target favorite execution and missing/stale/wrong-kind target rejection.
- Performance proof: marker-scoped Victoria metrics under deterministic fixtures, with product and automation latency separated.
- Instruments proof: SwiftUI update groups/platform-view updates for a SwiftUI backend; table/outline updates, layout, hangs, and Time Profiler for an AppKit backend.

## Planning inputs

The implementation plan must preserve the distinction between:

- feature model repair and keyed canonical observation;
- shared interaction contract;
- backend admission proof;
- private backend implementation;
- observability/proof harness repair;
- documentation and architecture enforcement.

These are separable responsibilities, not an implementation sequence.

## References

- Current Repo projection boundary: `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjectionWorker.swift`
- Current Inbox projection boundary: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListProjectionWorker.swift`
- Current hybrid UI architecture: `docs/architecture/appkit_swiftui_architecture.md`
- Current observability proof contract: `docs/architecture/observability_and_traceability.md`
- Apple, Demystify SwiftUI performance: https://developer.apple.com/videos/play/wwdc2023/10160/
- Apple, What's new in SwiftUI: https://developer.apple.com/videos/play/wwdc2025/256/
- Apple, Optimize SwiftUI performance with Instruments: https://developer.apple.com/videos/play/wwdc2025/306/
- Apple, NSOutlineView: https://developer.apple.com/documentation/appkit/nsoutlineview
- CodeEdit project navigator: https://github.com/CodeEditApp/CodeEdit/blob/cec6287a49a0a460cd7cab17f254eebc3ada828e/CodeEdit/Features/NavigatorArea/ProjectNavigator/OutlineView/ProjectNavigatorOutlineView.swift#L11
- CotEditor file browser: https://github.com/coteditor/CotEditor/blob/4bfff6e3997f07efc13f15b2d34f10764e1e3843/CotEditor/Sources/Document%20Window/Sidebar/FileBrowserViewController.swift#L36
- NetNewsWire sidebar: https://github.com/Ranchero-Software/NetNewsWire/blob/08d10f50167954821a161df877de9fd785e33557/Mac/MainWindow/Sidebar/SidebarViewController.swift#L40
