# LUNA-361 Phase 3c Ghostty Terminal Intelligence + OSC Smoke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make terminal-originated Ghostty signals complete and inspectable for the notification inbox, then prove the live OSC path in the real macOS app.

**Architecture:** Ghostty already emits terminal facts through the host action callback. Agent Studio translates those actions into `GhosttyEvent`, emits them through `TerminalRuntime` onto `PaneRuntimeEventBus`, and `InboxNotificationRouter` classifies notification-worthy events into the inbox. This plan audits that chain, fills missing action-router coverage, adds only carefully gated inbox routing for high-value terminal intelligence, and finishes with a live native smoke test using real OSC/BEL sequences.

**Tech Stack:** Swift 6.2, Swift Testing, vendored Ghostty action callbacks, `PaneRuntimeEventBus`, `InboxNotificationRouter`, Peekaboo for native visual verification, `mise run lint`, `mise run test`.

---

## Research Baseline

DeepWiki and local source search agree on these host-visible Ghostty signals:

```
OSC 9 / OSC 777 desktop notification
  vendor/ghostty/src/Surface.zig:1064
  vendor/ghostty/src/config/Config.zig:3645
  vendor/ghostty/include/ghostty.h:637
  Agent Studio: GhosttyEvent.desktopNotificationRequested
  Inbox today: yes

BEL / ring bell
  vendor/ghostty/src/Surface.zig:1083
  Agent Studio: GhosttyEvent.bellRang
  Inbox today: yes, gated by bell prefs

OSC 133 / shell integration command finish
  vendor/ghostty/src/Surface.zig:1114
  vendor/ghostty/include/ghostty.h:827
  Agent Studio: GhosttyEvent.commandFinished
  Inbox today: yes, gated by attended pane + duration

OSC 9;4 progress report
  vendor/ghostty/src/Surface.zig:1098
  vendor/ghostty/src/config/Config.zig:3649
  vendor/ghostty/include/ghostty.h:817
  Agent Studio: GhosttyEvent.progressReportUpdated
  Inbox today: no

OSC 7 current working directory
  vendor/ghostty/src/termio/stream_handler.zig:318
  Agent Studio: GhosttyEvent.cwdChanged
  Inbox today: no; used as context

Title/tab title changes
  vendor/ghostty/src/Surface.zig:949
  vendor/ghostty/src/Surface.zig:5495
  Agent Studio: titleChanged/tabTitleChanged
  Inbox today: no; used as context

Scrollbar / scrollback total
  vendor/ghostty/src/Surface.zig:1673
  Agent Studio: GhosttyEvent.scrollbarChanged
  Inbox today: no; runtime state only today

Renderer health
  vendor/ghostty/src/Surface.zig:1662
  Agent Studio: GhosttyEvent.rendererHealthChanged
  Inbox today: no
```

## Hard Invariants

1. Do not invent fake approval/security product emitters in this plan.
2. Terminal-originated Ghostty facts should either be routed to inbox with an explicit gate, or documented as runtime state only.
3. High-churn signals must not create notification spam.
4. Filesystem/git facts stay on the existing filesystem/git pipeline. Ghostty CWD only supplies pane context.
5. Tests stay mostly headless. The only visual/native step is the final live OSC smoke.

## Classification Rules

```
Persistent inbox notifications
  desktopNotificationRequested
  bellRang, gated by prefs
  commandFinished, gated by unattended + duration
  progress error, gated and deduped
  secureInputChanged(true), gated by unattended + edge-deduped
  renderer unhealthy edge, gated and deduped

Runtime/activity state only
  progress set / indeterminate / paused
  progress remove
  scrollbarChanged totals
  cwdChanged
  titleChanged / tabTitleChanged
  readOnlyChanged
  secureInputChanged(false)
  openURLRequested

Existing filesystem/git pipeline
  filesChanged
  gitSnapshotChanged
  branchChanged
  PaneFilesystemContextEvent.cwdSubtreeChanged
```

## File Structure

