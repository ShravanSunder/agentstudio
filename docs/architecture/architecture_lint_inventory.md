# Architecture Lint Inventory

This inventory maps AgentStudio's architecture rules to their current proof
surface. Update it in the same change when adding, removing, or reclassifying an
architecture lint rule.

Architecture lint now has two layers:

- stock SwiftLint from `.swiftlint.yml`, including regex `custom_rules`
- AgentStudio's repo-local SwiftPM/SwiftSyntax tool at
  `Tools/AgentStudioArchitectureLint`

The local architecture tool is not a SwiftLint plugin. It runs alongside stock
SwiftLint through `mise run lint` and CI. Do not restore an external
custom-SwiftLint toolchain. Do not reintroduce repo-local shell/`rg`
architecture-lint scripts for rules that SwiftSyntax can express, and do not
add SwiftSyntax dependencies to the app package.

Architecture diagnostics have three severity channels. `error` and `warning`
findings print and make the architecture-lint command exit non-zero. `report`
findings print through the same output path without affecting the exit code.
Performance-program guard rules begin as `report`; promoting one to blocking
under R19 is a review-visible severity change recorded in this inventory.

## SwiftSyntax Architecture Rules

| Contract | Rule ID | Severity | Source |
| --- | --- | --- | --- |
| Source layers follow the documented import direction. | `agentstudio_import_direction` | error | `docs/architecture/directory_structure.md` |
| Product atom state follows the Core, Feature, and App composition boundaries; removed compatibility, resolver, registration, and secondary-scope APIs stay absent. | `agentstudio_product_atom_boundary` | error | `docs/architecture/directory_structure.md` |
| Canonical atom-owner classes expose mutable stored state only as `private` or `private(set)` and reject writable bindings. | `agentstudio_canonical_atom_mutation` | error | `AGENTS.md#hard-rules` |
| `SharedComponents/` render from explicit inputs and do not access atoms or global stores. | `agentstudio_shared_components_are_stateless` | error | `docs/architecture/directory_structure.md` |
| `Infrastructure/AtomLib` stays generic and does not reference product atoms or feature state. | `agentstudio_atomlib_is_generic` | error | `docs/architecture/atom_persistence_boundaries.md` |
| `DerivedAtom` compute closures use declared inputs and do not hide atom reads through direct or same-file helper/wrapper calls. | `agentstudio_derived_atom_declared_inputs` | error | `docs/architecture/atom_persistence_boundaries.md` |
| Hot production reads use keyed repo-cache readers instead of raw observable dictionaries. | `agentstudio_repo_cache_keyed_reads` | error | `docs/architecture/atom_persistence_boundaries.md` |
| `WorktreeEnrichment` atom comparators do not use raw equality. | `agentstudio_worktree_enrichment_comparator` | error | `docs/architecture/atom_persistence_boundaries.md` |
| New state files use the `State/MainActor/{Atoms,Persistence}` path convention. | `agentstudio_state_actor_path` | warning | `docs/architecture/directory_structure.md` |
| Programmatic-control contracts stay transport/app/UI independent. | `agentstudio_ipc_programmatic_control_boundary` | error | `docs/architecture/agentstudio_ipc_architecture.md` |
| `AgentStudioAppIPC` exposes ports instead of concrete app/runtime owners. | `agentstudio_appipc_port_boundary` | error | `docs/architecture/agentstudio_ipc_architecture.md` |
| Concrete AppIPC port implementations and method contributions live under `Sources/AgentStudio/App/IPCComposition`. | `agentstudio_ipc_composition_location` | error | `docs/architecture/agentstudio_ipc_architecture.md` |
| Feature slices do not import the app IPC service target directly; feature IPC methods are app-composed contributions. | `agentstudio_features_do_not_import_appipc` | error | `docs/architecture/agentstudio_ipc_architecture.md` |
| Public IPC surfaces expose scrubbed DTOs, not zmx namespaces or raw runtime payloads. | `agentstudio_ipc_public_surface_sanitization` | error | `docs/architecture/agentstudio_ipc_architecture.md` |
| AppIPC services and adapters route through ports and owners instead of direct atom access. | `agentstudio_ipc_no_direct_atom_access` | error | `docs/architecture/agentstudio_ipc_architecture.md` |
| Sentinel fixture proves the local architecture rule registry is active. | `agentstudio_no_forbidden_architecture_marker` | error | `Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/Fixtures/Bad/Sources/AgentStudio/App/BadForbiddenArchitectureMarker.swift` |
| Production async delays avoid generic clock sleep overloads. | `agentstudio_no_generic_clock_sleep` | error | `AGENTS.md#no-wall-clock-tests` |
| Tests avoid direct wall-clock `Task.sleep(...)` calls and wait for events, state, or injected fake clocks. | `agentstudio_no_task_sleep_in_tests` | error | `AGENTS.md#no-wall-clock-tests` |
| Dense action controls use typed tooltip sources instead of raw `.help("...")`, AppKit `toolTip = "..."`, or custom hover strings. Shared components consume resolved render values only. | `agentstudio_toolbar_tooltip_source` | error | `docs/architecture/commands_and_shortcuts.md#tooltips-help-text-and-compact-control-copy` |
| Production EventBus subscriptions and wait helpers name an explicit semantic subscriber policy; wrappers cannot hide a default or zero-argument policy. | `agentstudio_eventbus_subscriber_policy_required` | error | `Sources/AgentStudio/Core/RuntimeEventSystem/Events/EventBus.swift` |
| Terminal-local `GhosttyActionDisposition` branches contract locally and cannot reach the shared exact semantic publication edge. | `agentstudio_terminal_local_disposition_publication` | error | [Pane Runtime Contract 7](pane_runtime_architecture.md#contract-7-typed-ghostty-source-admission-and-contraction) |
| Observation-capture closures use keyed reads instead of named whole-snapshot calls. | `agentstudio_observation_capture_keyed_reads` | report | `docs/specs/2026-08-10-performance-program/program-design.md#report-only-lint-severity-channel-r4` |
| `@MainActor` types do not perform named collection-wide sort, reduce, grouping, or hash calls without an allowlisted owner. | `agentstudio_mainactor_unbounded_collection_work` | report | `docs/specs/2026-08-10-performance-program/program-design.md#report-only-lint-severity-channel-r4` |
| Numeric timing and performance-threshold constants live in `AppPolicies`. | `agentstudio_performance_constants_in_app_policies` | report | `docs/specs/2026-08-10-performance-program/program-design.md#report-only-lint-severity-channel-r4` |
| `nonisolated async` declarations that make syntactically blocking file reads use `@concurrent`. | `agentstudio_nonisolated_async_blocking_io_requires_concurrent` | report | `docs/specs/2026-08-10-performance-program/program-design.md#report-only-lint-severity-channel-r4` |

The four performance guards are intentionally lexical and report-only. They
recognize only the call, declaration, and literal shapes named above; they do
not infer collection bounds, types, executor hops, or I/O behavior.
Exceptions belong in the centralized `ArchitectureAllowlists`, with paired
Good/Bad fixtures. R19 promotion changes the rule severity from `report` to a
blocking channel and updates this inventory in the same reviewed change.

Slice 3 checked `agentstudio_performance_constants_in_app_policies`, but its
current production/test scan still reports pre-existing findings outside the
slice-3 trigger owners, so R19 forbids its promotion. Slice 4's production scan
found no keyed-observation diagnostics, but the full lint surface found one
pre-existing diagnostic outside slice-4 ownership at
`Tests/AgentStudioTests/Features/CommandBar/CommandBarResultSessionTests.swift:264`.
The keyed-observation rule therefore also remains report-only. MainActor
collection-work and nonisolated blocking-I/O remain report-only because neither
slice owned and cleaned those lexical surfaces.

The Terminal publication guard is deliberately lexical. In AgentStudio's
Terminal source, it recognizes switches whose subject is
`GhosttyActionDisposition.classify(...)`; the exact classifier call must be the
direct switch subject rather than a stored result. Each `.latestPresentation`,
`.latestSemanticMetadata`, `.activityEvidence`, `.exactLocalLifecycle`, and
`.diagnostic` branch must end in a top-level `return` and must not directly call
`routeActionToTerminalRuntimeOnMainActor`. This blocks direct local-branch
publication, stored-classifier bypass, and post-switch fallthrough to the shared
semantic edge while leaving `.exactFactOrControl` eligible for that ordered
route. The rule does not perform general type resolution or control-flow
analysis. It does not enforce Inbox classification; `InboxNotificationRouter`
independently uses exhaustive top-level and nested owned-event switches with
typed ignore reasons.

## Former Shell And Custom SwiftLint Coverage

| Former behavior | Current status | Replacement |
| --- | --- | --- |
| Fail Core importing Features. | Blocking | `agentstudio_import_direction` |
| Fail Core importing App. | Blocking | `agentstudio_import_direction` |
| Fail Features importing sibling Features. | Blocking | `agentstudio_import_direction` |
| Fail SharedComponents importing Core, Features, or App. | Blocking | `agentstudio_import_direction` |
| Fail SharedComponents reading atoms, resolving global stores, or owning atom/store objects. | Blocking | `agentstudio_shared_components_are_stateless` |
| Fail AtomLib importing product layers or referencing product atoms. | Blocking | `agentstudio_atomlib_is_generic` |
| Fail `DerivedAtom` direct `atom(...)`, `CoreAtomScope`, or `CoreAtoms` reads. | Blocking | `agentstudio_derived_atom_declared_inputs` |
| Fail same-file helper/wrapper calls from `DerivedAtom` compute closures when the helper hides an atom read. | Blocking | `agentstudio_derived_atom_declared_inputs` |
| Fail raw `WorktreeEnrichment` equality as an atom comparator. | Blocking | `agentstudio_worktree_enrichment_comparator` |
| Fail hot `repoEnrichmentByRepoId`, `worktreeEnrichmentByWorktreeId`, and `pullRequestCountByWorktreeId` dictionary reads outside named cold surfaces. | Blocking | `agentstudio_repo_cache_keyed_reads` |
| Fail IPC contract code importing the app, AppKit, SwiftUI, or feature/runtime owners. | Blocking | `agentstudio_ipc_programmatic_control_boundary` and `agentstudio_appipc_port_boundary` |
| Fail IPC composition outside the approved app composition location. | Blocking | `agentstudio_ipc_composition_location` |
| Fail feature slices importing `AgentStudioAppIPC` directly. | Blocking | `agentstudio_features_do_not_import_appipc` |
| Fail public IPC zmx namespace/raw runtime payload leakage. | Blocking | `agentstudio_ipc_public_surface_sanitization` |
| Fail direct atom access from IPC services and adapters. | Blocking | `agentstudio_ipc_no_direct_atom_access` |
| Fail production `Task.sleep(for:)` and generic `.sleep(for:)` outside the approved delay seam. | Blocking | `agentstudio_no_generic_clock_sleep` |
| Fail direct `Task.sleep(...)` calls in test files. | Blocking | `agentstudio_no_task_sleep_in_tests` |
| Fail production EventBus subscriptions or wait helpers that omit semantic subscriber policy, use raw buffering policy, or hide a default policy in a wrapper. | Blocking | `agentstudio_eventbus_subscriber_policy_required` |
| Fail Terminal-local Ghostty disposition branches that directly publish or can fall through to the shared exact semantic publication edge. | Blocking | `agentstudio_terminal_local_disposition_publication` |
| Print repo-cache dictionary read inventory. | Reclassified to review-only | The old script's report-only inventory is replaced by this document plus blocking rules for the hot-path violation class. Broad inventory reports were noisy and not a required CI gate. |

## Test And Fixture Proof

| Proof | Covers |
| --- | --- |
| `swift test --package-path Tools/AgentStudioArchitectureLint` | Builds the local SwiftPM/SwiftSyntax tool, checks the exact rule inventory and severity map, lints good fixtures, verifies bad fixtures fail, and proves every migrated rule is exercised by the fixture corpus. |
| `ArchitectureSwiftLintRulesTests` | Verifies AgentStudio's `mise`, CI, stock SwiftLint, local architecture tool, deleted old-runner files, and `no_combine_import` regex custom-rule behavior through stock SwiftLint. |
| `mise run lint` | Runs swift-format, stock SwiftLint, the local AgentStudio architecture linter, and release script checks. |

## Review-Only Guidance

Some architecture guidance remains review-only because it depends on semantic
judgment rather than a reliable syntax pattern: when to extract a shared
component on second use, whether a coordinator owns domain decisions, and
whether a dictionary-shaped read is an explicitly measured cold exception.
