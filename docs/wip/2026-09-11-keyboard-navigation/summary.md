# Keyboard Navigation Work Trail

Source: [events.jsonl](./events.jsonl). **Covers events.jsonl through line 31.**
This view renders the bounded prefix only; evidence pointers in the records are
recorded claims, not independent verification.

## Current status — line 31

The arrangement branch is now aligned with latest `main` at
`1a467a1205f193baf1e90c1444862078875da222`. The recorded `MISE_RAW=1 mise run
test` aggregate passed at that head, with root-verified 8,356 Swift tests,
358 Swift run summaries, and 35 architecture tests; the focused alignment lane
also passed 35 tests / 7 suites. The Ghostty header conflict was resolved to
the main manifest-based fix and vendor pins/shared producer match. PR345 has
been pushed but remains unmerged; its CI watch is active.

The sidebar core design has completed independent review and parent correction
and is ready for a bounded implementation plan. The review’s accepted finding
was that group-dependent RowIDs cannot preserve destination continuity through
regrouping; the corrected design remaps by pane/worktree destination before
removal fallback. See [core design review](./core-design-review.md). Core U1,
U3, U4, U5, U12, U14, and U16 are ready to plan. U15 cold-preview restoration
remains open and required. No sidebar source implementation has started.

The general detached-drawer renderer/attachment invariant remains deferred to a
separate PR. No successful resumed Opus consultation, new Opus ping, wake, or cache-warmth
result is recorded for this continuation: the named cold resume was pending, later resumes were
unavailable, and Router discovery was unavailable. No PR merge or release is
claimed. Earlier native arrangement proof remains historical evidence; the
main-alignment review added no new native proof.

## Design and discovery — lines 1–15

- **Lines 1–3 — initial scope:** The work began as a documentation-only
  keyboard-navigation discussion focused on reduced hand strain. Activity
  navigation, sidebar visibility/focus/surface, and arrangement reveal were
  separated after source inspection found distinct operations and a visibility
  mismatch. Requirements were recorded while traversal choice, priorities,
  bindings, arrangement edges, and conflict audit remained open. An LFS
  sandbox error during status inspection was recorded; no repair was attempted.
- **Lines 4–8 — consultation and focus model:** An annotation-agent
  consultation was accepted; discovery first hit an address error, then the
  return address was corrected and a bounded reply was incorporated. The owner
  initially defined “last active pane” as the last focused pane (line 5). Line 6
  **corrected/reopened that interpretation**: settled-output activity, visit
  recency, and current focus are separate, and focus alone does not refresh
  output activity. The navigation contract stayed open. The keyboard map
  preserved Option-I/K drawer navigation after its modifier correction and
  recorded annotation search/edit/Escape boundaries without approving behavior.
- **Lines 9–11 — owner choices and corrections:** A bounded design cycle
  accepted all-window activity/visits, Shift-Option families, stable held-key
  sequencing, Current plus Default creation, and Current/Custom/Default reveal
  with parent-drawer expansion. Line 10 **reopened** activity-ranking and
  Bridge-exclusion contracts for sidebar-group investigation while retaining
  all-window reach, stable sequencing, immediate focus, and arrangement rules.
  Line 11 then **replaced separate last/next traversal with visual sidebar
  navigation**: Cmd-S visibility and Cmd-Shift-S activation, with the workspace
  visible and an indication shown. P/R/F, filtering/type-ahead, activation, and
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

## Arrangement implementation and proof — lines 16–28

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
  no source change, push, PR, or merge was claimed at that point.
- **Line 28 — publication gate:** Source-identical publication HEAD `3bb6378d6`
  failed its aggregate only in the configured annotation stress journey: one
  attempt failed before Copy and a retry failed Review telemetry quiescence.
  The failure was outside arrangement scope; a bounded diagnostic was prepared
  but not applied pending owner approval. The earlier `94e85dd5f` green
  aggregate and native arrangement proof remained valid distinct evidence.

## Main alignment and sidebar core design — lines 29–31

- **Line 29 — delivery resume:** The exact-head local aggregate passed after
  unchanged retries, while live GitHub reported a Swift failure and a main
  conflict. PR345 remained unmerged at `3bb6378d6`; the sidebar source was not
  started and preview preparation remained open.
- **Line 30 — main alignment:** Latest `main` was merged and pushed into PR345,
  then into the dependent sidebar branch without history rewriting. The
  main-aligned aggregate passed as recorded above, with setup and focused proof
  green. Source-grounded sidebar Specification/Program Design candidates were
  prepared in `tmp`; cold preview remained open. A named Opus cold resume was
  submitted with response pending, so no successful Opus result was claimed.
- **Line 31 — core design admission:** Independent core review and dispel
  completed read-only. The accepted CORE-1 finding corrected RowID-only removal
  fallback: destination identity must be remapped through regrouping first, then
  actual-removal fallback applied. The parent-verified correction introduced no
  new stores, atoms, events, coordinators, or policy decision. Core design is
  ready for bounded planning; preview cold-content restoration and
  renderer/geometry/cancellation realization remain open, and no core
  implementation, automated/native/performance proof, or PR gate is claimed.

## Gaps and accounting

All 31 JSONL records were readable. No malformed line or invalid in-range
`corrects_line` target was found. Corrections at lines 6, 10, 11, and 19, plus
the parent-verified design correction recorded at line 31, are represented.
Evidence pointers to normative `docs/specs` files and external GitHub state were
not independently opened under this bounded rendering assignment. This view
does not rerun any evidence named by a record.
