# Notification Inbox Visual Feedback Ledger

Date: 2026-05-11
Branch: `notification-inbox-redesign`
Purpose: capture user visual/product feedback as explicit acceptance criteria before more code is marked complete.

## Blocking Checklist

Legend:

- `[x]` verified by source/tests/screenshot
- `[ ]` not satisfied
- `[?]` needs product decision with user before implementation

### A. Visual Parity With RepoExplorer

- [ ] Inbox sidebar root background matches RepoExplorer in the running app.
- [x] Inbox sidebar row background and selected-row fill match RepoExplorer.
- [ ] Inbox sidebar separator/border treatment matches RepoExplorer.
- [x] Inbox section header typography, chevron placement, and spacing match RepoExplorer where semantics match.
- [x] Inbox child rows visibly indent/nest under group headers.
- [ ] Grouped inbox does not look flat or custom compared with RepoExplorer.
- [ ] Visual verification includes side-by-side screenshots of RepoExplorer and Inbox in the same build/session.

### B. Badge Parity

- [x] `UnreadCountBadge` exists as a shared stateless drawing primitive.
- [x] Global sidebar bell badge placement matches PaneInbox drawer badge placement.
- [x] Badge placement is shared or pinned by a reusable helper/geometry contract.
- [x] Global sidebar badge anchors to the bell affordance, not the outer AppKit button frame.
- [x] No legacy loose red dot remains for sidebar inbox unread state.
- [x] Badge geometry is covered by an automatic test or explicit mounted-view frame assertion.
- [ ] Visual verification includes the global sidebar badge and PaneInbox badge in the same run.

### C. PaneInbox Visual Rules

- [x] PaneInbox no longer shows the old Unread/All toggle.
- [x] PaneInbox does not show noisy row/group numeric counts unless user explicitly approves.
- [x] PaneInbox row rendering matches global inbox row semantics without redundant parent placement.
- [ ] PaneInbox clear button uses a distinct icon and does not crowd the close button.
- [x] PaneInbox badge clears only when source pane is actually observed: attended and pinned to bottom.
- [x] PaneInbox badge does not clear drawer-child rows from parent-pane focus alone.

### D. Row Source Context

- [x] Notification schema stores denormalized pane source context.
- [x] Router populates repo/worktree/tab/pane/drawer/runtime labels.
- [ ] Final row hierarchy is product-approved: what appears on line 1, line 2, and line 3.
- [x] Rows preserve the most useful distinguishing source detail under truncation.
- [x] No row displays `unknown source`.
- [x] No row displays UUID prefixes or implementation IDs.
- [x] Rows clearly distinguish main pane vs drawer child.
- [?] Decide whether branch belongs on the primary source line, placement line, or only when it differs from worktree.

### E. Grouping / Sorting / Filtering Controls

- [x] Sort icon is visually distinct and does not read like download.
- [x] Group/filter icon is visually distinct and does not read like arrangement/layout.
- [x] Clear icon is distinct and command-backed.
- [x] All header controls have clear tooltips.
- [x] Grouping by tab uses human tab names, not raw ids.
- [x] Grouping by pane separates main panes from drawer children.
- [x] Grouping by repo uses RepoExplorer-like section style.
- [?] Decide whether grouping and sorting are final product controls or temporary discovery/debug affordances.

### F. Command And Button Testability

- [x] `clearInboxNotifications` command identity exists.
- [x] `clearPaneInboxNotifications` command identity exists.
- [x] Sidebar clear method dispatches `.clearInboxNotifications`.
- [x] PaneInbox clear method dispatches targeted `.clearPaneInboxNotifications`.
- [x] Command bar clear row dispatches `.clearInboxNotifications`.
- [x] Clear commands explicitly assert `shortcut == nil`.
- [x] Clear commands explicitly assert command-bar priority.
- [x] Sidebar clear button has an accessibility identifier.
- [x] PaneInbox clear button has an accessibility identifier.
- [x] Mounted UI tests press the clear buttons instead of only calling methods directly.
- [x] MainSplit production clear wiring is covered with a real `InboxNotificationAtom`.

### G. Atom / Boundary Rules

- [x] `PaneInboxPresentationAtom` was removed from `AtomRegistry`.
- [x] Shared components added in this branch are stateless and atom-free.
- [x] `InboxNotificationAtom` remains feature-owned under `Features/InboxNotification`.
- [x] Existing Core `SidebarCacheAtom.collapsedInboxGroups` was moved into feature-owned inbox sidebar state.
- [x] Existing Core `InboxFilterDraftAtom` was replaced by feature-owned inbox sidebar state.
- [x] The two Core inbox state smells are in scope for this PR and are covered by feature-owned tests/persistence.

