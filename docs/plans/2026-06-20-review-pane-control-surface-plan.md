# Review Pane Control Surface Implementation Plan

Date: 2026-06-20
Source spec: `docs/specs/2026-06-20-review-pane-control-surface.md`

## Goal

Implement the Review Pane control surface so the human UI, command specs, typed
tooltips, IPC discovery, and programmatic pane control describe the same product
actions.

This plan does not execute the work. It sizes the implementation into provable
slices that can be parallelized after the branch is reconciled with `origin/main`.

## Source Coverage

- Spec file: `docs/specs/2026-06-20-review-pane-control-surface.md`
- Spec lines: 330, read in full.
- Incoming main dependency: PR #188 squash commit
  `238817488f118dfb47a95f65b4b060d9f651dafe`.
- Current branch evidence read:
  - `Sources/AgentStudio/App/Commands/AppCommand.swift`
  - `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
  - `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCCommandAdapter.swift`
  - `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCBridgeAdapter.swift`
  - `Sources/AgentStudio/Core/Models/Pane.swift`
  - `Sources/AgentStudio/Core/Models/PaneContent.swift`
  - `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeTypes.swift`
  - `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgeReviewOpening.swift`
  - `Sources/AgentStudio/Features/Bridge/State/BridgePaneState.swift`
  - `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift`
  - `Sources/AgentStudioProgrammaticControl/IPCBridgeContracts.swift`
  - `Sources/AgentStudioProgrammaticControl/IPCCommandContracts.swift`
  - `BridgeWeb/src/app/bridge-app-control.ts`
  - `BridgeWeb/src/app/bridge-app.tsx`
  - `BridgeWeb/src/review-viewer/models/review-projection-models.ts`
  - `BridgeWeb/src/review-viewer/navigation/review-projection-request.ts`
  - `BridgeWeb/src/review-viewer/navigation/review-projection.ts`
  - `BridgeWeb/src/review-viewer/state/review-viewer-store.ts`
  - `BridgeWeb/src/review-viewer/trees/bridge-trees-controller.ts`
- `origin/main` evidence read:
  - `docs/architecture/commands_and_shortcuts.md`
  - `docs/guides/style_guide.md`
  - `docs/superpowers/specs/2026-06-19-typed-tooltip-source-contract.md`
  - `Sources/AgentStudio/App/Commands/AppCommand+DisplayDescriptor.swift`
  - `Sources/AgentStudio/App/Commands/AppCommand+IPCProjection.swift`
  - `Sources/AgentStudio/Core/Actions/ControlTooltipSource.swift`
  - `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCCommandAdapter.swift`

## Non-Goals

- No patch apply, approve/reject, or source mutation.
- No raw WebKit automation endpoint.
- No file-content regex search in this slice.
- No broad persistence rename from `bridgePanel` / `.diff` to `.review` unless
  a later migration plan sizes it.
- No new observability stack ownership in this repo.

## Required Order

1. Commit this spec/plan checkpoint.
2. Merge `origin/main` into this branch after the checkpoint.
3. Resolve conflicts by preserving the PR #188 typed tooltip source contract.
4. Re-read the merged command, tooltip, IPC, and Bridge files before product
   implementation.
5. Execute tasks below in dependency order.

Do not rebase or merge the old `control-tooltip-source-contract` branch. PR
#188 was squash-merged; `origin/main` is the source of truth.

## Requirements And Proof Matrix

| Requirement | Task | Proof owner | Proof gate | Layer | Stale-proof guard | Red/green |
| --- | --- | --- | --- | --- | --- | --- |
| Native Review opens useful branch diff by default | 1 | Swift owner | focused `OpenBridgeReview` source tests + IPC/native smoke | unit + smoke | clean worktree with branch changes against default branch must not return 0-file unstaged package | yes |
| Review commands use PR #188 display/tooltip model | 2 | Swift UI owner | command spec tests + tooltip architecture lint | unit + lint | no raw `.help` / AppKit `toolTip` in dense Review controls | yes |
| Command list exposes Review discovery without abusing display DTOs | 2 | IPC owner | IPC command-list contract tests | integration | `IPCCommandListEntry` remains projection only | yes |
| Pane-local actions use typed IPC/page-control, not command-bar automation | 3 | IPC owner | Bridge IPC service tests | integration | non-Review target fails typed unsupported-target | yes |
| Search is typed and regex-capable | 4 | BridgeWeb owner | Zod/unit + browser integration | unit + browser integration | invalid regex returns rejected result/probe | yes |
| Search composes after projection filters without reprojecting per keystroke | 4 | BridgeWeb owner | browser test checking projection request count | browser integration | large fixture search does not enqueue projection churn | yes |
| Filters are facets, modes are Review/GUIDED/Plans | 5 | BridgeWeb UX owner | shell/component tests + browser screenshot proof | unit + browser visual | UI exposes one mode selector and one filter facet control | yes |
| Large real worktree remains performant | 6 | Perf owner | benchmark + dev server + native Victoria proof | benchmark + smoke | PR #180 or current worktree diff size recorded in proof | no, unless regression is found |
| All public TS variants use Zod discriminated unions | 4 | BridgeWeb owner | `pnpm --dir BridgeWeb run check` + type tests | unit + typecheck | no manual `Omit` of schema-derived variants | yes |
| SharedComponents remain render-only | 2 | Swift owner | architecture lint | lint | no imports of command/source/IPC semantics from SharedComponents | yes |

## Task 0: Merge Main And Reconcile Source Contracts

Write surfaces:

- Git merge resolution only.
- No product behavior changes unless required to resolve conflicts.

Steps:

1. Merge `origin/main`.
2. Reconcile conflicts in:
   - `docs/architecture/commands_and_shortcuts.md`
   - `Sources/AgentStudio/App/Commands/*`
   - `Sources/AgentStudio/Core/Actions/*`
   - `Sources/AgentStudio/Infrastructure/*Tooltip*`
   - `Sources/AgentStudio/App/IPCComposition/*`
3. Preserve PR #188's source contract:
   - `AppCommandSpec -> CommandDisplayDescriptor -> ControlTooltipSource`
   - `LocalActionSpec.actionSpec -> CommandDisplayDescriptor`
   - `AppCommandSpec.ipcExposure -> IPCCommandListEntry`
   - SharedComponents render only `ControlTooltipRenderValue`.
4. Run conflict proof:
   - `git diff --check`
   - focused command/tooltip tests if touched
   - `mise run lint` if architecture-lint rules are touched

Split trigger:

- If merge conflicts require changing product behavior outside Review/Bridge or
  tooltip source contract files, stop and replan.

## Task 1: Default Review Compare Source

Problem:

`openBridgeReview` currently creates `.workspace(..., baseline: .unstaged)`.
Clean branches with changes against default branch open as an empty Review Pane.

Write surfaces:

- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgeReviewOpening.swift`
- Review source provider/factory files as needed.
- Focused tests under `Tests/AgentStudioTests/App` or `Tests/AgentStudioTests/Features/Bridge`.

Implementation shape:

1. Introduce a Review compare-source resolver.
2. Resolve default branch comparison in this order:
   - configured repo default branch if available
   - `origin/main`
   - `main`
   - `origin/master`
   - `master`
   - fallback to workspace unstaged only when no branch base exists
3. Keep staged/unstaged as explicit selectable compare targets.
4. Ensure IPC `openReview` can accept compare target parameters once Task 3 adds
   the contract.

Proof:

- Unit test clean branch with changes against default branch creates non-empty
  branch/default compare source.
- Unit test fallback still supports unstaged workspace diff.
- Native IPC smoke after Task 3 proves `open -> getPackage` returns changed
  files on this branch.

## Task 2: Review Command Specs And Tooltip Sources

Write surfaces:

- `Sources/AgentStudio/App/Commands/AppCommand.swift`
- `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- `Sources/AgentStudio/App/Commands/AppCommand+DisplayDescriptor.swift` if a
  Review-specific display projection is needed.
- `Sources/AgentStudio/App/Commands/AppCommand+IPCProjection.swift` only for
  public command-list metadata.
- Review UI wrappers, not SharedComponents, for source resolution.

Implementation shape:

1. Audit the existing `Review` command from the worktree action path.
2. Add or refine Review-scoped command specs for:
   - Open Review
   - Refresh Review
   - Search Review Files
   - Filter Review Files
   - Select/Reveal Review File
   - Set Review Mode
   - Set Compare Target
3. For commands that require explicit pane/worktree parameters, expose
   `ipcExposure` as parameter-required or presentation-required until a typed IPC
   method exists.
4. Dense controls must resolve `ControlTooltipRenderValue` from command/local
   action sources before rendering.
5. SharedComponents receive only render values and closures.

Proof:

- `AppCommandSpecContractTests` or new Review command spec tests.
- `AgentStudioIPCCommandAdapterTests` proves Review commands appear in
  `command.list` with correct exposure and do not execute headlessly without
  explicit support.
- `mise run lint` catches tooltip-source violations.

## Task 3: Typed Review IPC Surface

Write surfaces:

- `Sources/AgentStudioProgrammaticControl/IPCBridgeContracts.swift`
- `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCBridgeAdapter.swift`
- `Sources/AgentStudioAppIPC/*Bridge*`
- `Sources/AgentStudioIPCClient*`
- Bridge IPC tests.

Implementation shape:

1. Decide final namespace:
   - preferred public product namespace: `review.*`
   - acceptable transition: keep current `bridge.*` methods and add Review
     aliases only if hard-cut risk is too high.
2. Add typed params/results for:
   - open review with compare target
   - set compare target
   - set review mode
   - set filters
   - set search query
   - select/reveal file
   - refresh
3. Preserve pane-handle authorization and unsupported-target errors.
4. Do not expose raw WebKit, raw JS, raw paths beyond existing approved handles,
   or generic event-bus command routing.

Proof:

- IPC contract tests for decoding/encoding.
- Authorization tests for wrong pane, missing pane, and privilege failures.
- Service tests for open, filter, search, select/reveal, refresh.
- CLI argument tests for new commands if CLI flags are added.

## Task 4: Typed Search Query And Regex

Write surfaces:

- `BridgeWeb/src/review-viewer/models/review-projection-models.ts`
- `BridgeWeb/src/app/bridge-app-control.ts`
- `BridgeWeb/src/app/bridge-app.tsx`
- `BridgeWeb/src/review-viewer/state/review-viewer-store.ts`
- `BridgeWeb/src/review-viewer/trees/bridge-trees-panel.tsx`
- `BridgeWeb/src/review-viewer/test-support/*`

Implementation shape:

1. Replace raw `treeSearchText: string` with typed search state:
   - `null`
   - plain text query
   - regex query
2. Keep plain text as the default search UI.
3. Support explicit regex entry through one canonical internal representation.
4. Match regex against `candidatePaths` by default so renamed/deleted paths can
   be found.
5. Keep regex path search tree-local in this phase.
6. Return typed rejected probe state for invalid regex.
7. Keep search out of projection request unless a later content-search or
   dataset-search plan changes that boundary.

Proof:

- Zod schema/unit tests for query variants.
- Store unit tests for pure state transitions.
- App-control integration tests for accepted/rejected search.
- Browser integration:
  - plain text expands matches
  - regex expands matches
  - invalid regex shows rejected/visible state
  - search does not add projection requests per keystroke
  - added files remain visible and expandable

## Task 5: Review Mode And Filter Facet UI

Write surfaces:

- `BridgeWeb/src/review-viewer/shell/*`
- `BridgeWeb/src/review-viewer/chrome/*`
- `BridgeWeb/src/review-viewer/trees/*`
- shadcn/Base UI wrappers already introduced in BridgeWeb.

Implementation shape:

1. Replace the ambiguous top button group with:
   - left: Review mode selector (`Review`, `Guided`, `Plans`)
   - right: search, filter facets, compare source
2. Filter button opens one popover with columns:
   - Git
   - Type
   - Scope
3. Search is visible as the primary fast filter/navigation control and may open
   a second row when active.
4. Keep the right-side file tree.
5. Use shadcn/base-mira components, Base UI primitives, Lucide icons, Tailwind
   v4, and Catppuccin Mocha/Pierre theme variables. Do not hand-roll a parallel
   design system.

Proof:

- Component tests for mode and filter state.
- Browser visual proof comparing dev server against DiffsHub target for the same
  PR/worktree class.
- Accessibility/keyboard tests for filter popover and search focus.

## Task 6: Performance, Observability, And Native Proof

Write surfaces:

- Benchmark scripts only if gaps exist.
- Existing Victoria proof scripts if Review-specific markers need extension.
- No new observability stack ownership.

Implementation shape:

1. Use dev server with real worktree/PR fixture for the fast loop.
2. Use browser tests for interaction proof:
   - file click scrolls to sticky header
   - collapse/expand does not jump unexpectedly
   - search/filter remains responsive
3. Use native AgentStudio debug app for outer-loop proof.
4. Capture Victoria metrics/logs for:
   - package push
   - projection worker
   - tree search/filter
   - content fetch
   - file select/reveal
5. Record diff size in proof artifacts.

Proof:

- `pnpm --dir BridgeWeb run check`
- BridgeWeb unit/integration/browser suites touched by Tasks 4-5
- `pnpm --dir BridgeWeb run benchmark:viewer`
- `pnpm --dir BridgeWeb run test:benchmark:browser`
- `mise run test -- --filter Bridge`
- `mise run lint`
- `mise run observability:up`
- debug app launch + Review IPC smoke + Victoria marker verification

## Parallelization

Safe parallel lanes after Task 0:

- Lane A: Task 1 default compare source and Swift tests.
- Lane B: Task 4 typed search query and BridgeWeb tests.
- Lane C: Task 5 UI facet/mode polish on top of current dev server.
- Lane D: Task 3 IPC contracts after Task 1's compare-source model is known.
- Lane E: Task 6 perf proof after B/C have stable controls.

Task 2 crosses Swift command specs and tooltip source rules and should be
integrated carefully after Task 0. It can run beside Task 4 only if ownership is
limited to Swift command/UI files.

## Risks

- Squash-merged PR #188 means old branch ancestry is historical only. Resolve
  conflicts against `origin/main`.
- `PaneContentType.review` exists but is not currently used by the review pane.
  Renaming persistence/runtime identity is a separate migration unless scoped.
- Adding regex to projection would regress large-diff responsiveness by
  reprojecting on keystrokes.
- Overusing `command.execute` would violate the command/UI presentation boundary.
- Tooltip-source lint will reject raw dense-control tooltip strings after merge.

## Open Questions Before Implementation

1. Use hard `review.*` IPC method names now, or keep `bridge.*` with Review
   aliases for one internal transition?
2. Which regex entry affordance ships first: toggle, `regex:` prefix,
   `/pattern/flags`, or all three feeding one canonical query?
3. Does `.review` pane content identity migrate in this PR, or after control
   surface/search/IPC stabilize?

## Recommended Next Step

Run `plan-review-swarm` on this plan after the branch is merged with
`origin/main`, then execute with implementation lanes.
