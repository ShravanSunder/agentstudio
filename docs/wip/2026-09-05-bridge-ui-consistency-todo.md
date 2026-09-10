# Bridge UI consistency TODO

Owner: UI lane. This is an open-work checklist, not completion evidence or a replacement
for the governing style-system plan. Transport work must not displace these tasks.
User screenshots and current source drive the drawer findings below.

## Current delivery order — 2026-09-08

- [ ] **UI-F05 Share Copy/Export unavailable or inert:** user reports both footer
  actions do not work; screenshot shows subdued controls. Reproduce with saved
  selected membership and inspect actual disabled/readiness state, pending lease,
  and command result. Distinguish intentional empty/unconfirmed disabling from
  stale readiness or failed dispatch. Never remove guards to make controls click.
  Prove Copy and Export through the dev server and record exact outcome.

This is the active checklist; older slice receipts below are historical proof,
not a claim that the entire current UI is finished.

- [ ] **UI-F04 Existing-highlight to new gutter range:** user reports that with an
  existing annotation focused, moving elsewhere and click-dragging a new
  range in the Review gutter does not start another annotation. Reproduce exactly
  that sequence; compare no-active-thread versus active-thread, same/different
  file and single-click versus multi-line drag. Inspect selection/active-thread
  ownership before editing; add permanent interaction regression and prove in
  Chrome plus native Debug. User confirmed annotation focus, not comparison/commit
  selection, is the starting state. Cause is not yet established.

- [x] Settle main background direction: owner selected B, cool native shell,
  matching top toolbars, file-header/tree/scroll-track shared value,3% annotation
  lane. Canonical transfer underway September9; this check marks the decision,
  not delivery or complete native proof.
- [ ] **UI-S14 Quiet pane separators:** no top toolbar border/shadow, one quiet
  vertical resize separator, visible hover/focus/drag grip with16px fine/28px coarse
  hit target. Permanent near-line pointer and keyboard test passes; delivery
  checkpoint/native proof pending.
- [ ] **UI-S15 Search composition:** evaluate input-to-results clearance and
  metadata truncation under the approved B colors. Do not broaden this into an
  unapproved drawer-width or typography change.
- [x] Integrate existing pure Share preview into live Share output controls so
  Pending/All show every participating saved comment, including non-inline ones.
- [x] Pass canonical thread resolution into shared UI Pending derivation and
  all badge/count/projection callers; resolved excluded, reopening recomputes.
  Native and UI predicates implemented/tested; real dev Resolve/Reopen and
  Pending/All preview proof in UI090; exact output parity E2E passes.
- [ ] Prove annotation create, multiline selection, edit/save, reply, resolve/
  reopen and exact Pending/All Copy/Export membership in Chrome and native app.
- [ ] Independently review integrated UI, satisfy aggregate gate, then scoped
  checkpoint commit/push. Preserve other lane edits; no broad staging.
- [ ] Native Git +0 metadata counts: UI087 requests owner investigation/handoff.
  This separate dependency must not block the annotation work above.
- [x] Review height regression: stable status grid slots;17 geometry tests and
  native exact-file scroll/full-height Compare proof recorded in UI085–UI086.

User instruction: finish drawer discussion, then annotation implementation;
do not leave annotation work paused at a visual checkpoint.

## Share drawer — explicitly reported by user

- [x] **UI-S01 Header density:** align title typography, header height and title-to-icon
  spacing with compact Bridge chrome. Reported baseline title used `text-lg` (14px/20px),
  while surrounding compact text uses `text-xs` (11px/14px).
- [x] **UI-S02 Header icon:** explicitly size the Share title icon through its owning
  shared recipe. `BridgeViewerIcon` is currently an unsized span; outside a Button,
  its child does not receive the Button's SVG sizing rule. Verify final rendered size.
- [x] **UI-S03 Section padding:** normalize header/body/footer insets and section gaps.
  Reported feature-local `p-4` supplied 16px on all sides; do not treat valid utility
  classes as proof of consistency with the compact 4/6/8 spacing system.
- [x] **UI-S04 Footer controls:** align Copy/Export button height, icon size, inner
  padding, inter-button gap and distance from the drawer edges with shared controls.
  Include disabled paint; do not use whole-control fading as a substitute for roles.
- [x] **UI-S05 Pending/All icons:** replace the mismatched yellow status-dot versus
  list-icon treatment with a matched visual family. Proposed direction: 12px outline
  icons, identical label gaps, selection indicated by the segment rather than a dot.
  Preserve the actual Pending/All filtering semantics.
- [ ] **UI-S06 Drawer visual review:** compare the complete drawer beside ordinary
  Bridge chrome at the same zoom/scale. Check surface/border/radius/elevation and the
  relationship between empty body space and compact controls; preserve host placement.

