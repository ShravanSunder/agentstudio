# Arrangement implementation review

## Subsequent owner decisions

The owner deferred the drawer attachment invariant to a detailed discussion and a
separate PR **after this PR is done**. Q1 remains an accepted known issue, but its
repair and requested third design review are not part of the current PR. Preserve
the evidence and disclose the limitation; do not silently claim it was fixed.

The owner approved the test-only Ghostty header lookup fix. It is committed in
`1c73f89d3`, with 3 focused tests passing and all vocabulary assertions unchanged.
Vendor pins, shared symlinks and both main ancestries were freshly verified.
At `94e85dd5f`, `MISE_RAW=1 mise run test` exited 0: 8,338 Swift tests plus
35 architecture-tool tests; lint and all web gates passed. Earlier bootstrap409,
direct-Swift timeout and real-FSEvents baseline failures remain documented, not
claimed fixed. The confirmation aggregate passed both latter failure points unchanged.

Native isolated debug proof now demonstrates main-pane creation in current+Default,
preservation of another custom, sidebar reveal to a visible custom, Default fallback,
and collapsed-drawer child expansion. Unexecuted markers establish actual input delivery
to each revealed terminal. Evidence: `tmp/sidebar-keyboard-design/arrangement-native-interaction-proof.md`.
Owner subsequently authorized foreground proof. Bridge native reveal now passes:
minimized Files in Layout2 → sidebar activation selects Layout1 → same5016-file
viewer returns → search acceptsREADME and filters to11items. Immediate DOM-local
CmdShiftF is not proved by native host focus; the baseline Bridge mount does not
forward focus into nested WebKit. Track that in the remaining keyboard design.

The review result below records the earlier boundary and must be read with these
owner decisions and subsequent proof. The general detached-drawer invariant remains
unfixed and deferred. PR readiness is not claimed.

Reviewed `96e7dbb..0e17351e1` against the unchanged
`tmp/plan-workflows/2026-09-12-arrangement-visibility-v2.md` and its separate
Requirements, Specification and Program Design. Scope is U6/U7 inside the larger
sidebar goal. No implementation-review remediation has been applied.

**Result: blocked-input, with an accepted design-assumption failure in R-A4.**
No implementation, native, full-suite or PR readiness is claimed.

## Independent lanes and parent reduction

- Spec compliance completed: creation, reveal policy, failure handling and dependent
  command sequencing trace to R-A1–R-A5. Its WIP-document scope observation is rejected
  as an unauthorized-extra finding: the user explicitly requested the broader WIP
  trail and continued sidebar design; separate files retain that boundary.
- Whole-capability quality review completed using a fresh Frontier reviewer. Parent
  accepted the drawer renderer finding after inspecting the action, restoration,
  representable, focus executor and renderer-state owners.
- Proof challenge completed read-only. Its reruns stopped at mandatory preflight:
  mise dependencies may install packages or write Corepack state outside its grant.
  No claimed independent rerun exists. Parent-observed command receipts and logs
  support the reported focused results; they do not establish native composition.
- Dispel completed after the other lanes. It mapped all delivered behavior to the
  rails, found no over-delivery, and classified drawer reattachment as required by R-A4.

## Accepted finding: child selected while renderer stays detached

Severity: important; blocks R-A4 completion.
Anchor: `PaneCommittedFocusOperation.swift` conditional drawer toggle/expansion,
and `WorkspaceSurfaceCoordinator+ActionExecution.swift` arrangement transition sets.
Rail: R-A4 requires exposing and focusing the exact child.

A child minimized in custom A is detached. With the physical drawer still expanded,
committed focus can select custom B where that child is unminimized, then skip both
actions that would reattach it. Main-pane-only arrangement transitions do not repair
the child. Existing-host restore and responder focus do not attach hidden renderers.
Removing reattachment cannot satisfy R-A4; the obligation gap is accepted, not a
specific new abstraction. The exact existing lifecycle action remains a design choice.

Smallest proposed correction: ensure the selected child receives the existing
reattachment effect after arrangement choice, without altering unrelated arrangements
or adding an owner. See [the assumption/evidence/proposal](drawer-reveal-design-gap.md).

Route: **caller reconvergence**, then `program-design`, updated planning and implementation.
The written sequence itself relies on the failed lifecycle assumption. AGENTS.md
requires stopping for that break. Two normal arrangement design-review rounds have
already run; the requested targeted third round requires owner permission.

Confirmation: managed terminal minimize→focus across customs with an already-open
drawer; inspect hidden/active renderer membership and renderer focus, then prove the
native path. Correct the Default-child fixture: calling minimize from Default creates
a custom and does not establish a minimized Default child.

Coverage invalidated: R-A4 realization and native reachability; its policy choice is
still supported. R-A1/R-A2 and existing-placement preservation have focused proof.
R-A3/R-A5 have policy/integration evidence but no launched native interaction proof.

## Proof boundary and other blockers

- Latest affected Core proof: 82 tests / 8 suites, exit 0.
- App focused proof: 150 tests / 40 suites, exit 0, before the final generic-drawer
  preservation correction; unchanged App code is not a fresh whole-HEAD aggregate.
- Webview production creation: 15 tests passed. Corrected Bridge rerun: 8 tests /
  2 suites, exit 0. Test barriers wait for actual queued commands.
- Fresh `mise run lint` on `0e17351e1`: exit 0.
- Isolated debug launch and marker-scoped startup verification: exit 0, PID 67497,
  code igj3. This proves startup only.
- Full `mise run test` on `ad92f6495`: exit 1. Lint/architecture, BridgeWeb and website
  lanes passed; Swift stopped at the unrelated `GhosttyEventRoutingCoverageTests`
  lookup of an unhydrated local vendor header. A test-only upstream-producer lookup
  patch is prepared under tmp; owner scope approval is pending. No vendor changes.
- Native capture failed because the macOS GUI session is locked. No visual or
  keyboard interaction was demonstrated. CUA previously stalled for 3973 seconds;
  its failure is not evidence about the app's behavior.

Evidence logs live under `tmp/sidebar-keyboard-design/`; the event trail records
their names and observed exits. Source corrections, full-suite success and native
proof are still required before another readiness claim or PR publication.
