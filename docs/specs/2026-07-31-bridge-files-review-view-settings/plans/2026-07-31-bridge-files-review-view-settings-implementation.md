# Bridge Files and Review View Settings Implementation Plan

Date: 2026-07-31

Sources:

- `../2026-07-31-bridge-files-review-view-settings-requirements.md`
- `../2026-07-31-bridge-files-review-view-settings-program-design.md`

## Goal

Implement UR-01–UR-25 as one focused hard cutover: consistent Filters, View
Settings, and Search in Files and Review; truthful registered-worktree source
lifecycle; native context-menu suppression; and a deliberate Reload Bridge Web
View command. Preserve the mounted Bridge pane, controller, `WebPage`, Swift
filesystem/Git authority, and existing product/session architecture.

## Scope guard

- Files and Review share visual and interaction primitives, not mutable state.
- Native Swift remains the only packaged registered-worktree, filesystem, Git,
  classification, and publication authority.
- Resolve the deepest registered worktree containing the current pane CWD.
- Retarget the existing mounted controller through one stable target binding;
  do not recreate the pane, controller, host, or `WebPage`.
- Reload means ordinary WebKit Reload on that existing `WebPage`.
- Use the existing shadcn-style BridgeWeb primitives and typed app command
  pipeline.
- Hard-cut schemas, DTOs, listeners, fixtures, and read-back together. Do not
  keep a legacy filter or fixed-source compatibility path.
- Preserve the unrelated Mindle sidecar and unrelated worktree changes.

Non-goals: classifier redesign; Files Git/binary/large filters; content search;
match navigation; comments, notes, editing, patches, or review workflow; themes
or durable settings; TypeScript production Git/filesystem access; a new source
identity; shared mutable Files/Review state; controller/host replacement;
custom Reload lifecycle or retry UI; native Bridge actions in the context menu;
new recovery policy; unrelated refactors.

## Current owners and likely write surfaces

The executor must re-anchor these paths before each slice; exact files may move
on `origin/main`, but ownership must not.

Native source and lifecycle:

- `Sources/AgentStudio/Core/State/MainActor/Atoms/RepositoryTopologyAtom.swift`
- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgeViewLifecycle.swift`
- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgeReviewOpening.swift`
- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+FilesystemSource.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+Bootstrap.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+DiffCommands.swift`
- `Sources/AgentStudio/Features/Bridge/Transport/BridgePaneProductSessionOwner.swift`
- `Sources/AgentStudio/Features/Bridge/Transport/BridgePaneProductMetadataCoordinator*.swift`
- File/Review source, cache, construction binder, and publication owners under
  `Sources/AgentStudio/Features/Bridge/`.

Native commands and host:

- `Sources/AgentStudio/Core/Actions/Commands/`
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- `Sources/AgentStudio/Features/Bridge/Views/BridgePaneContentView.swift`
- `Sources/AgentStudioProgrammaticControl/IPCBridgeContracts.swift`

BridgeWeb controls and projections:

- `BridgeWeb/src/app/bridge-app-control.ts`
- `BridgeWeb/src/app/bridge-app-file-viewer-mode.tsx`
- `BridgeWeb/src/app/bridge-app-review-viewer-mode.tsx`
- `BridgeWeb/src/app/bridge-viewer-filter-menu.tsx`
- `BridgeWeb/src/app/bridge-viewer-search-field.tsx`
- `BridgeWeb/src/app/bridge-viewer-search-control.tsx`
- `BridgeWeb/src/app/use-bridge-viewer-toolbar-shortcuts.ts`
- `BridgeWeb/src/file-viewer/state/bridge-file-viewer-store.ts`
- `BridgeWeb/src/file-viewer/use-bridge-file-viewer-control-event-listeners.ts`
- `BridgeWeb/src/app/use-bridge-review-control-event-listeners.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-file-metadata-projection.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-display-projection.ts`
- `BridgeWeb/src/core/comm-worker/bridge-worker-file-query-contracts.ts`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-options.ts`
- Files and Review shell/navigation/CodeView owners beneath their feature
  directories.

## Requirements and proof matrix

