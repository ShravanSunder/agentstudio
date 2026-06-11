# Inbox Notification Correctness: Auto-Clear Semantics, Focus Tracker Resilience, Coalescence Guard

Planned at: a80ebb05
Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.improve-v1
Status: proposed

## Problem

An adversarial trace of the inbox persistence pipeline **refuted** the headline
"unread count desynchronization" claim: `InboxNotification` is a struct in an
`@Observable` atom (in-place mutations fire observation — proven by the
pattern test in `ObservableStoreTests.swift:111-129`), saves are full snapshot
replaces (`replaceSnapshot` deletes all rows and reinserts), and coalescence +
retention logic were verified line-equivalent between atom and repository. The
real, verified problems are narrower:

1. **Auto-clear fires for visible-but-unattended panes.** The policy's gate is
   `isSourcePaneAttended` with keep-reason `"source_pane_unattended"` — intent
   is explicit: only the attended pane auto-clears. The router feeds it
   `isSourcePaneObserved(paneId)` (membership in the whole observed/visible
   set), so a notification in a visible side-split or drawer is cleared the
   moment its pane is pinned to bottom, even though the user is attending a
   different pane. Given this product's no-toast, persistent-unread contract,
   silently clearing unattended panes' notifications is a correctness bug.
2. **`PaneFocusTracker` dies permanently if its source stream ends.** On an
   unexpected end of `attendedPane.transitions` it logs, sets `isStopped`, and
   finishes its own continuation — auto-clear-on-focus silently stops for the
   rest of the session with no recovery.
3. **The SQL mergeable-lane list can drift from the enum.**
   `SQLiteInboxNotificationClaimStorage.mergeableLaneSQLValues` hardcodes
   `[laneActivity, laneActionNeeded]` while the source of truth is
   `InboxNotificationClaim.canMergeWithinActivitySession`. A future lane
   addition that merges would silently diverge atom-side and repository-side
   coalescence (duplicates after reload).
4. **Test gap:** no markRead → save → reload round-trip proves read/dismiss
   state survives persistence (the trace says it does; nothing pins it).

## Current Evidence

- `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift:519-522`
  — `autoClearPolicy.decision(notification:, isSourcePaneAttended:
  isSourcePaneObserved(paneId), ...)`;
  `InboxNotificationRouter.swift:590-592` — `isSourcePaneObserved` =
  `currentObservedPaneIds().contains(paneId)`;
  `InboxNotificationRouter.swift:594-600` — a distinct
  `currentAttendedPaneId()` already exists and is unused here.
- `Sources/AgentStudio/Features/InboxNotification/Models/PaneInboxAutoClearPolicy.swift:17-18`
  — `guard isSourcePaneAttended else { return .keep(reason:
  "source_pane_unattended") }`.
- `Sources/AgentStudio/Features/InboxNotification/Routing/PaneFocusTracker.swift:43-47`
  — stream-end path: warning log → `isStopped = true` → `continuation.finish()`,
  no restart.
- `Sources/AgentStudio/Core/State/MainActor/Persistence/SQLiteInboxNotificationClaimStorage.swift:10`
  — `static let mergeableLaneSQLValues = sqlValueList([laneActivity,
  laneActionNeeded])`;
  `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationClaim.swift:8`
  — `var canMergeWithinActivitySession: Bool` is the source of truth;
  duplicated predicate `canCoalesceClaim` at
  `InboxNotificationAtom.swift:145` and
  `InboxNotificationSQLiteRepository.swift:362`.
- Refuted during audit (do not re-implement): unread-count desync (no
  persisted count exists; recomputed on every load/mutation), retention
  divergence (identical `AppPolicies.InboxNotification.maxRetained` + ordering
  on both sides), read-state loss at quit
  (`AppDelegate+Termination.swift:73` flushes the inbox store).

## Non-Goals

- No persistence-layer redesign (the snapshot-replace model is verified
  sound).
- No change to retention policy or notification kinds.
- No immediate-save mode for individual mutations — the 500ms debounce +
  termination flush is accepted; crash-loss of sub-500ms read-state is a known
  bounded exposure.
