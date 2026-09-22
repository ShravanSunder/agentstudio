# Keyboard Navigation Work Trail

Source: [events.jsonl](./events.jsonl). **Covers events.jsonl through line 27.**
This view renders the bounded prefix only; event evidence pointers are recorded
claims, not independent verification.

## Context and design decisions

- **Lines 1–3 — scope and source model:** The work began as a documentation-only
  keyboard-navigation discussion in this checkout, centered on reduced hand
  strain. Activity navigation, sidebar visibility/focus/surface, and arrangement
  reveal were separated because the source showed distinct operations and a
  visibility mismatch. Requirements were recorded while history versus
  recent-list traversal, priorities, bindings, arrangement edge cases, and the
  conflict audit remained open. No implementation or specification readiness was
  claimed. The record also notes an LFS sandbox error during whole-worktree
  status inspection; no repair was attempted.
- **Lines 4–8 — consultation and focus correction:** An annotation-agent request
  was accepted; an initial discovery address was rejected without mutation, the
  return address was corrected, and the reply was later received. The reply's
  bounded source claims were recorded at annotation checkout HEAD
  `35de69e01505d75e1ee6f52d998af5bb3f5a6678`; broader traversal and native-proof
  gaps remained open. The owner first defined “last active pane” as the last
  focused pane (line 5), then line 6 **corrected/reopened that interpretation**:
  settled-output activity, visit recency, and current focus are separate, and
  focus alone does not refresh output activity. The navigation contract stayed
  open.
- **Lines 7–8 — keyboard map and annotation boundaries:** A visual keyboard map
  was created, preserving Option-I/K drawer navigation after the owner corrected
  the proposed modifier. It recorded current bindings and open proposals without
  finalizing behavior. Annotation search, editing, Escape, editor-return, action
  matching, and gutter behavior were incorporated with their source-version and
  verification boundaries; no new behavior was approved.
- **Lines 9–11 — owner choices and correction:** A bounded three-artifact design
  cycle accepted all-window activity/visits, Shift-Option families, a stable
  held-modifier sequence, Current plus Default creation, and Current/Custom/
  Default reveal with parent-drawer expansion. Line 10 **reopened** the
  activity-ranking and Bridge-exclusion contracts for a separate sidebar-group
  investigation while retaining all-window reach, stable sequencing, immediate
  focus, and arrangement rules. Line 11 then **replaced separate last/next
  traversal with visual sidebar navigation**: Cmd-S controls visibility and
  Cmd-Shift-S controls activation, with the workspace remaining visible and an
  indication shown. P/R/F meanings, filter and type-ahead behavior, row
  activation, return behavior, and the surface-local hint treatment remained
  proposals. The source-only activity investigation did not reproduce the live
  symptom.
- **Lines 12–15 — scope, interaction, and preview:** The scope tree retained
  sidebar navigation, direct Terminal pinned-pane Option-Shift-arrow movement,
  and arrangements; activity/history traversal and the bulky help strip were
  discarded. Contextual hints were discussed from the supplied video (row
  timestamps replaced by trailing shortcut pills; top actions gained pills),
  while the exact reveal trigger remained open. Source validation recorded
  effective focus, table-selection rejection, the Cmd-Shift-P conflict, and the
  rejection of icon-implied state, free native-list behavior, repository/pane
  pin conflation, unsupported usage claims, and unapproved digit addressing.
  The working design added filter Enter-to-table and first-nine actionable list
  results (digits remain text while filtering), but mapping details stayed
  proposed. Review documents were cleaned up, and U15 separated temporary pane
  preview from committed reveal by Enter; hold/toggle and numeric
  select-versus-activate remained open. No source changes or full design
  acceptance were claimed.

## Arrangement implementation and proof

- **Lines 16–18 — design handoff and Core/App slices:** After independent design
  review and dispel work, arrangement visibility proceeded while sidebar preview
  questions stayed open. The documented checkpoint was `aacd4171b`, aligned with
  main merge `96e7dbb`; setup/vendor verification and the baseline focused tests
  were recorded as passing. The Core slice began after an expected missing-API
  RED; MainActor set construction and validation concerns were caught before
  acceptance. Core proof was then recorded as 46 tests / 4 suites green, with
  targeted formatting, SwiftLint, and diff checks passing, and the App sidekick
  was granted focus-sequencing work. These entries made no full-feature, native,
  or PR-readiness claim.
- **Line 19 — creation-scope correction:** Generic insertion also serves move,
  undo, and reactivation, so applying the creation rule there exceeded scope.
  Reveal validation was kept off MainActor. A second program review and dispel
  completed, and an immutable v2 plan was admitted. The earlier Core 46-test
  result was explicitly corrected: it did **not** prove production birth routing;
  fresh proof was required. Core correction and App sequencing continued in
  disjoint files, while preview/digit choices remained pending.
- **Line 20 — scoped checkpoint:** Production creation routing, existing identity
  preservation, and committed focus ordering were reported passing in focused
  checks at commit `ad92f6495`. Recorded results were App 150 tests / 40 suites,
  Core 64 / 7 (including SQLite roundtrip), webview creation 15 tests, and the
  corrected Bridge rerun 8 tests / 2 suites. Hooks passed. The full aggregate was
  delegated, with native proof and independent implementation review still
  pending. A rowless-host sidebar focus issue and a Management policy question
  were queued; no new owner choice was assumed.