| Requirement | Owning slice | Proof modality and layer | Evidence source | Freshness guard | Red/green | Size fit |
| --- | --- | --- | --- | --- | --- | --- |
| UR-01–UR-03 separate, consistent controls | 1–3 | pure/component + browser visual + packaged interaction | shared primitives, Files/Review browser suites, packaged journey | current BridgeWeb bundle and current debug PID | yes | each control lands in its behavior slice |
| UR-04–UR-08 truthful Filters | 1 | unit algebra + contract integration + semantic read-back + packaged registered-worktree UI | filter reducer/schema tests, Swift classifier fixtures, IPC tests, packaged journey | fixture parity and current worktree ID | yes | one hard-cut contract slice |
| UR-09–UR-12 View Settings | 2 | pure option mapping + mounted renderer integration + visual/manual continuity | CodeView option tests, browser integration, packaged selection/source observation | current Pierre API and mounted owner identity | yes | isolated from source lifecycle |
| UR-13–UR-18 Search/focus/shortcuts | 3 | pure state machine + worker boundary + browser focus + packaged key delivery | search policy/store/listener tests, worker tests, packaged WKWebView | same maximum at all ingress; current active pane/PID | yes | local state first, packaged proof later |
| UR-19–UR-20 CWD source authority | 4 | Swift unit + native A→B/null integration + packaged initial registered-source journey | topology/coordinator/controller tests and packaged real worktree | canonical paths and current registered IDs | yes | split binding mechanics from terminal journey if needed |
| UR-21–UR-22 lifecycle/concurrency truth | 4 | actor/worker interleaving + teardown integration + packaged lifecycle | binding/session/coordinator/projection tests and live journey | epoch/generation captured from current run | yes | substeps 4A–4D each have a focused gate |
| UR-23 empty native context menu | 5 | Swift host inspection + packaged right-click interaction | host composition test and PID-targeted Peekaboo/manual proof | current installed WebKit and packaged bundle | yes | tiny native host change; failure reopens design |
| UR-24 explicit Reload | 5 | command routing/controller invocation + packaged command execution | command tests, bootstrap/session tests, command read-back, live UI | current pane/controller/page identity | yes | no custom lifecycle |
| UR-25 read-only and authority boundaries | all + 6 | architecture/static checks + integrated packaged smoke | source scans, architecture lint, final diff, packaged journey | final head SHA and current bundle | no separate waiver; behavior rows already red/green | terminal integration only |

No row may be declared proven by Vite fixtures alone when it requires Swift
authority, AppKit key routing, WKWebView context-menu behavior, or the packaged
product path.

## Security and reliability context

Assets and privileges: registered-worktree filesystem/Git authority, native
product publication, pane-local source identity, WebKit command execution, and
authenticated semantic control.

Entry points and untrusted input: visible Filter/Search controls, semantic IPC
Filter/Search candidates, pane CWD changes, asynchronous native File/Review
results, page Reload, and pane teardown.

Trust boundaries and invariants:

- only native topology containment selects packaged source authority;
- strict complete-candidate schemas admit Filter/Search mutations before state
  changes;
- target epoch plus existing generation/identity checks reject stale work;
- metadata coordination remains the sole subscription lifecycle owner;
- no raw path, query, regex, file content, or provider error enters telemetry;
  and
- Reload cannot refresh native authority, replace the host, or reinstall a
  revoked target.

Security non-goals: new authorization, new filesystem reach, content mutation,
network behavior, or a general security audit.

## Slice 0 — Baseline and proof harness readiness

Requirements: prerequisite only.

Work:

1. Confirm clean scoped branch state and preserve the Mindle sidecar.
2. Run `mise run setup`; do not use local vendors.
3. Run the narrow existing BridgeWeb and Swift suites that each later slice
   extends, recording current failures separately from scoped failures.
4. Dry-run or inspect the packaged journey runner/verifier and confirm it can
   address a worktree-isolated debug app without taking foreground focus.
5. Record exact current source owners and test commands in the execution log.

Gate: no unexplained baseline failure in a suite that will be used as a proof
gate. An unrelated baseline failure is reported and scoped; it does not
authorize changes outside this plan.

## Slice 1 — Hard-cut Filter contract and truthful projections

Requirements: UR-01–UR-08.

Behavior:

- Files exposes All plus its supported exclusive native categories only.
- Review exposes Git status, one exclusive category, and independent Binary and
  Large visibility gates.
