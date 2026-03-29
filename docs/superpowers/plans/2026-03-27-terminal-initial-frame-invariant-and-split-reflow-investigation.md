# Terminal Initial Frame Invariant And Split Reflow Investigation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce that Ghostty terminal surfaces never start without a real initial frame, fix the startup restore path that still creates terminals too early, and add targeted instrumentation to prove the remaining surviving-pane split corruption path.

**Architecture:** Treat startup sizing and split corruption as two separate bugs. Fix the first one now by making initial frame a hard invariant and by forbidding active-tab restore before `WindowLifecycleStore.isReadyForLaunchRestore`. For the second one, do not guess at a renderer fix yet; add narrow trace instrumentation around split insertion, reparenting, and authoritative size sync so the next change is grounded in evidence.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Ghostty/libghostty, zmx, Swift Testing, mise, swift-format, swiftlint

---

## Problem Statement

We currently have two distinct terminal problems:

```text
Bug A: startup terminal born with wrong size
  -> first live panel appears at 800x600-class geometry
  -> startup feels slow / unstable / visibly wrong

Bug B: creating a new pane still corrupts the surviving terminal
  -> old pane stays alive
  -> prompt/current line disappears or blanks
  -> new output often makes it recover
```

These are related to terminal geometry, but they are not the same bug.

## Proven Findings

### A. Starting a Ghostty surface without a real initial frame is a real bug

Current source shape:

- `Ghostty.SurfaceView.init(config:)` currently does:

```swift
super.init(frame: config?.initialFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600))
```

- then immediately reports that frame into Ghostty

That means any terminal creation path that does not pass a real `initialFrame` starts with the wrong geometry.

### B. Startup restore is still bypassing launch-readiness

`WindowLifecycleStore` already has the correct readiness contract:

- `terminalContainerBounds`
- `isLaunchLayoutSettled`
- `isReadyForLaunchRestore`

But `PaneCoordinator.restoreViewsForActiveTabIfNeeded()` still restores when bounds are merely non-empty, instead of requiring `isReadyForLaunchRestore` during the launch phase.

That allows this bad sequence:

```text
early small bounds
-> restoreViewsForActiveTabIfNeeded()
-> live terminal surface created too early
-> later final window size arrives
```

Important nuance:

```text
restoreViewsForActiveTabIfNeeded() is also used for runtime operations
after launch (tab switch, split insertion, worktree open, etc.)
```

So the readiness gate must be launch-only:

```text
before launch settles:
  require isReadyForLaunchRestore

after launch settles:
  never block runtime restore paths on launch-readiness again
```

### C. The split corruption bug is not yet explained only by 800x600

The new pane being born wrong is a smoking gun, but the already-existing surviving pane still corrupts after split insertion.

So:

```text
800x600 / missing initialFrame
  definitely explains the new pane birth problem

surviving old pane corruption
  still needs direct evidence
```

## Desired Invariants

### Invariant 1

```text
No Ghostty terminal surface may be created without a non-empty initialFrame.
If code attempts it, crash immediately.
```

### Invariant 2

```text
Before launch layout settles, no active-tab terminal restore may occur until
WindowLifecycleStore.isReadyForLaunchRestore == true.

After launch layout settles, runtime active-tab restore paths remain allowed.
```

### Invariant 3

```text
We do not change split/redraw behavior further
until we have exact size/order evidence for the surviving pane path.
```

## System Map

### Current bad startup path

```text
Window boot
  -> terminalContainerBounds becomes non-empty early
  -> restoreViewsForActiveTabIfNeeded()
  -> createViewForContent(...)
  -> Ghostty.SurfaceView.init(... initialFrame nil or premature)
  -> wrong terminal born
```

### Desired startup path

```text
Window boot
  -> terminalContainerBounds recorded
  -> launch layout settles
  -> isReadyForLaunchRestore becomes true
  -> only then create/restore terminal surfaces
  -> Ghostty starts with correct initialFrame
```

## File Structure Map

### Modify

- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
  - enforce the hard initial-frame invariant for terminal surface creation

- `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
  - gate `restoreViewsForActiveTabIfNeeded()` on `windowLifecycleStore.isReadyForLaunchRestore`
  - keep trace logs explicit when restore is skipped for unsettled layout

- `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift`
  - audit terminal creation entry points and ensure they either pass a real frame or defer creation until one exists

- `Sources/AgentStudio/App/PaneCoordinator.swift`
  - only if needed to thread explicit initial-frame requirements through coordinator helpers

- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
  - add narrow instrumentation for authoritative geometry sync during split insertion if needed

### Create

- `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceViewInitialFrameTests.swift`
  - lock the initial-frame invariant in tests

- `Tests/AgentStudioTests/App/PaneCoordinatorLaunchGeometryTests.swift`
  - prove that active-tab restore does not create views before launch layout is settled

### Existing tests to extend

- `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`
- `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift`
- `Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift`

## Task 1: Lock The Hard Initial-Frame Invariant

**Files:**
- Create: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceViewInitialFrameTests.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`