- **Line 21 — aggregate gate and permission boundary:** `mise run test` remained
  failed with exit 1 on `ad92f6495` because
  `GhosttyEventRoutingCoverageTests` could not find the upstream vendor header
  `vendor/ghostty/include/ghostty.h`. Swift lint/architecture, BridgeWeb, and
  website lanes passed. A test-only lookup patch was prepared, but owner
  permission was pending under the scope gate; no test or vendor edit was made.
  A minimal generic-minimization preservation correction was granted to Core,
  while native proof and independent review remained open.

## Historical checkpoint at line 22

At line 22, the implementation checkpoint was `0e17351e1`. The latest recorded Core
focused proof is 82 tests / 8 suites green; prior App 150 / 40 and Bridge 8 / 2
results plus webview creation 15 remain recorded, and fresh lint and isolated
debug startup/telemetry passed. The full aggregate is still blocked by the
unrelated upstream header lookup described above.

The independent review accepted a design-assumption failure in R-A4: a selected
unminimized drawer child can remain renderer-detached when an already-open
physical drawer causes the toggle/expansion actions to be skipped. The review
states that selection and AppKit responder focus do not prove renderer exposure;
the existing reattachment lifecycle action must be reconverged with the owner
before implementation. See [arrangement implementation review](./arrangement-implementation-review.md)
and [drawer reveal design gap](./drawer-reveal-design-gap.md). No remediation was
  applied. R-A1/R-A2 have focused proof; R-A3/R-A5 have policy/integration evidence;
  R-A4 realization is incomplete; native reachability remains unproven.

Native capture is blocked by a locked macOS GUI. CUA stalled for 3973 seconds;
the subsequent Opus continuity recovery reported zero cached reads, so cache
warmth was lost. The retained sessions were not restarted. Owner permission for
the drawer correction and targeted third design review is queued, as are the
unrelated header-lookup correction and the sidebar Preview/Digit/Management
choices. No sidebar source implementation is claimed.

There is no push, pull request publication, merge into main, or release in this
prefix. The recorded normal main-to-branch merge remains part of the history.
The permitted session detail is [agent-session.md](./agent-session.md); other
evidence paths named by the events were not opened while rendering this bounded
view.

## Subsequent decisions and validation — lines 23–26

- **Line 23:** The owner selected hold/release preview, immediate digit activation,
  and Cmd-Shift-S no-op during Management. The general drawer attachment invariant
  was deferred to a separate discussion/PR after this PR. The approved Ghostty
  header lookup fix was committed with focused proof. Ancestry, vendor pins and
  shared links matched main. A Bridge bootstrap failure passed unchanged on retry.
- **Line 24:** The direct Swift invocation timed out at its60-second inactivity
  default; post-termination status15 assertions were not independent failures.
  The canonical aggregate already uses600seconds. The unchanged large-group
  reproduction passed; no runner or vendor repair was justified.
- **Line 25:** The canonical aggregate passed the former timeout point but failed
  the real FSEvents test's initial authority renewal, before deletion. That test
  passed unchanged in isolation; no concrete fix was established. Native main-pane
  creation, custom reveal and Default fallback were demonstrated with input markers.
- **Line 26:** `MISE_RAW=1 mise run test` passed at `94e85dd5f`, exit0:8338Swift
  tests plus35architecture-tool tests, with web/lint gates passing. The earlier
  failures remain recorded and are not claimed fixed. Native collapsed-drawer
  reveal and exact-child input delivery also passed.

## Current outcome

The required suite is green. Native proof covers new main panes appearing in
current+Default while another custom remains unchanged, sidebar activation into
a visible custom, Default fallback, and expansion/focus of a collapsed drawer child.
Unexecuted markers provided observable destination-terminal input evidence.

Bridge native proof remains incomplete: background Return dispatch did not execute
the displayed directory-change command. No foreground activation was attempted;
the repository requires preserving the user's foreground. A narrow foreground
permission is the next owner question. This is not evidence of a Bridge defect.

The detached-child cross-arrangement invariant remains an accepted, unfixed issue
explicitly deferred to a separate PR. Ordinary collapsed-drawer proof does not
establish that invariant. Sidebar source implementation remains outstanding.
No push, PR publication, merge into main or release is claimed.

Details: [native interaction proof](../../../tmp/sidebar-keyboard-design/arrangement-native-interaction-proof.md)
and [timeout investigation](../../../tmp/debug-workflows/2026-09-12-arrangement-suite-timeout/debug-investigation.md).
These summarize parent-recorded evidence; this reading view does not independently
rerun or verify it. All26JSONL records parse. No malformed record or invalid
correction pointer was found. The delegated view assignment returned no receipt
within the bounded wait and was interrupted; the parent updated this view directly.

## Line27 — foreground Bridge proof and continued delivery

Owner approved foreground input for the isolated debug app and asked to continue
and finish. Watch Folder registered the checkout; Files loaded5016items. Minimizing
Files inLayout2 then activating its sidebar row selectedLayout1 and restored the
same viewer. Clicking Search and typingREADME produced11matches. The foreground
permission/native reveal blocker is resolved. Baseline native-container-to-DOM
shortcut focus remains a separate sidebar-keyboard design issue. Supplemental
8-test-file spec compliance passed; code/proof review is still running. No PR-ready
claim, publication or merge. The general detached-drawer invariant stays deferred.