- Visible and semantic controls submit one surface-discriminated candidate.
- Invalid or unsupported candidates change nothing.
- A projection change clears selection/content demand only when the selected
  item becomes ineligible; it never auto-selects a replacement.

TDD and work:

1. RED: add reducer/schema tests for Files/Review candidate inventories,
   exclusive classifier counterexamples, independent Review gates, invalid
   cross-surface payloads, atomic rejection, keyboard-only menu operation and
   dismissal, accessible names/states, and focus fallback when filtering makes
   the focused or selected row ineligible.
2. Hard-cut Swift IPC DTOs, BridgeWeb schemas, probes, listeners, fixtures, and
   read-back from the legacy combined `fileClassFilter` model to the complete
   discriminated candidate.
3. Put mutation in one surface-local action per surface. Visible menus and
   programmatic ingress call the same action.
4. Extend the existing shared shadcn dropdown primitives only for mechanics
   that are identical; keep Files and Review values in their local owners.
5. Reconcile selection after accepted projection changes and preserve every
   state field on rejection.
6. GREEN: run pure/contract tests, Files and Review browser interaction tests,
   Swift IPC contract/service tests, and fixture parity.

Checkpoint gate: both surfaces remain usable under the new schema with no
legacy decode/write path. Inspect the diff for a shared mutable store or
TypeScript classifier authority.

Split trigger: if native products do not contain a fact required by the
accepted filter vocabulary, return to Program Design; do not infer it in React.

## Slice 2 — View Settings on mounted Files and Review renderers

Requirements: UR-01–UR-03 and UR-09–UR-12.

Behavior:

- Files owns Line Numbers and Word Wrap.
- Review owns Line Numbers, Word Wrap, Change Backgrounds, split/unified
  layout, and visible Bars/Symbols/None indicators. The internal Pierre mapping
  remains `bars | classic | none`.
- Settings live for the browser page session, remain separate by surface, and
  retain across source target changes.
- Reset derives from current compatibility defaults.
- An option change updates the mounted renderer without source refresh,
  selection mutation, or owner remount.

TDD and work:

1. RED: add pure option-derivation tests for every setting and reset default,
   visible labels/accessibility names, two-pane and cross-surface state
   isolation, plus mounted CodeView observation tests for identity/selection
   continuity.
2. Add surface-local settings state and immutable Pierre option derivation.
3. Compose gear dropdowns through the owned shared menu primitives at the same
   visual scale as Filters.
4. Apply options to the existing mounted CodeView owner.
5. GREEN: run option tests, Files/Review component suites, browser visual tests,
   and mounted renderer integration.

Checkpoint gate: toggling settings changes only renderer options. Source,
generation, selection, and product-session identities remain stable.

Split trigger: if Pierre requires owner remount rather than its current
`setOptions` path, stop as a design break.

## Slice 3 — Search lifecycle, focus, shortcuts, and semantic ingress

Requirements: UR-13–UR-18.

Behavior:

- `⌘⇧F` toggles Search for the active Files or Review surface; `⌘⌥F` opens
  Filters with arrow navigation.
- Search open/focus/select, Clear-or-close, foreground Escape, trigger close,
  and focus restoration follow one controlled mechanic.
- Files Search filters paths and reconciles selection. Review Search is
  navigation-only and does not mutate selection or demand.
- Invalid regex preserves the last accepted projection while showing the
  entered error. Oversized input is rejected before mutation at every ingress.

TDD and work:

1. RED: encode each surface state machine, invalid-regex retention, empty
   close, blur persistence, focus fallback, 4,096/4,097 UTF-16-unit boundaries,
   non-BMP boundary examples, semantic/visible ingress parity, and a polite
   accessible announcement for invalid or oversized input without exposing raw
   query text.
2. Extract one pure Search admission policy and keep the worker maximum as a
   matching defensive schema.
3. Make the shared Search field controlled. Surface owners retain entered and
   accepted criteria, error/mode, open state, and semantic focus-return
   identity.
4. Route shortcuts through the existing active-Bridge/surface owner; do not add
   global DOM shortcut ownership that bypasses App command rules.
5. Ensure ordinary close clears query/error but retains mode, while
   different/null target and page Reload restore text mode.
