# AgentStudio Command Planes Precursor Implementation Plan

**Date:** 2026-06-15
**Goal id:** `2026-06-15-command-planes-precursor`
**Source spec:** `docs/superpowers/specs/2026-06-15-agentstudio-command-planes-actor-boundaries.md`
**Status:** Implemented locally; review findings addressed; awaiting PR wrap-up.

## Goal

Implement the command-planes precursor cleanup with feature parity:

- rename ambiguous command/runtime/coordinator vocabulary;
- remove terminal runtime shortcut cases from the workspace action plane;
- remove concrete terminal-runtime downcast knowledge from IPC composition or
  split it with a failing guard if current scope cannot safely absorb it;
- update architecture docs and lint/test tripwires;
- rewrite the IPC runtime lifecycle follow-up spec on the new vocabulary.

## Implementation Result

The precursor cleanup landed as a feature-parity hard cutover:

- `ActionExecutor` became `WorkspaceActionExecutor`.
- `PaneActionCommand` became `WorkspaceActionCommand`.
- `RuntimeCommand` became `PaneRuntimeCommand`.
- `CommandSpec` became `AppCommandSpec`.
- `CommandDispatcher` became `AppCommandDispatcher`.
- `PaneCoordinator` became `WorkspaceSurfaceCoordinator`.
- Terminal runtime shortcuts left `WorkspaceActionCommand` and route through
  `PaneRuntimeCommandDispatching`.
- IPC runtime composition no longer depends on
  `ActionExecutorRuntimeCommandDispatcher`.
- Terminal runtime snapshot extras now come through the terminal feature-owned
  `TerminalRuntimeSnapshotFactProviding`, not an IPC-layer concrete
  `TerminalRuntime` downcast and not the generic `PaneRuntime` contract.

Current proof:

- focused red/green command-plane gate: 6 tests passed before the broad
  cutover; only the green run was retained as a log artifact;
- focused IPC/command/runtime/coordinator gate:
  `SWIFT_TEST_TIMEOUT_SECONDS=180 mise run test -- --filter "..."`
  passed 363 tests in 22 suites after review fixes
  (`tmp/test-logs/command-planes-focused.log`);
- terminal snapshot seam focused gate:
  `SWIFT_TEST_TIMEOUT_SECONDS=180 mise run test -- --filter "AgentStudioIPCRuntimeAdapterTests|PaneRuntimeContractsTests"`
  passed 28 tests in 2 suites after moving terminal snapshot facts out of the
  generic `PaneRuntime` contract;
- WebKit serialized rename proof:
  `SWIFT_TEST_TIMEOUT_SECONDS=240 mise run test -- --filter WebKitSerializedTests/WorkspaceSurfaceBridgeFilesystemRefreshTests`
  passed 1 test in 2 suites
  (`tmp/test-logs/webkit-workspace-surface-bridge-filesystem-refresh.log`);
- architecture-linter package tests:
  `swift test --package-path Tools/AgentStudioArchitectureLint` passed 7 tests
  in 3 suites (`tmp/test-logs/architecture-lint-package-test.log`);
- `mise run format`: passed;
- `mise run lint`: passed with SwiftLint 0 violations in 1245 files,
  architecture lint OK, and release script verification passed
  (`tmp/test-logs/mise-lint.log`);
- `mise run build`: passed (`tmp/test-logs/mise-build.log`);
- full `SWIFT_TEST_TIMEOUT_SECONDS=240 mise run test`: exited 0 after the
  WebKit serialized filter was updated; `E2ESerializedTests` and `ZmxE2ETests`
  were intentionally skipped by default because their include flags were unset
  (`tmp/test-logs/full-test.log`);
- stale-name scan: clean except an intentional guard assertion checking that
  `ActionExecutorRuntimeCommandDispatcher` is absent.

Live debug proof:

- launched `Agent Studio Debug wpzc` through `mise run run-debug-observability`
  with `AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1`,
  `AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1`, and
  `AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=ipc-terminal-smoke`;
