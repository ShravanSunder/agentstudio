# Keyboard Navigation Work Trail

Source: [events.jsonl](./events.jsonl). **Covers events.jsonl through line 50.**
This is a bounded Markdown view. Event evidence pointers and the four permitted
detail records are rendered as recorded claims, not independently verified
external evidence.

## Context and superseded design decisions

- **Lines 1–3 — scope and source model:** The work began as a documentation-only
  keyboard-navigation discussion in this checkout, centered on reduced hand
  strain. Activity navigation, sidebar visibility/focus/surface, and arrangement
  reveal were separated because the source showed distinct operations and a
  visibility mismatch. Requirements were recorded while traversal, priorities,
  bindings, arrangement edge cases, and the shortcut-conflict audit remained
  open. No implementation or specification readiness was claimed. An LFS
  sandbox error during whole-worktree status inspection was recorded; no repair
  was attempted.
- **Lines 4–8 — consultation and live-focus correction:** An annotation-agent
  request was accepted; an initial discovery address was rejected without
  mutation, the return address was corrected, and the reply was later received.
  The bounded reply claims were tied to annotation checkout HEAD
  `35de69e01505d75e1ee6f52d998af5bb3f5a6678`, with broader traversal and
  native-proof gaps still open. The owner first defined “last active pane” as
  the last focused pane (line 5). Line 6 **corrected/reopened** that
  interpretation: settled-output activity, visit recency, and current focus are
  separate, and focus alone does not refresh output activity. The navigation
  contract stayed open.
- **Lines 7–8 — keyboard map and annotation boundaries:** A visual keyboard map
  preserved Option-I/K drawer navigation after the owner corrected the modifier.
  It recorded current bindings and proposals without finalizing behavior.
  Annotation search, editing, Escape, editor return, action matching, and
  gutter behavior were incorporated with source-version and verification
  boundaries; no new behavior was approved.
- **Lines 9–11 — owner choices then replacement:** A bounded three-artifact
  design cycle accepted all-window activity/visits, Shift-Option families, a
  stable held-modifier sequence, Current plus Default creation, and
  Current/Custom/Default reveal with parent-drawer expansion. Line 10
  **reopened** activity-ranking and Bridge-exclusion contracts for a sidebar
  group investigation while retaining all-window reach, stable sequencing,
  immediate focus, and arrangement rules. Line 11 then **replaced separate
  last/next traversal with visual sidebar navigation**: Cmd-S controls
  visibility and Cmd-Shift-S controls activation, while the workspace remains
  visible with an indication. P/R/F meanings, filtering versus type-ahead, row
  activation, return behavior, and surface-local hints remained proposals. The
  source-only activity investigation did not reproduce the live symptom.
  Earlier activity/history mappings are historical and superseded.
- **Lines 12–15 — scope, interaction, and preview:** The scope tree retained
  sidebar navigation, direct Terminal pinned-pane Option-Shift-arrow movement,
  and arrangements; activity/history traversal and the bulky help strip were
  discarded. Video-based contextual-hint discussion recorded trailing shortcut
  pills in place of row timestamps and pills on top actions, while the exact
  reveal trigger remained open. Source validation recorded effective focus,
  table-selection rejection, the Cmd-Shift-P conflict, and rejection of
  icon-implied state, free native-list behavior, repository/pane pin conflation,
  unsupported usage claims, and unapproved digit addressing. Filter
  Enter-to-table and first-nine actionable results entered the working design,
  but mapping details stayed proposed. Review cleanup separated temporary pane
  preview from committed reveal by Enter; hold/toggle and numeric
  select-versus-activate remained open. No source changes or full design
  acceptance were claimed.

## Arrangement history and proof boundaries

- **Lines 16–22 — arrangement slices and the drawer gap:** Arrangement
  visibility proceeded while sidebar preview questions stayed open. The
  documentation checkpoint was `aacd4171b`, aligned with normal main merge
  `96e7dbb`; setup/vendor verification and baseline focused tests were recorded
  as passing. Core work began after an expected missing-API RED, with MainActor
  set construction and validation concerns caught before acceptance. Core 46
  tests / 4 suites were recorded green, and App focus-sequencing work was
  granted. Line 19 corrected the scope model: generic insertion also serves
  move, undo, and reactivation, so birth-only behavior must be separated and
  reveal validation stays off MainActor. It explicitly corrected the earlier
  proof: Core 46 did not establish production birth routing. At `ad92f6495`,
  focused results recorded App 150 / 40 suites, Core 64 / 7, webview creation
  15, and Bridge 8 / 2. The aggregate then failed on the missing upstream
  Ghostty header. At `0e17351e1`, Core 82 / 8, fresh lint, and isolated startup
  were recorded, alongside an accepted R-A4 gap where an unminimized drawer
  child can remain renderer-detached when an already-open drawer skips
  toggle/expansion. No remediation was applied; that detached-drawer invariant
  remains deferred.