- [ ] **Step 1: Write the failing test for terminal surface creation requirements**

```swift
@Test("terminal surface creation rejects nil initial frame")
func terminalSurfaceCreation_rejectsMissingInitialFrame() {
    let config = Ghostty.SurfaceConfiguration(
        workingDirectory: nil,
        startupStrategy: .surfaceCommand(nil),
        initialFrame: nil
    )

    #expect(config.hasValidInitialFrameForSurfaceCreation == false)
}

@Test("terminal surface creation rejects empty initial frame")
func terminalSurfaceCreation_rejectsEmptyInitialFrame() {
    let config = Ghostty.SurfaceConfiguration(
        workingDirectory: nil,
        startupStrategy: .surfaceCommand(nil),
        initialFrame: .zero
    )

    #expect(config.hasValidInitialFrameForSurfaceCreation == false)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-initial-frame-red \
swift test --build-path .build-agent-initial-frame-red \
  --filter GhosttySurfaceViewInitialFrameTests
```

Expected: FAIL because no invariant helper exists yet.

- [ ] **Step 3: Add the invariant helper and the crash**

Required code shape:

```swift
extension Ghostty.SurfaceConfiguration {
    var hasValidInitialFrameForSurfaceCreation: Bool {
        guard let initialFrame else { return false }
        return !initialFrame.isEmpty
    }

    func requireInitialFrameForSurfaceCreation() {
        precondition(
            hasValidInitialFrameForSurfaceCreation,
            "Ghostty terminal surfaces must not start without a non-empty initialFrame"
        )
    }
}
```

And in `Ghostty.SurfaceView.init(config:)`:

```swift
config?.requireInitialFrameForSurfaceCreation()
super.init(frame: config!.initialFrame!)
```

No `800x600` fallback remains.

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-initial-frame-green \
swift test --build-path .build-agent-initial-frame-green \
  --filter GhosttySurfaceViewInitialFrameTests
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceViewInitialFrameTests.swift
git commit -m "fix: require initial frame for terminal surface creation"
```

## Task 2: Stop Active-Tab Restore From Starting Terminals Too Early

**Files:**
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`
- Create: `Tests/AgentStudioTests/App/PaneCoordinatorLaunchGeometryTests.swift`

- [ ] **Step 1: Write the failing launch-gating test**

```swift
@Test
func restoreViewsForActiveTabIfNeeded_doesNotCreateViewsBeforeLaunchLayoutSettles() {
    let harness = makeHarness()

    let pane = harness.store.createPane(
        source: .floating(workingDirectory: harness.tempDir, title: "Early Restore"),
        provider: .zmx
    )
    let tab = Tab(paneId: pane.id, name: "Early Restore")
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)

    harness.windowLifecycleStore.recordTerminalContainerBounds(
        CGRect(x: 0, y: 0, width: 512, height: 552)
    )
    #expect(harness.windowLifecycleStore.isReadyForLaunchRestore == false)

    harness.coordinator.restoreViewsForActiveTabIfNeeded()

    #expect(harness.surfaceManager.createdPaneIds.isEmpty)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-launch-red \
swift test --build-path .build-agent-launch-red \
  --filter PaneTabViewControllerLaunchRestoreTests
```

Expected: FAIL because `restoreViewsForActiveTabIfNeeded()` still restores on mere non-empty bounds.

- [ ] **Step 3: Gate active-tab restore on `isReadyForLaunchRestore` only during launch**

Required behavior:

- while `windowLifecycleStore.isLaunchLayoutSettled == false`:
  - require `windowLifecycleStore.isReadyForLaunchRestore`
  - otherwise return immediately
- once `windowLifecycleStore.isLaunchLayoutSettled == true`:
  - do not block runtime restore paths on launch-readiness anymore
- log the skip with both:
  - `terminalContainerBounds`
  - `isLaunchLayoutSettled`

Required code shape:

```swift
if !windowLifecycleStore.isLaunchLayoutSettled {
    guard windowLifecycleStore.isReadyForLaunchRestore else {
        RestoreTrace.log(
            "restoreViewsForActiveTabIfNeeded skipped launchLayoutUnsettled bounds=... settled=..."
        )
        return
    }
}
```

