# Architecture Lint Inventory

This inventory maps AgentStudio's architecture rules to their current proof
surface. Update it in the same change when adding, removing, or reclassifying an
architecture lint rule.

## Blocking SwiftLint Rules

| Contract | Enforcement | Source |
| --- | --- | --- |
| Source layers follow the documented import direction. | `agentstudio_import_direction` | `docs/architecture/directory_structure.md` |
| `SharedComponents/` stays stateless and does not subscribe to atoms or observable owners. | `agentstudio_shared_components_are_stateless` | `docs/architecture/directory_structure.md` |
| `Infrastructure/AtomLib` stays generic and does not reference product atoms or feature state. | `agentstudio_atomlib_is_generic` | `docs/architecture/atom_persistence_boundaries.md` |
| `DerivedValue` compute closures use declared inputs and do not hide atom reads through direct or same-file helper/wrapper calls. | `agentstudio_derived_value_declared_inputs` | `docs/architecture/atom_persistence_boundaries.md` |
| Hot production reads use keyed repo-cache readers instead of raw observable dictionaries. | `agentstudio_repo_cache_keyed_reads` | `docs/architecture/atom_persistence_boundaries.md` |
| `WorktreeEnrichment` atom comparators do not use raw equality. | `agentstudio_worktree_enrichment_comparator` | `docs/architecture/atom_persistence_boundaries.md` |
| New state files use the `State/MainActor/{Atoms,Persistence}` path convention. | `agentstudio_state_actor_path` | `docs/architecture/directory_structure.md` |
| `AgentStudioProgrammaticControl` stays a UI-free, app-owner-free contract target. | `agentstudio_ipc_programmatic_control_boundary` | `docs/architecture/agentstudio_ipc_architecture.md` |
| `AgentStudioAppIPC` depends on protocol ports rather than concrete app/runtime owners. | `agentstudio_appipc_port_boundary` | `docs/architecture/agentstudio_ipc_architecture.md` |
| Concrete AppIPC port implementations stay under `Sources/AgentStudio/App/IPCComposition/`. | `agentstudio_ipc_composition_location` | `docs/architecture/agentstudio_ipc_architecture.md` |
| Public IPC surfaces do not expose `zmx.*` methods or raw runtime/zmx payload types. | `agentstudio_ipc_public_surface_sanitization` | `docs/architecture/agentstudio_ipc_architecture.md` |
| AppIPC services and composition adapters do not read atoms directly. | `agentstudio_ipc_no_direct_atom_access` | `docs/architecture/agentstudio_ipc_architecture.md` |
| The custom SwiftLint extension remains registered through a sentinel rule. | `agentstudio_no_forbidden_architecture_marker` | ai-tools SwiftLint fixtures |

## Former Shell Script Coverage

| Former script behavior | Current status | Replacement |
| --- | --- | --- |
| Fail Core importing Features. | Blocking | `agentstudio_import_direction` |
| Fail Core importing App. | Blocking | `agentstudio_import_direction` |
| Fail Features importing sibling Features. | Blocking | `agentstudio_import_direction` |
| Fail SharedComponents importing Core, Features, or App. | Blocking | `agentstudio_import_direction` |
| Fail AtomLib importing product layers or referencing product atoms. | Blocking | `agentstudio_atomlib_is_generic` |
| Fail `DerivedValue` direct `atom(...)`, `AtomScope`, `AtomReader`, or test-registry reads. | Blocking | `agentstudio_derived_value_declared_inputs` |
| Fail same-file helper/wrapper calls from `DerivedValue` compute closures when the helper hides an atom read. | Blocking | `agentstudio_derived_value_declared_inputs` |
| Fail raw `WorktreeEnrichment` equality as an atom comparator. | Blocking | `agentstudio_worktree_enrichment_comparator` |
| Fail hot `repoEnrichmentByRepoId`, `worktreeEnrichmentByWorktreeId`, and `pullRequestCountByWorktreeId` dictionary reads outside named cold surfaces. | Blocking | `agentstudio_repo_cache_keyed_reads` |
| Print repo-cache dictionary read inventory. | Reclassified to review-only | The old script's report-only inventory is replaced by this document plus blocking rules for the hot-path violation class. Broad inventory reports were noisy and not a required CI gate. |

## Test And Fixture Proof

| Proof | Covers |
| --- | --- |
| ai-tools `scripts/verify-agentstudio-swiftlint.sh` | Builds the custom SwiftLint binary, checks `agentstudio_*` rules are registered, lints good fixtures, and verifies bad fixtures fail. |
| `ArchitectureSwiftLintRulesTests` | Verifies AgentStudio's lint wiring, pinned tool identity, fixture verifier, and legacy `.swiftlint.yml` regex custom-rule behavior through the custom runner. |
| `mise run lint` | Runs swift-format, the pinned AgentStudio SwiftLint distribution with repo `.swiftlint.yml`, and release script checks. |

## Review-Only Guidance

Some architecture guidance remains review-only because it depends on semantic
judgment rather than a reliable syntax pattern: when to extract a shared
component on second use, whether a coordinator owns domain decisions, and
whether a dictionary-shaped read is an explicitly measured cold exception.