- **Lines 23–27 — correction, timeout, and native arrangement evidence:** The
  owner selected hold/release preview, immediate digit activation, and
  Management precedence, while deferring drawer-invariant repair to a separate
  discussion/PR. The approved Ghostty-header fix committed `1c73f89d3`; focused
  checks passed and vendor pins matched main. A direct Swift timeout was
  diagnosed without changing runner defaults; the canonical timeout and serial
  groups later passed. An initial exact-item aggregate failure at unrelated
  real-FSEvents renewal was preserved as history. Native arrangement evidence
  then recorded Current plus Default creation, custom preservation, visible
  custom reveal, Default fallback, collapsed-drawer reveal/input, and target
  terminal input. The aggregate at `94e85dd5f` was recorded green with 8338
  Swift and 35 architecture tests. Line 27 completed isolated foreground Bridge
  native reveal proof (Files topology, minimization, sidebar
  activation/restoration, and README search), with the outer-native-mount
  shortcut-focus limitation tracked; supplemental file-spec review had no
  findings. These records did not establish PR readiness.
- **Lines 28–31 — publication failure and branch alignment:** A source-identical
  publication attempt at `3bb6378d6` failed external annotation stress (Copy
  unavailable on one attempt; Review quiescence failed on retry), although the
  earlier green aggregate/native evidence remained valid as separate historical
  evidence. The diagnostic patch was prepared but not applied. The prior
  approval-pending stop for that unrelated diagnostic is historical: line 46
  records the updated scope gate permitting a controlled-domain annotation
  diagnostic, and says it was applied without behavior or assertion changes.
  PR345 was then aligned with latest main: arrangement head `1a467a120` had
  focused 35 / 7 and a recorded full aggregate of 8356 Swift, 358 summaries,
  and 35 architecture tests. Sidebar core design candidates were admitted for
  planning, but no sidebar source implementation was present; U15 cold-preview
  restoration and the detached-drawer invariant remained open/deferred, and
  Opus/Router resume attempts were not claimed successful.

## Sidebar and terminal delivery

- **Lines 32–34 — settled choices and visible spatial behavior:** Space preview
  was defined to fill the pane, follow selection, load existing panes as needed,
  and never start a replacement terminal session. Pinned order follows the
  sidebar and wraps. Terminal directions were set to Cmd-Shift J/L at 90%,
  Option-Shift J/L at 25%, and Cmd-Shift I/K for previous/next Ghostty prompts;
  Option-Shift K for absolute bottom remained proposed, while Option-Shift
  arrows remained pinned traversal. Spatial Option-J/L must skip hidden or
  minimized panes. U18 was implemented through visibility projection and
  canonical row-neighbor lookup, with 67 focused tests passing across five
  suite runs; lint found three existing dirty-sidebar-core issues and recheck
  was underway. Manual app proof, current aggregate, and remaining sidebar
  delivery were not claimed complete.
- **Lines 35–37 — terminal v2 implementation and native evidence:** The settled
  seven-key terminal family was implemented with a missing-Ghostty-source guard.
  Its intended RED exposed 7 cases / 21 issues; the narrow runtime guard then
  passed all 16 Ghostty tests, and IPC metadata/fingerprint checks passed. A
  refreshed fingerprint was accepted only after readable metadata and old-ID
  absence assertions passed. The rebuilt isolated app recorded fresh 68-row
  numbered output, 22-row and 61-row movement in both directions, bottom
  clamping, previous/next actual shell prompts, and Cmd-Option-K bottom
  behavior. All seven keys targeted the same terminal and retained Default. See
  [terminal native v2 proof](./terminal-native-v2-proof.md). This is terminal
  implementation and native evidence, not a claim that terminal delivery or the
  broader keyboard goal is done; the bounded work remains ongoing.
- **Lines 38–39 — filter-focus correction:** A real production SwiftUI journey
  reproduced a filter Return bug: a redundant FocusState-clearing callback
  displaced list focus, so F/Escape failed. Removing that callback passed the
  focused correction and native empty/populated filter journeys without adding
  delay, retry, observer, or extra focus state. The aggregate failure at Bridge
  annotation stress (Review settling and Copy unavailable) was preserved as an
  external failure; no unrelated repair was made. The correction recorded 9
  tests / 3 suites and native Enter/Down/Escape, hidden visibility, origin
  restoration, and Management no-op. Rapid F-then-type before focus settles
  remained unproven at this point; the permitted focus detail records a later
  rapid-entry check with established list focus, without inferring fully
  synchronous initial entry.
- **Lines 40–42 — index, reconciliation, and overlay preparation:** The
  immutable navigation index was accepted with direct per-key lookups that skip
  static/fault rows and preserve pane/worktree identity; its RED was 6 tests /
  41 issues, followed by 31 tests / 5 suites passing and a 6-test fixture
  reproof with lint/diff clean. UI wiring was not yet claimed. Semantic
  selection reconciliation then passed 12 tests / 2 suites with lint/diff
  clean, preserving exact RowIDs, same-destination translation, and prior-order
  fallback; native Option-L hidden-neighbor behavior and visible Option-J/L were
  recorded, while UI remained unwired. Overlay validation continued under sole
  proof ownership, with historical 55-test/8-suite and 73-test/13-suite
  receipts retained and fresh overlay proof still pending.