### H. Event / Runtime Coverage

- [x] Inbox integration tests use a real `EventBus<RuntimeEnvelope>`.
- [x] Inbox tests use `RuntimeEnvelopeHarness` for runtime facts.
- [x] Bridge `inbox.post` reaches router and atom through runtime events.
- [x] Approval/security receive-side events route into inbox surfaces.
- [x] Observed-pane auto-clear uses attended + pinned-bottom state.
- [x] Tests avoid wall-clock `Task.sleep` in inbox paths.
- [x] Add/confirm test for final visual badge geometry or mounted toolbar placement.

### I. Verification / Evidence

- [x] `mise run test` was green before PR.
- [x] `mise run test-e2e` was green before PR.
- [x] `mise run test-zmx-e2e` was green before PR.
- [x] `mise run lint` was green before PR.
- [x] `mise run build` was green before PR.
- [x] Final visual verification is not product-passed; repeated PID-based Peekaboo attempts could not observe the branch app window, one isolated-data debug launch exited before capture, and screen capture returned `loginwindow` instead of Agent Studio.
- [x] Plan status must be updated so "complete" does not mean "visually accepted."
- [ ] PR description/checklist should call out remaining visual blockers if PR stays open.

## Why This File Exists

The plan had real technical coverage, but user-visible design feedback stayed in chat instead of being promoted into a blocking checklist. That allowed code/test-green status to be treated as completion even while screenshots still showed visual mismatches.

Do not mark the notification inbox redesign complete until every item in this file is either implemented, visually verified, or explicitly moved to a named follow-up with user approval.

## Current Plan Audit

The implementation plan already says the right high-level thing:

- `docs/superpowers/plans/2026-05-07-notification-inbox-sidebar-redesign.md:94`
  - Inbox sidebar background and row rhythm must match RepoExplorer.
- `docs/superpowers/plans/2026-05-07-notification-inbox-sidebar-redesign.md:98`
  - Global inbox toolbar badge must match PaneInbox badge treatment.
- `docs/superpowers/plans/2026-05-07-notification-inbox-sidebar-redesign.md:83-86`
  - Rows must always show useful source context and never fall back to useless labels.
- `docs/superpowers/plans/2026-05-07-notification-inbox-sidebar-redesign.md:95`
  - Sort/group controls must use clear icons and tooltips.

But the plan is not strict enough where screenshots exposed failures:

- It marks implementation complete while final visual verification was tool-blocked, not product-passed.
- It describes `UnreadCountBadge` reuse, but not shared badge placement. Reusing the badge view alone was insufficient.
- It says RepoExplorer chrome parity, but does not define measurable background, indentation, group-header, and row-rhythm checks.
- It has tests for method seams, but not enough mounted UI/button geometry checks.

## Feedback Items

### 1. Global sidebar inbox badge does not match PaneInbox badge

Observed:

- Sidebar/titlebar badge floats over the bell and looks visually wrong.
- PaneInbox drawer badge is anchored like a normal corner badge.
- Same badge drawing is reused, but placement is not reused.

Root cause to verify in code:

- PaneInbox uses SwiftUI `.overlay(alignment: .topTrailing)` on the compact icon button.
- Global sidebar titlebar uses an `NSHostingView<UnreadCountBadge>` constrained to the outer `NSButton` frame with top/trailing offsets.
- The AppKit button frame is wider than the actual bell glyph, so the badge anchors to the wrong geometry.

Acceptance:

- Global sidebar badge and PaneInbox badge use the same placement contract.
- Badge is a red numeric capsule anchored to the bell affordance's top-trailing corner.
- No loose red dot or badge floating over the middle/top of the icon.
- Add an automatic geometry test or shared placement test so this cannot drift again.

Preferred implementation direction:

- Extract shared badge placement, not just badge drawing.
- If feasible, host the sidebar titlebar bell as SwiftUI so it can use the same overlay primitive.
- If AppKit must remain, anchor the badge to an explicit icon-sized layout guide, not the full `NSButton` frame.

### 2. Sidebar inbox background does not match RepoExplorer

Observed:

- User repeatedly called out that the inbox sidebar background color does not match the repo sidebar.
- Current screenshots still read as visually different.

Acceptance:

