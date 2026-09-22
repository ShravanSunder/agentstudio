# Arrangement creation and committed pane reveal

[Requirements](../../wip/2026-09-11-keyboard-navigation/requirements.md) →
this Specification → [Program Design](program-design.md).

This capability realizes U6 and U7 independently of sidebar key selection and
temporary preview. A user creates a pane in a chosen arrangement, or activates
an existing pane through a committed navigation action. Creation should not disturb
other custom layouts; activation should reach visible content rather than a
minimized representation. Terminal, Bridge and other existing pane content types
follow the same visibility rule. A drawer child retains its parent relationship.

```text
Create pane in arrangement Work       Activate existing target pane
              |                                     |
Work + Default show it                current if visible
Other customs unchanged               else first visible custom in stored order
                                      else Default
                                             |
                                      reveal drawer as needed → focus target
```

The owner selected these outcomes in the arrangement answers. This Specification
does not select Preview, sidebar filtering/number keys, pinned ordering, a new
multiwindow architecture, new persistence, or changes to merge/move-pane semantics.
The broader Requirements retains those independent needs and their current status.

## Observable obligations

**R-A1 — Main-pane creation.** Inserting a new main pane into a tab MUST make it
visible in the current arrangement and Default. If current is Default, it is the
only existing arrangement changed to include the pane. Every unrelated custom
arrangement MUST preserve its layout, minimized set and active-pane selection.
The tab MUST continue to own the pane exactly once. Basis: U6. Contract C-A1.

**R-A2 — Drawer creation.** A new drawer child MUST be present and unminimized in
the current arrangement's drawer view and Default's corresponding drawer view.
Other custom arrangement drawer views MUST remain unchanged. The child remains a
drawer child, not a new main pane. No extra drawer identity or runtime is created.
Basis: U6 and the accepted parent/drawer model. Contract C-A1.

**R-A3 — Main-pane committed reveal.** If a target main pane is present and not
minimized in the owning tab's current arrangement, committed reveal MUST keep that
arrangement. Otherwise it MUST choose the first non-Default custom arrangement in
stored order where that condition holds. If none qualifies, it MUST choose Default.
It MUST NOT expand a different custom arrangement merely to make it qualify.
Basis: U7. Contract C-A2.

**R-A4 — Drawer committed reveal.** A current/custom arrangement qualifies for a drawer child
when its parent is present and not minimized, and its drawer view contains the
child unminimized. Use the same current/custom/Default order. Drawer collapsed
state is revealed by opening the drawer, not by rejecting an otherwise eligible
arrangement. Default fallback requires canonical parent/child membership, not prior
unminimized child state; a minimized child there is expanded after selection. If
Default lacks the relationship, reject without a substitute. After choosing,
committed activation MUST expose the parent, expand
the drawer, expand the target child when fallback requires it, select and focus
that exact child. Basis: U7 and the owner-accepted question 8. Contract C-A2.

**R-A5 — Consistency and failure.** All committed explicit pane targeting that
already reaches the shared focus path MUST use the same selection policy. A missing
pane/tab/parent MUST NOT cause a substitute pane to be created or focused. An invalid
request leaves selection unchanged. If the target disappears after an already-applied
reveal effect, later work MUST stop without recreating it or rolling back unrelated
newer state. Closing a target remains owned by the existing close path. Preview is
not committed activation and MUST NOT be implemented by invoking this path then
blindly reversing its mutations. Basis: U7 and existing stale-target behavior.
Contract C-A2.

## Examples and boundaries

| Situation | Result |
| --- | --- |
| New pane while Default is active and two customs exist | Default gains it; both customs are unchanged |
| New pane while custom Work is active | Work and Default gain it; other customs unchanged |
| Target minimized in current but visible in later custom | Switch to the first qualifying custom, leave current minimization unchanged |
| Target visible in current custom and an earlier custom | Keep current |
| Target absent/minimized in all customs | Default fallback |
| Parent visible but child minimized in current; child visible in next custom | Choose next eligible custom, then open drawer |
| Target child visible in current drawer view but drawer collapsed | Stay and expand drawer |
| No visible custom; child minimized in Default | Choose Default, expand child and drawer |
| Child absent from Default and no eligible custom | Reject without changing selection |
| Stale target UUID | No substitute and no new pane |

Default remains complete within the tab's existing main/drawer model. The change
does not flatten drawer children or impose a single-pane preview layout. No old
custom arrangement is retroactively rewritten to hide previously present panes.
Existing arrangement navigation shortcuts and resize/minimize/close behavior remain.

## Proof coverage

| Need | Problem → outcome | Obligation / contract | Proof |
| --- | --- | --- | --- |
| U6 | Creation spreads into unrelated layouts → intentional creation visibility | R-A1/R-A2, C-A1 | V-A1: real store mutation scenarios plus persistence round-trip preserving untouched custom values |
| U7 | Membership is mistaken for visibility → exact target exposed | R-A3/R-A4, C-A2 | V-A2: automated policy cases and real targeted-focus integration; native terminal/Bridge/drawer reveal |
| U7 | Stale or interleaved targets select wrong content → exact-or-no-target result | R-A5, C-A2 | V-A3: stale-target and close/interleaving scenarios through existing command path |

Current source evidence is not runtime proof. A policy unit test cannot alone prove
AppKit focus or native host visibility. Persistence verification must inspect custom
layouts, minimized sets and drawer placement after round-trip, not only pane count.
New list-sized filtering/sorting or background admission on MainActor is outside
this capability. Existing atomic workspace mutation remains with its owner; any new
expensive derivation must use an off-main path and revalidate before publication.