6. GREEN: run pure state, worker query, control listener, browser focus, and
   typed shortcut tests.

Checkpoint gate: all programmatic and visible mutation paths share admission;
no invalid/oversized input briefly appears in accepted state.

Split trigger: if AppKit/WKWebView consumes a required key equivalent before
the existing Bridge routing seam, stop and re-anchor command ownership rather
than adding a parallel shortcut listener.

## Slice 4 — CWD-first source retargeting and truthful lifecycle

Requirements: UR-19–UR-22.

This is the highest-risk slice. Execute its substeps serially because they share
the controller, session, and product publication boundary.

### 4A — Canonical target edge

1. RED: topology/coordinator tests for deepest registered CWD containment,
   nested worktrees, no registered containing worktree, opening, restoration,
   and CWD changes.
2. Route every Bridge target decision through
   `RepositoryTopologyAtom.repoAndWorktree(containing:)` from current CWD.
3. Remove identity-first, manual-scan, and sole-worktree fallback behavior from
   this Bridge path.
4. Add the controller entry point for one complete optional target snapshot.

Gate: all initial/replayed/changed CWD paths reach the same mounted controller;
no surface recreation occurs.

### 4B — Stable binding and whole-target rebind

1. RED: tests for idempotent same target, W→X, W→null, W→X→Y,
   session rotation while sealed/open, and stale acknowledgement rejection.
2. Introduce one stable source-target binding owned by the controller. It holds
   a complete target installation or tombstone and private target epoch.
3. Supply stable façades to construction-bound File/Review consumers. Build a
   complete inert successor, revoke/seal predecessor admission, then install
   and open only after the product-session target edge is acknowledged.
4. Extend `BridgePaneProductSessionOwner` with one whole-target rebind. Retire
   File/Review subscriptions, clear one-shot File discovery, project the target
   edge to both surfaces, and replay through the existing metadata coordinator.
5. Keep the metadata coordinator as the sole subscription registry.
6. Create and complete a target-sensitive call-site cutover ledger. Filesystem
   and status invalidation, initial/retry Review loading, IPC refresh, repo
   selection, endpoint selection, and baseline selection must capture the
   binding snapshot/epoch. After installation, none may use
   `runtime.metadata` or immutable `bridgePaneState.source` as current target
   authority.

Gate: a new target's `worktreeId` is visible before Loading; old target work
cannot cross the binding façade after revocation.

### 4C — Product projection and surface reset

1. RED: worker/display tests for same-W Refreshing/Stale retention, complete
   candidate acceptance, logical-identity selection retention across same-W
   rename/refresh, different-worktree matching paths still clearing selection,
   X/null clearing before Loading, inactive-surface reset and disabled
   source-dependent controls, authority loss closing any open Filters/Search
   transient and returning focus to the active surface root, edits during X
   Loading surviving X acceptance, and separate source, projection,
   validation, and content lanes.
2. Project `targetWorktreeId` on Files and Review lifecycle payloads.
3. Give Files separate accepted and candidate generation slots so progressive
   same-W work cannot clear or partially replace the accepted tree.
4. Keep Review's transactional publication boundary.
5. Reset Filter/Search/selection/content/demand once at different/null target
   edge; retain View Settings. Never repeat reset at product acceptance.

Gate: W content cannot reappear after X/null edge, and same-W failed refresh
leaves the predecessor truthfully Stale/Refreshing.

Truth-table gate: cover Loading, Ready, Refreshing, Stale, Unavailable, Failed,
empty source, filter no-match, Search no-match, and selected-content unavailable
without collapsing source, projection, validation, or content state. Prove
cancellation is non-terminal and every displayed reason is bounded/scrubbed.

### 4D — Drain, teardown, and overlap proof

1. RED: tests for late File `sourceAccepted`, Review cache fulfillment,
   publication commits, construction leases, artifact pins, Reload overlap,
   pane close with multiple predecessor drains, close before target-edge
   acknowledgement, close between acknowledgement and open, close during
   W→X→Y drains, and apply-target after close.
2. Revalidate epoch admission at request capture and every publication edge;
   keep existing generation and identity fences.