- clean debug data root:
  `~/.agentstudio-db/wpzc/runs/ipc-proof-1781577761`;
- `agentstudio-ipc identify`, `list-panes`, and `command-list` worked against
  the debug runtime metadata;
- raw JSON-RPC `pane.split`, `drawer.addPane`, and `drawer.toggle` worked
  against the debug socket;
- `terminal.status` and `terminal.send` did not pass because the new terminal
  runtime reported `runtime not ready`;
- Victoria proof for marker `debug-observability-wpzc-1781577768-95699`
  showed `ipc-terminal-smoke` was requested/dispatched and then blocked with
  `terminal_view.count=1`, `surface_reference.count=0`, `surface.count=0`,
  `valid_geometry.count=0`, and `render_proof.succeeded=false`.

The live IPC layout/query proof is valid. The terminal runtime/render proof is
not complete and should be treated as the next blocker before claiming full
headless terminal control.

Split follow-up:

- `docs/superpowers/plans/2026-06-16-agentstudio-ipc-terminal-runtime-surface-proof-followup.md`
  owns the remaining live terminal surface/runtime proof gate. The precursor
  branch keeps the command-plane cleanup and app-level IPC query/layout proof;
  the follow-up must prove `terminal.status`, `terminal.snapshot`,
  `terminal.send`, and `terminal.wait` against a ready real terminal surface.

Review reduction:

- Accepted reviewer finding: active IPC runtime lifecycle follow-up spec still
  used the old runtime dispatch chain. Fixed the flow to
  `AgentStudioIPCRuntimeAdapter -> PaneRuntimeCommandDispatching ->
  WorkspaceSurfaceCoordinator.dispatchRuntimeCommand`.
- Accepted reviewer finding: terminal snapshot facts belonged to the terminal
  feature/runtime slice, not the generic `PaneRuntime` contract. Moved the
  facts/protocol to `Features/Terminal/Runtime`, added the generic contract
  absence guard, and added the positive IPC snapshot mapping test.
- Accepted reviewer finding: proof commands used stale suite names. Updated
  plan filters to `WorkspaceActionExecutorTestsQuick` and
  `WorkspaceRuntimeDispatchNonTerminalTests`, and fixed the serialized WebKit
  runner filter to `WorkspaceSurfaceBridgeFilesystemRefreshTests`.
- Deferred blocker: live terminal surface/render proof still fails before a
  ready runtime exists. This branch proves IPC query/layout and command-plane
  architecture, not full terminal runtime control.
- Claude Opus advisory review was attempted, but the `claude --print --model
  opus` process hung and produced an empty artifact at
  `tmp/review-workflows/2026-06-15-command-planes-precursor/claude-opus-review.md`;
  it is not counted as a completed review gate.

## Non-Goals

- No new public IPC capability.
- No public `zmx.*` IPC surface.
- No broad `command.execute` command catalog.
- No generic command bus or EventBus command routing.
- No new remote/MCP transport.
- No release tag in this plan.

## Source Coverage

- Spec line count: 1085 lines.
- Spec chunks read completely: `1-220`, `221-440`, `441-660`,
  `661-880`, `881-1085`.
- Repo evidence inspected:
  - `.mise.toml`
  - `Package.swift`
  - `Sources/AgentStudio/Core/Actions/WorkspaceActionCommand.swift`
  - `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeCommand.swift`
  - `Sources/AgentStudio/App/Commands/WorkspaceActionExecutor.swift`
  - `Sources/AgentStudio/App/Commands/AppCommand.swift`
  - `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+RuntimeDispatch.swift`
  - `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  - `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCRuntimeAdapter.swift`
  - `Tests/AgentStudioTests/App/IPC/AgentStudioIPCCommandAdapterTests.swift`
  - `Tests/AgentStudioTests/App/WorkspaceActionExecutorTests.swift`
  - `Tests/AgentStudioTests/App/WorkspaceActionExecutorTests_Quick.swift`
  - `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorRuntimeDispatchTests.swift`
  - `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorRuntimeDispatchNonTerminalTests.swift`
  - `Tests/AgentStudioTests/App/AppCommandTests.swift`
  - `Tests/AgentStudioTests/Features/CommandBar/CommandBarTerminalCommandTests.swift`
  - `Tests/AgentStudioTests/App/TerminalAppOwnedShortcutPolicyTests.swift`
  - `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceShortcutTests.swift`
  - `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
  - `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`
  - `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`
  - `Tools/AgentStudioArchitectureLint/.../IPCBoundaryRules.swift`
  - `Tools/AgentStudioArchitectureLint/.../RuleInventoryTests.swift`
  - `docs/superpowers/specs/2026-06-15-agentstudio-ipc-runtime-lifecycle-followup.md`