Source anchors: `BridgeWeb/src/worktree-annotations/worktree-annotation-share-mode.tsx`,
`BridgeWeb/src/app/bridge-viewer-button.tsx`, `BridgeWeb/src/components/ui/drawer.tsx`,
`BridgeWeb/src/components/ui/button.tsx`, `BridgeWeb/src/app/bridge-app.css`.

### Drawer implementation evidence — UI-S01 through UI-S05 verified

UI-S01 through UI-S05 have a working-tree candidate: shared DrawerHeader/Footer now
own 8px insets; header owns 11px typography and 12px SVGs. Share removes its larger
title/frame overrides, uses 8px body padding and matched ListFilter/List outline icons.
After independent review, shared ToggleGroup enforces 20px segmented items within its
24px frame while preserving the chosen 12px icons. Copy/Export remain 24px with 8px gap.
No callback, filtering, enablement, output or host-placement behavior changed.

RED: Share geometry test received 16px padding rather than 8px; 1 failed/3 passed, exit1.
GREEN: `mise run test:bridge-web:browser -- src/worktree-annotations/worktree-annotation-share-mode.browser.test.tsx src/worktree-annotations/worktree-annotation-share-surface.browser.test.tsx src/components/ui/style-system.browser.test.tsx`
returned 3 files/26 tests passed, exit0. `mise run test:bridge-web:check` returned exit0
(existing warnings, no errors; format/type/product-contract gates passed).
Parent visually inspected [browser screenshot](../../tmp/bridgeweb-worktree-annotation-share-mode.png).
The initial native candidate was inspected after a standard fresh debug launch (PID67150,
window121242, marker `debug-observability-1owk-1788611495-63747`). First Share click
opened the compact drawer. Full-window pixels: `/private/tmp/bridge-native-drawer-density-after.png`;
unscaled detail crop: `/private/tmp/bridge-native-drawer-density-detail.png`.
Counts were unknown dashes with disabled output; this is style/drawer-interaction proof,
not successful annotation convergence. This native capture predates the final 20px
segmented-item correction and is superseded by the final proof below.

Independent Sol onlook found one important issue: 24px segmented items contradicted
the Program Design's 20px inner items. Parent verified and corrected the shared primitive,
not a feature-local override. Corrected browser RED was 24 rather than20 (1failed/3passed);
the three-file browser rerun passed26/26. The reviewer found no other visible drawer issue
in its bounded scope; this was not a whole-PR readiness review.

Final corrected native build: standard launcher exit0, PID7361/window121845,
marker `debug-observability-1owk-1788613234-6070`, build14.03s. Parent opened Share on
the first click and inspected `/private/tmp/bridge-final-density-native-detail.png`
(full window `/private/tmp/bridge-final-density-native.png`): 20px inner segments now
fit within the frame; icon family and compact section/header/footer remain intact.
The independent correction re-review result follows; no whole-flow completion inferred.

Fresh raw proof retained for review (both parent-observed exit0, no source changes):
[26-test browser output](../../tmp/plan-workflows/2026-09-05-final-drawer-browser.log)
and [quality-check output](../../tmp/plan-workflows/2026-09-05-final-drawer-check.log).

Final fresh-context Sol correction re-review completed read-only, no findings, at
HEAD `d1bee274d` plus the inspected dirty correction. Receipt:
`/private/tmp/bridge-final-density-review.txt`. Parent verified the shared20px rule,
all three segmented callers, current native screenshot and test assertions, and accepted
closure of the one earlier finding. Raw proof logs above additionally close the review's
ledger-only evidence uncertainty. This closes UI-S01–UI-S05 only. Enabled/hover/focus native
states, full drawer comparison and app-wide/annotation/aggregate gates remain below.

## App-wide consistency — retain original scope

Source inventory: [22 shared component families and Bridge consumers](2026-09-05-bridge-component-inventory.md).

- [ ] **UI-S11 Popover family:** shared inset/gap/title and admission action sizes now
  corrected;29 browser tests and quality check pass. Native and independent visual proof pending.
- [ ] **UI-S12 Loading wrappers:** inspect Review canvas/tree50% fading as a shared
  loading-presentation concern; candidate removes dimming only,14tests pass with all
  interaction/admission gates preserved. Native and independent proof pending.
- [ ] **UI-S13 Motion recipes:** reconcile live100/150ms defaults against the existing
 120/200ms scale with rendered transition tests; candidate has22focused tests green.
 Actual Collapsible ending-state150vs120 RED observed; native/reduced-motion proof pending.

Latest combined gate: check exit0; full browser357passed/1known post-Save failure/5skipped,
exit1. Raw logs `tmp/plan-workflows/2026-09-05-shared-component-check.log` and
`tmp/plan-workflows/2026-09-05-shared-component-browser.log`. No global green claim.

