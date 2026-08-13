# Doc-Drift Inventory — admitted stale claims and missing concepts

The closed set of documentation defects admitted by the 2026-08-10 research
(source-verified against HEAD ca4cb95c4 / origin/main). R18 in the
[Specification](2026-08-10-performance-program.md) requires every item here to
be resolved by its owning slice; the program is not complete while any item
is unresolved. A slice plan may re-assign an item's owner with a note, but
every item has exactly one owner at all times. Removing an item without
resolving it requires an owner-authorized exclusion recorded here.

Slices: 1 rails (LUNA-400) · 2 admission/equality (LUNA-401) · 3 git/forge
triggers (LUNA-402) · 4 keyed observation/off-main (LUNA-403) · 5 startup
(LUNA-404).

## Stale claims (doc contradicts current code)

| ID | Doc anchor | Defect | Slice |
|----|-----------|--------|-------|
| D1 | workspace_data_architecture.md:9 TL;DR | "WorkspaceCacheCoordinator consumes all events" — three other consumers exist; coordinator ignores `.pane` | 2 |
| D2 | workspace_data_architecture.md:333-355 | Git projection described without admission, capacity-retry, status-backoff, quarantine, priority policies | 3 |
| D3 | atom_persistence_boundaries.md:80-114,157-190 | Pane graph shown as one owner; misses dual canonical/structural `AtomFamily` slots + `acceptedCommitRevision` (origin/main vocabulary) | 4 |
| D4 | pane_runtime_architecture.md:7,140 | Opening "Problem" claims 12-of-40 actions, `DispatchQueue.main.async`/NotificationCenter debt, no runtimes — all superseded | 2 |
| D5 | pane_runtime_architecture.md:2958,3075 | Migration inventory claims 23 `DispatchQueue.main.async` / 20 selector observers remain; current counts are 0/0 | 2 |
| D6 | pane_runtime_architecture.md:38 | EventBus called "dumb fan-out (post + subscribe only)"; current bus has policies, replay, diagnostics | 2 |
| D7 | pane_runtime_architecture.md:1740-1758 | Contract 7 describes one generic accumulator/drain; current code has independent `.immediate`/`.title` lanes with deadline | 2 |
| D8 | pane_runtime_architecture.md:3151 | `FSEventsWatcher` listed as future; reality is `FilesystemActor`/`DarwinFSEventStreamClient` | 3 |
| D9 | pane_runtime_eventbus_design.md:365-410 | Pre-hardening EventBus API (unbounded `subscribe()`); current is `subscribe(policy:subscriberName:)` with replay/drop accounting | 2 |
| D10 | pane_runtime_eventbus_design.md:1229-1247 | Adoption plan presented as future; those steps shipped | 2 |
| D11 | pane_runtime_eventbus_design.md:1327-1355 | "No `Task.detached`, no `MainActor.run`" claims; current source uses both intentionally | 2 |
| D12 | pane_runtime_eventbus_design.md:1148 | `ForgeActor` listed as future; it is implemented and started | 3 |
| D13 | observability_and_traceability.md:140-150 | OTLP atom allowlist omits exported `agentstudio.performance.atom.label` | 1 |
| D14 | component_architecture.md:932 | Command-bar custom action example uses removed `NotificationCenter.post(.selectTabById)` | 2 |
| D15 | component_architecture.md:5 vs 974-987 | TL;DR says "twelve invariants"; section lists ten | 4 |
| D16 | CLAUDE.md:450-453 | `WorkspacePaneGraphAtom` row omits structural-facts map / accepted commit revision | 4 |

## Missing concepts (current behavior no doc explains)

