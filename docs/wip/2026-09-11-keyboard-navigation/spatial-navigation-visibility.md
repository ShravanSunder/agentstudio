# Spatial navigation uses visible panes only

Owner correction U18: normal Option-J/L navigates visible panes in the current
arrangement and main/drawer row. Skip minimized/backgrounded entries, keep focus
at an edge, and never reveal, expand or switch arrangements. Explicit sidebar,
pinned and ordinal activation retains intentional reveal. I/K, next/previous
cycling and Management remain separate.

```text
A visible    B minimized/backgrounded    C visible
Option-L: A --------------------------> C
Option-J: A <-------------------------- C
```

## Design review and implementation basis

Requirements U18, Specification R-S7 and Program Design “Visible horizontal pane
movement” are distinct current identities. One bounded independent round completed:
`/root/spatial_design_review` mode-complete and `/root/spatial_design_dispel` dispel.
Both found the existing visibility projection, canonical row lookup and synchronous
focus owners sufficient; no new state/cache/async/reveal owner is needed.

Accepted U18-PROOF-TRACE: proof matrices omitted visible-only cases. Parent corrected
both matrices and verified the current rows name hidden skipping, native focus,
edge behavior, unchanged visibility and explicit reveal. Parent verified current
WorkspaceArrangementViewDerived main/drawer eligibility, Layout/DrawerGridLayout
adjacency, controller ingress and focus executor behavior against the recommendation.
Result: bounded U18 design ready; no second round or third-review recovery used.
This does not certify unfinished sidebar/preview/terminal work or the deferred drawer
renderer invariant. The original core plan remains immutable; this correction has
its own bounded implementation plan under tmp/plan-workflows.

## Pre-change evidence

- Main regression: `spatial-visible-red-retry.log`, exit 1: 8 tests, 5 passed,
  3 failed with 12 issues. Minimized panes were expanded; minimized/backgrounded
  intervening targets prevented native focus reaching the visible destination.
- Drawer real Option-J/L events: `spatial-drawer-red.log`, exit 1: 1 test / 4
  parameter cases failed with 16 issues in selection/focus.
- First main attempt stopped before tests with a vendor-pin mismatch. A fresh
  committed-pin comparison matched primary; unchanged vendor verification exited 0;
  one unchanged retry reached the expected behavioral failures. No vendor edits.

Logs are under tmp/sidebar-keyboard-design. Implementation and final proof are
tracked separately; red tests are not a completed fix.

## Implemented scoped behavior

Layout now scans toward the nearest eligible pane without changing canonical layout.
Main/drawer horizontal command targeting supplies the existing visibility projection;
drawer movement retains its containing row. Source proof is green: 8 main-command,
32 drawer-command, 19 layout/grid and 8 visibility-projection tests, all exit 0.
The drawer suite includes actual Option-J/L events and native responder assertions.
This is native integration coverage, not a packaged-app smoke claim.

Lint found three issues in the existing sidebar core changes; equivalent enum/pattern
and repeated-case corrections are being checked. Manual app proof, final aggregate,
and unfinished sidebar/preview work remain separate obligations.

## Current scoped review and quality result

Spec-compliance found no U18 mismatch. Source reviewer raised SPATIAL-FOCUS-1:
existing main-row keyboard focus intentionally preserves the native responder for
nonterminal content. Parent verified the decider, its existing webview contract test
and selection-refocus suppression. Dispel classified a new horizontal-only responder
policy as scope expansion: deleting that proposed change still satisfies U18. Parent
rejected the expansion, clarified the Program Design wording, and preserved the
existing executor. Eligibility includes every content kind; this does not claim
new native/WebKit focus behavior. The prior focusSidebar hunk remains core-owned.

Lint recheck passed (exit 0; SwiftLint and architecture lint), shell-focus regression
passed 5 tests (exit 0), and diff whitespace check passed (exit 0). Sidebar focus
regression logged 5 passing tests; its terminal exit metadata was lost and is not
invented. Manual isolated-app proof and full aggregate remain pending.

## Native edge proof, revised debug binary

Debug igj3 PID88535, marker debug-observability-igj3-1789320429-86987. In the preexisting Terminal tab, Layout2 had two visible terminals. Used the right pane's existing Management Minimize control, exited Management, and observed the left terminal fill the pane area with one minimized item in Layout2. Option-L left the same terminal as native first responder and did not reveal the right pane or switch arrangement. Restored the right pane using Arrangement Panel -> its Expand Pane control; Layout2 remained selected and two terminals returned. Option-J then focused left and Option-L focused right. Returned to tab3 Default afterward. This proves main-pane edge no-reveal and preserved visible movement; skip-over-middle and drawer cases still rely on the previously recorded67 automated tests, not new native claims. CUA screenshots/AX observations are in the session trace. An Option-2 attempt did not change this fixture; no ordinal target identity or successful ordinal-reveal claim is inferred from that attempt.
