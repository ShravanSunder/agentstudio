# Keyboard Navigation Trail

Source: [events.jsonl](./events.jsonl). Covers events.jsonl through line 15.

## Context

The session is a documentation-only keyboard-navigation discussion in the
`agent-studio.navigation-cmds` checkout. The central need recorded in line 1
is reduced hand strain; bindings remain proposals.

## Decisions and checkpoints

- **Line 1 — WIP scope:** Keep the requirements and work trail under this
  keyboard-navigation directory. No implementation was authorized or claimed.
- **Line 2 — Source distinction:** Treat activity navigation, sidebar
  visibility/focus/surface, and arrangement reveal as separate operations.
  The record reports shortcut and arrangement mismatches, with no native proof
  attempted. It also records an LFS sandbox error during whole-worktree status
  inspection; no repair was attempted.
- **Line 3 — Requirements draft:** Record explicit needs, while leaving history
  navigation versus recent-list traversal as the first owner choice. The
  requirements document is an initial draft: scope, priorities, exact
  bindings, arrangement edge cases, and the full shortcut-conflict audit remain
  open at this checkpoint; line 9 later records traversal and scope choices,
  which lines 10–11 subsequently reopen and replace for traversal. No
  specification readiness is claimed.
- **Line 4 — Consultation:** An annotation-agent message was **accepted** and
  its **reply was pending at that point**. The record says discovery required
  escalation, the first send used a rejected recipient-address shape, without
  mutation, and the accepted request carried a return-address field needing
  correction. A follow-up corrected that return address. It makes no claim
  about annotation behavior; line 8 later records the reply as received.
- **Line 5 — Owner decision:** “Last active pane” was defined as the pane the
  user last focused. Background activity was excluded from navigation ordering;
  history versus recent-list traversal remained open at this checkpoint. Line 9
  later records accepted traversal choices, which lines 10–11 supersede. No
  implementation was claimed.
- **Line 6 — Correction to line 5:** The focus-only interpretation was reopened
  after distinguishing existing terminal activity from visit recency. Source
  inspection recorded settled-output timestamps, visit recency, and the
  currently focused flag as separate concepts; mere focus does not refresh
  output activity. The navigation contract remained open, with no source
  changes or runtime proof.
- **Line 7 — Visual discussion artifact:** The owner corrected the drawer
  modifier to preserve Option-I/K drawer movement and requested a whole-system
  keyboard map. The new map records current bindings, the correction, distinct
  activity and visits, sidebar focus/surface/visibility, arrangement rules, and
  remaining action/finder needs. The Shift-Option proposal remains unselected;
  no implementation or finalized mapping was claimed.
- **Line 8 — Annotation evidence:** The annotation reply was received, resolving
  the earlier pending status. The record says the parent inspected the reply's
  bounded source claims at annotation checkout HEAD
  `35de69e01505d75e1ee6f52d998af5bb3f5a6678`, including search
  bindings/restoration, composer save/Escape, action matching, editor return,
  and gutter source. The broader traversal and native-proof gaps remain
  attributed to that agent; the map and requirements were updated, with no new
  behavior approved.
- **Line 9 — Design-owner confirmation:** A bounded three-artifact design cycle
  began after the owner invoked `orchestrator-design`. The owner accepted
  all-window activity and visits, Shift-Option families, Bridge visits only, a
  stable held-modifier sequence, creation in Current plus Default, and reveal
  in Current/Custom/Default with parent-drawer expansion. Chords and sidebar
  restructuring were deferred. Existing Requirements will be reused, with
  separate Specification and Program Design homes under `docs/specs/`.
  The traversal choices from this line were later superseded by line 11;
  arrangement choices remain retained. No code changes or design readiness were
  claimed.
- **Line 10 — Correction and investigation:** Activity-specific traversal was
  reopened, with sidebar activity groups investigated separately. The earlier
  activity-ranking and Bridge-exclusion contracts were reopened, while
  all-window reach, the held stable sequence, immediate focus, and arrangement
  rules were retained. The investigation was source-only and delegated; no app
  mutation, code fix, or runtime diagnosis was claimed. Line 11 later replaces
  this traversal framing.