| ID | Concept | Slice |
|----|---------|-------|
| M1 | Pane graph canonical vs `PaneStructuralFacts`, atomic paired-map commits, accepted commit revision | 4 |
| M2 | Per-pane structural reads (Bridge eligibility, drawer placement, residency, CWD routing) | 4 |
| M3 | `PaneObservationResolver` observed/attended resolution without full `Pane` materialization | 4 |
| M4 | `TabBarAdapter` per-tab observation generations and keyed tab-item refresh | 2 |
| M5 | RepoExplorer off-main projection worker, cancellation, immutable row index, command candidate snapshot | 4 |
| M6 | Git projector admission priorities, reserved active-pane capacity, circuit breaker, capacity retry, quarantine, scoped status projection | 3 |
| M7 | `CoalescingBusApplier` off-main coalescing with one bounded MainActor batch | 2 |
| M8 | EventBus per-source replay capacity, truncation status, drop classes, recovery diagnostics, delivery telemetry | 2 |
| M9 | Terminal independent immediate/title lanes and title admission slack | 2 |
| M10 | Atom telemetry labels and runtime-delivery OTLP metrics (live/replay drops, delivery debt) | 1 |
| M11 | `Task.detached` exception policy for cancellation-resistant SDK/process work | 1 |
| M12 | Eager pane-graph slot population, structural-facts pairing, per-tab observer registration | 4 |

## Slice resolution status

| ID | Status | Resolution |
|----|--------|------------|
| D13 | Resolved in slice 1 | `observability_and_traceability.md` now lists the exported controlled atom `label`. |
| M10 | Resolved in slice 1 | `observability_and_traceability.md` now defines atom dimensions and runtime-delivery pending, debt, live/replay drop, and retired-undelivered metrics. |
| M11 | Resolved in slice 1 | `pane_runtime_eventbus_design.md` now limits detached work to cancellation-resistant SDK/process ownership with explicit completion/cancellation and no actor-isolated mutable capture. |
| D1 | Resolved in slice 2 | `workspace_data_architecture.md` names the independent runtime-fact subscribers and the cache coordinator's bounded ownership. |
| D4 | Resolved in slice 2 | `pane_runtime_architecture.md` opens with the shipped typed admission and runtime model. |
| D5 | Resolved in slice 2 | `pane_runtime_architecture.md` records zero remaining callback-trampoline dispatches and selector observers. |
| D6 | Resolved in slice 2 | `pane_runtime_architecture.md` limits EventBus ownership to transport matching, replay, and diagnostics rather than calling it a dumb pipe. |
| D7 | Resolved in slice 2 | `pane_runtime_architecture.md` documents independent immediate/title drains, title admission slack, and acknowledgement-backed publication state. |
| D9 | Resolved in slice 2 | `pane_runtime_eventbus_design.md` documents named policy-bearing subscriptions with optional fact-topic interests. |
| D10 | Resolved in slice 2 | `pane_runtime_eventbus_design.md` labels the shipped adoption and separates remaining deferred capabilities. |
| D14 | Resolved in slice 2 | `component_architecture.md` removes the retired NotificationCenter command-bar action example. |
| M4 | Resolved in slice 2 | `pane_runtime_architecture.md` documents TabBarAdapter per-tab observation generations and keyed refresh/publication. |
| M7 | Resolved in slice 2 | `pane_runtime_architecture.md` documents off-main keyed coalescing with one bounded MainActor batch. |
| M8 | Resolved in slice 2 | `pane_runtime_eventbus_design.md` documents per-source replay, truncation, drop classes, recovery diagnostics, and delivery debt. |
| M9 | Resolved in slice 2 | `pane_runtime_architecture.md` documents independent terminal drain lanes and title admission slack. |
| R19 | Checked in slice 2; no slice-2-owned flip | The four R4 report-only lexical surfaces cover keyed observation reads, MainActor collection-wide work, performance constants, and nonisolated blocking I/O. None covers terminal publication admission, CWD authority, EventBus fact-interest matching, or this documentation cleanup; no rule was broadened. |

## Exclusions

None. An exclusion requires owner authorization and is recorded here with its
evidence.