- [ ] **Step 4: Re-run launch restore tests**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-launch-green \
swift test --build-path .build-agent-launch-green \
  --filter PaneTabViewControllerLaunchRestoreTests
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift \
  Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift
git commit -m "fix: block terminal restore until launch layout settles"
```

## Task 3: Audit Terminal Creation Entry Points For Real Frames

**Files:**
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift`

- [ ] **Step 1: Enumerate all terminal surface creation paths in code comments or local notes**

Must account for:

- startup restore
- restore missing active-tab views
- split insertion / new terminal
- open worktree terminal
- undo / restore
- repair / recreateSurface

- [ ] **Step 2: For each terminal path, make the behavior explicit**

Required rule:

```text
if real initial frame exists:
  create live surface

if real initial frame does not exist:
  do not create live surface
  defer / placeholder / retry path instead
```

- [ ] **Step 3: Add or update focused tests**

Example:

```swift
@Test("new terminal pane creation does not call createSurface until geometry is available")
func newTerminalPaneCreation_defersWithoutGeometry() {
    let harness = makeHarnessCoordinator()
    // arrange missing geometry
    // execute insert
    // expect surface manager createSurface not called yet
}
```

- [ ] **Step 4: Run focused coordinator tests**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-terminal-paths \
swift test --build-path .build-agent-terminal-paths \
  --filter "PaneCoordinatorTests|PaneCoordinatorHardeningTests|PaneTabViewControllerLaunchRestoreTests"
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift \
  Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift \
  Tests/AgentStudioTests/App/PaneCoordinatorTests.swift
git commit -m "fix: require geometry before live terminal creation"
```

## Task 4: Instrument The Surviving-Pane Split Bug

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`

- [ ] **Step 1: Add narrow, durable trace points**

Need exact logs for split insertion:

- pane id
- surface id
- object identifier of the surface view
- frame / bounds before and after
- whether the surface detached and reattached
- every authoritative geometry sync reason and size

- [ ] **Step 2: Add explicit logs to distinguish**

```text
new pane born with frame X
surviving pane resized from Y -> Z
reattach happened / did not happen
authoritative size sync fired with size N
```

- [ ] **Step 3: Build and reproduce on the clean invariant-fixed branch**

Run with:

```bash
: > /tmp/agentstudio_debug.log
AGENTSTUDIO_RESTORE_TRACE=1 .build/debug/AgentStudio
```

Repro:

- startup
- create new pane

- [ ] **Step 4: Capture the evidence**

We want to distinguish:

```text
Hypothesis 1:
  wrong new-pane birth frame is the dominant cause

Hypothesis 2:
  surviving pane corrupts during legitimate resize / reattach even with correct initial frame
```

- [ ] **Step 5: Do not implement the split fix yet**

At the end of this task, stop and summarize:

- what the new pane’s first real frame was
- what the surviving pane’s authoritative resize sequence was
- whether reparenting occurred

- [ ] **Step 6: Commit instrumentation only if it is judged useful enough to keep**

If the logging is only temporary and not worth keeping, do not commit it.

If it is worth keeping:

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift
git commit -m "chore: add terminal split geometry trace logging"
```

## Task 5: Full Verification Of The Startup Fixes

**Files:**
- no new product files required

- [ ] **Step 1: Run formatting, lint, and full tests**

Run:

```bash
mise run format
mise run lint
AGENT_RUN_ID=terminal-init-frame-final mise run test
```

Expected:

- `format` exit `0`
- `lint` exit `0`
- `test` exit `0`

- [ ] **Step 2: Verify startup trace**

Required evidence:

- no terminal surface creation before `isReadyForLaunchRestore == true`
- no Ghostty surface created from the premature small bounds epoch
- no `800x600` fallback path remains in code

- [ ] **Step 3: Verify the built app visually**

Use Peekaboo on the built app and confirm the first live panel no longer appears with tiny wrong geometry.

- [ ] **Step 4: Commit any remaining verification-driven code changes**

If verification revealed no new code changes, skip this step.

If verification required small follow-up fixes:

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift \
  Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift \
  Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceViewInitialFrameTests.swift \
  Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift \
  Tests/AgentStudioTests/App/PaneCoordinatorTests.swift
git commit -m "fix: enforce terminal geometry invariants on startup"
```

## Notes For Implementers

- The hard initial-frame invariant is required even if it exposes more bad callers.
- Do not add another silent fallback frame.
- Do not try to solve the surviving-pane split corruption in the same patch unless instrumentation makes the root cause obvious.
- Fix startup first, then investigate split corruption with evidence.
