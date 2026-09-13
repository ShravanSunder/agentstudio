# Keyboard sidebar and coherent arrangement visibility — Requirements

Owner: Shravan. Authority: explicit choices and corrections in this conversation,
2026-09-11/12. This is the single Requirements home. The [keyboard map](keyboard-map.md)
is the current human review entry point. Historical discussion and withdrawn
contracts are outside that review path.

## Goal and boundary

Make the existing sidebar a usable visual keyboard navigator, with deliberate
focus/hint behavior and reliable pane visibility. Users include keyboard-oriented
Agent Studio users and the owner seeking less hand strain. No medical benefit is
claimed. The system must not depend on a second invisible navigation stack.

Current scope: sidebar focus, surface selection, filtering, rows/groups, numbered
results, temporary pane preview, committed activation/return; direct pinned-pane
arrows; arrangement navigation and creation/reveal coherence. Existing terminal,
Bridge, webview and drawer pane identities remain the foundation.

Explicitly removed: activity-stack and visit-history navigation, their held-order
machinery, a sticky sidebar navigation-owner flag, large help panels, added header
rows and workspace dimming. Deferred: broad shortcut/chord restructuring, pin/rename
action bindings, viewer/annotation redesign and a finished-agent attention queue.
The sidebar activity-grouping bug is a separate source-only investigation, not a
proven fix or a definition of keyboard order.

The owner subsequently authorized Program Design and independent review, then
implementation of clear scope; independent settled sections may progress while
questions are collected. Numeric activation is settled. Preview restoration is not silently
selected by that delivery authority. New persistence,
new pane sessions, or app-wide state machinery are not automatically authorized by
preview. Existing command authority, focus ownership and feature boundaries apply.

## Needs and authority

All rows concern direct app users. Priority within current scope is unassigned by
the owner; this does not authorize omitting a requested need. “Proposed” details
are not promoted by appearing beside an authorized need.

| ID | Need/outcome | Authority and disposition |
| --- | --- | --- |
| U1 | Navigate with less hand effort and predictable feedback. | Authorized; current |
| U3 | Separate sidebar visibility from choosing its Repos/Panes surface. | Authorized; current |
| U4 | Enter sidebar keyboard navigation, reveal if hidden, and return to work. | Authorized; current; return defaults in Specification |
| U5 | Navigate/filter rows and groups, including first-nine result shortcuts. | Authorized; current; counting/live-update defaults in Specification |
| U6 | New panes appear in current arrangement and Default, without disturbing other custom arrangements. | Authorized; current |
| U7 | Reach a visible target through current/custom/Default fallback and parent/drawer reveal. | Authorized; current |
| U8 | Pin/unpin action by keyboard. | Authorized need; deferred action binding, distinct from U14 |
| U9 | Rename by keyboard. | Authorized need; deferred |
| U10 | Reach Review/Bridge and search their files. | Authorized broader need; redesign deferred |
| U11 | Reach repository file finder. | Authorized broader need; deferred; do not reinterpret F silently |
| U12 | A coherent command/shortcut system. | Current sidebar/arrangement slice; broad restructuring deferred |
| U13 | General visible follow-up action families. | Earlier assistant advisory proposal; not an app-wide requirement |
| U14 | Option-Shift-Up/Down from terminal switches previous/next pinned pane. | Authorized; current; ordering defaults in Specification |
| U15 | Temporarily show a selected pane in Preview; Enter takes the user there. | Owner's latest request; current; hold-to-preview and release-to-cancel selected; detailed placement open |
| U16 | Show sidebar keyboard ownership and contextual floating key hints within existing UI. | Authorized; current; exact visual/reveal details proposed |

Retired identity U2 is not reused: the owner removed activity/history traversal.
Its historical wording is outside this current needs table.

Evidence for U1 and U3–U12: opening request and subsequent explicit scope corrections.
U14: owner selected Option-Shift-Up/Down and replaced activity/back-forward.
U15: latest request for a preview button showing the pane while picked, with Enter
taking the user there. U16: marked sidebar screenshot, Cursor video, and explicit
request for an overlay/layer. The video shows visual behavior, not configured
thresholds or input-event telemetry.

## Selected decisions

| Decision | Meaning |
| --- | --- |
| Command-S | Show/hide sidebar; preserve selected surface |
| Command-Shift-S | Reveal sidebar if hidden and give it keyboard focus; do nothing while Management is active |
| P / R with list focus | Select Panes / Repos |
| F | Enter the existing current-list filter; viewer search stays separate |
| Filter Enter | Keep query/results and focus table; do not open a result |
| Digits 1–9 | Address first nine list results; open the numbered result immediately |
| Option-Shift-Up/Down from terminal | Direct previous/next pinned-pane navigation |
| Creation | Current arrangement plus Default visible; unrelated custom arrangements do not reveal new pane |
| Committed reveal | Current if visible; otherwise first visible custom in arrangement order; otherwise Default |
| Drawer destination | Reveal parent, expand drawer and reach child |
| Preview versus commit | Hold a preview key to inspect; release cancels uncommitted preview; Enter commits |

## Source constraints and review gaps

Effective keyboard ownership is derived from real focus, key window and active
surface. Sidebar focus also covers filter input today, so list command handling
must inspect actual responder context. No independent navigation-owner Boolean.
Selected row, return target and temporary preview state are distinct interaction
data; their existence is not permission to duplicate keyboard ownership.

The native table currently rejects/deselects row selection. Filter onSubmit exists
in the shared field but is not wired by the sidebar. Pane activation mutates tab,
arrangement/minimization and focus; it is not an established reversible preview.
The pre-change arrangement baseline inserted into all arrangements and revealed by
membership before visibility. Its separate reviewed correction is now implemented
with full aggregate and native reveal proof. Source pointers live in the map.

The core Specification now makes ordinary selection/group/return/pinned defaults
concrete; [provenance](core-design-decisions.md) distinguishes those decisions from
explicit owner answers. Preview cold-content restoration remains the material open
question. Core review and implementation may progress independently, while U15
remains in the delivery goal.

Proof expectation: native keyboard journeys through list/filter/pane focus and
real terminal/Bridge/drawer destinations, state inspection for arrangement visibility,
and preview cancellation/commit evidence. Sidebar implementation and native proof
remain outstanding. The separate U6/U7 arrangement capability has bounded design
review and focused implementation checks; [implementation review](arrangement-implementation-review.md)
found an R-A4 renderer-reattachment gap. The owner explicitly deferred that general invariant to a separate discussion and PR after this arrangement PR. Full aggregate validation and native main/Bridge/ordinary drawer reveal have now passed; the deferred invariant is not claimed fixed.