- **Line 11 — Sidebar-first correction:** Separate last/next traversal was
  replaced by visual sidebar navigation. **Selected:** Cmd-S controls sidebar
  visibility, Cmd-Shift-S controls activation, and the workspace stays visible
  with a visible indication. **Pending/proposed:** the meanings of P/R and F,
  the surface-local navigation mode and hint strip, F as a list filter, row
  activation, and return behavior. The map removed obsolete activity/history
  traversal diagrams; the activity-group investigation produced source-only
  findings and did not reproduce the live symptom. No source changes were made.
- **Line 12 — Scope and visual reference:** The current scope tree keeps
  sidebar navigation, direct pinned-pane Option-Shift-Up/Down movement from
  Terminal, and arrangements. Activity/history traversal was discarded, and
  the bulky help strip was rejected. Contextual-hint discussion instead uses
  the supplied video reference: trailing shortcut pills replace row timestamps
  and top actions gain pills. Pinned-pane Option-Shift-arrow movement is
  selected; the exact reveal trigger remains a proposal. Video temporal
  analysis was delegated. No implementation was claimed.
- **Line 13 — Source validation and holistic correction:** Derived focus and
  table-selection rejection were verified. The design rejects an icon implying
  a second state, free native-list behavior, repository/pane pin conflation, an
  unsupported 90-percent usage claim, and unapproved digit-address shortcuts.
  The exact Cmd-Shift-P conflict was documented. P/R/F are owner-selected, with
  filtering versus type-ahead recorded as an explicit tradeoff. The proposed
  complete interaction has no sticky navigation flag. Source remained
  unchanged; no native proof or independent design acceptance was claimed.
- **Line 14 — Filter and numbered results:** The working design adds
  filter-Enter-to-table and first-nine list-result shortcuts. Enter is proposed
  to retain the query and focus the table without activating; digits activate
  only the first nine actionable results when the table has focus, while digits
  remain text in the filter. This is not pinned-only numeric addressing, and
  mapping details remain proposals. No source edits were made.
- **Line 15 — Review cleanup and preview:** The current map and Requirements
  were rewritten as a coherent review pair; duplicate sections and discarded
  traversal contracts were removed from the active review path, with history
  preserved outside it. Preview need U15 now separates temporary pane preview
  from committed reveal by Enter. Hold/toggle and numeric select-versus-
  activate remain visibly open. A bounded reader check found the current
  scope/preview distinction clear, and the parent verified document
  corrections. No implementation or complete three-artifact acceptance was
  claimed.

## Current outcome and gaps

Discussion and the bounded three-artifact design cycle continue. No
implementation, native proof, finalized design, or finalized keyboard mapping
is recorded in the covered prefix. The recorded evidence pointers were not
independently verified while rendering this bounded view, and no linked detail
files were authorized. The consultation message was accepted and its reply was
later received at line 8. **Selected:** Cmd-S visibility, Cmd-Shift-S
activation, a visible indication while keeping the workspace visible,
Option-Shift-Up/Down direct pinned-pane movement from Terminal, the retained
arrangement choices, P/R/F as owner-selected keys, filter Enter-to-table, and
the first-nine list-result direction. **Proposed/pending:** the filtering
versus type-ahead tradeoff, contextual-hint treatment, the exact reveal
trigger, the preview hold/toggle contract, numeric select-versus-activate, and
the complete interaction without a sticky navigation flag. Enter-to-table and
numbered-result mapping details remain proposals, and preview is separate from
Enter commit. The earlier activity/history traversal and bulky help strip are
discarded; the activity investigation was source-only and produced no live
diagnosis. No pinned-only numeric-address shortcut was approved. Native proof
and design readiness remain open. Later events, including
requirements/design resolution, are outside this cutoff.