## Current Repo Findings

1. `WorkspaceActionCommand` no longer contains terminal runtime shortcut cases:
   `scrollToBottom`, `scrollPageUp`, and `jumpToPrompt`.
2. `PaneTabViewController` already routes focused terminal shortcuts through
   `PaneRuntimeCommand.terminal(...)`, so extraction is likely a cleanup of stale
   workspace-action cases plus all live mixed-plane call sites rather than a
   new behavior path. The current mixed-plane path includes
   `ActionResolver.swift`, `ActionValidator.swift`, and
   `WorkspaceSurfaceCoordinator+ActionExecution.swift`.
3. `AgentStudioIPCRuntimeAdapter.terminalSnapshot` reads `rendererHealthy`,
   `readOnly`, and `secureInput` through `TerminalRuntimeSnapshotFactProviding`.
4. `.mise.toml` is the task file, not `mise.toml`.
5. `AppCommandSpec` and `AppCommandDispatcher` currently live in
   `AppCommand.swift`, so the plan must update names without pretending the
   file split already exists.
6. Architecture lint already has IPC boundary rules and an expected rule
   inventory. New SwiftSyntax rules must update both rule registry and tests.

## Requirements / Proof Matrix

| Requirement / claim | Owning task | Proof owner | Proof gate | Layer | Stale-proof guard | Red/green required |
| --- | --- | --- | --- | --- | --- | --- |
| R1 feature parity is preserved for command bar, shortcuts, workspace actions, runtime commands, and IPC command/UI separation. | T1-T8 | parent | targeted tests plus `mise run test` or scoped split evidence | integration/repo | current branch after implementation | yes for changed behavior guards |
| R2 `ActionExecutor` becomes `WorkspaceActionExecutor` with no long-lived alias. | T2 | parent | compile plus stale-name architecture test | unit/architecture | `rg` after rename | red/green for stale-name guard |
| R3 `PaneActionCommand` becomes `WorkspaceActionCommand`, and terminal shortcut cases leave the workspace action plane. | T1, T3 | parent | failing test first, resolver/validator tests, compile | unit/integration | source `rg` and test output | yes |
| R4 `RuntimeCommand` becomes `PaneRuntimeCommand`. | T2 | parent | compile and runtime command contract tests | unit/integration | source `rg` after rename | red/green for stale-name guard |
| R5 `CommandSpec` becomes `AppCommandSpec`. | T2 | parent | command spec contract tests and compile | unit | source `rg` after rename | red/green for stale-name guard |
| R6 `CommandDispatcher` becomes `AppCommandDispatcher`. | T2 | parent | command routing tests and compile | unit/integration | source `rg` after rename | red/green for stale-name guard |
| R7 `PaneCoordinator` becomes `WorkspaceSurfaceCoordinator`. | T2 | parent | coordinator tests and compile | integration | source `rg` after rename | red/green for stale-name guard |
| R8 command/UI/runtime/event planes remain separate and `command.execute` keeps the existing error contract. | T1, T6 | parent | `AgentStudioIPCCommandAdapterTests` plus architecture tests | unit/architecture | exact test command after implementation | yes |
| R9 IPC decode/auth stays off-main; MainActor hops are named through adapters/ports. | T7 | parent | docs + lint/test where practical | architecture/docs | source and docs `rg` | yes if lint rule added |
| R10 expensive runtime work stays behind runtime owners. | T4, T7 | parent | runtime snapshot provider tests/docs | integration/docs | current code inspection | yes for IPC snapshot seam |
| R11 IPC composition stops downcasting to `TerminalRuntime`, or gets a failing first-follow-up guard. | T4 | parent | failing test/architecture lint before implementation, then pass | integration/architecture | adapter source `rg "as\\? TerminalRuntime"` | yes |
| R12 architecture enforcement is layered and inventory is updated. | T5 | parent | `swift test --package-path Tools/AgentStudioArchitectureLint` and `mise run lint` | architecture/repo | current rule inventory | yes for new lint rule |
| R13 IPC lifecycle follow-up spec is rewritten on new vocabulary. | T8 | parent | docs `rg` for old vocabulary in active docs/spec | docs | current docs after implementation | no, docs verification enough |
| Pane-bound auth, grant, and authenticated-socket revocation stay green through the cleanup. | T0, T9 | parent | `AgentStudioIPCAuthenticationTests`, `AgentStudioIPCRegistryAuthorizationTests`, `AgentStudioAppIPCServiceTests` | security/integration | current branch after IPC adapter changes | no unless a failure appears |
| Runtime IPC dispatch does not route through `WorkspaceActionExecutor`. | T4 | parent | IPC runtime adapter tests plus source/architecture scan | integration/architecture | `rg "WorkspaceActionExecutor.*dispatchRuntime|ActionExecutorRuntimeCommandDispatcher"` after cutover | yes |
| Rename-sensitive suites start green before broad cutover. | T0 | parent | mandatory focused baseline commands or explicit blocker | unit/integration/security | captured before T2 product edits | no |

