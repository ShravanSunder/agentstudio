> Historical archive — not current review or implementation authority. Relative links retain their original document context.

# Pane traversal and arrangement reveal

> **Superseded traversal direction:** the owner selected navigation through the
> visible sidebar and a chord for entering it, replacing the separate held
> activity/history traversal system. R1–R4 require replacement from the new
> sidebar decisions; they are not implementation authority. Arrangement decisions
> remain reusable. This draft is retained for traceability while sidebar behavior
> is discussed in the linked Requirements and keyboard map.

> **Activity contract reopened:** the owner clarified that the traversal should
> go through all panes. R1's terminal-activity assignment and R2's Bridge exclusion
> below record the earlier interpretation and are not currently authorized
> obligations. Their replacement ordering is being discussed. Do not implement
> this draft or infer exclusions from activity timestamps. The settled immediate
> movement and arrangement sections remain available for continued design work.

## Purpose and authority

Navigate work across Agent Studio windows without the destination order moving
under the user's hands, and reveal the chosen pane without unnecessarily changing
custom arrangements.

[Requirements](../../wip/2026-09-11-keyboard-navigation/requirements.md#current-design-cycle--owner-decisions-2026-09-12)
→ this Specification → Program Design (not yet authored).

The owner decisions dated 2026-09-12 authorize the obligations below. This draft
covers U1, U2, U6, U7 and the traversal portion of U12. Explicit open slots are not
requirements. Sidebar/chord restructuring, pin/rename keys, annotation changes,
search redesign, releases and implementation are outside this design cycle.

## The user journey

```text
Working in any pane
       |
Hold Shift + Option and press a traversal key
       |
Choose from a fixed order ──→ reveal destination window/tab/arrangement
       |                                   |
       |                             focus destination
       |                                   |
       +──── another traversal key ←───────+
                                           |
                                    release modifiers
                                           |
                                  continue work there
```

The relevant pain is unstable navigation order while panes produce new output
or receive focus. The desired change is repeated, predictable movement with one
held modifier combination. The ordered set must not change merely because the
user passed through a pane. U1/U2 authorize this outcome; comfort remains subject
to actual user interaction evidence, not a medical or latency claim.

```text
Keyboard ────────────→ [ Agent Studio ] ──→ destination across app windows
Pane click/search ───→ [              ] ──→ same arrangement reveal rule
Pane creation ───────→ [              ] ──→ current + Default visibility

Existing terminal output supplies activity evidence.
Other applications and sidebar/chord redesign are outside the boundary.
```

## Traversal contract

**R1 — Navigation families (C1).** Shift-Option-I/K MUST navigate terminal
activity; Shift-Option-J/L MUST navigate visits. The existing Option-I/J/K/L
spatial bindings and Command-Shift-I/J/K/L terminal navigation MUST retain their
existing roles. I denotes newer activity, K older; J denotes earlier visits, L
later visits. Basis: U2/U12, accepted proposed key family.

**R2 — Reach (C1).** Activity and visit traversal MUST span all application
windows, tabs and arrangements. Pane type MUST NOT exclude a pane from visits;
Bridge panes are included. Activity traversal MUST exclude Bridge panes and use
existing terminal activity evidence rather than invent a Bridge activity timestamp.
Drawer panes are targets, not merely proxies for their parent. Closed versus
temporarily unavailable destination handling is an open slot below. Basis: U2/U7,
all-windows, all-pane-types, and drawer answers.

**R3 — Stable held sequence (C2).** While the user continues one traversal with
Shift and Option held, new output or focus changes MUST NOT reorder that traversal.
Releasing the required modifier combination MUST end the held sequence. The next
sequence may use refreshed activity evidence. End-of-list and family-change behavior
are explicit open slots; no hidden timeout is selected. Basis: U1/U2, stable and
held-modifier answers.

**R4 — Immediate movement (C2).** Every successful traversal step MUST immediately
reveal and focus its destination, including the destination window when different.
Releasing modifiers MUST keep the final reached destination. There MUST NOT be a
chooser that defers the actual switch until release. “Immediately” distinguishes
per-keypress movement from release-to-commit, not a new numerical performance SLA.
Basis: U2, owner answer “immediately.”

## Arrangement contract

**R5 — Creation visibility (C3).** A newly created pane MUST be visible in the
arrangement where it is created and in that tab's Default arrangement. Creation
MUST NOT automatically reveal it in unrelated existing custom arrangements.
Creating in Default therefore reveals it in Default only among existing
arrangements. Default remains the complete tab arrangement; drawer structure is
preserved rather than flattening all children into main panes. Basis: U6, owner's
creation answer. Existing panes are not retroactively hidden by this rule.

**R6 — Main-pane reveal (C4).** For a target in a tab, if it is visible in that
tab's current arrangement, reveal MUST keep that arrangement. Otherwise it MUST
select the first custom arrangement in arrangement order where the target is
visible. If none qualifies, reveal MUST select Default. A minimized pane is not
visible for this selection. Other custom arrangements MUST NOT be expanded merely
to make them eligible. Basis: U7 and the accepted question-7 rule.

**R7 — Drawer reveal (C4).** A drawer target MUST have its parent revealed and
its drawer expanded before focus reaches the child. The final result MUST expose
the target child, not merely focus a parent while leaving the target hidden.
How child minimization affects arrangement eligibility is an open slot below.
Basis: U7, accepted question 8.

**R8 — Consistent entry points (C4).** Clicking/selecting a pane, selecting it
from search, activity traversal and visit traversal MUST use the same target
reveal rule. Spatial stepping remains a local movement operation, rather than
becoming cross-window navigation. Basis: U7/U12, accepted question 7 and preserved
spatial bindings. Programmatic targeting needs classification before public IPC
behavior is claimed.

## Concrete examples

| Scenario | Required observable result |
| --- | --- |
| Terminal produces new activity while a held sequence is moving through panes | Existing sequence order stays fixed |
| A visit target is a Bridge pane in another window | That window and pane receive focus on the step, before modifier release |
| New pane created in custom arrangement Work | Work and Default show it; other custom arrangements do not automatically show it |
| Target is visible in current arrangement | Stay in current arrangement |
| Target minimized here, visible in custom arrangement Two | Select the first eligible custom arrangement, which may be Two |
| Target is minimized in every custom arrangement | Reveal through Default |
| Target is in a collapsed drawer | Reveal parent, expand drawer, reach child |

## Open slots — do not silently choose

The first three are in a grouped owner question while design work continues.

| Slot | Exact missing meaning | Current recommendation / evidence |
| --- | --- | --- |
| D1 | Initial activity target when current pane is Bridge or has no activity timestamp | Start at newest eligible terminal; existing Activity has no focus-time fallback |
| D2 | Behavior at either end of activity/visit traversal | Stop at ends; wrapping is a credible alternative |
| D3 | Repeated visits: A → B → A → C becomes Back A → B → A, or unique recent panes A → B | Recommend literal visit history; existing recency stores only latest focus per pane |
| D4 | Switching between activity and visit keys without releasing modifiers | Resolve after D3; do not infer a mixed ordering |
| D5 | Destination closes, moves, or cannot be focused during a held sequence | Recommended skip unavailable target without closing/recreating panes; not yet owner-selected failure contract |
| D6 | Drawer child minimized in one arrangement but parent visible there | Must reach child under R7; distinguish expanding child here versus finding a custom arrangement already exposing it |
| D7 | App deactivation, other commands, and Escape while modifiers are held | End held sequence without undoing successful navigation is a candidate, not an accepted cancellation rule |
| D8 | Unknown-activity terminals, temporary zoom companions and non-workspace app windows | All actual pane types are requested; eligibility at these lifecycle boundaries needs source-grounded classification |
| D9 | Which focus transitions enter visit history, lifetime, and persistence across restart | Existing focus recency is evidence only; avoid inventing a new durable history requirement |

Draft scope is authorized; these gaps prevent an implementation-ready observable
contract. They do not prevent current-system inspection or completion of independent
contract sections. No unspecified behavior may weaken R1–R8.

## Need-to-proof coverage

| Need | Problem → outcome | Requirement / contract | Required proof modality |
| --- | --- | --- | --- |
| U1/U2 | Reordering and repeated effort → predictable held navigation | R1/R3/R4; C1/C2 | V1: automated ordered-input behavior plus real keyboard interaction across terminal and Bridge |
| U2 | Work spread across windows and pane kinds → destinations reachable | R2/R4; C1/C2 | V2: real multi-window journey, including a Bridge visit and drawer child; inspect focus and destination |
| U6 | New panes disrupt saved layouts → creation scoped to intended arrangements | R5; C3 | V3: arrangement-state inspection plus a runnable creation journey in Default and custom arrangements |
| U7 | Selection lands on hidden/minimized content → target actually visible | R6/R7/R8; C4 | V4: real reveal journeys through click/search/traversal, with parent/drawer/child visibility and focus evidence |
| U12 | Conflicting command families → consistent direct navigation | R1/R8; C1/C4 | V5: shortcut dispatch coverage and native checks preserving spatial and terminal shortcuts |

Proof must include held modifiers across window changes and modifier release after
focus enters embedded content. Synthetic key matching alone cannot establish that
journey. Native and embedded text entry must retain their existing local behavior
outside the explicitly selected commands; no annotation draft-discard or terminal
input rewrite is authorized. No new data collection, output retention, external
service, security privilege, schema migration, or global shortcut recorder is
required by this Specification. Any such structural proposal needs a separately
justified requirement and scope check.