- The 950-line router's broader decomposition is deferred (track with the
  pane-shell decomposition pattern if it recurs).

## Scope

Write surfaces:
- `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`
  — pass attended-pane truth to the policy.
- `Sources/AgentStudio/Features/InboxNotification/Routing/PaneFocusTracker.swift`
  — bounded restart on unexpected stream end.
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/`
  — single shared coalescence predicate; lane-list exhaustiveness guard.
- Tests under `Tests/AgentStudioTests/Features/InboxNotification/`.

Read-only context:
- `Sources/AgentStudio/Features/InboxNotification/Routing/PaneObservationResolver.swift`
  (or equivalent) — attended-pane resolution semantics.
- `Sources/AgentStudio/Features/InboxNotification/Models/PaneInboxAutoClearPolicy.swift`
  — decision contract.

## Task Sequence

1. **Decide and fix the auto-clear gate.** Default decision per the policy's
   own naming: pass `currentAttendedPaneId() == paneId`. Check call sites of
   `clearObservedPaneInboxRowsIfNeeded` first — if some call sites genuinely
   want observed-set semantics (e.g. a clear triggered by scroll-to-bottom in
   that very pane), thread the caller's pane-attendance fact explicitly rather
   than the global observed set. Add tests: notification in a visible
   unattended drawer pinned to bottom is KEPT (reason
   `source_pane_unattended`); notification in the attended pane pinned to
   bottom is cleared.
2. **Focus tracker restart.** On unexpected stream end while active:
   re-subscribe to `attendedPane.transitions` after a short injected-clock
   delay, capped attempts (e.g. 3, then stay stopped + log error). Test with a
   fake transitions stream that ends after N events: tracker resumes emitting.
3. **Single coalescence predicate.** Extract `canCoalesceClaim` into one
   shared site (e.g. on `InboxNotificationClaim` or a small policy type) used
   by both `InboxNotificationAtom` and `InboxNotificationSQLiteRepository`.
   Add an exhaustiveness test: for every `InboxNotificationClaimLane`,
   `mergeableLaneSQLValues` contains the lane's SQL token iff
   `canMergeWithinActivitySession == true` — so adding a lane breaks the test,
   not production.
4. **markRead round-trip test.** append → markRead + dismiss → save → load
   into fresh atom → assert `isRead`/`isDismissedFromPaneInbox` and unread
   counts. (The deep-dive trace sketched this test; adapt to the existing
   repository fixture helpers.)

## Proof Gates

- Red/green: task 1 tests fail against current router (observed-set
  clearing); task 3 exhaustiveness test fails if a mergeable lane is removed
  from the SQL list.
- Focused validation:
  `mise run test -- --filter "InboxNotification"`,
  `mise run test -- --filter "PaneFocusTracker"`.
- Full validation: `mise run test`, `mise run lint` — zero errors.
- Manual: two panes side by side, generate a bell in the unattended pane
  (pinned to bottom), confirm its unread indicator persists until that pane is
  attended; attend it, confirm auto-clear.

## Stop Conditions

- Stop if call-site analysis in task 1 shows the observed-set semantics were a
  deliberate product choice somewhere (e.g. explicit user scroll in that
  pane) — surface the conflict and ask before changing behavior.
- Stop if extracting the shared predicate forces a Core ↔ Feature import that
  violates the directory import rules — pick the placement that satisfies
  `Features/InboxNotification` ownership and report.

## Risks

- Tightening auto-clear means more notifications persist — that is the stated
  product contract (persistent unread over silent clearing), but watch for
  noisy kinds (`unseenActivity`) accumulating; retention cap bounds it.
- Focus-tracker restart could mask a real upstream bug that ends the stream —
  the capped attempts + error log preserve the signal.

## Handoff Prompt

```text
Use implementation-execute-plan on this plan.

Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.improve-v1
Plan: docs/plans/2026-06-10-inbox-notification-correctness.md
Start by validating the plan against current git state before editing files.
Tasks 1-4 are independent slices; task 1 requires the call-site analysis
before any behavior change. Parent owns integration and final proof
(mise run test, mise run lint).
```