## Task Sequence

### T0. Baseline And Branch Hygiene

Actions:

- Confirm branch and dirty state.
- Record existing untracked spec and workflow-state files.
- Run a mandatory targeted baseline before T2 product edits. A baseline may be
  skipped only when the command itself is blocked by environment/tooling; record
  that blocker before editing.
  - command adapter tests;
  - runtime adapter tests;
  - concrete IPC layout adapter tests;
  - concrete IPC UI presentation adapter tests;
  - IPC authentication, authorization, and socket revocation tests;
  - app command metadata/catalog tests;
  - workspace action executor tests;
  - workspace surface runtime dispatch tests;
  - terminal command-bar, shortcut policy, Ghostty shortcut, controller, and
    runtime command tests;
  - action validator/resolver tests;
  - architecture lint tests.

Proof:

- `git status --short --branch`
- targeted `swift test` command output, or explicit environment blocker.

### T1. Add Failing Boundary Tests First

Actions:

- Add/adjust tests that fail on the current code for the semantic cleanup:
  - `WorkspaceActionCommand` must not contain terminal runtime shortcut cases;
  - terminal shortcuts route through `PaneRuntimeCommand.terminal(...)`;
  - IPC runtime snapshot must not require concrete `TerminalRuntime` downcast;
  - `command.execute` still rejects presentation ids with
    `requiresPresentation` and unknown ids with `unsupportedCommand`;
  - `command.execute` rejects non-nil `targetHandle` rather than adding target
    semantics;
  - socket-facing `command.execute` with non-nil `targetHandle` preserves the
    outward error contract;
  - stale old command-plane type names are caught outside intentional history.

Likely files:

- `Tests/AgentStudioTests/Core/PaneRuntime/Contracts/PaneRuntimeContractsTests.swift`
- `Tests/AgentStudioTests/App/PaneTabViewControllerTerminalShortcutCommandTests.swift`
- `Tests/AgentStudioTests/App/IPC/AgentStudioIPCRuntimeAdapterTests.swift`
- `Tests/AgentStudioTests/App/IPC/AgentStudioIPCCommandAdapterTests.swift`
- `Tests/AgentStudioTests/App/IPC/AgentStudioIPCLayoutAdapterTests.swift`
- `Tests/AgentStudioTests/App/IPC/AgentStudioIPCUIPresentationAdapterTests.swift`
- `Tests/AgentStudioAppIPCTests/` if new security fixtures are needed
- `Tests/AgentStudioTests/App/AppCommandTests.swift`
- `Tests/AgentStudioTests/Features/CommandBar/CommandBarTerminalCommandTests.swift`
- `Tests/AgentStudioTests/App/TerminalAppOwnedShortcutPolicyTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceShortcutTests.swift`
- `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`
- `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`
- `Tools/AgentStudioArchitectureLint/Tests/...` if a SwiftSyntax rule is added.

Proof:

- Run each new/changed test and watch it fail for the intended reason.

### T2. Hard Rename Vocabulary

Actions:

- Rename files and symbols in one hard cutover:
  - `ActionExecutor` -> `WorkspaceActionExecutor`
  - `PaneActionCommand` -> `WorkspaceActionCommand`
  - `RuntimeCommand` -> `PaneRuntimeCommand`
  - `CommandSpec` -> `AppCommandSpec`
  - `CommandDispatcher` -> `AppCommandDispatcher`
  - `PaneCoordinator` -> `WorkspaceSurfaceCoordinator`
- Update comments, log categories, helper names, test names, fixtures, and
  architecture allowlists.
- Add a responsibility inventory for the renamed coordinator. For this
  precursor, `WorkspaceSurfaceCoordinator` still owns the existing cross-surface
  orchestration bundle: pane/tab/drawer graph sequencing, view host ordering,
  runtime registry dispatch, restore/repair/undo, filesystem projection/root
  sync, startup/performance tracing, and Bridge pane surface integration.
  Future extraction of filesystem/event/tracing sub-owners is explicitly out of
  scope unless implementation reveals a compile blocker.
- Cut over `WorkspaceSurfaceCoordinator*` helper/protocol/test names unless a remaining use
  is explicitly documented as historical.
- Avoid long-lived typealiases.

Likely production files:

- `Sources/AgentStudio/App/Commands/*`
- `Sources/AgentStudio/App/Coordination/*`
- `Sources/AgentStudio/App/Panes/*`
- `Sources/AgentStudio/App/IPCComposition/*`
- `Sources/AgentStudio/Core/Actions/*`
- `Sources/AgentStudio/Core/RuntimeEventSystem/*`
- `Sources/AgentStudio/Features/*/Runtime/*`
- `Sources/AgentStudio/Features/CommandBar/*`

Proof:

- Compile targeted tests.
- `mise run test -- --filter "WorkspaceActionExecutorTests|WorkspaceActionExecutorTestsQuick"`
- `mise run test -- --filter AppCommandTests`
- `rg` for old names in production Swift; remaining hits must be intentional
  historical docs/specs only.

### T3. Extract Terminal Shortcuts From Workspace Actions

Actions:

- Remove `scrollToBottom`, `scrollPageUp`, and `jumpToPrompt` cases from
  `WorkspaceActionCommand`.
- Remove all live mixed-plane workspace-action handling for these shortcuts:
  - `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
  - `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
  - `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ActionExecution.swift`
- Preserve existing `PaneTabViewController` runtime dispatch behavior through
  `PaneRuntimeCommand.terminal(...)`.
- Update tests and docs that used these as workspace actions.

Proof:

- Red/green boundary tests from T1.
- `PaneTabViewControllerTerminalShortcutCommandTests`.
- `WorkspaceCommandResolver` and `WorkspaceCommandValidator` tests.
- Terminal parity suites for all three runtime commands:
  - `AppCommandTests`
  - `CommandBarTerminalCommandTests`
  - `TerminalAppOwnedShortcutPolicyTests`
  - `GhosttySurfaceShortcutTests`
  - `PaneTabViewControllerCommandTests`
  - `PaneTabViewControllerTerminalShortcutCommandTests`
  - `TerminalRuntimeTests`