- [ ] **UI-S07 Control inventory:** verify size, font, icon, radius, spacing and state
  parity across File, Review, annotation editors/threads, menus, tooltips and Share.
- [ ] **UI-S08 State paint:** verify enabled, disabled, hover, selected, focus and invalid
  controls against shared recipes. Cover fading/grayed-out buttons and opacity issues.
- [ ] **UI-S09 Rendering paths:** recheck portaled versus in-tree appearance and effective
  Pierre code/tree typography and colors against CSS tokens and checked palette mirror.
- [ ] **UI-S10 Remove local overrides:** route control/frame styling through owned shared
  primitives; feature code chooses size/variant and layout. Do not add ad hoc corrections.

## Functional dependencies — separate from styling

- [ ] **UI-F01 Save/new-comment/reply:** coordinate the accepted canonical message or
  tombstone receipt with transport; install command-confirmed UI state before resolving
  the command, without fabricating server data or blocking on projection convergence.
- [ ] **UI-F02 Share truthfulness:** verify membership/counts and output readiness after
  Save, during unavailable/delayed projection, and after recovery. A disabled output
  button or a displayed zero is not proof that the saved-message flow is healthy.
- [ ] **UI-F03 Full real flow:** prove single-line and multiline first-plus admission,
  edit, Save, another comment, reply and Share in browser and a current packaged debug app.
  Preserve the existing failing native instance while transport needs its evidence.

Coordination: [UI append-only log](communications/2026-09-05-bridge-ui-agent-log.md)
and [transport append-only log](communications/2026-09-05-pr-a-transport-agent-comms.md).

## Current queue — 2026-09-09

Implementation checkpoint (not final completion): category icons/labels and compact
Review submenus implemented; File category behavior8/8 passes. File boundary
shadows removed, header uses --separator (4/4 source regressions). Annotations
outline trigger implemented; Compare shared results viewport adds standard frame
and8px input/note clearance. Browser integration initially75pass/3fail: two stale
zero-gap assertions and one ambiguous non-exact Annotations locator; corrections
retain geometry/interaction proof. Settings controls under final parent checks.
Real Chrome switch/reset/Escape verified before last visual refinements; latest
Chrome control reconnect failed, native6sby reachable but package still old.
No final readiness, push or cleanup claim.

- [ ] Redesign shared File/Review filters and view settings using Pierre examples
  as composition guidance, not palette/theme authority. Trace actual classification
  and filtering before renaming. Replace letter badges with meaningful icons;
  remove redundant subtitle copy, oversized equal columns and mismatched label
  typography. Make binary/large inclusion visibly interactive with clear labels;
  establish compact setting rows and shared segmented choices. Verify fixtures,
  Other and all statuses against real filtering, including empty-result feedback.
- [ ] Finish current palette/divider checkpoint verification and push before new UI changes.
- [ ] Fix Review file boundary double lines. Screenshot shows heavy top/bottom edges;
  source has per-diffs-container top/bottom shadows using --input in
  bridge-code-view-panel-frame.tsx and a default-header top border using --border
  in bridge-code-view-options.ts. Verify rendered overlap and give each boundary
  one quiet separator owner; preserve file headers and resize affordance.
  User explicitly requires standard line colors: use the shared --separator
  layout role, not --input/component-border paint or a feature-specific color.
- [ ] Fix Compare persistent search/list composition: search focus clearance,
  list boundary, row spacing, scrollbar and bottom-note placement.
- [ ] Replace Share icon-only trigger with outlined Annotations button and thread icon,
  using the existing command display and shared button system.
- [ ] After verified transfer and push, remove only ui-surface-options-2026-09-08
  via wt; preserve unique evidence first. Archive already created at
  tmp/2026-09-09-surface-experiment-evidence.tar.gz; cleanup not yet performed.

## Completion gates

September8 drawer-contract slice: progressive documentation and parent source audit
in [drawer style audit](2026-09-08-drawer-style-audit.md). Shared recipe fixes have
scoped browser/check evidence; native, independent review and aggregate gates below
remain open. Do not conflate this presentation slice with unresolved annotation
or transport proof.

- [ ] Add/run permanent style and interaction regression coverage for the changed paths.
- [ ] Capture before/after browser and native screenshots at the same scale, with measured
  control/icon/text geometry. Tests or accessibility data alone are not visual proof.
- [ ] Run relevant mise quality/test lanes; preserve exact commands, counts and exit codes.
- [ ] Obtain independent review, verify findings, and make scoped checkpoint commits.
- [ ] Mark individual items complete only with current source/test/manual evidence links.
  Do not mark the whole UI complete from a transport fix or one passing slice.