3. Retain predecessor close receipts and join all receipts on binding close.
4. Keep runtime metadata post-commit and diagnostic only.
5. Serialize apply-target and teardown initiation at the same controller
   boundary. Close is terminal: no acknowledgement or later coordinator call
   can open or construct a successor after close begins.
6. Add a static negative scan that rejects target-sensitive decisions from
   `runtime.metadata` and `bridgePaneState.source` after binding installation.

Gate: no target-scoped work or resource survives pane teardown; Reload cannot
resurrect a revoked provider. All close interleavings end with zero live
installations, tasks, leases, pins, publications, or retained drain receipts.

Design-break triggers: a second subscription registry, public/durable target
epoch, partial mutation of target-specific providers, browser target resolver,
controller replacement, or new recovery coordinator.

## Slice 5 — Empty native context menu and deliberate Reload command

Requirements: UR-23–UR-24.

Behavior:

- Right-clicking Bridge content exposes none of the default WebKit page menu,
  including Reload.
- `Reload Bridge Web View` appears in the command surface only for the resolved
  active Bridge pane, has no shortcut, and calls ordinary Reload on the existing
  controller's existing `WebPage`.
- Reload resets browser-local state through ordinary page lifecycle but does
  not refresh native source authority or replace the pane/controller/host.

TDD and work:

1. RED: host composition/AppKit test for empty replacement, command visibility
   and pane routing tests, controller invocation test, and product-session
   rotation test preserving the binding target. Add a command-description
   contract test that describes Web View Reload without implying native source
   refresh, plus a typed Management Layer `⌘R` regression test proving one
   execution and no WebKit navigation/session retirement.
2. Apply the supported SwiftUI WebKit empty context-menu replacement in
   `BridgePaneContentView`.
3. Add the typed `AppCommandSpec`, pane-aware resolver, and direct controller
   Reload effect.
4. Reuse existing pageReload bootstrap/session behavior; add no Reload state,
   retry, debounce, or replacement coordinator.
5. GREEN: run focused Swift host, command, controller, and bootstrap tests.

Checkpoint gate: current controller/page/source identity is unchanged across
dispatch; the default context menu is absent in the packaged host; typed
Management Layer `⌘R` still executes once without WebKit navigation.

Split trigger: if the supported empty replacement does not suppress the
packaged menu, stop as a platform/design break. Do not use browser DOM
suppression or replace the host without agreement.

## Slice 6 — Integrated hard-cut and packaged product proof

Requirements: UR-01–UR-25.

1. Delete every legacy schema/state/fallback path made unreachable by the hard
   cutover. Run source scans for fixed-source consumers, legacy combined filter
   fields, TypeScript production Git/filesystem access, and parallel control
   state.
2. Run BridgeWeb formatting/check/type validation and full relevant unit,
   integration, browser, and E2E gates.
3. Run focused Swift suites, `mise run lint`, `mise run build`, and the relevant
   broad Swift test gate.
4. Start the shared observability stack.
5. Run the strict packaged Bridge product journey, which owns the
   worktree-isolated debug launch and its Victoria marker, against disposable registered
   worktrees and extend its assertions where necessary for:
   - Files/Review Filter inventories and semantic read-back;
   - separate View Settings and selection/source continuity;
   - Search shortcuts, invalid/oversized input, Escape/close, and focus return;
   - initial registered-source truth, same-worktree refresh, and no stale rows;
   - representative Loading, Refreshing/Stale, Unavailable/Failed, no-match,
     selected-content-unavailable, cancellation, and bounded-reason states;
   - authority loss closes open Filters/Search, disables source-dependent
     controls, and restores focus to the active surface root;
   - keyboard-only dropdown operation/dismissal, accessible names/states,
     filter-exclusion focus fallback, oversized-input announcement, and
     two-pane View Settings isolation;
   - right-click empty context menu;
   - typed Management Layer `⌘R` executes once without navigation;
   - command-surface Reload with browser-local reset and native identity
     continuity; and
   - read-only behavior.
6. Use PID-targeted Peekaboo/manual interaction only for visual, focus, key,
   menu, and WKWebView behavior that headless proof cannot establish. Do not
   take over the user's foreground.
7. Run `implementation-review-swarm`, address only validated findings, rerun
   affected proof, then execute PR-ready wrap-up. Do not merge without explicit
   authorization.