```
Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/
  PaneRuntimeEvent.swift                                inspect / maybe add helpers only

Sources/AgentStudio/Features/Terminal/Ghostty/
  GhosttyActionRouter+ObservedActions.swift             add/verify action coverage
  GhosttyAdapter.swift                                  add/verify translations

Sources/AgentStudio/Features/Terminal/Runtime/
  TerminalRuntime.swift                                 ensure state emission is complete

Sources/AgentStudio/Features/InboxNotification/
  Routing/InboxNotificationRouter.swift                 classify progress error + renderer unhealthy
  Models/InboxNotification.swift                        add kind only if needed

Tests/AgentStudioTests/Features/Terminal/Ghostty/
  GhosttyAdapterTests.swift                             extend
  GhosttyActionRouterTests.swift                        extend action callback -> runtime envelope

Tests/AgentStudioTests/Features/Terminal/Runtime/
  TerminalRuntimeTests.swift                            extend state emission tests

Tests/AgentStudioTests/Features/InboxNotification/Routing/
  InboxNotificationRouterTests.swift                    extend classification gates

docs/wip/
  luna361-phase3c-ghostty-terminal-intelligence-smoke-2026-04-24.md
```

## 2026-04-24 Scope Note

The code path for terminal secure-input requests now routes `secureInputChanged(true)` to the inbox as an edge-triggered notification. Non-error progress, CWD, URL requests, and scrollbar/output totals are tracked as runtime/activity state. Raw terminal file-link extraction and richer semantic output parsing remain in the separate follow-up plan:

`docs/superpowers/plans/2026-04-24-terminal-output-file-link-tracking-followup.md`

The live OSC smoke remains a manual/native verification task until Peekaboo evidence is appended to the smoke WIP document.

## Current PR Boundary

Included in this PR:

- Terminal secure-input request notification routing.
- Terminal progress-error and renderer-unhealthy notification routing.
- Terminal activity state for non-error progress, CWD, URL requests, secure-input state, and scrollbar-derived output bursts.
- Headless router/activity tests proving those event paths.

Not included in this PR:

- Raw terminal output text parsing.
- Claude/Codex file-link extraction from printed output.
- Structured agent status/update pipelines beyond the Ghostty facts already exposed.
- Approval/security product emitters; receive-side inbox routing remains ready, but those source systems are separate work.
- Live OSC visual smoke evidence; the code path is covered headlessly, while native UI proof still needs the manual Peekaboo-backed smoke.

## Task A1: Audit Ghostty action vocabulary against Agent Studio

**Files:**
- Create: `docs/wip/luna361-phase3c-ghostty-terminal-intelligence-smoke-2026-04-24.md`

- [ ] **Step 1: Write the audit table**

Record every `GhosttyActionTag` case and mark it as:

```
inbox-notification
runtime-state
command-action
intercept-only
ignored-with-log
```

Required rows include:

```
desktopNotification -> inbox-notification
ringBell -> inbox-notification
commandFinished -> inbox-notification
progressReport -> runtime-state, progress error may notify
rendererHealth -> runtime-state, unhealthy edge may notify
scrollbar -> runtime-state
pwd -> runtime-state/context
setTitle -> runtime-state/context
setTabTitle -> runtime-state/context
openURL -> command-action
```

- [ ] **Step 2: Verify against code**

Run:

```bash
rg -n "case .*GhosttyActionTag|case \\.desktopNotification|case \\.progressReport|case \\.rendererHealth|case \\.scrollbar|case \\.pwd|case \\.setTitle|case \\.commandFinished" Sources/AgentStudio/Features/Terminal/Ghostty Sources/AgentStudio/Core/RuntimeEventSystem/Contracts
```

- [ ] **Step 3: Commit**

```bash
git add docs/wip/luna361-phase3c-ghostty-terminal-intelligence-smoke-2026-04-24.md
git commit -m "docs(notification-inbox): audit Ghostty terminal intelligence signals

Co-authored-by: Codex <noreply@openai.com>"
```

## Task A2: Cover host action callback paths