- **Lines 43–46 — native overlay, focus hydration, pinned order, and guards:**
  Bounded native overlay evidence recorded ordinary entry, filtering, Enter,
  digit-8 drawer activation, digit-9 offscreen worktree activation, group
  navigation, Bridge/custom reveal, overlay fit at 250/436 points, and no
  projection-counter increase during 40 selection keys. A presentation-value
  correction was the only source correction in that slice. A later production
  focus-hydration regression found that post-presentation restoration cleared
  the runtime focus fact; its RED was 8 tests (6 pass, 2 fail / 6 issues), then
  the corrected GREEN was 38 tests / 6 suites with the exact list-focus
  handshake and no persistence, atom, mode, or preview change. Shared Panes and
  pinned ordering extraction then recorded Safe RED 8 / 17 issues, GREEN 73 / 7
  suites, and corrected actual-suite integration 50 / 3 suites; initial fixture
  failures were corrected without a product-contract change. This was an
  interim checkpoint before line 46 connected the shared-order/raw-capture path
  through composed pinned projection, App, and regression lanes.
  Finally, line 46 recorded composed pinned projection/App/regression lanes
  green (2 / 2 / 31), while the App RED remained 2 tests with 1 pass, 1 fail /
  6 issues. Availability complexity, stale/native-text tests, IPC fingerprint
  delta, native pinned proof, aggregate, and independent review were still
  incomplete. The controlled-domain annotation diagnostic was applied under the
  updated scope gate; it changed no behavior or assertions.

- **Lines 47–50 — pinned native proof, diagnosis, alignment, and current
  boundary:** Native pinned effects were observed across terminal, drawer, and
  Bridge routes. App/IPC focused proof recorded 9 tests / 2 suites with quality
  and diff clean. A full aggregate attempt recorded 4863 Swift / 715 suites
  with one stale private-property spelling issue, while web lanes passed and
  telemetry initially failed 25 tests / 6 issues because the requested labels
  were outside the closed taxonomy. The exact two-phase/one-trigger admission
  and complete dimensions were corrected; the taxonomy reproof passed 29 tests
  / 3 suites with quality clean, but live timing remained unproven. A subsequent
  aggregate rerun failed before Copy at Review metadata readiness and annotation
  save; no timeout, retry, or assertion weakening was introduced, and the cause
  was not established. The temporary diagnostic was removed before the clean
  merge checkpoint.
- **Lines 49–50 — main alignment and delivery boundary:** Two signing attempts
  failed, so unsigned checkpoint `2c58e3484` was recorded with hooks passing,
  followed by clean merge `990c947db` and main alignment. At committed
  main-aligned head `10383d28f`, the full `mise run test` passed, and native
  sidebar, terminal, and pinned effects were recorded. The latest result is
  explicitly **partial/blocked**: fresh live telemetry was unavailable through
  CUA (`cgWindowNotFound`), independent final implementation review and
  publication were incomplete, and no PR-ready claim was made. The updated scope
  gate permitted and line 46 applied the controlled annotation diagnostic; the
  earlier approval-pending stop is historical. No new atoms, stores, events, or
  vendor changes were recorded.

## Current outcome and unresolved work

The bounded trail ends with work ongoing and no terminal-wide completion claim.
Terminal v2 has implementation and native movement evidence, and the sidebar
index/reconciliation, overlay, focus, and composed pinned paths have focused or
native evidence. The committed main-aligned head `10383d28f` has a recorded full
`mise run test` exit 0. Earlier external Bridge annotation stress failures and
the later annotation rerun failure remain historical/current proof-boundary
records; the latest result still says whole delivery is partial/blocked because
fresh telemetry, independent final review, and publication are incomplete. No
PR-ready claim is made.

Preview remains pending at the safe implementation boundary. The confirmed rule
is to load an existing pane's renderer as needed without starting a replacement
terminal session. The existing zmx attach path can create a daemon and shell
when the saved session is absent or refuses attachment, so exact session identity
alone cannot guarantee existing-pane-only preview. The permitted [preview
boundary](./preview-existing-session-boundary.md) records that an attach-only
prerequisite or follow-up is awaiting scope agreement; no vendor change is
authorized by that detail. The detached-drawer invariant is separately
deferred and unfixed.

The navigation index/reconciliation work has recorded focused proof. Line 46
records composed pinned projection, App, and regression lanes green (2 / 2 / 31)
while retaining an App RED at that checkpoint; line 47 then records App/IPC
focused proof and native pinned effects. The committed line-50 result leaves
fresh live telemetry, final guards/catalog review, independent final review,
publication, and the preview scope decision open. Rapid initial filter typing
remains bounded by its proof record. No claim is made that sidebar or terminal
delivery is complete.

Source gaps in this bounded render: no malformed event lines, missing permitted
detail files, or invalid in-range correction links were found. Other paths named
as evidence by the events were not opened, and no external evidence was verified
while rendering. The prefix records pushes and branch merges, including main
alignment; it does not record final PR publication, merge into main, or release
completion.