Native integration, not the packaged journey, owns direct A→B→null triggering,
inactive-surface target-edge reset, and stable controller/`WebPage` identity.
The packaged journey composes with that evidence by proving the real initial
registered source and the resulting WKWebView behavior. Do not add a test-only
CWD mutation API merely to collapse these proof layers.

## Execution DAG and parallel write lanes

```text
gate 0: current source and baseline proof
  |
  +--> slice 1 -> slice 2 -> slice 3: shared surface integration (serial)
  |
  +--> slice 4A-4D: native target binding/lifecycle (serial, exclusive owner)
  |
  +--> slice 5A: native host + command catalog (no controller/session writes)
          |
          +--> after 4D: slice 5B controller route + session continuity proof
          |
integration gate: parent verifies hard-cut contracts and resolves shared files
  |
slice 6: full tests + packaged WKWebView/native proof
  |
implementation-review-swarm
  |
PR checks/comments/threads/head/mergeability ready; no merge
```

Slices 1–3 integrate serially because current Files and Review surface owners
co-own Filter, Search, and View Settings state. Leaf pure-policy, shared-control,
and test files may be prepared in parallel, but the parent exclusively edits
the two surface shells and semantic listeners. Slice 4 is serial internally and
its owner exclusively edits binding/controller/session internals. Slice 5A may
run beside Slice 4 only in host and command-catalog files; controller routing
and session-continuity work waits for 4D and is integrated by the parent.

Suggested delegated write scopes:

- Lane A: BridgeWeb Filter contracts, stores, menus, listeners, projections,
  and their tests/fixtures.
- Lane B: BridgeWeb View Settings leaf menu/option derivation and tests only;
  parent owns both surface-shell integrations after Lane A lands.
- Lane C: BridgeWeb Search policy/shared control/shortcut leaf files and tests
  only; parent owns surface stores/shells and semantic listener integration
  after Slice 2.
- Lane D: native topology/controller/binding/session/source/publication work and
  Swift tests; one owner, serial substeps.
- Lane E: native context-menu host and command catalog/spec tests only while
  Lane D runs; parent adds controller routing after 4D. Lane E never edits
  binding/session internals.
- Parent: shared DTO and surface-shell integration, conflict resolution, static cutover scan,
  packaged proof, final review, and PR readiness.

Before delegation, write a path-level ownership ledger with no simultaneously
writable path. If a required file crosses lanes, serialize that edit under the
parent rather than relying on later conflict resolution.

Lane reasoning effort: medium for bounded BridgeWeb UI slices; high for Filter
contract integration, native binding/reliability, validation/proof, and final
scope-fit review.

## Validation commands

Focused commands must be selected from current package/test support and recorded
with counts and exit codes during execution. Terminal gates include:

```text
mise run setup
mise run bridge-web-check
mise run bridge-web-unit-test
mise run bridge-web-integration-test
mise run bridge-web-browser-test
mise run bridge-web-e2e-test
mise run lint
mise run build
mise run test
mise run observability:up
mise run run-bridge-packaged-product-journey
mise run verify-bridge-packaged-product-journey
```

The executor may use narrower test filters while developing, but cannot replace
the mapped terminal gates with a single broad command or call fixture-browser
evidence packaged proof.

## Rollback, cleanup, and risk controls

- Commit verified scoped checkpoints so a failed later slice can be reverted
  without restoring legacy dual paths.
- Hard cutover means rollback is by reverting the complete affected checkpoint,
  not by adding compatibility flags or schemas.
- Disposable worktrees, debug app state, and proof markers are cleaned through
  existing harness cleanup paths; never delete broad directories manually.
- Preserve unrelated dirty/untracked work throughout.
- Highest risks are stale target publication, orphaned drains, split native/web
  schema cutover, packaged WebKit menu behavior, and a renderer remount hidden
  by component tests. Each has a slice-local proof gate above.

## Completion condition

Implementation is ready for PR wrap-up only when every requirement row has
fresh slice-level proof, quality gates pass, packaged WKWebView/native behavior
is observed, the final source scan shows no legacy or forbidden path, and an
independent implementation review has no unresolved validated findings. PR
readiness additionally requires fresh checks, comments, threads, head SHA, and
mergeability. Merging remains outside this plan without explicit authorization.