- Source scan proving these shortcuts are absent from `WorkspaceActionCommand`
  and `WorkspaceSurfaceCoordinator` action execution.

### T4. Runtime Dispatch And Snapshot Ownership Seams

Actions:

- Remove the runtime-command forwarding seam from `WorkspaceActionExecutor`.
- Replace `ActionExecutorRuntimeCommandDispatcher` with the dedicated
  `PaneRuntimeCommandDispatching` port backed by
  `WorkspaceSurfaceCoordinator.dispatchRuntimeCommand`.
- Update `AgentStudioIPCRuntimeAdapterTests` so terminal send proves IPC runtime
  dispatch does not depend on the workspace action executor.
- Add a runtime-owned terminal snapshot facts protocol or data surface that can
  be queried through `PaneRuntime` without IPC composition downcasting to
  `TerminalRuntime`.
- Make `TerminalRuntime` provide `rendererHealthy`, `readOnly`, and
  `secureInput` facts through that seam.
- Update `AgentStudioIPCRuntimeAdapter` to map the exported facts only.
- Do not move terminal-specific snapshot knowledge sideways into another
  app-layer helper. Exported terminal snapshot facts must come from
  runtime-owned contracts or feature runtime files.
- If this cannot be completed safely in this branch, add a failing
  architecture/behavior test and split it as the first follow-up; do not leave
  the downcast undocumented.

Proof:

- Red/green IPC runtime adapter test proving terminal send uses the dedicated
  runtime dispatcher and no longer names `WorkspaceActionExecutor`.
- Red/green IPC runtime adapter test.
- `mise run test -- --filter "WorkspaceSurfaceCoordinatorRuntimeDispatchTests|WorkspaceRuntimeDispatchNonTerminalTests"`
- Source/architecture scan for
  `ActionExecutorRuntimeCommandDispatcher` and
  `WorkspaceActionExecutor.dispatchRuntimeCommand`.
- `rg -n "as\\? TerminalRuntime|as! TerminalRuntime" Sources/AgentStudio/App/IPCComposition` has no hits, unless the split follow-up is explicitly recorded with a failing guard.
- Broader app-layer source scan or architecture test proves no app-owned helper
  moved the same terminal snapshot knowledge out of IPC composition:
  `rg -n "rendererHealthy|isReadOnly|isSecureInput|TerminalRuntime" Sources/AgentStudio/App`
  must have only intentional non-snapshot references.

### T5. Architecture Lint And Architecture Tests

Actions:

- Add only accurate SwiftSyntax rules for real tripwires:
  - exact-symbol old-name guard in production Swift;
  - IPC command adapter must not reference UI presentation seams;
  - IPC runtime adapter must not downcast concrete runtime classes.
- The old-name guard must not be a broad substring ban. It must allow
  intentional survivors such as `RuntimeCommandEnvelope` unless the envelope is
  renamed in this slice.
- Classify `event_backed_runtime_wait_replay_or_subscribe` as a behavior or
  architecture-test concern for this slice, not a SwiftSyntax lint rule, because
  the adapter has allowed timeout sleeps and the explicitly excluded
  lifecycle-backed `attachReady` path.
- Account for every R12 enforcement check as one of:
  - already covered by existing architecture lint;
  - newly covered by SwiftSyntax lint;
  - covered by architecture tests;
  - review-only with rationale because a lint would be brittle.
- Prefer architecture tests over brittle lint where syntax matching would cause
  false positives.
- Update `RuleInventoryTests`, fixtures, and
  `docs/architecture/architecture_lint_inventory.md`.

Proof:

- `swift test --package-path Tools/AgentStudioArchitectureLint`
- `mise run lint`
- Good/bad architecture-lint fixtures if the exact-symbol old-name guard is a
  SwiftSyntax rule:
  - bad fixture uses an exact old type name;
  - good fixture proves `RuntimeCommandEnvelope` does not trip the rule.
- Runtime wait tests cover replay, live subscription, replay gap, and timeout;
  do not add a brittle syntax rule for event-backed waits unless a precise
  implementation becomes obvious.

