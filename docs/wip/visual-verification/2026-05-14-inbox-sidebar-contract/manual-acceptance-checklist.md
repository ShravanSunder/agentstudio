# Manual Native Visual Acceptance Checklist

Date: 2026-05-14

Branch: `notification-inbox-redesign`

Purpose:
- Close the remaining product-window visual acceptance gap once macOS screen
  capture or manual review is available.
- Compare the native Inbox and PaneInbox surfaces against the native
  RepoExplorer sidebar, not just the offscreen component artifact.

Prerequisites:
- Build or run branch head `130797b2` or newer.
- Open the primary sidebar with RepoExplorer visible.
- Open the Notification Inbox sidebar.
- Open PaneInbox from a pane that has at least one parent-pane notification and
  one drawer-child notification.

Accept when these match RepoExplorer:
- Source group rows use the shared sidebar header grammar:
  - same disclosure icon slot
  - same source icon slot
  - same title baseline
  - same row height and horizontal indentation
  - same transparent/sidebar background behavior
- Repo/source icons use the existing repo/sidebar presentation colors:
  - main repo family color matches RepoExplorer
  - secondary worktree/source color matches RepoExplorer
  - Other sources uses the shared fallback source icon treatment
- Inbox grouping modes share the same group-row grammar:
  - None does not introduce plain ad hoc headers
  - By Repo aligns with RepoExplorer repo groups
  - By Pane groups by parent pane only; drawer children do not create separate
    top-level pane groups
  - By Tab uses the shared source group row style
  - Other sources uses the shared source group row style
- Notification rows line up with RepoExplorer row rhythm:
  - unread dot aligns with row text
  - metadata text does not shift or stretch rows
  - selected row background uses the shared sidebar row chrome
  - no row background color reads as a new feature-local theme
- PaneInbox uses the same visual contract:
  - background matches the sidebar/window surface contract
  - rows use `SidebarRowShell` chrome
  - no pane-group count pills are shown
  - no terminal metadata icon protrudes beyond the shared leading columns
  - clear/filter controls do not reuse the arrangement/grouping icon

Reject if any of these appear:
- A plain text group header that does not use the shared source group row.
- An icon column that starts at a different x-position than RepoExplorer.
- By Pane grouping showing drawer children as independent top-level groups.
- PaneInbox count pills next to group labels.
- Terminal metadata icons sticking out beyond the normal row columns.
- A blue/gray selected-row background that visually disagrees with RepoExplorer
  selected-row chrome.

Capture guidance:
- Prefer PID-targeted Peekaboo against the branch debug build.
- Capture at least:
  - RepoExplorer with several expanded repo families.
  - Inbox grouped By Repo.
  - Inbox grouped By Pane.
  - Inbox grouped By Tab.
  - Inbox with Other sources visible.
  - PaneInbox open over a pane with parent + drawer-child notifications.
- Attach the successful screenshots to this folder or the PR description.

