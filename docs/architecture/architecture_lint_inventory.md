# Architecture Lint Inventory

This inventory maps AgentStudio's architecture rules to their current proof
surface. Update it in the same change when adding, removing, or reclassifying an
architecture lint rule.

Architecture lint now has two layers:

- stock SwiftLint from `.swiftlint.yml`, including regex `custom_rules`
- AgentStudio's repo-local SwiftPM/SwiftSyntax tool at
  `Tools/AgentStudioArchitectureLint`

The local architecture tool is not a SwiftLint plugin. It runs alongside stock
SwiftLint through `mise run lint` and CI.

## SwiftSyntax Architecture Rules

| Contract | Rule ID | Severity | Source |
| --- | --- | --- | --- |
| Source layers follow the documented import direction. | `agentstudio_import_direction` | error | `docs/architecture/directory_structure.md` |
| `SharedComponents/` stays stateless and does not subscribe to atoms or observable owners. | `agentstudio_shared_components_are_stateless` | error | `docs/architecture/directory_structure.md` |
| `Infrastructure/AtomLib` stays generic and does not reference product atoms or feature state. | `agentstudio_atomlib_is_generic` | error | `docs/architecture/atom_persistence_boundaries.md` |
| `DerivedValue` compute closures use declared inputs and do not hide atom reads through direct or same-file helper/wrapper calls. | `agentstudio_derived_value_declared_inputs` | error | `docs/architecture/atom_persistence_boundaries.md` |
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
| Production async delays avoid generic clock sleep overloads. | `agentstudio_no_generic_clock_sleep` | error | `docs/superpowers/specs/2026-06-18-agentstudio-swiftsyntax-async-sleep-rule-spec.md` |
| Tests avoid direct wall-clock `Task.sleep(...)` calls and wait for events, state, or injected fake clocks. | `agentstudio_no_task_sleep_in_tests` | error | `AGENTS.md#no-wall-clock-tests` |
| Dense action controls use typed tooltip sources instead of raw `.help("...")`, AppKit `toolTip = "..."`, or custom hover strings. Shared components consume resolved render values only. | `agentstudio_toolbar_tooltip_source` | error | `docs/superpowers/specs/2026-06-19-typed-tooltip-source-contract.md` |

## Former Shell And Custom SwiftLint Coverage

| Former behavior | Current status | Replacement |
| --- | --- | --- |
| Fail Core importing Features. | Blocking | `agentstudio_import_direction` |
| Fail Core importing App. | Blocking | `agentstudio_import_direction` |
| Fail Features importing sibling Features. | Blocking | `agentstudio_import_direction` |
| Fail SharedComponents importing Core, Features, or App. | Blocking | `agentstudio_import_direction` |
| Fail SharedComponents owning state or reading atoms. | Blocking | `agentstudio_shared_components_are_stateless` |
| Fail AtomLib importing product layers or referencing product atoms. | Blocking | `agentstudio_atomlib_is_generic` |
| Fail `DerivedValue` direct `atom(...)`, `AtomScope`, `AtomReader`, or test-registry reads. | Blocking | `agentstudio_derived_value_declared_inputs` |
| Fail same-file helper/wrapper calls from `DerivedValue` compute closures when the helper hides an atom read. | Blocking | `agentstudio_derived_value_declared_inputs` |
| Fail raw `WorktreeEnrichment` equality as an atom comparator. | Blocking | `agentstudio_worktree_enrichment_comparator` |
| Fail hot `repoEnrichmentByRepoId`, `worktreeEnrichmentByWorktreeId`, and `pullRequestCountByWorktreeId` dictionary reads outside named cold surfaces. | Blocking | `agentstudio_repo_cache_keyed_reads` |
| Fail IPC contract code importing the app, AppKit, SwiftUI, or feature/runtime owners. | Blocking | `agentstudio_ipc_programmatic_control_boundary` and `agentstudio_appipc_port_boundary` |
| Fail IPC composition outside the approved app composition location. | Blocking | `agentstudio_ipc_composition_location` |
| Fail feature slices importing `AgentStudioAppIPC` directly. | Blocking | `agentstudio_features_do_not_import_appipc` |
| Fail public IPC zmx namespace/raw runtime payload leakage. | Blocking | `agentstudio_ipc_public_surface_sanitization` |
| Fail direct atom access from IPC services and adapters. | Blocking | `agentstudio_ipc_no_direct_atom_access` |
| Fail production `Task.sleep(for:)` and generic `.sleep(for:)` outside the approved delay seam. | Blocking | `agentstudio_no_generic_clock_sleep` |
| Fail direct `Task.sleep(...)` calls in test files. | Blocking | `agentstudio_no_task_sleep_in_tests` |
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