### T6. Command Execute Compatibility

Actions:

- Confirm `command.execute` does not gain `targetHandle` semantics.
- Preserve:
  - open string id decoding;
  - `requiresPresentation`;
  - `unsupportedCommand`;
  - `targetHandle != nil` returns `.targetNotFound`;
  - empty/narrow headless catalog.

Proof:

- `Tests/AgentStudioTests/App/IPC/AgentStudioIPCCommandAdapterTests.swift`
  including a non-nil `targetHandle` rejection case.
- `Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceTests.swift`
  including a socket-facing `command.execute` non-nil `targetHandle` case with
  the preserved outward error contract.

### T7. Architecture Docs And Agent Guidance

Actions:

- Treat R9 as satisfied by the existing compile-time target split plus a source
  audit in this precursor unless implementation introduces a new IPC entrypoint.
  If a new IPC entrypoint appears, add a named adapter/port test or lint guard
  before continuing.
- Update durable docs to use the new vocabulary and command-plane model:
  - `AGENTS.md`
  - `docs/architecture/README.md`
  - `docs/architecture/commands_and_shortcuts.md`
  - `docs/architecture/agentstudio_ipc_architecture.md`
  - `docs/architecture/pane_runtime_architecture.md`
  - `docs/architecture/pane_runtime_eventbus_design.md`
  - `docs/architecture/component_architecture.md`
  - `docs/architecture/directory_structure.md`
- Keep progressive disclosure diagrams from the spec where they clarify the
  mental model.
- Do not preserve old names in current architecture docs except as explicit
  historical notes.

Proof:

- `rg` old-name scan across current architecture docs and `AGENTS.md`.
- Link check by inspection for touched docs.

### T8. Rewrite IPC Runtime Lifecycle Follow-Up Spec

Actions:

- Rewrite `docs/superpowers/specs/2026-06-15-agentstudio-ipc-runtime-lifecycle-followup.md`
  to depend on the new names and command-plane boundaries.
- Narrow it to pane-agent lifecycle revocation and terminal runtime fact proof.
- Carry forward the R13 authority model:
  - friendly ordinals are convenience references;
  - canonical UUID handles are durable authority targets;
  - pane-bound principals and grants are pane-lifetime, not socket-lifetime;
  - revocation semantics remain explicit.
- Carry forward secret-bearing runtime-output scope boundaries:
  - no raw terminal output/readback API in this precursor or follow-up rewrite;
  - no public `zmx.*` IPC surface;
  - terminal input and terminal output/readback remain separate privileges.

Proof:

- `rg` for old names in the follow-up spec.
- targeted `rg` for `ordinal`, `UUID`, `pane-bound`, `revocation`, and the new
  command-plane type names in the rewritten follow-up spec.
- targeted `rg` for `readback`, `output`, `zmx`, and privilege-split language
  in the rewritten follow-up spec.
- Plan/spec review if the rewrite changes implementation scope materially.

### T9. Full Verification And Review

Actions:

- Run targeted tests after each slice.
- Run full repo gates after the final implementation/doc sync.
- Run implementation review swarm before PR/wrap-up.

Required commands unless split/replanned:

- Targeted Swift tests for changed command/runtime/IPC slices.
- `swift test --package-path Tools/AgentStudioArchitectureLint`
- `mise run lint`
- `mise run test`
- `mise run build`

Manual/debug proof:

- Required only if this branch changes runnable IPC behavior beyond naming and
  adapter internals. If required, use the repo debug observability path and
  prove live control with app identity and command results.

## Write Surfaces

Expected:

- `Sources/AgentStudio/App/Commands/`
- `Sources/AgentStudio/App/Coordination/`
- `Sources/AgentStudio/App/Panes/`
- `Sources/AgentStudio/App/IPCComposition/`
- `Sources/AgentStudio/Core/Actions/`
- `Sources/AgentStudio/Core/RuntimeEventSystem/`
- `Sources/AgentStudio/Features/*/Runtime/`
- `Tests/AgentStudioTests/`
- `Tools/AgentStudioArchitectureLint/`
- `AGENTS.md`
- `docs/architecture/`
- `docs/superpowers/specs/`