**Files:**
- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift`

- [ ] **Step 1: Add adapter coverage**

Ensure tests cover:

```swift
.desktopNotification(title: "Build", body: "Complete") -> .desktopNotificationRequested
.progressReport(stateRawValue: GHOSTTY_PROGRESS_STATE_ERROR, progress: 80) -> .progressReportUpdated(...)
.rendererHealth(rawValue: unhealthy value) -> .rendererHealthChanged(healthy: false)
.scrollbar(total: 1000, offset: 900, length: 40) -> .scrollbarChanged(...)
.cwdChanged("/tmp/project") through .pwd payload
```

- [ ] **Step 2: Add action-router envelope coverage**

Mirror the existing command-finished end-to-end test for:

```
GHOSTTY_ACTION_DESKTOP_NOTIFICATION
GHOSTTY_ACTION_PROGRESS_REPORT
GHOSTTY_ACTION_RENDERER_HEALTH
GHOSTTY_ACTION_SCROLLBAR
GHOSTTY_ACTION_PWD
```

Each test asserts that `TerminalRuntime.eventsSince(seq: 0)` contains the expected `PaneRuntimeEvent.terminal(...)`.

- [ ] **Step 3: Run focused tests**

```bash
swift test --build-path ".build-agent-$PPID" --filter "GhosttyAdapterTests|GhosttyActionRouterTests"
```

Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add Tests/AgentStudioTests/Features/Terminal/Ghostty
git commit -m "test(terminal): cover Ghostty notification action callback paths

Co-authored-by: Codex <noreply@openai.com>"
```

## Task B1: Add progress-error inbox routing

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotification.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift`

- [ ] **Step 1: Write failing router tests**

Cases:

```
progress .set does not notify
progress .indeterminate does not notify
progress .paused does not notify
progress nil does not notify
progress .error creates one notification
repeated progress .error for same pane is deduped until progress clears
```

- [ ] **Step 2: Implement classification**

Add a new notification kind only if the existing kind vocabulary cannot express it cleanly:

```swift
case progressError
```

Router behavior:

```swift
case .terminal(.progressReportUpdated(let state)):
    guard state?.kind == .error else {
        clearProgressErrorState(for: paneId)
        return nil
    }
    return notifyOncePerPaneUntilCleared(...)
```

- [ ] **Step 3: Add title/body**

Title:

```
Progress error
```

Body:

```
Terminal reported progress error
```

Include percent if present.

- [ ] **Step 4: Run focused tests**

```bash
swift test --build-path ".build-agent-$PPID" --filter "InboxNotificationRouterTests|NotificationTests"
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification Tests/AgentStudioTests/Features/InboxNotification
git commit -m "feat(notification-inbox): route terminal progress errors

Co-authored-by: Codex <noreply@openai.com>"
```

## Task B2: Add renderer-unhealthy inbox routing

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotification.swift`
- Modify tests.

- [ ] **Step 1: Write failing router tests**

Cases:

```
healthy -> no notification
healthy then unhealthy -> notification
unhealthy then unhealthy -> no duplicate
unhealthy then healthy then unhealthy -> second notification
```

- [ ] **Step 2: Implement edge gate**

Use a per-pane dictionary like sandbox health:

```swift
private var rendererHealthWasHealthyByPaneId: [UUID: Bool] = [:]
```

- [ ] **Step 3: Title/body**

Title:

```
Terminal renderer unhealthy
```

Body:

```
Renderer health transitioned to unhealthy
```

- [ ] **Step 4: Verify**

```bash
swift test --build-path ".build-agent-$PPID" --filter "InboxNotificationRouterTests"
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification Tests/AgentStudioTests/Features/InboxNotification
git commit -m "feat(notification-inbox): route renderer health failures

Co-authored-by: Codex <noreply@openai.com>"
```

## Task C1: Document runtime-only terminal intelligence

**Files:**
- Modify: `docs/wip/luna361-phase3c-ghostty-terminal-intelligence-smoke-2026-04-24.md`

- [ ] **Step 1: Add runtime-only section**

Document why these do not create inbox rows:

```
cwdChanged: context, not notification
titleChanged/tabTitleChanged: context, not notification
scrollbarChanged: useful for activity/line-count heuristics, not persistent inbox
progress set/paused/indeterminate/remove: live state, not persistent inbox
openURLRequested: user action, not notification
readOnly and secureInputChanged(false): state badges, not inbox
secureInputChanged(true): persistent inbox notification, gated and edge-deduped
filesystem filesChanged/gitSnapshotChanged/branchChanged: existing filesystem pipeline
```

- [ ] **Step 2: Commit**

```bash
git add docs/wip/luna361-phase3c-ghostty-terminal-intelligence-smoke-2026-04-24.md
git commit -m "docs(notification-inbox): classify runtime-only terminal signals

Co-authored-by: Codex <noreply@openai.com>"
```

## Task D1: Live OSC visual smoke

**Files:**
- Modify: `docs/wip/luna361-phase3c-ghostty-terminal-intelligence-smoke-2026-04-24.md`

- [ ] **Step 1: Build and launch by PID**

```bash
mise run build
BUILD_PATH=".build-agent-$PPID"
"$BUILD_PATH/debug/AgentStudio" &
APP_PID=$!
```

Do not use `pkill AgentStudio`.

- [ ] **Step 2: Capture baseline**

```bash
peekaboo see --app "PID:$APP_PID" --json
```

- [ ] **Step 3: Emit real terminal sequences in an Agent Studio terminal pane**

Use the terminal pane, not an external Terminal.app, so Ghostty receives the sequences:

```
printf '\a'
printf '\033]9;Agent Studio smoke\a'
printf '\033]777;notify;Agent Studio smoke;desktop notification body\a'
printf '\033]9;4;1;25\a'
printf '\033]9;4;3;80\a'
printf '\033]9;4;0\a'
```

Command-finished smoke:

```
sleep 11; exit 0
```

If shell integration does not emit command-finished in this environment, record that as a smoke limitation and keep the headless `GHOSTTY_ACTION_COMMAND_FINISHED` action-router test as the proof.

- [ ] **Step 4: Verify surfaces**

Use Peekaboo screenshots and app interaction to verify:

```
inbox row appears for OSC desktop notification
toolbar bell dot appears for unread
drawer bell/count/popover sees the notification
worktree pill count increments for source worktree
click-through focuses source pane
progress error creates a notification only if Task B1 landed
renderer unhealthy is covered by headless test, not manual smoke
```

- [ ] **Step 5: Record evidence**

Append:

```
date/time
build command exit code
app PID
sequences emitted
Peekaboo evidence summary
pass/fail matrix
known limitations
```

to `docs/wip/luna361-phase3c-ghostty-terminal-intelligence-smoke-2026-04-24.md`.

- [ ] **Step 6: Commit**

```bash
git add docs/wip/luna361-phase3c-ghostty-terminal-intelligence-smoke-2026-04-24.md
git commit -m "test(notification-inbox): record live Ghostty OSC smoke evidence

Co-authored-by: Codex <noreply@openai.com>"
```

## Task E1: Final verification

- [ ] **Step 1: Run lint**

```bash
mise run lint
```

Expected: exit `0`.

- [ ] **Step 2: Run full tests**

```bash
mise run test
```

Expected: exit `0`.

- [ ] **Step 3: Commit final status**

```bash
git add docs/wip/luna361-phase3-gaps-and-followup-2026-23-04.md docs/wip/luna361-phase3c-ghostty-terminal-intelligence-smoke-2026-04-24.md
git commit -m "docs(notification-inbox): close phase 3c verification status

Co-authored-by: Codex <noreply@openai.com>"
```

## Self-Review Notes

- Spec coverage: terminal notifications, progress, renderer health, scrollback/scrollbar state, CWD/title context, filesystem/git boundary, and live OSC smoke are all represented.
- Placeholder scan: no `TBD` or fake emitter task remains.
- Type consistency: existing `GhosttyEvent` cases are used first; new inbox kinds are reserved for terminal conditions that need durable attention, such as progress error, renderer unhealthy, and secure-input requested.
- Scope honesty: approval/security product subsystems remain separate future work. This plan handles terminal-originated Ghostty intelligence and existing filesystem/git facts only.
