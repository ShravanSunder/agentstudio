# Keyboard Navigation Work Trail

Source: [events.jsonl](./events.jsonl). **Covers events.jsonl through line 28.**
This view renders the bounded prefix only; evidence pointers in the records are
recorded claims, not independent verification.

## Current status — line 28

Current publication HEAD `3bb6378d6` has a failed aggregate gate. The
lint, architecture, BridgeWeb unit, integration, and browser
stages passed, but the configured annotation stress journey failed: attempt one
returned unavailable when Copy was invoked; the retry passed Copy
and later failed Review telemetry quiescence. Later Swift stages were not reached.
The failure is outside arrangement scope. The bounded diagnostic described in
[scope proposal](../../../tmp/debug-workflows/2026-09-13-annotation-copy-publication-gate/scope-proposal.md)
is prepared but not applied; owner approval is required before editing that
unrelated transport/test layer.

The earlier source-identical `94e85dd5f` checkpoint recorded a green full
aggregate (8,338 Swift tests plus 35 architecture-tool tests) and remains the
valid arrangement baseline. Native arrangement proof is complete for the
recorded main-pane creation, custom reveal, Default fallback, ordinary drawer
reveal/input, and Bridge reveal/search journeys; the bounded evidence is in
[native interaction proof](../../../tmp/sidebar-keyboard-design/arrangement-native-interaction-proof.md).
All supplemental review lanes reported no findings. There is no push, PR
publication, merge into `main`, or release. The general detached-drawer
attachment invariant remains deferred to a separate PR. Broader sidebar
implementation is still not done; the exact preview key, cold-preview realization, and pinned-wrap questions
remain open. Numeric activation is settled: 1–9 opens the result immediately.

## Design and discovery — lines 1–15

- **Lines 1–3 — initial scope:** The work began as a documentation-only
  keyboard-navigation discussion focused on reduced hand strain. Activity
  navigation, sidebar visibility/focus/surface, and arrangement reveal were
  separated after source inspection found distinct operations and a visibility
  mismatch. Requirements were recorded while traversal choice, priorities,
  bindings, arrangement edges, and conflict audit remained open. The record also
  notes an LFS sandbox error during status inspection; no repair was attempted.
- **Lines 4–8 — consultation and focus model:** An annotation-agent
  consultation was accepted; discovery first hit an address error, then the
  return address was corrected and a bounded reply was incorporated. The owner
  initially defined “last active pane” as the last focused pane (line 5). Line 6
  **corrected/reopened that interpretation**: settled-output activity, visit
  recency, and current focus are separate, and focus alone does not refresh
  output activity. The navigation contract stayed open. The keyboard map
  preserved Option-I/K drawer navigation after the owner corrected its modifier,
  and recorded annotation search/edit/Escape boundaries without approving new
  behavior.
- **Lines 9–11 — owner choices and corrections:** A bounded design cycle
  accepted all-window activity/visits, Shift-Option families, stable held-key
  sequencing, Current plus Default creation, and Current/Custom/Default reveal
  with parent-drawer expansion. Line 10 **reopened** activity-ranking and
  Bridge-exclusion contracts for a sidebar-group investigation while retaining
  all-window reach, stable sequencing, immediate focus, and arrangement rules.
  Line 11 then **replaced separate last/next traversal with visual sidebar
  navigation**: Cmd-S visibility and Cmd-Shift-S activation, with the workspace
  visible and an indication shown. P/R/F, filter/type-ahead, activation, and
  return behavior remained proposals; the source-only investigation did not
  reproduce the live symptom.
- **Lines 12–15 — scope and preview:** The scope tree retained sidebar
  navigation, direct Terminal pinned-pane Option-Shift-arrow movement, and
  arrangements, while activity/history traversal and the bulky help strip were
  discarded. Video review informed contextual shortcut pills, but the reveal
  trigger remained open. Source validation corrected assumptions about effective
  focus, table selection, Cmd-Shift-P, icon-implied state, repository/pane pin
  conflation, usage claims, and digit addressing. Filter Enter-to-table and
  first-nine actionable results were added to the working design (digits remain
  text while filtering). Review documents were cleaned up; U15 separated
  temporary preview from committed reveal by Enter, with hold/toggle and
  select-versus-activate questions still open. No source implementation or full
  design acceptance was claimed.

## Arrangement implementation and proof — lines 16–27

- **Lines 16–18 — design handoff and Core/App slices:** Independent design
  review and dispel work admitted arrangement visibility for implementation
  while sidebar preview questions stayed open. Setup/vendor verification and
  baseline focused tests passed; Core work began after an expected missing-API
  RED. MainActor construction and validation concerns were caught before Core
  acceptance. Core proof reached 46 tests / 4 suites green, and App focus
  sequencing was authorized. No full-feature, native, or PR claim was made.
- **Line 19 — scope correction:** Generic insertion also serves move, undo, and
  reactivation, so creation-only behavior was separated from existing placement;
  reveal validation remained off MainActor. The earlier Core 46-test result was
  explicitly corrected as insufficient proof of production birth routing. A
  bounded v2 plan was admitted; fresh proof was required.
- **Lines 20–21 — focused proof and aggregate failure:** Focused production
  routing, identity preservation, and focus ordering passed at `ad92f6495`, with
  recorded App/Core/webview/Bridge results. The full aggregate then failed with
  exit 1 because the upstream Ghostty header lookup was missing. A test-only
  lookup patch was prepared, but no edit was made pending scope approval; a
  minimal Core preservation correction and regression were separately allowed.
- **Line 22 — verified gap and blocked native capture:** At checkpoint
  `0e17351e1`, Core focused proof and prior App/Bridge/webview results remained
  green, but the aggregate and native capture were blocked. Independent review
  accepted an R-A4 design gap: a selected unminimized drawer child can remain
  renderer-detached when an already-open physical drawer skips toggle/expansion.
  No remediation was applied; owner reconvergence was required. Preview,
  digits, and Management choices were still pending.
- **Lines 23–26 — decisions, repair, and green baseline:** The owner selected
  hold/release preview, immediate digit activation, and Management precedence,
  and deferred the general drawer invariant to a separate PR. The approved
  header lookup correction reached focused green proof and matching ancestry and
  vendor pins. A direct Swift timeout was diagnosed as the runner's short
  inactivity default, not a justified runner or vendor change. The canonical
  aggregate later passed unchanged at `94e85dd5f`; native proof covered main
  creation, custom reveal, Default fallback, and ordinary collapsed-drawer
  reveal/input. Earlier intermittent failures remain recorded and are not
  silently reclassified.
- **Line 27 — Bridge native proof:** With explicit foreground permission for the
  isolated debug app, Watch Folder and Files were exercised live. Layout2
  minimization followed by sidebar activation selected Layout1 and restored the
  same viewer; README filtering produced 11 matches from 5,016 items. The
  baseline native-container-to-DOM shortcut-focus limitation remained a broader
  sidebar-keyboard issue. Supplemental eight-file spec review had no findings;
  quality/proof review continued. No source change, push, PR, or merge was
  claimed.

## Gaps and accounting

All 28 JSONL records were readable. No malformed line, missing allowed detail,
or invalid in-range `corrects_line` target was found. Corrections at lines 6,
10, 11, and 19 are represented above. This rendering does not independently
rerun any evidence named by a record.