Do not touch:

- public zmx IPC;
- release scripts except if lint reveals a direct docs/reference break;
- unrelated BridgeWeb implementation;
- auth behavior beyond preserving existing command-plane/IPC tests.

## Validation Gates

Baseline/targeted:

```bash
mise run test -- --filter AgentStudioIPCCommandAdapterTests
mise run test -- --filter AgentStudioIPCRuntimeAdapterTests
mise run test -- --filter AgentStudioIPCLayoutAdapterTests
mise run test -- --filter AgentStudioIPCUIPresentationAdapterTests
mise run test -- --filter AgentStudioIPCAuthenticationTests
mise run test -- --filter AgentStudioIPCRegistryAuthorizationTests
mise run test -- --filter AgentStudioAppIPCServiceTests
mise run test -- --filter AppCommandTests
mise run test -- --filter "WorkspaceActionExecutorTests|WorkspaceActionExecutorTestsQuick"
mise run test -- --filter "WorkspaceSurfaceCoordinatorRuntimeDispatchTests|WorkspaceRuntimeDispatchNonTerminalTests"
mise run test -- --filter "AppCommandTests|CommandBarTerminalCommandTests|TerminalAppOwnedShortcutPolicyTests|GhosttySurfaceShortcutTests|PaneTabViewControllerCommandTests|PaneTabViewControllerTerminalShortcutCommandTests|TerminalRuntimeTests"
mise run test -- --filter PaneRuntimeContractsTests
mise run test -- --filter PaneTabViewControllerTerminalShortcutCommandTests
mise run test -- --filter WorkspaceCommandValidatorTests
mise run test -- --filter WorkspaceCommandResolverTests
```

Architecture:

```bash
swift test --package-path Tools/AgentStudioArchitectureLint
mise run test -- --filter CoordinationPlaneArchitectureTests
```

Repo:

```bash
mise run lint
mise run test
mise run build
```

If a repo-wide gate fails outside this scope, stop changed-code edits, report the
unrelated blocker with evidence, and keep changed-surface proof separate.

## Risks And Recovery

- Broad rename risk: many files and tests change. Recovery is to split the hard
  rename from semantic cleanup only if compile/test proof becomes too large.
- Merge risk: command/coordinator files are active areas. Recovery is to commit
  the plan and use narrow mechanical patches with frequent targeted tests.
- Architecture lint false positives: add tests/fixtures first; demote to
  architecture tests if SwiftSyntax matching becomes brittle.
- Terminal snapshot seam risk: if the seam wants a larger runtime API redesign,
  split it with a failing first-follow-up guard rather than smuggling a downcast
  forward.

## Split / Replan Triggers

- `WorkspaceSurfaceCoordinator` rename causes cross-module churn that cannot be
  compiled and tested in one branch.
- The runtime snapshot provider requires changing runtime lifecycle semantics,
  not just exported snapshot facts.
- Architecture lint cannot express a rule without false positives.
- `mise run test` exposes unrelated infra/tooling failures outside touched
  command/runtime/IPC slices.

## Plan Review Questions

1. Should the `WorkspaceSurfaceCoordinator` hard rename happen in the same
   changeset as the command/runtime renames, or should it be split if compile
   churn dominates the proof loop?
2. Is the terminal snapshot ownership seam small enough for this precursor, or
   should the plan intentionally require a failing guard and first follow-up?
3. Should old-name guards be SwiftSyntax lint rules, architecture tests, or both?

## Phase Footer

phase_result: complete
evidence: `docs/superpowers/plans/2026-06-15-agentstudio-command-planes-precursor-implementation-plan.md`
recommended_next_workflow: `shravan-dev-workflow:plan-review-swarm`
recommended_transition_reason: The implementation plan now maps the precursor spec to ordered tasks, write surfaces, proof gates, and split triggers.