- Inbox sidebar root background, row background, section background, separators, and selected-row fill must visually match RepoExplorer.
- Do not use a near-match token if it produces a visibly different color in the running app.
- Add a visual smoke screenshot or explicit color-token audit in the plan before marking complete.

### 3. Group indentation and expandable hierarchy do not read like RepoExplorer

Observed:

- In grouped inbox screenshots, expandable indentation is not visually clear.
- The "Pane" section and child rows do not read with the same hierarchy/rhythm as RepoExplorer.
- The section header/row spacing feels flat and custom rather than native to the existing sidebar.

Acceptance:

- Group headers should use the same chevron placement, left inset, spacing, and row rhythm as RepoExplorer where semantics match.
- Child notification rows should visibly nest under the group header.
- Selected rows must not obscure the hierarchy.
- Add a mounted view test or source-level contract test that both RepoExplorer and Inbox group headers use the shared `SidebarSectionHeader` where applicable.

### 4. PaneInbox should not show numeric counts unless explicitly approved

Observed:

- User feedback: "in paneinbox i dont want to show numbers i think can be."
- Numeric count badges inside grouped inbox/PanInbox contexts risk adding visual noise.

Acceptance:

- PaneInbox popover should not show row/group count numbers.
- If a pane-scoped unread count remains on a bell affordance, it must be only the compact affordance badge and must match the shared badge placement.
- If there is any ambiguity between global sidebar grouping counts and PaneInbox counts, resolve with the user before implementation.

### 5. Row source context still needs product review

Observed:

- Rows improved, but screenshots still show long truncated lines:
  - repo/worktree line
  - tab/branch/pane/runtime line
  - message line
- User wants to know source, tab, pane, drawer, and useful terminal context.

Acceptance:

- Every notification row must show:
  - useful source label
  - repo/worktree when known
  - tab label when known
  - main pane vs drawer child placement when known
  - message/body
- Fallbacks must be useful human labels, never `unknown source`, UUID prefixes, or raw implementation IDs.
- Truncation should preserve the most useful distinguishing detail first.

Open design question:

- Decide the final two-line or three-line row hierarchy with the user before more implementation churn.

### 6. Sort/group/filter controls still need icon review

Observed:

- User said the sort/group/filter icon treatment is confusing.
- A previous screenshot showed a control looking like a download button.
- The current filter/group icon also visually collides with arrangement-style iconography.

Acceptance:

- Sort, grouping, filter, and clear controls must each have distinct icons that read correctly in this app.
- The grouping/filter control must not look like arrangement, download, or layout controls.
- Tooltips must name the action clearly.

### 7. Clear buttons need mounted UI testability

Observed:

- Method-level tests exist, but visible SwiftUI buttons need identifiers and mounted click tests.

Acceptance:

- Add stable accessibility identifiers:
  - `inboxSidebarClearButton`
  - `paneInboxClearButton`
- Add mounted tests that trigger the button surface, not just `clearAllNotifications()` or `clearNotifications()`.

### 8. MainSplit production wiring needs direct coverage

Observed:

- Pane command tests use a recorder closure.
- The real `MainSplitViewController.makePaneInboxPresentation()` clear closure should be tested against a real `InboxNotificationAtom`.

Acceptance:

- Add a MainSplit composite test that uses the production presentation wiring, dispatches/executes clear, and verifies:
  - parent pane rows clear
  - drawer child rows clear
  - unrelated pane/global rows remain
  - global unread count updates

### 9. Plan status must not say complete while visual acceptance is failed

Observed:

- Plan status currently says implementation steps are complete and valid P2 findings were addressed.
- Screenshots show visual acceptance criteria are not satisfied.

Acceptance:

- Update plan status to distinguish:
  - code implemented
  - tests green
  - visual acceptance still failed / pending
  - blocked by tool vs failed by screenshot

## Retrospective

What went wrong:

- The plan had the right goals, but too many tasks were marked complete from code/test evidence without a visual acceptance gate.
- Badge reuse was interpreted as reusing the badge view, not reusing the placement behavior.
- RepoExplorer parity was stated as a goal but not converted into measurable checks for background, indentation, section header, and row rhythm.
- User screenshot feedback was not immediately written into the plan or a feedback ledger, so the same issues had to be repeated.

What changes now:

- Screenshot feedback becomes a blocking checklist.
- Visual requirements must be validated by screenshot or explicitly marked unverified.
- Shared UI means shared behavior and geometry, not only shared drawing code.
- "Done" for this redesign requires passing the product acceptance criteria in this file, not only `mise run test` and `mise run lint`.
