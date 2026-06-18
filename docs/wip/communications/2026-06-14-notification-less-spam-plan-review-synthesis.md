# Notification Less-Spam Plan Review Synthesis

Date: 2026-06-14
Target plan: `docs/plans/2026-06-14-notification-less-spam-rollup-alerts-implementation.md`
Source spec: `docs/superpowers/specs/2026-06-14-notification-less-spam-rollup-alerts.md`
Baseline: `7b1ed70f`

## Swarm Lanes

- `spec-compliance`: needs revision
- `architecture-assumptions`: needs revision
- `testability-validation`: needs revision
- `security-reliability`: needs revision
- `execution-scope`: needs revision
- `adversarial-design`: needs revision

## Accepted Findings Applied

1. Reopen/undismiss invariant:
   Any read-to-unread transition clears `isDismissedFromPaneInbox`, including
   manual unread toggles and stronger action/safety coalescence into a read row.

2. Scoped read-all mutation owner:
   Repo/worktree/pane/workspace read-all requires a feature-owned atom plus
   SQLite persistence mutation. Controller-filtered workspace `markAllRead()` is
   forbidden for scoped read-all.

3. Pane Inbox control decision:
   The first slice exposes both pure `Mark Pane Read` and separately labeled
   `Clear Pane Inbox`. Mark-read changes only `isRead`; clear sets read plus
   pane dismissal.

4. Chrome-entry temporary override:
   Feature runtime state owns temporary `rollupAlerts + unreadOnly` overrides
   for global and pane entry. Overrides are consumed by chrome-driven opens,
   discarded on close if unchanged, and only explicit user interaction persists
   preferences.

5. Workspace-scoped pane mode:
   Pane content mode and row-state filter are single workspace-scoped observable
   preferences, not per-parent pane caches. Cross-popover sync proof is required.

6. Tab-dot boundary and invalidation:
   App composes primitive tab-dot render tokens from inbox roll-up candidates and
   live pane ownership. Core tab state remains notification-free. Inbox-only
   read changes must invalidate tab dots without waiting for pane/tab mutation.

7. Worktree-count cutover:
   `WorkspaceNotificationCountProjection` consumers in pane-management and
   launcher chrome are in scope so blue activity rows do not light one app-shell
   surface while another stays quiet.

8. Settings and legacy preference ownership:
   `WorkspaceSettingsStore` owns active inbox preferences. Any remaining
   `InboxNotificationStore` legacy preference payload is import-only, with
   negative proof that current saves do not write active prefs there.

9. Text-bound proof:
   Reuse current shared inbox max title/body constants for newly bounded
   ingress paths and prove bridge `inbox.post` through current handler or WebKit
   integration seams.

10. Retention parity:
    Shared retention priority must cover atom append/upsert, SQLite
    append/upsert, snapshot replace, legacy-import materialization, and reload
    with identical mixed-lane survivors.

11. Validation and observability corrections:
    Focused filters name concrete changed-surface suites. The `already_running`
    observability path must quit the reported debug PID, relaunch, rerun
    `verify-debug-observability`, then run Peekaboo against the verified PID.

## Rejected Or Deferred Findings

- None. The review lanes were consistent on the material blockers and important
  fixes; all actionable blocker/important findings were folded into the plan.

## Follow-On Requirement

Execute the revised plan with `shravan-dev-workflow:implementation-execute-plan`
before editing product code.
