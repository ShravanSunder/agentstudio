# Drawer planning discovery

Requested terminal: plan-only. Product code remains unchanged.
Current checkout: agent-studio.drawer-changes, HEAD `3c7a4ea3293eeac9e94cae6dc269c3bb0d378900`.

## Recovered governing material

The dedicated drawer documents are in the sibling improvements-viewing checkout, not navigation-cmds and not this checkout. They are currently untracked in that sibling. Do not mistake the older memory summary's unresolved free-positioning discussion for the latest selected behavior.

- [Requirements](../../../agent-studio.improvements-viewing/docs/specs/2026-09-13-drawer-presentation/requirements.md)
- [Specification](../../../agent-studio.improvements-viewing/docs/specs/2026-09-13-drawer-presentation/specification.md)
- [Program Design](../../../agent-studio.improvements-viewing/docs/specs/2026-09-13-drawer-presentation/program-design.md)

Canonical absolute directory: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.improvements-viewing/docs/specs/2026-09-13-drawer-presentation/`.
Original source record: sibling `docs/specs/2026-09-12-bridge-navigation/2026-09-12-requirements.md`, S9–S15. Earlier exploratory messages are in session `01a09726-dd3a-7e01-b28c-72f26de5669b`; later dedicated artifacts narrow free dragging to two side placements.

## Recovered behavior, not new decisions

Full-screen means app Pane Zoom, not macOS window full-screen.

- Normal mode: top-edge resizing only; stable pointer tracking and independent height memory per owning pane.
- Zoom: terminal side initially; remember explicit terminal/Bridge side per owner across ordinary restart. Hidden Bridge temporarily uses terminal without overwriting the saved side.
- Fixed Zoom outline: approximately 85% of chosen content-region height including connector, with 15% context above; no visible or invisible resize target.
- Width follows the actual selected region, reduced by 2–5%; program design chooses 97%, centered. No half-workspace minimum.
- Full outline ends at content-region bottom; common toolbar is already excluded.
- Same owner, children, running content, collapse/dismissal and close/undo. Normal Bridge-owned drawers remain available.

```text
Selected content region
  top 15%: underlying context remains visible
  lower 85%: drawer panel plus connector
  region bottom: outline ends here
Shared toolbar below: excluded once
```

The existing program design proposes one shared pure geometry resolver for overlay and native bootstrap, a transient normal resize session, committed preferences on the existing drawer atom, workspace-local SQLite persistence/undo retention, and two command-catalog actions. These are recovered design proposals; this discovery does not independently accept or modify their structure.

## Current-source check

Parent inspected the decisive sources after two read-only native Workers returned evidence.

`DrawerPanelOverlay.swift:198–208` still computes width from full tab size and bottom as `info.frame.maxY - iconBarFrame.height`. Its 40-point connector is intentional, included in the unified outline.

Ordinary `PaneLeafContainer.swift:255–302` includes a reserved toolbar in its VStack; frame publication is at `:579–607`. Zoom instead places its common toolbar below the source/companion split (`ZoomPresentationContainer.swift:137–170`). Zoom children reserve no toolbar (`ZoomPresentationContainerRenderStateTests.swift:47–55`). Zoom feeds child frames and common toolbar frame into the unchanged shared overlay (`ZoomPresentationContainer.swift:394–419`).

This predicts an extra toolbar-height gap in Zoom: the child frame already excludes the toolbar, then the overlay subtracts its height again. This is a strong source-backed hypothesis, not native reproduction of the screenshot. Do not remove the intentional connector as a substitute for establishing the coordinate error.

Current tests cover Zoom toolbar/management geometry and drawer dismissal/preferences, but the evidence lane found no expanded Zoom drawer-to-toolbar alignment assertion. No tests, build, app launch or runtime measurements were performed in this planning discovery.

## Planning admission and next work

The three artifacts exist. A bounded search of sibling docs/wip and tmp found no drawer-specific completed independent design review. Raw session confirmation of the two final side choices was not recovered; their explicit owner attribution is in the dedicated Requirements. The recovered Fable workspace review explicitly excludes drawer obligations U-BN-08–12; it cannot be reused as drawer review coverage. Therefore this is a planning discovery record, not a ready canonical implementation plan.

Continue by verifying drawer review history, re-anchoring the recovered structural design against current persistence/bootstrap/command owners, and satisfying the design-review gate. Then author the implementation plan against the preserved obligations. Proof must include measured native gap/resize evidence, normal and unequal Zoom splits, no Zoom resize hit targets, independent preferences across restart, hidden/restored Bridge, consistent bootstrap/hit bounds, and ownership/undo preservation. Before any eventual PR readiness, current HEAD must pass `mise run test` and additional native/marker proof required by the design.

## Shared work reference

Selected Router: default local service `0ff962c5-7fa3-4c18-a5ca-1bbe8db09e89`, endpoint `codex-local`.
Project `01a09c8d-bfa1-7eb2-8432-595da973724f`; board `01a09c8f-fdef-79e2-9add-1942d7c0f0de`; topic `01a0c92e-7ed9-7722-9483-f4530f3630e9` (Drawer presentation).
Root thread `01a0c92e-b6cb-7240-b578-7d1c22487767`.
Orchestrator session `01a0c92b-c12a-7441-80cc-902a2dd57331`; role and watch confirmed by thread-create response. Thread remains unresolved.

## Continuation: review admission and current structural evidence

The design-review workflow was loaded. It requires explicit structural-realization confirmation for three-artifact review. Existing owner attribution settles the requested behavior, but no confirmation of the recovered persistence/geometry structure was found. A question is pending with the owner: use the recovered shared geometry resolver plus existing-workspace per-pane preference persistence as the basis for independent review, or revisit that structure first. This is review-only confirmation, not implementation authority. No reviewer has been dispatched pending that answer.

The same native geometry Worker returned a bounded persistence/bootstrap source inventory, and Main inspected the decisive anchors:

- `WorkspaceDrawerCursorAtom.swift:4–38` remains expansion-only. Per-owner preference values and revision are proposed additions.
- `WorkspaceStore.swift:422–465` owns save observation; `WorkspaceSQLiteSaveCoordinator.swift:138–171` owns current composition revision and immutable capture. Current capture/revision has no presentation payload/revision.
- `WorkspaceLocalRepository.swift:228–246` writes window and replaced cursor rows in one transaction. New preference rows must preserve the design's separation from destructive cursor replacement.
- `WorkspaceSQLiteDatastoreActor.swift:210–213` returns after core commit for journal mutations. Ordinary saves subsequently write local state. Preserve this existing distinction; do not silently turn close/undo into synchronous local-preference durability.
- `WorkspaceSurfaceCoordinator+ViewLifecycle.swift:823–929` duplicates normal drawer geometry and has no Zoom-region input. The proposed shared resolver needs explicit current Zoom inputs along bootstrap/recovery callers; an arithmetic-only extraction cannot satisfy the recovered Zoom contract.

These are source-applicability observations, not independent-review findings or structural acceptance. Product code remains unchanged. Three source links in this record were verified; `git diff --check` exited 0. Current untracked work is this discovery note only (scratch files are ignored).
