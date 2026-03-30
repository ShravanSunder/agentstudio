# Terminal Startup, Ratio Drift, and Redraw Debugging

This note records what we are trying to fix, what evidence we have from code and logs, what we changed, what did not work, and what is still only a hypothesis.

The main trace source is `/tmp/agentstudio_debug.log`.

Every `##` header in this document is a debugging epoch with an explicit timestamp or time window so later readers can match observations, code changes, and trace evidence to a concrete phase of the investigation.

Relevant code paths:
- `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- `Sources/AgentStudio/App/AppDelegate+LaunchRestore.swift`
- `Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift`
- `Sources/AgentStudio/Core/Views/Splits/SplitView.swift`
- `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`

## Debugging Epoch 0 (2026-03-27 to 2026-03-29): Problem Statement

There are three related but distinct problems:

1. Startup launch/restore timing.
   - Terminal surfaces must not be created from provisional startup bounds.

2. Ratio drift across restarts.
   - The split layout should round-trip stably through restart.
   - If the user does not drag a divider, pane ratios should not change.

3. Terminal redraw corruption after restore, split changes, or reparenting.
   - The terminal prompt/current line can disappear even when pane geometry itself looks correct.

The important distinction is:

```text
layout persistence bug:
  ratios change when the user did not resize

terminal redraw bug:
  one logical geometry event produces multiple terminal resizes
```

These two bugs amplify each other, but they are not the same bug.

## Debugging Epoch 1 (2026-03-27T23:47:35Z to 2026-03-27T23:54:43Z): Early Startup Restore At Tiny Bounds

This was the first proven startup bug.

Older runs showed:

```text
terminalContainerBoundsChanged -> 512x552
restoreViewsForActiveTabIfNeeded fires immediately
createView success with tiny initialSurfaceFrame widths
applyLaunchMaximize happens later
```

That meant live terminal surfaces were being created from the first non-empty bounds instead of waiting for launch readiness.

Why it happened:
- `restoreViewsForActiveTabIfNeeded()` only required non-empty bounds.
- It did not wait for `WindowLifecycleStore.isReadyForLaunchRestore`.

What we changed:
- Added a launch-only gate in `PaneCoordinator+ViewLifecycle.swift`:

```text
if launch layout is not settled:
  require isReadyForLaunchRestore
after launch settles:
  runtime restore paths stay open
```

What the trace shows now:

```text
restoreViewsForActiveTabIfNeeded skipped launchLayoutUnsettled bounds={{0, 0}, {512, 552}} settled=false
restoreViewsForActiveTabIfNeeded skipped launchLayoutUnsettled bounds={{0, 0}, {512, 532}} settled=false
launchRestore triggered source=windowRestoreBridge bounds={{0, 0}, {2800, 1151}}
```

Current status:
- This specific early-startup bug appears fixed in the newer runs.

## Debugging Epoch 2 (2026-03-27 to 2026-03-28): Initial Frame Invariant

We also found that Ghostty surfaces must never be created without a real initial frame.

Problem:
- `Ghostty.SurfaceView.init` previously had a hardcoded fallback frame.
- That allowed terminal surfaces to start from invented geometry instead of caller-provided geometry.

What we changed:
- `Ghostty.SurfaceView` now requires a non-optional `SurfaceConfiguration`.
- Surface creation now hard-fails if `initialFrame` is missing or empty.

Current status:
- This guards surface creation at the Ghostty boundary.
- It does not, by itself, explain later ratio drift or prompt-loss bugs.

## Debugging Epoch 3 (2026-03-28 to 2026-03-29): Correcting The "Full-Width Panes" Assumption

At one point we misread partial-width startup panes as necessarily wrong.

That was not the right model.

The saved workspace state intentionally contains split layouts, so narrow panes at startup can be correct if the layout on disk is split.

The real question is not:

```text
why are there split panes at startup?
```

The real questions are:

```text
are the restored ratios the same ones the user left behind?
does the terminal render correctly inside the restored pane frame?
```

Current status:
- The shape of the split tree can be valid even while the restored result is still wrong.

## Debugging Epoch 4 (2026-03-27T23:47:35Z to 2026-03-29T13:49:38Z): Ratio Drift Across Restarts

This is now one of the strongest proven issues.

The key distinction:

```text
persisting ratios is normal
persisting changed ratios that the user did not choose is the bug
```

How ratios persist in this app:

```text
TerminalSplitContainer adjustedRatioBinding setter
  -> action(.resizePane(...))
  -> PaneCoordinator execute
  -> WorkspaceStore.resizePane(...)
  -> WorkspaceStore.markDirty()
  -> WorkspaceStore.persistNow()
  -> workspace.state.json updated
```

So the suspicious part is not `persistNow()` itself.
The suspicious part is that `.resizePane(...)` appears to be firing during startup or layout churn without a real user drag.

What the trace showed in earlier investigation:
- repeated `WorkspaceStore.resizePane` entries
- ratios changing step-by-step
- later `WorkspaceStore.persistNow` writing the new layout

What this means:

```text
the disk file is not the origin of the bug
the disk file is where an accidental in-memory mutation becomes durable
```

Current status:
- Proven model: ratio drift is a mutation-before-persist problem.
- Still open: which non-user path is causing the binding setter to fire.

## Debugging Epoch 5 (2026-03-28T01:02:15Z to 2026-03-29T13:51:10Z): Terminal Redraw / SIGWINCH Storm

The other strong finding is that a single logical restore/reparent event causes several terminal size reports.

The trace shows the same surface often receiving:

```text
sizeDidChange source=init
sizeDidChange source=mountView.layout
sizeDidChange source=setFrameSize
sizeDidChange source=viewDidMoveToWindow
sizeDidChange source=forceGeometrySync
```

Example from the trace:

```text
Ghostty.SurfaceView.sizeDidChange source=mountView.layout logical={696, 1149}
Ghostty.SurfaceView.sizeDidChange source=setFrameSize logical={696, 1149}
Ghostty.SurfaceView.sizeDidChange source=viewDidMoveToWindow logical={696, 1149}
Ghostty.SurfaceView.sizeDidChange source=forceGeometrySync logical={696, 1149}
```

Even when the logical size is the same, each one currently calls:
- `ghostty_surface_set_size(...)`
- `ghostty_surface_refresh(...)`

That means one pane can send multiple resize notifications to the shell for what is effectively one geometry event.

Why this matters:
- repeated resize notifications can force repeated shell redraws
- this matches the visible symptom where the prompt/current line disappears while earlier output remains visible

Current status:
- Proven: there is a size-report storm.
- Still open: whether deduplicating identical backing sizes is sufficient, or whether some paths need stronger ordering guarantees.

## Debugging Epoch 6 (2026-03-27 to 2026-03-28): Failed Geometry Rewrite

We previously tried a broader "authoritative geometry only" rewrite.

That approach:
- suppressed some automatic resize paths
- attempted to centralize geometry sync

It made things worse:
- startup became more fragile
- it exposed an existing launch sequencing bug
- it still did not solve the surviving-pane corruption

Current status:
- That experiment was backed out.
- We are no longer using that as the primary fix direction.

## Debugging Epoch 7 (2026-03-29T13:49:38Z onward): Current Best Model Before Restart-by-Restart Correlation

As of now, the best model is:

```text
Problem A: startup launch timing
  old early restore bug
  appears fixed by launch-only readiness gate

Problem B: ratio drift
  split ratios change and persist without a real user divider drag

Problem C: terminal redraw corruption
  one logical layout event produces multiple Ghostty size updates
```

And the relationship is:

```text
ratio drift
  -> more real pane geometry churn
  -> more chances to hit the terminal resize storm

terminal resize storm
  -> prompt/current-line loss
  -> but does not explain why ratios changed on disk
```

## Debugging Epoch 8 (2026-03-29T13:49:38Z onward): Next Evidence We Still Need

The next debugging slice should answer two questions with logs, not guesses.

### 1. Is `.resizePane(...)` firing without a real divider drag?

We need logging around:
- `TerminalSplitContainer.adjustedRatioBinding(...).set`
- split drag begin/end
- `WorkspaceStore.resizePane(...)`

Goal:

```text
prove whether ratio mutations are happening while isSplitResizing == false
```

### 2. How many distinct backing sizes reach Ghostty for one logical event?

We already know multiple size paths fire.
The next step is to confirm whether they are:
- exact duplicates
- or contradictory intermediate sizes

Goal:

```text
separate:
  duplicate size spam
from:
  genuine rapid size sequence changes
```

### Current Working Hypotheses

### Hypothesis A: Ratio drift is caused by non-user writes through the split binding

This would mean:
- SwiftUI layout/render churn is invoking the `Binding.set`
- or some other code path is writing through the same binding path

This hypothesis is not yet proven.

### Hypothesis B: Prompt loss is caused by repeated terminal size updates for one event

This would mean:
- Ghostty receives too many resize notifications
- the shell redraws repeatedly
- the prompt/current line can be left out of the visible viewport

This hypothesis is strongly supported by the trace, but the exact minimal fix is not proven yet.

### What To Avoid

The current evidence does not justify another broad geometry rewrite.

Avoid:
- suppressing large classes of size updates without proof
- assuming ratio drift and redraw corruption are a single bug
- treating persistence as the source of the problem instead of the place where bad state becomes durable

The next fixes should be narrow and evidence-driven.

## Debugging Epoch 9 (2026-03-29T13:49:38Z to 2026-03-29T13:50:04Z): Baseline Before Restart

User action:
- clear terminal output
- run fresh commands
- close the app

Expected on the next launch:
- same split layout shape
- same pane ratios
- prompt/current line visible in every restored terminal

This baseline matters because it rules out "old garbage from a prior terminal session" as the explanation for the next restore symptom.

## Debugging Epoch 10 (2026-03-29T13:50:04Z to 2026-03-29T13:50:08Z): Restart 1, Window Geometry Correct But Prompt Missing In Some Panes

User observation:
- window geometry looked correct
- split layout looked expected
- only some panes in both tabs were missing the prompt/current line

Trace correlation:

```text
13:50:04Z restoreViewsForActiveTabIfNeeded skipped launchLayoutUnsettled
13:50:04Z launchRestore triggered source=windowRestoreBridge bounds={{0,0},{2800,1151}}
```

The launch gate is working here. This is not the old "create surfaces at 512x552" bug.

What the terminal restore paths did for the affected panes:

```text
init
mountView.layout
setFrameSize
forceGeometrySync
viewDidMoveToWindow async
```

Concrete examples from this restart:

```text
954x1149 pane:
  init -> mountView.layout -> setFrameSize -> forceGeometrySync -> viewDidMoveToWindow

526x1149 pane:
  init -> mountView.layout -> setFrameSize -> forceGeometrySync -> viewDidMoveToWindow

527x1149 pane:
  init -> mountView.layout -> setFrameSize -> forceGeometrySync -> viewDidMoveToWindow

782x1149 pane:
  init -> mountView.layout -> setFrameSize -> forceGeometrySync -> viewDidMoveToWindow
```

What did not happen:

```text
TerminalSplitContainer.adjustedRatioBinding.set: 0
SplitView.drag*: 0
WorkspaceStore.resizePane: 0
```

Conclusion for Restart 1:
- This restart corruption was not caused by ratio mutation.
- It was a terminal restore/redraw event with multiple size reports per pane.
- The symptom matches the prompt/current-line loss bug, not the ratio-drift bug.

## Debugging Epoch 11 (2026-03-29T13:51:09Z to 2026-03-29T13:51:12Z): Restart 2, Same Restore Storm With Worse Visible Corruption

User observation:
- after another restart, pane widths looked more corrupted
- the visual state looked worse than Restart 1

Trace correlation:

```text
13:51:09Z restoreViewsForActiveTabIfNeeded skipped launchLayoutUnsettled
13:51:09Z launchRestore triggered source=windowRestoreBridge bounds={{0,0},{2800,1151}}
```

Again, the launch gate is working. This is still not the early-startup tiny-bounds bug.

The same multi-path size-report pattern appears again:

```text
696x1149 pane:
  init -> mountView.layout -> setFrameSize -> forceGeometrySync -> viewDidMoveToWindow

347x1149 pane:
  init -> mountView.layout -> setFrameSize -> forceGeometrySync -> viewDidMoveToWindow

348x1149 pane:
  init -> mountView.layout -> setFrameSize -> forceGeometrySync -> viewDidMoveToWindow

1398x1149 pane:
  init -> mountView.layout -> setFrameSize -> forceGeometrySync -> viewDidMoveToWindow
```

What still did not happen:

```text
TerminalSplitContainer.adjustedRatioBinding.set: 0
SplitView.drag*: 0
WorkspaceStore.resizePane: 0
```

What did happen:
- `WorkspaceStore.persistNow` still ran
- but it wrote the already-existing layout shape and ratios
- no new ratio mutation path was observed during this restart slice

Conclusion for Restart 2:
- The visual corruption on this restart also does not line up with ratio writes.
- The most specific correlated mechanism remains repeated terminal size reporting during restore.

## Debugging Epoch 12 (2026-03-29T13:50:04Z to 2026-03-29T13:51:12Z): What The Latest Restarts Rule Out

The recent 2026-03-29 restart sequence is especially useful because it rules out one tempting explanation.

It does **not** support:

```text
"the latest prompt-loss/corruption was caused by ratio drift during that restart"
```

Why:

```text
no SplitView drag
no adjustedRatioBinding.set
no WorkspaceStore.resizePane
```

So for the latest restart sequence:

```text
ratio bug:
  not active in the traced restart

terminal redraw bug:
  definitely active in the traced restart
```

This does not mean the ratio-drift bug is gone.
It means the most recent restart corruption can be explained without it.

## Debugging Epoch 13 (2026-03-29T13:51:12Z onward): Updated Model After The Restart Sequence

We now have stronger separation between the two bugs:

```text
Bug A: ratio drift across restarts
  evidenced in earlier sessions
  caused by non-user ratio mutation before persistence

Bug B: prompt/current-line loss after restore
  evidenced in the latest sessions
  happens even when no ratio mutation occurs during that restart
```

This updated model is important because it changes fix ordering:

1. We still need to catch the source of non-user `resizePane(...)` writes.
2. But the currently reproducible restore corruption is primarily a terminal size-report storm problem.

The latest restarts make that separation much clearer than before.

## Debugging Epoch 14 (2026-03-29T13:50:04Z to 2026-03-29T13:56:33Z): Exact Duplicate Sizes Are Deduped, But Distinct Restore Sizes Still Exist

### What changed in the analysis

The earlier "pure SIGWINCH storm" model was too strong.

The important correction is:

```text
exact duplicate backing sizes
  are deduped by Ghostty
```

That means not every repeated Swift-side `sizeDidChange(...)` call turns into a real terminal resize.

### Evidence: Ghostty deduplicates internally

From `vendor/ghostty/src/Surface.zig` line 2422:

```zig
pub fn sizeCallback(self: *Surface, size: apprt.SurfaceSize) !void {
    const new_screen_size = ...;
    if (self.size.screen.equals(new_screen_size)) return;  // ← DEDUP
    try self.resize(new_screen_size);
}
```

Ghostty already deduplicates at the C level. If the backing pixel size matches what the surface already has, `resize()` is never called.

This means:
- Our repeated Swift calls only matter when they produce a new pixel size.
- The duplicate-only version of the resize-storm model was wrong about the impact.

### Evidence: zmx still applies real resize messages

From zmx research (`vendor/zmx/src/main.zig`):
- On client attach, zmx sends an `Init` message with the window size
- zmx calls `ioctl(pty_fd, TIOCSWINSZ, &winsize)` to set the PTY size
- zmx then calls `term.resize(...)`

What this proves:
- same-size reports are not as dangerous as we first thought
- real size changes still propagate through the PTY path

### What the latest traces still show

The latest restart traces still include some genuinely different pixel sizes for the same restore sequence.

Examples from `2026-03-29T13:50:04Z` and `2026-03-29T13:51:09Z`:

```text
347.125 logical width -> backing width 694.25 -> UInt32 694
348 logical width     -> backing width 696      -> UInt32 696

697.25 logical width  -> backing width 1394.5   -> UInt32 1394
696 logical width     -> backing width 1392     -> UInt32 1392

1397.5 logical width  -> backing width 2795     -> UInt32 2795
1398 logical width    -> backing width 2796     -> UInt32 2796
```

So the remaining bug is not explained away by duplicate dedup alone.
Some panes still see real small-step size churn during restore.

### Revised model from the evidence we actually have

The safest statement now is:

```text
Exact duplicate size reports:
  mostly harmless because Ghostty dedups them

Distinct pixel-size changes during restore:
  still real
  still candidates for prompt/current-line loss
```

So the corrected diagnosis is not:

```text
"the bug is lack of SIGWINCH, not too many"
```

The corrected diagnosis is:

```text
"the bug is not a pure duplicate-only resize storm.
Exact duplicates are deduped, but some distinct restore sizes still occur."
```

### What is still hypothesis, not proof

The following ideas are still hypotheses:
- missing prompt because zmx attach reused the exact same size and the shell never redrew
- prompt visibility being restored specifically by a forced size change across restart
- a zmx-side "force redraw on attach" being the minimal fix

Those are plausible, but the current local trace does not prove them yet.

### What to verify next

The next useful verification would be one of:

```text
1. Log at the Ghostty/zmx boundary when a Swift size report is deduped vs when it actually executes resize()
2. Log whether zmx attach sends an init resize whose rows/cols match the previous PTY size exactly
3. Run a controlled "same final size" vs "forced +1px size jiggle" experiment
```

Until then, the right conclusion is narrower:
- the other agent was right to weaken the pure storm theory
- but the trace still supports real restore-time size churn as an active bug source

## Debugging Epoch 15 (2026-03-29T14:00:00Z onward): New Boundary Instrumentation And Next Restart Strategy

We added one more round of instrumentation at the actual resize boundaries.

### New Swift-side instrumentation

In `Ghostty.SurfaceView.sizeDidChange(...)` we now log:

```text
requestedPx={w,h}
currentPx={w,h}
currentGrid={cols,rows}
dedupLikely=true|false
```

This tells us whether a given Swift-side size report is likely to be dropped by Ghostty before `Surface.resize(...)` runs.

### New zmx-side instrumentation

In `vendor/zmx/src/main.zig` we now log:

```text
init resize prev_rows=... prev_cols=... requested_rows=... requested_cols=... changed=true|false
resize prev_rows=... prev_cols=... requested_rows=... requested_cols=... changed=true|false
```

This tells us whether zmx is actually applying a changed terminal size on attach/resize, or just receiving an idempotent same-size message.

### Verification status for the instrumentation

The new instrumentation was verified with:

```text
mise run lint                           -> exit 0
AGENT_RUN_ID=debug-boundary-0329 mise run build -> exit 0
```

### Next restart-loop strategy

Use the freshly built app from the `debug-boundary-0329` build output and run the same restart loop again.

For each restart, capture these two artifacts:

```text
1. /tmp/agentstudio_debug.log
2. ~/.agentstudio/z/logs/zmx.log
```

### What we want to answer on the next run

#### Question 1: Are the bad Swift size reports mostly no-ops?

Interpretation:

```text
If dedupLikely=true for most restore-time sizeDidChange calls:
  duplicate Swift calls are not the main direct cause

If dedupLikely=false for many restore-time calls:
  distinct pixel-size churn is still active at the Ghostty boundary
```

#### Question 2: Does zmx attach with a changed terminal size or not?

Interpretation:

```text
If zmx init resize changed=false on prompt-missing restores:
  same-size attach becomes a stronger hypothesis

If zmx init resize changed=true on prompt-missing restores:
  same-size attach is not sufficient to explain the bug
```

#### Question 3: Does prompt loss correlate better with same-size attach or with distinct size churn?

This is the main decision point for the next diagnosis.

### Decision rule after the next run

After the next restart loop, we should be able to choose between two tighter models:

```text
Model A:
  prompt-loss bug is primarily a same-size reattach / no-redraw problem

Model B:
  prompt-loss bug is primarily caused by distinct restore-time size churn
```

We do not need to guess between them now. The new logs are intended to decide that.

## Debugging Epoch 16 (2026-03-29T14:21:54Z to 2026-03-29T14:23:02Z): Restart 1 On Boundary-Instrumented Build, All Terminal Prompts Missing

User observation:
- after restart, pane geometry looked correct
- terminal content width looked correct
- the prompt/current line disappeared in all terminal panes across both tabs
- non-terminal panes such as Claude/Codex still looked fine

This is stronger than the earlier restart observations because it removes the "only some panes are bad" ambiguity. In this run, terminal prompt loss was effectively global while pane geometry still looked stable.

### Restore-trace correlation

The launch gate still worked:

```text
2026-03-29T14:22:53Z restoreViewsForActiveTabIfNeeded skipped launchLayoutUnsettled bounds={{0,0},{512,552}} settled=false
2026-03-29T14:22:53Z restoreViewsForActiveTabIfNeeded skipped launchLayoutUnsettled bounds={{0,0},{512,532}} settled=false
2026-03-29T14:22:54Z launchRestore triggered source=windowRestoreBridge bounds={{0,0},{2800,1151}}
```

So this run is still not the old early-startup tiny-bounds bug.

### Swift -> Ghostty boundary evidence

The new `dedupLikely` logs show an important pattern:

1. `init` calls are real changes from the placeholder state:

```text
requestedPx={1911,2298} currentPx={800,600} dedupLikely=false
requestedPx={1561,2298} currentPx={800,600} dedupLikely=false
requestedPx={1052,2298} currentPx={800,600} dedupLikely=false
requestedPx={1394,2298} currentPx={800,600} dedupLikely=false
```

2. The later `viewDidMoveToWindow` and `forceGeometrySync` calls are mostly exact no-ops:

```text
source=viewDidMoveToWindow requestedPx={1908,2298} currentPx={1908,2298} dedupLikely=true
source=viewDidMoveToWindow requestedPx={1052,2298} currentPx={1052,2298} dedupLikely=true
source=viewDidMoveToWindow requestedPx={1054,2298} currentPx={1054,2298} dedupLikely=true
source=viewDidMoveToWindow requestedPx={1564,2298} currentPx={1564,2298} dedupLikely=true

source=forceGeometrySync requestedPx={1908,2298} currentPx={1908,2298} dedupLikely=true
source=forceGeometrySync requestedPx={1052,2298} currentPx={1052,2298} dedupLikely=true
source=forceGeometrySync requestedPx={1054,2298} currentPx={1054,2298} dedupLikely=true
source=forceGeometrySync requestedPx={1564,2298} currentPx={1564,2298} dedupLikely=true
```

3. The only distinct restore-time size churn visible in this run comes from `mountView.layout` correcting fractional initial sizes to integer AppKit sizes:

```text
954 pane: currentPx={1911,2298} -> requestedPx={1908,2298} dedupLikely=false
696 pane: currentPx={1394,2298} -> requestedPx={1392,2298} dedupLikely=false
527 pane: currentPx={1052,2298} -> requestedPx={1054,2298} dedupLikely=false
782 pane: currentPx={1561,2298} -> requestedPx={1564,2298} dedupLikely=false
1398 pane: currentPx={2795,2298} -> requestedPx={2796,2298} dedupLikely=false
348 pane: currentPx={694,2298}  -> requestedPx={696,2298}  dedupLikely=false
```

Interpretation:

```text
Most post-restore follow-up size reports are no-ops at the Ghostty boundary.
The only real post-init size changes in this restart are small integer/fractional corrections.
```

That weakens the "huge repeated-resize storm" model substantially for this specific run.

### zmx log correlation

The zmx log did not show the new `init resize prev_rows=... prev_cols=... changed=...` lines we expected.

What it did show:

```text
session already exists, ignoring command session=...
attached session=...
session unresponsive: Timeout
```

That tells us:
- the restart is attaching to already-existing zmx sessions
- at least some of those sessions are timing out / becoming unresponsive

What it does **not** yet tell us:
- whether attach happened with same rows/cols or changed rows/cols
- whether zmx applied a no-op resize or a real resize on attach

Two plausible reasons the new zmx resize logs are missing:

```text
1. The attach path for already-running daemons is not exercising the instrumented init/resize code we expected.
2. The long-lived session daemons were started from an older zmx binary before the new instrumentation was built.
```

At this point, the zmx log is still useful, but it has not yet answered the attach-size question.

### What this restart changes in the model

This restart strongly suggests:

```text
Prompt loss can happen even when:
  - pane geometry is correct
  - most post-init Ghostty size reports are deduped no-ops
```

So the simplest remaining candidates are now:

```text
1. The first real attach/init size is enough to lose prompt state
2. zmx attach/session restore is missing a redraw step
3. session unresponsive / timeout behavior is part of the missing-prompt symptom
```

And the older "lots of repeated identical size writes are directly causing it" explanation is weaker than it was before this run.

## Debugging Epoch 17 (2026-03-29T14:22:54Z to 2026-03-29T14:25:04Z): Restart 2, Pane Widths Visibly Corrupted While Boundary Pattern Stays Similar

User observation:
- after the next restart, pane widths looked visibly more corrupted
- the layout looked worse than Restart 1
- terminal lines came back
- in the short-width panes, the cursor / active prompt row was restored at the wrong vertical position
- the problem remained terminal-specific; non-terminal panes still rendered normally

### Restore-trace correlation

The launch gate still worked:

```text
2026-03-29T14:22:53Z restoreViewsForActiveTabIfNeeded skipped launchLayoutUnsettled bounds={{0,0},{512,552}} settled=false
2026-03-29T14:22:53Z restoreViewsForActiveTabIfNeeded skipped launchLayoutUnsettled bounds={{0,0},{512,532}} settled=false
2026-03-29T14:22:54Z launchRestore triggered source=windowRestoreBridge bounds={{0,0},{2800,1151}}
```

So Restart 2 is also not the old tiny-bounds startup bug.

### Swift -> Ghostty boundary evidence

The same general pattern remained true:

1. `init` was always a real change from the placeholder state:

```text
requestedPx={1911,2298} currentPx={800,600} dedupLikely=false
requestedPx={1561,2298} currentPx={800,600} dedupLikely=false
requestedPx={1052,2298} currentPx={800,600} dedupLikely=false
requestedPx={1394,2298} currentPx={800,600} dedupLikely=false
```

2. Most later follow-up reports were exact no-ops:

```text
source=viewDidMoveToWindow requestedPx={1908,2298} currentPx={1908,2298} dedupLikely=true
source=viewDidMoveToWindow requestedPx={1052,2298} currentPx={1052,2298} dedupLikely=true
source=viewDidMoveToWindow requestedPx={1054,2298} currentPx={1054,2298} dedupLikely=true
source=viewDidMoveToWindow requestedPx={1564,2298} currentPx={1564,2298} dedupLikely=true
```

3. The real post-init size churn again came from fractional-to-integer correction:

```text
954 pane: currentPx={1911,2298} -> requestedPx={1908,2298} dedupLikely=false
527 pane: currentPx={1052,2298} -> requestedPx={1054,2298} dedupLikely=false
782 pane: currentPx={1561,2298} -> requestedPx={1564,2298} dedupLikely=false
```

So Restart 2 did not produce a fundamentally different Ghostty-boundary pattern from Restart 1. The later restore writes were still mostly dedupable no-ops, with only a small number of real pixel changes.

### Workspace / ratio evidence

Even in this visually more corrupted restart, the trace slice still did not show:

```text
TerminalSplitContainer.adjustedRatioBinding.set
SplitView.drag*
WorkspaceStore.resizePane
```

That means the visible width corruption in this restart still does not line up with a newly observed runtime divider-drag path during the restore itself.

`WorkspaceStore.persistNow` continued to fire, but that only tells us state was being saved. It does not, by itself, prove a fresh ratio mutation in this restart slice.

### zmx log correlation

The zmx log again showed:

```text
session already exists, ignoring command session=...
attached session=...
session unresponsive: Timeout
```

And again, it did **not** show the new `init resize prev_rows=... prev_cols=... changed=...` lines we hoped to see.

So after two instrumented restarts, the zmx-side evidence is now:

```text
proven:
  restart attaches to already-running sessions
  some sessions are timing out / becoming unresponsive

not yet proven:
  whether attach is same-size or changed-size at the zmx resize boundary
```

### What Restart 2 adds to the model

Restart 2 matters because it shows:

```text
Worse visible pane corruption does not imply a different Ghostty boundary pattern.
```

That suggests the visible "width corruption" may not be caused by a brand-new category of size event. It may instead be:
- the same restore-time terminal corruption expressed more severely
- compounded by session unresponsiveness / stale restore state
- or a higher-level pane/layout state issue that is not visible in the traced resize command path
- or a cursor/prompt-row restore problem that only becomes obvious in short-width panes

## Debugging Epoch 18 (2026-03-29T14:21:54Z to 2026-03-29T14:25:04Z): Side-By-Side Comparison Of Restart 1 And Restart 2

Across the two latest instrumented restarts:

### What stayed the same

```text
launch gate works
init is always a real size change from placeholder 800x600
most post-init writes are dedupLikely=true
small fractional-to-integer corrections still happen
no SplitView.drag
no adjustedRatioBinding.set
no WorkspaceStore.resizePane in the restore slice
zmx logs show session reuse + timeouts, not resize-detail lines
```

### What changed

```text
Restart 1:
  geometry looked correct
  prompts missing everywhere

Restart 2:
  geometry looked visibly more corrupted
  lines came back
  short-width panes had the cursor/prompt row in the wrong place
```

### Current interpretation after both restarts

The two instrumented restarts together support this reading:

```text
1. Prompt-loss is not explained by fresh ratio writes during these restarts.
2. Prompt-loss is not well explained by large numbers of identical post-init size reports.
3. The remaining active suspects are:
   - the first real init/attach resize
   - session reuse / stale state across zmx attach
   - incorrect cursor/prompt-row restore after content replay, especially in short-width panes
   - zmx session unresponsiveness
   - a higher-level layout/state corruption not captured by resizePane logs
```

## Debugging Epoch 19 (2026-03-29): Upstream Ghostty and zmx Research, Grounded Against Our Logs

We looked up the relevant upstream behavior in the actual Ghostty and zmx source and compared it to our traces.

Upstream repositories:
- `ghostty-org/ghostty`
- `neurosnap/zmx`

### What Ghostty upstream says

From `vendor/ghostty/src/Surface.zig`:

```zig
pub fn sizeCallback(self: *Surface, size: apprt.SurfaceSize) !void {
    const new_screen_size = .{ .width = size.width, .height = size.height };
    if (self.size.screen.equals(new_screen_size)) return;
    try self.resize(new_screen_size);
}
```

Grounded conclusion:

```text
Ghostty deduplicates exact same screen pixel sizes before running Surface.resize().
```

That matches our local `dedupLikely=true` interpretation and weakens the duplicate-only resize-storm theory.

From `vendor/ghostty/src/termio/Termio.zig` and `vendor/ghostty/src/terminal/Terminal.zig`:
- a real size change still propagates into PTY/backend resize
- then into `terminal.resize(cols, rows)`
- and `Terminal.resize` itself also early-returns if `cols` and `rows` are unchanged

Grounded conclusion:

```text
Exact duplicate pixel sizes are cheap.
Distinct pixel-size changes still matter because they can change grid cols/rows and trigger terminal reflow.
```

### What zmx upstream says

From `vendor/zmx/src/main.zig`:
- attach to an existing session still goes through daemon/client init
- `handleInit` serializes terminal state only when:
  - `has_pty_output == true`
  - `has_had_client == true`
- `handleInit` calls `ioctl(TIOCSWINSZ)` and `term.resize(...)`
- then serializes terminal state **after** resize, specifically to capture the correct post-resize cursor location

The zmx-side rationale in source is explicit:

```text
Serialize terminal state BEFORE resize to capture correct cursor position.
Resizing triggers reflow which can move the cursor, and the shell's
SIGWINCH-triggered redraw will run after our snapshot is sent.
```

And then in code the snapshot is taken in the init path around the resize handling so the intended invariant is:

```text
snapshot sent to the client should already reflect the post-resize terminal state
including cursor location
```

Grounded conclusion:

```text
zmx is designed to preserve cursor location across attach/resize by replaying
terminal state after resize, not by relying purely on the shell to redraw later.
```

### The most important mismatch with our app behavior

Our observed restart behavior is:

```text
Restart 1:
  all terminal prompt/current lines missing

Restart 2:
  terminal lines came back
  short-width panes had the cursor/prompt row in the wrong vertical place
```

But upstream zmx’s intended contract is:

```text
after attach + resize + replay,
the client should receive terminal state with the correct post-resize cursor position
```

That means the symptom is no longer well described as:

```text
"shell never redrew"
```

because zmx is explicitly trying to replay a post-resize cursor state even before shell redraw completes.

### What upstream research weakens

The following explanations are now weaker than before:

```text
1. Pure duplicate resize storm:
   weakened by Ghostty dedup and Terminal.resize dedup

2. Pure no-SIGWINCH-on-same-size attach:
   weakened by zmx's design to replay terminal state with post-resize cursor position
```

Those theories are not impossible, but they are no longer the strongest source-backed model.

### What upstream research strengthens

The following explanation is now stronger:

```text
The failing contract is likely in "state replay / cursor placement / viewport restoration"
for restored sessions, especially in narrow panes.
```

Why:
- Ghostty should ignore exact duplicate sizes
- zmx should replay state after resize with the correct cursor location
- yet our restored narrow panes can still show:
  - visible content
  - but wrong cursor/prompt row placement

That points toward:
- mismatch between replayed terminal state and what the Ghostty client surface ends up displaying
- or stale / corrupted session state inside zmx for those panes
- or attach/session-timeout behavior interfering with replay completion

### How our local logs line up with that

Our local logs still show:

```text
zmx:
  session already exists
  attached session=...
  session unresponsive: Timeout
```

And on the app side:

```text
short-width panes:
  do see small real pixel corrections
  but most later writes are dedupLikely=true
```

So the current best grounded clue is:

```text
The remaining bug is less about "too many resize messages"
and more about "after attach/replay, the restored active cursor/prompt state
is wrong or incomplete in some terminal sessions, especially narrow ones."
```

### What remains unproven

We still do **not** have direct proof of:
- whether the missing zmx `init resize prev_rows=...` logs are absent because old daemons are still running
- whether session timeout correlates directly with wrong cursor placement
- whether narrow-width panes are failing because of replay ordering, replay content, or viewport math

Those are still open questions.

This is a better bounded problem than we had before these two runs.

## Debugging Epoch 20: Why zmx Instrumentation Didn't Fire, And What The Timeout Means

### Concrete finding 1: zmx daemons are old binaries

Running `pgrep -fl zmx` shows the daemon processes are long-lived and were started from the pre-instrumented zmx binary:

```text
886 vendor/zmx/zig-out/bin/zmx attach agentstudio--..--89e051b9d401545d /bin/zsh -i -l
3778 vendor/zmx/zig-out/bin/zmx attach agentstudio--..--84fcdac607cd8bba /bin/zsh -i -l
```

The zmx daemon stays alive across app restarts. When AgentStudio restarts and runs `zmx attach`, it connects to the **already running daemon** (the `session already exists` log confirms this). The daemon process is the old binary without the `init resize prev_rows=... changed=...` log line.

The zmx log correctly shows zero `[debug]` level entries. The `handleInit` instrumentation uses `std.log.debug` (line 530 of main.zig), which is filtered out at the default zmx log level.

```text
grep -c "\[debug\]" zmx.log → 0
```

This is a concrete answer: the zmx-side instrumentation exists in code but is not reaching the running daemons because:

```text
1. The daemon binaries are older than the instrumented build
2. Even if they were current, std.log.debug is filtered at runtime
```

### Concrete finding 2: timeout happens BETWEEN restarts, not during attach

The zmx log timestamps for the latest restart cycle:

```text
[1774794114621] attached session=..a3638ee9ec631ab9
[1774794115577] session unresponsive: Timeout    ← 956ms after attach
                r/.agentstudio/z/agentstudio--..--9a177622d958de11
```

The timeout log shows a DIFFERENT session ID than the one that just attached. This means:

```text
The timeout is NOT about the session that just attached.
It is about a DIFFERENT session that was probed and found unresponsive.
```

Looking at the attach pattern more carefully:

```text
attach session=a3638ee9ec631ab9   ← succeeds
attach session=989b13cfaca05586   ← succeeds
attach session=89e051b9d401545d   ← succeeds
session unresponsive: Timeout     ← session 9a177622d958de11
```

The timeout comes from `ipc.probeSession` (ipc.zig line 181-194), which polls the daemon's socket with a 1000ms timeout. If the daemon doesn't respond to an `.Info` probe within 1 second, it's marked unresponsive.

This tells us:

```text
At least one zmx daemon per restart cycle is unresponsive to probe requests.
That session's pane would fail to attach properly.
```

### Concrete finding 3: the zmx Init path sends terminal size from STDOUT

From `vendor/zmx/src/main.zig` line 1213:

```zig
const size = ipc.getTerminalSize(posix.STDOUT_FILENO);
try ipc.appendMessage(alloc, &sock_write_buf, .Init, std.mem.asBytes(&size));
```

And `getTerminalSize` (ipc.zig line 34-40):

```zig
pub fn getTerminalSize(fd: i32) Resize {
    var ws: cross.c.struct_winsize = undefined;
    if (cross.c.ioctl(fd, cross.c.TIOCGWINSZ, &ws) == 0 and ws.ws_row > 0 and ws.ws_col > 0) {
        return .{ .rows = ws.ws_row, .cols = ws.ws_col };
    }
    return .{ .rows = 24, .cols = 80 };  // ← fallback if ioctl fails
}
```

The zmx client gets its terminal size from `ioctl(STDOUT, TIOCGWINSZ)`. Since the zmx process's stdout is the Ghostty surface's PTY, this returns whatever Ghostty last set via `ghostty_surface_set_size`.

The question is: at the moment the zmx client calls `getTerminalSize`, has Ghostty already processed the `sizeDidChange(source=init)` call and set the PTY size? From the trace:

```text
Ghostty.SurfaceView.init → sizeDidChange source=init → ghostty_surface_set_size → PTY gets sized
(then Ghostty creates the surface, which spawns the zmx command)
```

The init `sizeDidChange` happens BEFORE the surface is created (line 228 of GhosttySurfaceView.swift). But `ghostty_surface_set_size` requires a surface to exist. The init flow is:

```text
1. super.init(frame: config.initialFrame!) → NSView created at correct frame
2. sizeDidChange(frame.size, source: "init") → calls ghostty_surface_set_size
   BUT: surface is nil at this point! Guard `guard let surface` returns early!
3. ghostty_surface_new(...) → creates the surface, spawns the zmx command
4. The zmx command runs, calls getTerminalSize(STDOUT)
   → ioctl(TIOCGWINSZ) on the PTY
   → PTY size was NEVER set because step 2 was guarded out
   → returns whatever Ghostty's default initial size is, or the fallback 24x80
```

This is a critical finding. The init `sizeDidChange` fires BEFORE the surface exists, so it's a no-op. The PTY size is set by Ghostty internally during `ghostty_surface_new`, based on the NSView's frame. But there may be a timing gap where the zmx client reads the PTY size before Ghostty finishes setting it up.

### What to verify next

```text
1. Kill all zmx daemons and restart the app to test with fresh daemons
   (eliminates the stale-binary problem)
   Command: pkill -f "zmx attach" && sleep 1

2. Change zmx log level to include debug messages
   (makes handleInit instrumentation visible)

3. Add logging at the Ghostty surface creation boundary to see
   what PTY size is set during ghostty_surface_new

4. Check whether the session that times out correlates with a
   specific missing-prompt pane
```

### Relationship to the restart paradox

The restart paradox (Restart 1: correct sizes, prompt missing; Restart 2: wrong sizes, prompt visible) may be explained by:

```text
Restart 1:
  zmx daemon has old size from previous app session
  new client sends Init with same size (PTY was already at that size)
  ioctl(TIOCSWINSZ) with same size → no SIGWINCH → no shell redraw
  zmx replays terminal state, but shell prompt is readline-managed state
  prompt is missing

Restart 2:
  ratios drifted during Restart 1 (Bug A, unrelated)
  new client sends Init with DIFFERENT size
  ioctl(TIOCSWINSZ) with different size → SIGWINCH → shell redraws
  prompt appears

OR:

  the timed-out session in Restart 1 corresponds to the missing-prompt pane
  the session recovered by Restart 2 or was restarted fresh
```

Both explanations are consistent with the evidence but neither is proven yet.

## Debugging Epoch 21: zmx Init Resize Evidence — The 14x41 Ghost Size

### What the zmx logs now show

With the rebuilt instrumented zmx binary (info-level `handleInit` logging), we can now see exactly what happens at the zmx boundary during each restart.

### Restart 1 (fresh daemons, ~1774795730)

14 sessions attached. 9 had `changed=true`, 5 had `changed=false`.

The `changed=false` sessions (same-size reattach, no SIGWINCH):

```text
9a177622: prev=54x81  requested=54x81  changed=false
9ee4ea3e: prev=54x36  requested=54x36  changed=false
ac921150: prev=54x36  requested=54x36  changed=false
a60e3448: prev=54x294 requested=54x294 changed=false
b1298f57: prev=54x73  requested=54x73  changed=false
```

The `changed=true` sessions overwhelmingly came FROM `prev_rows=14 prev_cols=41`:

```text
84fcdac6: prev=14x41 requested=54x146 changed=true
889f8cb2: prev=14x41 requested=54x36  changed=true
89e051b9: prev=14x41 requested=54x54  changed=true
9698db61: prev=14x41 requested=54x73  changed=true
989b13cf: prev=14x41 requested=54x54  changed=true
9a990ba2: prev=14x41 requested=54x146 changed=true
9eb81260: prev=14x41 requested=54x36  changed=true
ae76062e: prev=14x41 requested=54x294 changed=true
b2595cab: prev=14x41 requested=54x146 changed=true
```

### What is 14x41?

14 rows, 41 columns is NOT a real pane size. It does not correspond to any layout frame in our app.

This is the PTY size that Ghostty assigns internally during `ghostty_surface_new` BEFORE the zmx client reads it via `getTerminalSize(STDOUT_FILENO)`. The zmx client calls `ioctl(STDOUT, TIOCGWINSZ)` immediately in `clientLoop`, and at that moment the Ghostty surface's PTY has not yet received its real size from our Swift code.

Evidence chain:

```text
1. GhosttySurfaceView.init calls sizeDidChange(frame.size, source: "init")
2. BUT: guard let surface returns early because surface is nil at this point
3. ghostty_surface_new(...) creates the surface + PTY
4. Ghostty internally sets some default PTY size (14x41)
5. zmx command is spawned as the PTY's child
6. zmx clientLoop calls getTerminalSize(STDOUT) → gets 14x41
7. zmx sends Init(rows=14, cols=41) to daemon
8. Daemon resizes from prev_size to 14x41 → SIGWINCH
9. LATER: our Swift code sends the real size via setFrameSize/layout/forceGeometrySync
10. zmx sends Resize with the real size → second SIGWINCH
```

This means every zmx session that was killed and restarted goes through a DOUBLE resize:
- First to 14x41 (wrong, from the PTY default)
- Then to the real size (from our Swift geometry sync)

### Restart 2 (reattaching to daemons from Restart 1, ~1774798330)

8 sessions attached. The striking pattern:

```text
SHRINKING from correct to 14x41:
889f8cb2: prev=54x36  requested=14x41  changed=true
9698db61: prev=54x36  requested=14x41  changed=true
9a990ba2: prev=54x72  requested=14x41  changed=true
9eb81260: prev=54x36  requested=14x41  changed=true
a60e3448: prev=54x146 requested=14x41  changed=true
ae76062e: prev=54x146 requested=14x41  changed=true

SAME SIZE (no change):
b1298f57: prev=54x36  requested=54x36  changed=false
b2595cab: prev=54x72  requested=54x72  changed=false
```

The sessions that changed are being resized FROM their correct post-Restart-1 sizes DOWN TO 14x41 again. Then later (from our Swift geometry sync) they get resized back to the real size.

This proves:

```text
Every restart cycle produces a resize storm:
  correct size → 14x41 → correct size

That is 2 SIGWINCHs + 2 terminal reflows for every session.
The 14x41 intermediate reflow corrupts the shell's prompt/cursor state.
```

### Correlation with prompt loss

The `changed=false` sessions in Restart 1 (5 sessions that kept their size) did NOT get the 14x41 intermediate resize. The `changed=true` sessions (9 sessions) DID.

If the prompt loss correlates with the 14x41 intermediate, then:
- `changed=false` sessions should have their prompt
- `changed=true` sessions should have missing/corrupted prompt

This matches the observation that "some panes lose prompt, others don't" and that the behavior varies between restarts.

### Why Restart 2 sometimes shows prompt recovery

In Restart 2, sessions go from correct→14x41→correct. The FINAL size is different from what the daemon had before Restart 2 started (because of ratio drift during Restart 1). So the final resize is a REAL change that triggers SIGWINCH, and the shell redraws the prompt correctly at the final size.

But in Restart 1, if the final size happens to match the daemon's original size (from the previous app session), the final `sizeDidChange` is deduped by Ghostty, and the shell never gets a second SIGWINCH to recover from the 14x41 corruption.

### Root cause

```text
The root cause of the prompt loss is the 14x41 ghost size.

It comes from a timing gap:
  Ghostty creates the PTY with a default grid size
  before our Swift code can set the real size.

The zmx client reads this default and sends it to the daemon.
The daemon reflows to 14x41, corrupting the cursor/prompt position.
The later correction to the real size may or may not trigger a shell redraw,
depending on whether the final size matches what Ghostty already has.
```

### Fix direction

The fix should prevent the zmx client from ever sending 14x41 as the Init size. Options:

```text
Option 1: Delay zmx Init until after the first real sizeDidChange
  zmx clientLoop could wait for a Resize message before sending Init
  but this requires zmx protocol changes

Option 2: Set the PTY size BEFORE ghostty_surface_new
  if we can ioctl(TIOCSWINSZ) on the PTY fd before the zmx process reads it
  but we don't have the PTY fd at the Swift level

Option 3: Pass the real size in the zmx command itself
  add --cols=N --rows=M to the zmx attach command
  zmx uses those for Init instead of getTerminalSize(STDOUT)
  this is the simplest change — it keeps the real size in the command string

Option 4: Have the Ghostty surface set its real size synchronously during creation
  modify the SurfaceView.init to call sizeDidChange AFTER surface creation
  instead of before (where it's guarded out by nil surface)
```

Option 4 is the most correct — it fixes the timing gap at the source. But Option 3 is the most practical and doesn't require Ghostty changes.

## Debugging Epoch 20 (2026-03-29T15:32:06Z to 2026-03-29T15:32:23Z): Launch-Empty Active Tab, Then Wrong Cursor Row In Short Panes

This restart surfaced a second restore bug very clearly.

### User observation

At app launch:

```text
the main selected tab showed no panes at all
```

After clicking a tab:

```text
the panes appeared
the terminal restore bug was still present
short-width panes still had the cursor/prompt row in the wrong place
```

So this cycle had two separate visible failures:

```text
1. launch-empty active tab
2. restored narrow-pane cursor/prompt-row corruption
```

### Correlated app logs for the empty-tab symptom

Before the user clicked anything:

```text
2026-03-29T15:32:06Z ActiveTabContent.body activeTab=E1D45A9A-9806-40B8-BB57-977C4C09547E viewRevision=0 tabPaneCount=4 registeredPaneCount=0 hasTree=false
2026-03-29T15:32:06Z launchRestore triggered source=windowRestoreBridge bounds={{0,0},{2800,1151}}
```

This is direct evidence that:

```text
the active tab already had 4 panes in model state
but the visible tree had not been materialized yet
registeredPaneCount = 0
hasTree = false
```

Then, after the user clicked a different tab:

```text
2026-03-29T15:32:10Z WorkspaceStore.setActiveTab previous=E1D45A9A-9806-40B8-BB57-977C4C09547E new=83962C36-F413-4D88-963A-AFF8CC614116
2026-03-29T15:32:10Z SurfaceManager.createSurface begin pane=...
2026-03-29T15:32:10Z createView success pane=...
2026-03-29T15:32:10Z SurfaceManager.attach requested surface=...
2026-03-29T15:32:10Z TerminalPaneMountView.displaySurface pane=...
2026-03-29T15:32:10Z ActiveTabContent.body activeTab=83962C36-F413-4D88-963A-AFF8CC614116 viewRevision=1 tabPaneCount=4 registeredPaneCount=4 hasTree=true
```

Grounded conclusion:

```text
The launch-empty-tab symptom is real.
It is not just "terminals failed to render."
The active tab tree itself starts out unregistered/absent and becomes visible only after a tab switch.
```

### Correlated app logs for the terminal-state symptom

Once panes did appear, the narrow-pane pattern remained the same:

```text
short panes:
  347 wide -> currentGrid {36,54}
  348 wide -> currentGrid {36,54}

later after additional layout churn:
  325 wide -> currentGrid {33,54}
  326 wide -> currentGrid {33,54}

wider neighbor:
  652 / 653 wide -> currentGrid {68,54}
  1307 / 1308 wide -> currentGrid {137,54}
```

The short panes are still the ones most associated with the wrong cursor/prompt-row placement.

And the same pattern remains true at the Ghostty boundary:

```text
most post-init writes:
  dedupLikely=true

meaningful changes:
  small integer/fractional corrections such as
  2795 -> 2794
  694  -> 696
  648  -> 650
  653  -> 652
  2614 -> 2616
```

Grounded conclusion:

```text
This cycle does not revive the "fresh ratio write during restore" theory.
It still looks like:
  pane/materialization timing bug at launch
plus
  narrow-pane terminal-state restore bug after panes appear
```

### How this changes the overall model

This restart means the "main quest" is now clearly two restore failures that can happen in sequence:

```text
+--------------------------------------+
| Restore Failure A                    |
| active tab launches with no visible  |
| pane tree even though model has panes|
+-------------------+------------------+
                    |
                    | user changes tab / tab state advances
                    v
+--------------------------------------+
| Restore Failure B                    |
| terminals appear, but short-width    |
| panes restore cursor/prompt row      |
| incorrectly                           |
+--------------------------------------+
```

That is a better description of the current behavior than treating everything as a single "terminal redraw" bug.

### What remains supported after this cycle

Still supported:

```text
1. The old early-startup tiny-bounds bug is fixed by the launch gate.
2. Fresh ratio writes were not observed in the restore slice.
3. Exact duplicate size writes are mostly deduped.
4. zmx attach/reuse remains involved.
5. Short-width panes remain the most fragile cases.
```

Newly strengthened:

```text
The app has an additional launch-time pane-tree materialization bug
that is separate from the terminal cursor/prompt-row restore bug.
```

## Debugging Epoch 24 (2026-03-29): Visual Layout Mental Model vs Actual Data Structure

This epoch records an important modeling correction.

### User mental model

The visible UI can look like a single flat row of panes:

```text
[A][B][C][D][E]
```

From that perspective, it is natural to think:

```text
"we only have proportions"
"this is a single-level split"
```

### Actual persisted/rendered model

Grounded in code:
- `Sources/AgentStudio/Core/Models/Layout.swift`
- `Sources/AgentStudio/Core/Views/Splits/SplitTree.swift`

Both define a binary recursive structure:

```swift
indirect enum Node {
    case leaf(...)
    case split(Split)
}

struct Split {
    let id: UUID
    let direction: ...
    let ratio: Double
    let left: Node
    let right: Node
}
```

So the actual data structure is:

```text
binary split tree
```

not:

```text
flat list of panes with one shared proportions array
```

### Why a flat row still appears flat

This is the key visual/model mismatch.

Multiple nested horizontal binary splits still render as one flat horizontal row.

Example:

```text
Visual row:
[A][B][C][D]

Actual model:

        split
       /     \
      A      split
            /     \
           B      split
                 /     \
                C       D
```

Because each nested `SplitView(horizontal, ...)` draws inside the right child of the previous split, the UI still looks like one flat row.

### Why this matters for the restore bug

This modeling detail explains why the problem starts showing up once pane count and subdivision increase.

It is not just:

```text
more panes
```

It is:

```text
deeper binary subdivision of the row
-> smaller leaf widths
-> narrower terminal grids
```

That matches our logs:

```text
~697/698 px  -> ~72/73 cols
~347/348 px  -> ~36 cols
~325/326 px  -> ~33 cols
~172/173 px  -> ~17 cols
```

So the threshold is better described as:

```text
restore becomes fragile once the binary split tree produces very narrow leaves
```

not merely:

```text
"3 panes is bad"
```

### Correlation to restore code

The path is:

```text
workspace.state.json
  -> Layout.Node tree
  -> resolveInitialFramesByTabId(...)
  -> recursive frame assignment per split ratio
  -> Ghostty surfaces created at those leaf frames
  -> zmx attach/replay occurs inside those restored leaf sizes
```

So a visually flat row of panes is still restored through nested binary geometry decisions.

### Grounded conclusion

This matters because it changes the main quest from:

```text
"some arbitrary pane count breaks restore"
```

to:

```text
"deep binary split restore creates narrow leaves, and those narrow leaves are where
cursor/prompt-row restoration becomes unstable"
```

That is a stronger and more code-grounded framing than the earlier flat-row intuition.

## Debugging Epoch 23 (2026-03-29): Steelman And Counterarguments For The Current Leading Root-Cause Theory

This epoch does not replace any earlier section. It records the strongest version of the current leading theory and the strongest grounded counterarguments against treating it as proven root cause.

### Steelman of the current leading theory

The strongest current theory is:

```text
zmx replays terminal state before the attach resize settles,
then Ghostty resize/reflow changes prompt/input placement,
and narrow panes are where that mismatch becomes visible.
```

This theory fits several grounded facts:

```text
1. zmx handleInit serializes terminal state before calling ioctl(TIOCSWINSZ) and term.resize
2. Ghostty Screen.resize can clear prompt/input lines when prompt_redraw is enabled
3. narrow panes are consistently the ones with wrong cursor/prompt-row placement
4. exact duplicate post-init size writes are mostly deduped, so the bug is not well explained by
   "lots of identical resize spam"
5. zmx logs show attach/reuse/timeouts, so session state is definitely part of the picture
```

ASCII view:

```text
+-------------------------------+
| existing zmx session          |
| old cursor / old prompt row   |
+---------------+---------------+
                |
                | handleInit
                v
+-------------------------------+
| zmx serializes terminal state |
| before resize                  |
+---------------+---------------+
                |
                | replay to client
                v
+-------------------------------+
| Ghostty client paints replay  |
+---------------+---------------+
                |
                | then resize/reflow
                v
+-------------------------------+
| prompt/input lines can move   |
| or be cleared for redraw      |
+---------------+---------------+
                |
                v
+-------------------------------+
| content visible               |
| cursor/prompt row wrong       |
| worst in short-width panes    |
+-------------------------------+
```

If this theory is right, the failing contract is:

```text
replayed terminal state cursor position
!=
post-resize prompt/input position that Ghostty ends up expecting
```

### Counterargument 1: the 14x41 / 24x80-style ghost-size explanation is still not sufficient

Earlier sections identify a "ghost size" path and argue it may be the root cause.

The strongest grounded objection is:

```text
the latest restart slices show the active bug even when most later writes are dedupLikely=true,
and the symptom has evolved from "prompt missing" to "cursor row wrong in short panes"
```

That means the ghost-size story is a plausible contributor, but it does not yet explain the full symptom set by itself.

Grounded evidence:

```text
Restart 1:
  prompts missing globally

Restart 2:
  lines came back
  short-width panes had wrong cursor/prompt row placement
```

If the root cause were only "a bad initial ghost size", the doc would still need to explain why the symptom shape changes that much across restarts.

### Counterargument 2: old daemons are not a complete explanation for missing zmx instrumentation

An earlier section attributes missing zmx boundary logs to old long-lived daemons.

That is now too strong as a complete explanation.

Grounded evidence from current `zmx.log`:

```text
creating session=...ae76062e0d304adc
creating session=...a60e34486802fbbe
creating session=...b2595cabde65439b
creating session=...b1298f57139e2ac3
creating session=...889f8cb21d2a3197
creating session=...9a990ba28780f9f4
creating session=...9698db61ef426f5d
creating session=...9eb81260a99e2c91
```

That means:

```text
at least some current workspace sessions are being created with the current build,
not only inherited from stale daemons
```

So the absence of expected zmx boundary logs still needs explanation.

### Counterargument 3: there is clearly a second restore bug before terminal replay is even visible

We now have direct evidence for:

```text
ActiveTabContent.body ... tabPaneCount=4 registeredPaneCount=0 hasTree=false
```

That is a separate launch-time failure:

```text
model has panes
UI tree absent
no terminal-state replay can be visible yet because the pane tree is not materialized
```

So any single-cause explanation focused only on zmx replay or Ghostty resize is incomplete.

ASCII split of the problem:

```text
+------------------------------------+     +------------------------------------+
| Failure A                          |     | Failure B                          |
| active tab launches empty          | --> | panes visible, but narrow terminal |
| registeredPaneCount=0, hasTree=false|    | cursor/prompt row restored wrong   |
+------------------------------------+     +------------------------------------+
```

### Counterargument 4: zmx timeouts matter, but the direct linkage is still unproven

Grounded evidence:

```text
session unresponsive: Timeout
probe slow (Timeout), proceeding to attach session=...
stale socket found, cleaning up session=...
```

This is enough to say:

```text
zmx session health is unstable during our restart cycles
```

But it is not yet enough to say:

```text
the exact session that timed out is the exact pane with wrong cursor row
```

We do not yet have a strict pane/session-to-symptom correlation proving that.

### Current bounded conclusion

The best grounded statement after steelmanning and pushback is:

```text
The leading theory is still "replay-before-resize plus prompt/cursor restore mismatch,"
especially in narrow panes.

But it is not proven as the sole root cause because:
1. launch-empty active tab is a separate failure,
2. some zmx sessions are fresh, so stale-daemon explanations are incomplete,
3. timeout correlation to a specific bad pane is not proven,
4. the symptom changes across restarts in a way the simple ghost-size story does not fully explain.
```

### What would move this from theory to proof

We need one of these forms of evidence:

```text
1. zmx handleInit logs showing pre-serialize cursor/cols/rows and post-resize cursor/cols/rows
   for the exact bad narrow pane

2. a direct pane/session mapping between:
   - session unresponsive / probe slow
   - wrong cursor/prompt-row pane

3. proof that the empty-active-tab bug and the narrow-pane cursor bug share one upstream cause,
   or proof that they do not
```

Until then, the root cause is not fully settled.

## Debugging Epoch 22: Grounded Source Of The 14x41 Ghost Grid

### Where 14x41 comes from — exact code references

The zmx logs show `prev_rows=14 prev_cols=41` for fresh daemon sessions. This section traces where that number originates, with exact file:line references.

**Step 1: Ghostty Surface.init hardcodes 800x600**

File: `vendor/ghostty/src/apprt/embedded.zig` line 465-477

```zig
pub fn init(self: *Surface, app: *App, opts: Options) !void {
    self.* = .{
        .app = app,
        .platform = try .init(opts.platform_tag, opts.platform),
        .userdata = opts.userdata,
        .core_surface = undefined,
        .content_scale = .{
            .x = @floatCast(opts.scale_factor),
            .y = @floatCast(opts.scale_factor),
        },
        .size = .{ .width = 800, .height = 600 },   // ← line 475
        ...
    };
```

Every `ghostty_surface_new` call goes through this init. The surface starts at 800x600 pixels regardless of what NSView frame was set on the Swift side.

**Step 2: Our Swift init — surface creation then sizeDidChange**

File: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`

```text
line 152: super.init(frame: config.initialFrame!)
          → NSView frame = correct size (e.g. 954x1149)

line 186: self.surface = ghostty_surface_new(ghosttyApp, &surfaceConfig)
          → Ghostty creates the surface at its hardcoded 800x600 (embedded.zig:475)
          → Ghostty creates PTY with grid computed from 800x600
          → Ghostty spawns the zmx command as the PTY's child process
          → zmx process starts running CONCURRENTLY

line 250: sizeDidChange(frame.size, source: "init")
          → surface IS non-nil at this point (set at line 186)
          → ghostty_surface_set_size(surface, realWidth, realHeight)
          → Ghostty resizes PTY to real grid
```

The `sizeDidChange(source: "init")` at line 250 DOES fire with a live surface and DOES send the real size. But between line 186 (zmx spawned) and line 250 (real size sent), the zmx process has already started and may have already called `getTerminalSize(STDOUT)` — reading the 800x600-derived 14x41 grid from the PTY before Ghostty received the real size.

This is a race condition: the zmx child process and the Swift init code run concurrently. The zmx process reads the PTY size (14x41) before line 250 sends the real size to Ghostty.

**Step 3: zmx reads the PTY size — gets the 800x600-derived grid**

File: `vendor/zmx/src/main.zig` lines 346-356

```zig
fn spawnPty(self: *Daemon) !c_int {
    const size = ipc.getTerminalSize(posix.STDOUT_FILENO);  // ← line 347
    var ws: cross.c.struct_winsize = .{
        .ws_row = size.rows,    // ← 14
        .ws_col = size.cols,    // ← 41
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };
    const pid = cross.forkpty(&master_fd, null, null, &ws);  // ← PTY at 14x41
```

The zmx daemon's STDOUT is the Ghostty surface's PTY. At this moment, the PTY has the 800x600-derived grid (14 rows, ~41 cols with padding). zmx creates its own PTY at that size and spawns the shell.

File: `vendor/zmx/src/main.zig` lines 1360-1365

```zig
const init_size = ipc.getTerminalSize(pty_fd);  // ← reads 14x41 from zmx PTY
var term = try ghostty_vt.Terminal.init(daemon.alloc, .{
    .cols = init_size.cols,   // ← 41
    .rows = init_size.rows,   // ← 14
    .max_scrollback = daemon.cfg.max_scrollback,
});
```

**Step 4: the real size arrives later**

After `ghostty_surface_new` returns, AppKit layout runs and `setFrameSize` fires with the correct size. That calls `sizeDidChange` which now reaches `ghostty_surface_set_size` (because surface is no longer nil). Ghostty resizes the PTY. zmx receives a Resize message and resizes its terminal.

But by then, the zmx daemon has already initialized at 14x41 and potentially replayed session state at that wrong grid.

### The math

With observed font metrics from our traces (cellWidthPx=19, cellHeightPx=42):

```text
800px / 19px per cell = 42.1 → with padding → ~41 cols
600px / 42px per cell = 14.3 → 14 rows
```

This matches `prev_rows=14 prev_cols=41` in the zmx logs exactly.

### What is grounded vs what is still hypothesis

Grounded in code:

```text
1. Ghostty Surface.init hardcodes .size = { 800, 600 }
   → vendor/ghostty/src/apprt/embedded.zig:475

2. Our sizeDidChange(source: "init") fires AFTER surface exists (line 250) and DOES send the real size.
   But ghostty_surface_new at line 186 already spawned the zmx child process before line 250 runs.
   This is a race: zmx reads the PTY size before our sizeDidChange corrects it.
   → Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift:186, 250

3. zmx reads the 800x600-derived grid via getTerminalSize(STDOUT)
   → vendor/zmx/src/main.zig:347

4. zmx initializes its terminal at 14x41
   → vendor/zmx/src/main.zig:1360-1363

5. The zmx logs show prev_rows=14 prev_cols=41 for fresh sessions
   → ~/.agentstudio/z/logs/*.log
```

Still hypothesis (not proven):

```text
1. Whether the 14x41 intermediate grid directly causes the prompt loss
2. Whether the timing gap between surface creation and first real setFrameSize
   is long enough for zmx to replay session state at the wrong size
3. Whether fixing this timing gap would fix the prompt loss
```

## Debugging Epoch 24: Quantitative Log Evidence For The 800x600 → 14x41 Race

This epoch adds quantitative evidence from the actual log data, not theory.

### Fact 1: 71 out of 71 init sizeDidChange entries show currentPx={800,600}

Every `sizeDidChange source=init` entry with `currentPx` instrumentation shows the same pattern:

```text
grep -c "sizeDidChange source=init.*currentPx" /tmp/agentstudio_debug.log → 71
grep "sizeDidChange source=init.*currentPx" ... | grep -v "currentPx={800,600}" → 0
```

100% of surface inits start from `currentPx={800,600} currentGrid={41,14}`. Zero exceptions across 71 entries spanning multiple restart cycles (14:21:54 through 16:03:12).

This is not a one-off. It is the universal starting state for every Ghostty surface in our app.

### Fact 2: Two zmx sessions from the same restart show the race winning both ways

Session `8358261bb70812b1` (from `~/.agentstudio/z/logs/`):

```text
pty spawned pid=9681
daemon started pty_fd=6
client connected fd=7
init resize prev_rows=54 prev_cols=294 requested_rows=54 requested_cols=294 changed=false
```

The daemon's PTY started at 54x294 — the CORRECT size. `changed=false` — no resize needed.
This means `spawnPty → getTerminalSize(STDOUT)` read the PTY AFTER Ghostty had already set the real size.

Session `ae5bfc7fa93e7c7d` (from `~/.agentstudio/z/logs/`):

```text
pty spawned pid=17965
daemon started pty_fd=6
client connected fd=7
init resize prev_rows=14 prev_cols=41 requested_rows=54 requested_cols=294 changed=true
```

The daemon's PTY started at 14x41 — the 800x600-derived WRONG size. `changed=true` — resize applied.
This means `spawnPty → getTerminalSize(STDOUT)` read the PTY BEFORE Ghostty had set the real size.

Both sessions are from the same app launch. The difference is timing: one zmx process read the PTY size before `sizeDidChange(source=init)` at GhosttySurfaceView.swift:250 executed, the other read it after.

This is direct evidence of a race condition, not a theory.

### Fact 3: The session that got 14x41 then experienced rapid connect/disconnect churn

Session `ae5bfc7fa93e7c7d` continued:

```text
client disconnected fd=7 remaining=0
client connected fd=7 total=1
client disconnected fd=7 remaining=0
client connected fd=7 total=1
client disconnected fd=7 remaining=0
client connected fd=7 total=1
client disconnected fd=7 remaining=0
client connected fd=7 total=1
client disconnected fd=7 remaining=0
```

5 connect/disconnect cycles after the first client. Each cycle is a zmx client attaching and immediately exiting. This matches the "Process Exited" crash loop visible in the user's screenshot (11ms runtime).

Session `8358261bb70812b1` (the one that got the correct size) shows no such churn — just one client connection that stayed stable.

### Fact 4: The app-side log confirms repeated surface creation for the same pane

```text
grep "createSurface begin" /tmp/agentstudio_debug.log | sed 's/.*pane=//' | sed 's/ .*//' | sort | uniq -c | sort -rn | head -5

  32 019D30DA-D746-7A49-AD6D-E9550C9B11AA
  32 019D2F70-36E0-78F9-989B-13CFACA05586
  32 019D2F6F-3076-728E-9A17-7622D958DE11
  32 019D2F6F-2E6F-72B0-A363-8EE9EC631AB9
  29 019D31B9-C920-737B-84FC-DAC607CD8BBA
```

Some panes had their surface created 32 times across the debugging session. Each creation starts from `currentPx={800,600}`, sends the real size, but the zmx child process has already raced to read the PTY.

### What this evidence proves

```text
Proven:
1. Every Ghostty surface starts at 800x600 internally (embedded.zig:475)
   — 71/71 init entries confirm this
2. The zmx daemon can read either the correct or incorrect PTY size depending on timing
   — two sessions from the same launch demonstrate both outcomes
3. The session that got the wrong size experienced immediate client churn
   — 5 rapid connect/disconnect cycles
4. The app recreates surfaces many times per pane
   — up to 32 times for a single pane ID
```

### What this evidence does NOT prove

```text
Not proven:
1. Whether the 14x41 starting grid directly causes the prompt/cursor loss
   (the session that got correct size — did it have a correct prompt? we don't have that correlation)
2. Whether the connect/disconnect churn is caused by the wrong size or by something else
   (correlation is not causation — the zmx binary was also rebuilt in Debug mode)
3. Whether fixing the race would fix all three bugs
   (launch-empty-tab, prompt loss, and ratio drift are still not proven to share one root cause)
```

### What the other agent's counterarguments mean in light of this data

Epoch 23 raised four counterarguments. Here is how this new evidence interacts with each:

```text
Counterargument 1: "ghost size doesn't explain changing symptoms across restarts"
  Still valid. The 14x41 race is real, but the varying symptom shape (missing prompt vs wrong cursor row)
  is not explained by the race alone. The race produces a consistent starting condition (14x41),
  but what happens AFTER the correction (reflow, replay, cursor placement) may vary.

Counterargument 2: "some sessions are fresh, so stale-daemon is incomplete"
  Strengthened by this data. Session ae5bfc7f was a FRESH daemon (pty spawned in this run)
  and still got 14x41. The race is in the fresh-daemon path too, not only in stale reattach.

Counterargument 3: "there is a separate empty-tab bug"
  Unchanged. The 14x41 race does not explain registeredPaneCount=0 / hasTree=false.
  That is still a separate pane-tree materialization failure.

Counterargument 4: "timeout-to-pane correlation is unproven"
  Unchanged. We still don't have a strict mapping from "session X timed out" to "pane Y has wrong cursor."
```
## Debugging Epoch 2026-03-29T15:10:00-04:00 — Hard Cutover To Flat Pane Strips

This epoch replaced the binary split-tree layout model with a flat ordered pane-strip model for pane containers.

### What changed

- `Sources/AgentStudio/Core/Models/Layout.swift`
  - replaced recursive `Node/Split` tree structure with:
    - ordered `panes`
    - ordered `dividerIds`
    - preserved sibling `ratio` values
- `Sources/AgentStudio/Features/Terminal/Restore/TerminalPaneGeometryResolver.swift`
  - switched pane-frame resolution from recursive split subdivision to one-pass flat strip allocation
- `Sources/AgentStudio/Core/Models/FlatTabStripMetrics.swift`
  - new shared geometry helper for flat pane-strip frames and divider frames
- `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`
  - new shared flat strip renderer for pane containers
- `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`
  - tab container now renders from flat strip metrics instead of recursive split tree
- `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
  - drawer container now renders from the same flat strip primitive

### What was removed from the production pane-layout path

- `Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift`
- `Sources/AgentStudio/Core/Views/Splits/SplitTree.swift`
- `Sources/AgentStudio/Core/Views/Splits/TerminalPaneView.swift`
- `Sources/AgentStudio/Core/Models/SplitRenderInfo.swift`
- `ViewRegistry.renderTree(for:)`

This was an intentional hard cutover. No compatibility layer was kept for the old binary tree model.

### Grounded verification

- `swift build --build-path .build-agent-flatlayout-cutover2`
  - exit `0`
- `swift test --build-path .build-agent-flatlayout-cutover2 --filter LayoutFlatStripTests`
  - passed
- `swift test --build-path .build-agent-flatlayout-cutover2 --filter WorkspaceStoreDrawerTests`
  - passed
- `swift test --build-path .build-agent-flatlayout-cutover2 --filter TerminalPaneGeometryResolverTests`
  - passed
- `swift test --build-path .build-agent-flatlayout-cutover2 --filter ActionExecutorTests`
  - passed
- `swift test --build-path .build-agent-flatlayout-cutover2 --filter PaneCloseTransitionCoordinatorTests`
  - passed
- `swift test --build-path .build-agent-flatlayout-cutover2 --filter PaneCoordinatorHardeningTests`
  - passed
- `swift test --build-path .build-agent-flatlayout-cutover2 --filter PaneTabViewControllerCommandTests`
  - passed
- `swift test --build-path .build-agent-flatlayout-cutover2 --filter Luna295DirectZmxAttachIntegrationTests`
  - passed
- `mise run lint`
  - exit `0`
- `AGENT_RUN_ID=flatcutover0329g mise run test`
  - exit `0`
  - non-E2E/default parallel suite block passed in `3.772s`
  - serialized WebKit suites passed
  - `E2ESerializedTests` and `ZmxE2ETests` were skipped by task configuration

### Important behavior change in command-driven pane creation

During the cutover, command-driven pane creation initially regressed because new terminal / drawer pane commands still relied on `restoreViewsForActiveTabIfNeeded()` to materialize views after inserting panes into canonical state.

That caused:

- no immediate surface creation when trusted bounds already existed
- no later creation on reveal/bounds in some cases because the launch gate still guarded the retry path

The fix was:

- command-driven pane creation now uses `createViewForContentUsingCurrentGeometry(pane:)` first
- if geometry is unavailable, it leaves the `.preparing` placeholder and falls back to `restoreViewsForActiveTabIfNeeded()`
- `restoreViewsForActiveTabIfNeeded(forceWhenBoundsExist:)` now allows command/reveal-driven restores without weakening the startup launch gate globally

### Current status after cutover

- pane containers are now flat strips in production code
- the old binary tree model is no longer on the live production path
- restart/restore regressions tied to hidden nested split ancestry are removed at the app layout layer

## Debugging Epoch 2026-03-29T15:40:00-04:00 — Startup Blank Visible Tab Was Launch-Settled Ordering

### Observation

After the flat-strip cutover:

- restart width corruption was gone
- the active visible tab could still come up blank at startup until a manual tab switch

The trace for blank startups showed:

```text
ActiveTabContent.body ... registeredPaneCount=0 hasTree=false
terminalContainerBoundsChanged bounds=512x552
restoreViewsForActiveTabIfNeeded skipped launchLayoutUnsettled
terminalContainerBoundsChanged bounds=512x532
restoreViewsForActiveTabIfNeeded skipped launchLayoutUnsettled
terminalContainerBoundsChanged bounds=2800x1151
restoreViewsForActiveTabIfNeeded skipped launchLayoutUnsettled
launchRestore triggered source=windowRestoreBridge ...
```

That means the visible tab already had final usable bounds, but the active-tab restore was still gated off because `isLaunchLayoutSettled` had not been recorded yet.

### Grounded root cause

`MainWindowController` was marking launch settled in the wrong order:

- `windowDidResize`
- `applyLaunchMaximizeIfNeeded` when already at target frame

Both paths did:

```text
1. force layoutSubtreeIfNeeded()
2. then recordLaunchLayoutSettled()
```

That ordering let the terminal container publish its final `2800x1151` bounds while
`WindowLifecycleStore.isLaunchLayoutSettled == false`, so
`restoreViewsForActiveTabIfNeeded()` skipped at exactly the moment it should have succeeded.

### Fix

The order was reversed:

```text
1. recordLaunchLayoutSettled()
2. then force layoutSubtreeIfNeeded()
```

Files:

- `Sources/AgentStudio/App/MainWindowController.swift`

### Verification

- `swift test --build-path .build-agent-flatlayout-cutover2 --filter PaneTabViewControllerLaunchRestoreTests`
  - passed
- `swift test --build-path .build-agent-flatlayout-cutover2 --filter Luna295DirectZmxAttachIntegrationTests`
  - passed

### Remaining issues after this fix

- narrow panes still show prompt/cursor-row corruption
- newly created narrow panes can still show the same prompt-row issue

Those remaining issues are no longer layout corruption; they are terminal-state/render behavior after correct geometry.

## Debugging Epoch 2026-03-29T20:15:00-04:00 — Narrow-Pane Cursor Bug Is Below The Layout Layer

### Observation

After the flat-strip cutover:

- restart width corruption was gone
- small-width panes still restored with the prompt/cursor row in the wrong place

For the bad panes in the active 5-pane tab:

- `019D3B13-58BA-70E2-8E9C-C4158339FF9C`
- `019D3B13-5EA5-71E2-989D-1232E980A811`

the app-side geometry was already correct and stable:

```text
logical = 347.5 x 1149
backing = 695 x 2298
grid    = 36 cols x 54 rows
```

The restore trace showed:

```text
init:
  currentGrid = 41x14
  requested   = 36x54

our narrow-pane redraw nudge:
  36x54 -> 37x54 -> 36x54

after that:
  forceGeometrySync dedupLikely=true
  viewDidMoveToWindow dedupLikely=true
```

So the bad cursor row survives after the pane reaches its final stable size.

### Grounded conclusion

This remaining bug is no longer:

- ratio drift
- flat layout math
- width corruption
- repeated post-restore resize churn

It is now localized to reattaching existing narrow sessions after correct geometry has already settled.

The matching zmx session suffixes for the bad panes are:

- `8e9cc4158339ff9c`
- `989d1232e980a811`

and `zmx.log` still only shows:

```text
session already exists
attached session=...
```

### Next evidence to collect

Local-only zmx instrumentation was added around the attach/resize path to log:

- `session`
- `has_pty_output`
- `has_had_client`
- pre-serialize `rows/cols`
- pre-serialize cursor `{x,y,pending_wrap}`
- serialized output length
- post-resize `rows/cols`
- post-resize cursor `{x,y,pending_wrap}`

This instrumentation is for tracing only and is not intended for commit.

The next restart should let us answer:

```text
for a bad 36-column pane,
does zmx restore a cursor state that is already inconsistent
before or immediately after resize?
```

## Debugging Epoch (2026-03-29T20:11:00Z): New Pane Insertion Reparents All Existing Surfaces

### Problem under investigation

When a new pane is created (split right/left), the LEFT (existing) pane loses its terminal prompt/content. The new pane works fine.

### Grounded evidence from logs

Even after the flat layout cutover, inserting a new pane causes ALL existing surfaces in the tab to go through `viewDidMoveToWindow window=false` then `viewDidMoveToWindow window=true reparent=true`.

From `/tmp/agentstudio_debug.log` at 20:11:19, when a new pane is created on tab 2:

```text
5 existing surfaces go window=false in sequence:
  viewId=...cf600 window=false  (696.5px wide, 72 cols)
  viewId=...ced00 window=false  (697px wide, 72 cols)
  viewId=...cf300 window=false  (347.5px wide, 36 cols)
  viewId=...cf000 window=false  (347px wide, 36 cols)
  viewId=...cea00 window=false  (347.5px wide, 36 cols)

Then 5 surfaces from the OTHER tab appear with reparent=true:
  viewId=...0e2100 window=true reparent=true  (697px)
  viewId=...0e1e00 window=true reparent=true  (347.5px)
  viewId=...0e1800 window=true reparent=true  (347.5px)
  viewId=...0e2400 window=true reparent=true  (697px)
  viewId=...0e1b00 window=true reparent=true  (697px)

Then the new surface is created:
  createSurface begin pane=019D3B38-5446-70D4-83F9-65945D745FC4

Then the ORIGINAL 5 surfaces go window=false AGAIN and then window=true reparent=true AGAIN.
```

Total: **223 reparenting events across the entire debugging session.**

### What this means

SwiftUI is removing and re-adding ALL `PaneViewRepresentable` NSViews from the window hierarchy when the `FlatPaneStripContent` re-renders. This happens because:

1. Layout changes (new pane inserted, ratios change)
2. `FlatPaneStripContent.body` is inside a `GeometryReader`
3. The `GeometryReader` re-evaluates, recomputes `FlatTabStripMetrics`
4. `ForEach(metrics.paneSegments, id: \.paneId)` has a new item count
5. SwiftUI rebuilds the hosting view tree, removing and re-adding NSViews

Even though `ForEach` uses stable pane IDs, the addition of a new item can cause SwiftUI to restructure its internal hosting, which triggers `viewDidMoveToWindow(nil)` → `viewDidMoveToWindow(window)` on all existing surfaces.

### How this relates to the LEFT pane losing its terminal

During the reparenting cycle:

```text
1. Existing surface removed from window (window=false)
   → Ghostty surface may stop rendering
   → CVDisplayLink may stop (if visible && focused check fails)

2. Surface re-added to window (window=true, reparent=true)
   → viewDidMoveToWindow async fires sizeDidChange
   → but the size may be the SAME as before
   → if same size → Ghostty deduplicates → no resize → no SIGWINCH
   → shell never redraws prompt
   → terminal shows stale content or blank
```

This is the same pattern as the restart prompt-loss bug, but triggered by pane insertion instead of app restart.

### What is NOT yet proven

```text
1. Whether the reparenting is the direct cause of the blank terminal
   (correlation with the user's observation, but not strict causation proof)
2. Whether preventing the reparenting would fix the issue
3. Whether SwiftUI's ForEach actually NEEDS to reparent when item count changes
   (it might be avoidable with different view identity or layout approach)
```

### Relationship to the restart prompt-loss bug

Both bugs share the same mechanism:
- Surface goes through window=false → window=true
- Size may not change
- Shell doesn't get a redraw signal
- Prompt/content is lost

The difference is the trigger:
- Restart: surfaces reparented during app launch/restore
- New pane: surfaces reparented during SwiftUI ForEach structural change

## Debugging Epoch (2026-03-29T20:33:45Z): Pane Insertion Does NOT Reparent — Corrected Model

### Evidence from new instrumentation

With `PaneViewRepresentable.makeNSView`, `dismantleNSView`, and `FlatPaneStripContent.body` logging, the insertion path is now traced.

**During new pane insertion (20:33:45, paneCount 3→4):**

```text
FlatPaneStripContent.body paneCount=4 segmentCount=4 geoSize={2800,1151}
PaneViewRepresentable.makeNSView paneId=019D3B4D-7487 (NEW pane only)
```

No `dismantleNSView` for existing panes. No `viewDidMoveToWindow window=false` for existing surfaces. The `ForEach` with stable pane IDs correctly adds only the new representable.

**During second insertion (20:33:49, paneCount 4→5):**

```text
FlatPaneStripContent.body paneCount=5 segmentCount=5 geoSize={2800,1151}
PaneViewRepresentable.makeNSView paneId=019D3B4D-8605 (NEW pane only)
```

Same — only the new pane gets a `makeNSView`. Existing panes untouched.

**During RESTART (20:33:36 and 20:36:21), different behavior:**

```text
FlatPaneStripContent.body paneCount=3 geoSize={512,552}   ← pre-maximize
FlatPaneStripContent.body paneCount=3 geoSize={2800,1151} ← post-maximize
  makeNSView × 3                                          ← creates all
  dismantleNSView × 3                                     ← DESTROYS all
FlatPaneStripContent.body paneCount=3 geoSize={2800,1151} ← re-evaluates
  makeNSView × 3                                          ← RECREATES all
```

The restart dismantle→recreate cycle is triggered by GeometryReader re-evaluating as the window goes from 512px to 2800px during maximize. This is a restart-specific problem, not a pane-insertion problem.

### Correction to the earlier model

The earlier Epoch stated "SwiftUI reparents all pane views when a new pane is inserted." That was wrong for the current flat layout.

Corrected:

```text
Pane insertion: NO reparenting of existing surfaces (ForEach stable IDs work)
App restart:    YES reparenting of all surfaces (GeometryReader resize triggers dismantle+recreate)
```

### What this means for the "left pane goes blank on insertion" bug

If existing surfaces are NOT reparented during insertion, the blank left pane has a different cause. Possible candidates:

```text
1. Focus change — the new pane takes focus, the old pane loses it
   → CVDisplayLink stops if visible && focused is false
   → but unfocused panes normally keep their last rendered frame

2. The existing pane's frame/size changes (halved ratio) but the Ghostty surface
   doesn't receive the resize because setFrameSize is deduped or layout hasn't settled

3. SwiftUI's .offset() / .frame() modifier change causes an intermediate
   zero-size or clipped frame on the existing pane

4. The user observation might be about the NEW pane (right side) being blank,
   not the existing (left side) — need to confirm with the user
```

These are hypotheses, not proven. Need user confirmation of which pane goes blank and additional logging of the existing pane's frame/size changes during insertion.

## Debugging Epoch (2026-03-29T20:33:36Z): Why SwiftUI Dismantles And Recreates Representables On Startup

### Grounded evidence

From the logs, the dismantle→recreate cycle happens between the THIRD and FOURTH `FlatPaneStripContent.body` evaluation, both at the same `geoSize={2800,1151}`:

```text
body paneCount=3 geoSize={2800,1151} → makeNSView × 3
dismantleNSView × 3
body paneCount=3 geoSize={2800,1151} → makeNSView × 3
```

The geometry didn't change. What changed was `store.viewRevision` — bumped by `bumpViewRevision()` during the restore path after creating views.

### Why viewRevision bump causes full teardown

From `Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift` line 40-73:

```swift
var body: some View {
    let currentViewRevision = store.viewRevision  // ← @Observable tracks this
    ...
    if let activeTabId, let tab {
        FlatTabStripContainer(
            layout: tab.layout,
            ...
            action: action,              // ← closure
            shouldAcceptDrop: ...,       // ← closure
            onDrop: ...,                 // ← closure
            ...
        )
    }
}
```

`FlatTabStripContainer` takes closures (`action`, `shouldAcceptDrop`, `onDrop`). Closures cannot conform to `Equatable`. SwiftUI cannot compare two `FlatTabStripContainer` values.

When `viewRevision` changes:
1. `ActiveTabContent.body` re-evaluates (because `@Observable` tracks `viewRevision`)
2. A new `FlatTabStripContainer` struct is created
3. SwiftUI cannot tell if it's equal to the previous one (closures prevent comparison)
4. SwiftUI treats it as a new view → tears down the old subtree → creates new subtree
5. All child `PaneViewRepresentable` instances get `dismantleNSView` → `makeNSView`
6. All Ghostty surfaces go through `viewDidMoveToWindow(nil)` → `viewDidMoveToWindow(window)`

### Why ForEach stable IDs don't help

`ForEach(metrics.paneSegments, id: \.paneId)` has stable IDs, but those IDs are within a `ForEach` instance. When SwiftUI recreates the parent `FlatTabStripContainer` (and its child `FlatPaneStripContent` and its child `GeometryReader`), the `ForEach` itself is a new instance. The stable IDs only prevent churn WITHIN a single `ForEach` lifetime. They don't survive parent view recreation.

### What this means

The dismantle→recreate cycle is not caused by geometry changes. It's caused by SwiftUI's inability to diff view structs that contain closures. Every `@Observable` property change that triggers `ActiveTabContent.body` re-evaluation causes a full teardown of the pane hosting tree.

### Grounded in code

```text
1. FlatTabStripContainer takes closures → cannot be Equatable
   → Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift

2. ActiveTabContent.body reads store.viewRevision → re-evaluates on bump
   → Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift:42

3. bumpViewRevision fires during restore after creating views
   → Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift

4. Logs confirm dismantle→recreate at same geoSize after viewRevision bump
   → /tmp/agentstudio_debug.log at 20:33:36
```

### What is NOT yet proven

```text
1. Whether removing closures from FlatTabStripContainer would prevent the teardown
2. Whether using @EnvironmentObject or other indirection for action dispatch would help
3. Whether SwiftUI has a way to mark a view subtree as "stable" despite parent identity changes
4. Whether the dismantled NSView containers retain their Ghostty surface state correctly
   across the dismantle→recreate cycle (the same lazy swiftUIContainer is returned)
```

## Debugging Epoch (2026-03-29): Complete Inventory Of What Can Trigger Pane Representable Teardown

### The core problem

`PaneViewRepresentable` wrapping Ghostty surfaces should never be dismantled and recreated. It should only receive `updateNSView` calls. But our logs show `dismantleNSView` → `makeNSView` cycles happening on startup.

### Mechanism: SwiftUI view identity invalidation

A `PaneViewRepresentable` is dismantled when SwiftUI considers its parent view to be a NEW view rather than an UPDATE of an existing view. This happens when SwiftUI cannot prove the parent is equal to its previous value.

`FlatTabStripContainer` takes closures (`action`, `shouldAcceptDrop`, `onDrop`). Closures cannot be compared. So whenever `ActiveTabContent.body` re-evaluates and creates a new `FlatTabStripContainer`, SwiftUI treats it as a new view and rebuilds the entire subtree.

### Trigger 1: `store.viewRevision` changes (bumpViewRevision)

`ActiveTabContent.body` reads `store.viewRevision` at line 42. Any bump triggers body re-evaluation → new `FlatTabStripContainer` → teardown.

Callers of `store.bumpViewRevision()`:

```text
PaneCoordinator+ViewLifecycle.swift:608  — after restoring visible panes (stage 1)
PaneCoordinator+ViewLifecycle.swift:631  — after restoring hidden panes (stage 2 batch)
PaneCoordinator+ViewLifecycle.swift:637  — after restoring hidden panes (final)
PaneCoordinator+ViewLifecycle.swift:801  — after restoreViewsForActiveTabIfNeeded creates views
PaneCoordinator+ActionExecution.swift:637  — after repair action
PaneCoordinator+ActionExecution.swift:655  — after repair action
PaneCoordinator+TerminalPlaceholders.swift:52  — after placeholder mode change
PaneCoordinator+TerminalPlaceholders.swift:61  — after placeholder mode change
PaneCoordinator+TerminalPlaceholders.swift:76  — after new placeholder creation
```

9 call sites. Every one can cause full pane teardown.

### Trigger 2: `store.activeTabId` changes

`ActiveTabContent.body` reads `store.activeTabId` at line 43. Tab switches trigger body re-evaluation → teardown.

### Trigger 3: Any `@Observable` property on `store` accessed via `store.tab($0)`

Line 44: `let tab = activeTabId.flatMap { store.tab($0) }`. This reads the tab's layout, activePaneId, zoomedPaneId, minimizedPaneIds. Any change to these triggers re-evaluation.

### Trigger 4: `GeometryReader` size changes

`FlatTabStripContainer.body` has `GeometryReader { tabGeometry in ... }` at line 27. When the terminal container resizes (window maximize, split view resize), the geometry proxy changes → body re-evaluates → child views may be recreated.

### Trigger 5: `FlatPaneStripContent.body` has its own `GeometryReader`

Line 18. Nested `GeometryReader` means two levels of geometry-dependent re-evaluation.

### Trigger 6: `managementMode.isActive` changes

`FlatTabStripContainer.body` reads `managementMode.isActive`. Toggling management mode triggers body re-evaluation.

### Trigger 7: `appLifecycleStore.isActive` changes

`FlatTabStripContainer.body` reads `appLifecycleStore.isActive`. App activate/deactivate triggers body re-evaluation.

### Which of these actually caused the observed teardown

From the logs at 20:33:36, the teardown happened between:

```text
body at geoSize={2800,1151} → makeNSView × 3  (first creation after restore)
body at geoSize={2800,1151} → dismantleNSView × 3 → makeNSView × 3  (same size, teardown+recreate)
```

The geometry didn't change. The most likely trigger was `bumpViewRevision()` at `PaneCoordinator+ViewLifecycle.swift:801`, which fires immediately after `restoreViewsForActiveTabIfNeeded` creates views. This bump causes `ActiveTabContent.body` to re-evaluate → new `FlatTabStripContainer` (with closures SwiftUI can't compare) → full subtree teardown.

### Why this shouldn't happen

None of these triggers should cause `PaneViewRepresentable` teardown. The pane content didn't change. The pane IDs didn't change. Only the parent view struct was recreated because SwiftUI can't diff closures.

The `ForEach(id: \.paneId)` stable IDs protect against churn WITHIN a single `ForEach` lifetime. But when the `ForEach`'s parent is torn down, the `ForEach` itself is destroyed and all its children are dismantled, regardless of stable IDs.

### Relationship to the terminal bugs

Every teardown→recreate cycle causes:
1. `viewDidMoveToWindow(nil)` on all Ghostty surfaces (window goes away)
2. `viewDidMoveToWindow(window)` when recreated (window comes back)
3. If the size didn't change → Ghostty deduplicates → no SIGWINCH → shell doesn't redraw
4. Prompt/content may be lost

This is the shared upstream cause for:
- Startup prompt loss (triggered by `bumpViewRevision` after restore)
- Tab switch prompt loss (triggered by `activeTabId` change)
- Any `@Observable` change on `WorkspaceStore` that touches tab state

## Debugging Epoch (2026-03-29T20:36:22Z): Late Lifecycle Injection Is A Proven Startup Recreate Trigger

The startup trace now gives us a direct trigger, not just a general SwiftUI suspicion.

Evidence:
- `AppDelegate.applicationDidFinishLaunching` calls `showWindow(nil)` and then `wireLifecycleConsumers()`
- `wireLifecycleConsumers()` calls `paneTabViewController()?.setAppLifecycleStore(appLifecycleStore)`
- `PaneTabViewController.setAppLifecycleStore` calls `replaceSplitContentView()` when the controller is already loaded
- the trace shows `PaneViewRepresentable.dismantleNSView` after `mainWindow showWindow` and `appDidFinishLaunching: end`
- the same pane bridge objects are then recreated immediately afterward
- the same Ghostty surfaces report `viewDidMoveToWindow ... reparent=true wasDetached=true`

Conclusion:
- late `AppLifecycleStore` injection is a proven startup recreate trigger
- the fix should remove the post-load hosting replacement path entirely
- we should keep the terminal hosting subtree stable and update lifecycle state in place before it is built

## Debugging Epoch (2026-03-29T22:55:49Z): Startup Reparenting Fixed, Tab Switch Teardown Remains

### After the lifecycle injection fix

With constructor injection of `AppLifecycleStore`, the startup sequence shows:

```text
grep -c "dismantleNSView" → 0 (during startup)
grep -c "reparent=true" → 0 (during startup)
makeNSView count = 11 (one per pane, created once, never dismantled)
```

Startup reparenting is eliminated.

### Tab switch still causes dismantle→recreate

After switching to a new tab, all 6 panes from the previous tab were dismantled:

```text
PaneViewRepresentable.dismantleNSView × 6
```

The ancestry chain confirms these are inside the SAME `NSHostingView<ActiveTabContent>` (id `0x...afaa1400`), which stays in the window. SwiftUI is dismantling the representables because the tab content changed, not because the hosting view moved.

### Why this happens — grounded in architecture and external research

Our `ActiveTabContent.body` conditionally renders the active tab's content:

```swift
if let activeTabId, let tab {
    FlatTabStripContainer(layout: tab.layout, ...)
}
```

This is a single-content model: one `NSHostingView` renders whichever tab is active. When the active tab changes, SwiftUI destroys the old tab's `ForEach` children and creates new ones for the incoming tab. Inactive tabs have no views in the SwiftUI tree at all.

This contradicts how SwiftUI's native `TabView` works. From external research:

Source: https://oleb.net/2022/swiftui-view-lifecycle/ (Ole Begemann, 2022)
```text
"A TabView starts the lifetime of all child views right away, even the non-visible tabs.
onAppear and onDisappear get called repeatedly as the user switches tabs,
but the tab view keeps the state alive for all tabs."
```

Source: https://developer.apple.com/forums/thread/683138 (Apple Developer Forums)
```text
Conditionally rendering views (if/else or switch on selection) does NOT preserve view state.
.hidden() also fails because it changes the view hierarchy structure.
```

Source: https://vicegax.substack.com/p/nsviewrepresentable-breaks (2024)
```text
NSViewRepresentable views can become blank/unresponsive after being removed from
and re-added to the view hierarchy. Fix: use NSViewControllerRepresentable.
```

Source: https://gist.github.com/Amzd/2eb5b941865e8c5cccf149e6e07c8810
```text
Community workaround for SwiftUI TabView state loss: use actual UITabBarController
behind the scenes, with each tab having its own persistent hosting controller.
```

### What the correct architecture would be

Instead of one `NSHostingView` swapping content, each tab should have its own persistent view subtree. Options:

```text
Option A: Per-tab NSHostingView
  Each tab gets its own NSHostingView in AppKit.
  PaneTabViewController shows/hides them at the AppKit level.
  SwiftUI never sees a structural change — each tab's ForEach is stable.
  Tab switch = show/hide NSViews, not create/destroy SwiftUI content.

Option B: Render all tabs in SwiftUI, show/hide with opacity/offset
  All tabs' pane strips exist in the SwiftUI tree simultaneously.
  Non-active tabs are hidden via .opacity(0) and .allowsHitTesting(false).
  This keeps all NSViewRepresentable instances alive.
  But it means all terminals render simultaneously (GPU cost).

Option C: Keep current model but accept the teardown
  Live with the dismantle→recreate on tab switch.
  Ensure the PaneViewRepresentable returns the same swiftUIContainer
  (which it already does via the lazy property) so the NSView survives.
  Focus on making the surface recovery after reparenting reliable.
```

### What is grounded vs hypothesis

Grounded:
```text
1. Startup reparenting is fixed by constructor injection (0 dismantles on startup)
2. Tab switch causes dismantle→recreate (6 dismantles observed)
3. This is caused by conditional rendering in ActiveTabContent.body
4. SwiftUI's native TabView preserves ALL tab children — our architecture doesn't match
5. External research confirms this is a known SwiftUI limitation
```

Not proven:
```text
1. Whether per-tab NSHostingView would eliminate all terminal issues
2. Whether the tab switch teardown is causing user-visible bugs
   (the pane NSViews survive via the lazy container — they may re-enter the window fine)
3. Whether Option C (accept teardown, fix recovery) is sufficient
```

## Debugging Epoch (2026-03-29T23:00:00Z): How SwiftUI TabView Actually Works — Research Findings

### How TabView preserves views internally

Source: Perplexity AI research with high search context, cross-referencing Apple docs, Swift Forums, and community analysis.

Key findings:

```text
1. TabView keeps ALL tab content views alive simultaneously in the render tree.
   Inactive tabs are hidden, not destroyed.

2. NSViewRepresentable inside TabView is NOT dismantled on tab switch.
   makeNSView is called once. updateNSView handles changes.
   viewDidMoveToWindow does NOT fire on tab switch.
   The NSView stays in the window hierarchy.

3. @State preservation is via render tree identity.
   All tabs have stable view identity because they all exist in the tree simultaneously.
   No conditional rendering = no identity change = no state loss.

4. On macOS, TabView uses SwiftUI's own hosting mechanism, NOT NSTabViewController.
   No NSTabViewController in the view debugger hierarchy.

5. For heavy stateful NSView content (terminals, web views),
   the recommended pattern is per-tab NSHostingView at the AppKit level,
   NOT SwiftUI TabView.
```

### Why our architecture is wrong

Our `ActiveTabContent.body` does conditional rendering:

```swift
if let activeTabId, let tab {
    FlatTabStripContainer(layout: tab.layout, ...)
}
```

This is the OPPOSITE of what TabView does. We destroy the inactive tab's SwiftUI subtree and rebuild the active tab's subtree on every switch. TabView keeps all subtrees alive and hides inactive ones.

For NSViewRepresentable, this means:
- TabView: NSView stays in window, never leaves, no reparenting
- Our approach: NSView removed from window, dismantled, recreated on switch

### Recommended architecture for our use case

For macOS apps hosting heavy stateful NSViews (Ghostty terminals, WKWebViews):

```text
Per-tab NSHostingView at the AppKit level

Each tab gets its own NSHostingView (or NSViewController wrapping one).
PaneTabViewController manages showing/hiding at the AppKit layer.
SwiftUI inside each tab never sees structural changes.
Tab switch = AppKit show/hide, not SwiftUI create/destroy.
```

This matches what the community UIKitTabView gist does, and is the pattern recommended for heavy NSView content.

### What this means for our remaining bugs

```text
The tab switch dismantle→recreate is caused by our architecture,
not by SwiftUI being inherently broken.

SwiftUI CAN preserve NSViewRepresentable across tab switches —
TabView proves this. We just need to adopt the same approach:
keep all tab views alive, show/hide at the AppKit level.
```

### Sources

```text
- betterprogramming.pub: "Working Around the Shortfalls of SwiftUI's TabView"
- forums.swift.org: "Replicating TabView view hierarchy behavior"
- oleb.net: "Understanding SwiftUI view lifecycles" (2022)
- developer.apple.com: WWDC 2022 session 10075
- vicegax.substack.com: "NSViewRepresentable breaks" (2024)
- kodeco.com: "Using SwiftUI in AppKit" (macOS Apprentice v2)
```

## Debugging Epoch (2026-03-29T23:54:17Z): Proven — Prompt Loss On Pane Insert Is zmx, Not Ghostty

### Experiment

Bypassed zmx entirely by forcing all terminal panes to use plain shell (`/bin/zsh -i -l`) instead of `zmx attach`. No other code changes.

Code change: `PaneCoordinator+ViewLifecycle.swift` — both `createView` and `createFloatingTerminalView` zmx paths replaced with plain shell command.

### Result

Created 3 panes on startup, then added 2 more (3→4→5). Existing panes resized from full width to narrower widths. **All prompts survived.** No prompt loss. No blank panes.

### What this proves

```text
Proven:
  Pure Ghostty handles resize from wide→narrow correctly.
  The terminal reflow from 146→73 cols preserves the prompt.
  The shell (zsh) receives SIGWINCH and redraws correctly.

  The prompt loss on pane insertion is caused by zmx,
  not by Ghostty's terminal reflow or our SwiftUI hosting.
```

### What this means for the fix

The remaining prompt-loss bugs (on pane insertion and on restart) are both zmx issues:

```text
1. New pane insertion: existing pane resizes → zmx receives Resize message →
   something in zmx's resize handling corrupts the cursor/prompt state

2. Restart: zmx reattach with same or different size →
   zmx's terminal state replay + resize sequence loses the prompt
```

Both need investigation at the zmx level — specifically in `handleResize` and `handleInit` in `vendor/zmx/src/main.zig`.

### What is NOT the cause

```text
- Ghostty's terminal reflow (proven by this experiment)
- SwiftUI reparenting during pane insertion (proven by earlier logs — zero dismantles)
- The 800x600 ghost size (that's a startup-specific issue, not pane insertion)
- Our AppKit/SwiftUI hosting architecture (no reparenting on insert)
```

## Debugging Epoch (2026-03-29T23:55:00Z): Root Cause Found — zmx prompt_redraw + Missing State Serialization

### Evidence chain

Three code research agents traced the full path through zmx and Ghostty VT. Combined with the pure-Ghostty experiment (zero prompt loss without zmx), the root cause is now grounded in specific code.

### The mechanism, with file:line references

```text
1. Our app calls ghostty_surface_set_size(new_width, new_height)
   → Ghostty surface resizes its terminal immediately

2. SIGWINCH reaches zmx client → client sends Resize(73, 54) to daemon

3. Daemon handleResize (vendor/zmx/src/main.zig:571-606):
   → ioctl(TIOCSWINSZ) on shell PTY (line 584)
   → term.resize(alloc, 73, 54) (line 585)

4. term.resize calls Terminal.resize (vendor/ghostty/src/terminal/Terminal.zig:2820-2865):
   → calls Screen.resize with prompt_redraw = self.flags.shell_redraws_prompt

5. Screen.resize (vendor/ghostty/src/terminal/Screen.zig:1698-1750):
   → BEFORE reflow, checks:
     if prompt_redraw != .false AND cursor.semantic_content != .output
   → If cursor is on a prompt/input line: CLEARS the prompt cells
   → THEN performs reflow at new column count (line 1753)

6. The daemon's internal terminal now has:
   → Cleared prompt cells
   → Reflowed content at 73 cols
   → Updated cursor position

7. Shell receives SIGWINCH → outputs redraw sequences

8. Daemon reads shell output, feeds through vt_stream.nextSlice(),
   broadcasts RAW bytes to client

9. Client's Ghostty terminal processes the shell output
   BUT: client never received the daemon's post-resize terminal state
   Client's terminal may be at a different reflow state than the daemon
```

### Why this causes prompt loss

The daemon's `Screen.resize()` clears prompt lines at step 5 BEFORE reflow. This is designed for direct terminal emulators where the shell's SIGWINCH redraw arrives at the SAME terminal that cleared the prompt. The clear + redraw are atomic.

In zmx, the daemon clears the prompt in ITS terminal, but the CLIENT's Ghostty terminal never sees that clear. When the shell's redraw output arrives at the client, the client processes it against a terminal state that doesn't match the daemon's — they're desynchronized.

### The specific code gap

`handleResize` (vendor/zmx/src/main.zig:571-606) does NOT serialize and send terminal state to clients after resize. Compare:

```text
handleInit (lines 487-569):
  1. Serialize terminal state via serializeTerminalState() → send to client
  2. THEN resize (ioctl + term.resize)
  Result: client gets consistent state

handleResize (lines 571-606):
  1. Resize (ioctl + term.resize)
  2. Return — sends NOTHING to client
  Result: client state diverges from daemon
```

The serialization function already exists (vendor/zmx/src/util.zig:211-239) and captures full screen content, cursor, modes, scrolling region.

### Fix options

```text
Option 1: Serialize after resize
  After term.resize(), call serializeTerminalState() and send to client.
  This resynchronizes the client with the daemon's post-resize state.
  Same pattern as handleInit.

Option 2: Disable prompt_redraw in zmx
  When zmx calls term.resize(), set shell_redraws_prompt = false first.
  This prevents Screen.resize from clearing prompt lines.
  The shell's SIGWINCH response handles the redraw naturally.
  Simpler but may miss other state that prompt_redraw affects.

Option 3: Both
  Disable prompt_redraw to prevent intermediate corruption,
  AND serialize state for full resync.
  Most robust.
```

### Grounded vs hypothesis

```text
Grounded in code:
1. Screen.resize clears prompt lines when prompt_redraw is enabled
   → vendor/ghostty/src/terminal/Screen.zig:1698-1750
2. handleResize does NOT send state to client
   → vendor/zmx/src/main.zig:571-606
3. handleInit DOES send state to client
   → vendor/zmx/src/main.zig:520-536
4. serializeTerminalState captures full screen + cursor + modes
   → vendor/zmx/src/util.zig:211-239
5. Pure Ghostty without zmx does NOT lose prompts on resize
   → proven by experiment at 23:54:17

Hypothesis (not yet tested):
1. Whether adding state serialization to handleResize fixes the bug
2. Whether disabling prompt_redraw alone is sufficient
3. Whether there are other state divergence issues beyond prompt clearing
```

## Debugging Epoch (2026-03-30): Summary Of All Attempted Fixes And Current State

### What we tried and what each proved

```text
Fix 1: prompt_redraw=false in zmx handleInit + handleResize
  Result: Startup prompts fixed. Pane insertion prompts still lost.
  Proved: zmx-side prompt_redraw was causing startup prompt loss.
  Proved: zmx-side prompt_redraw is NOT the only cause of pane insertion prompt loss.

Fix 2: Skip term.resize() entirely in zmx handleResize
  Result: No handleResize events fire during pane insertion.
  Proved: The pane insertion prompt loss doesn't go through handleResize at all.

Fix 3: Delayed ghostty_surface_refresh after resize (150ms)
  Result: Prompt still missing after the delay.
  Proved: The issue is not just rendering timing.
  Proved: The shell's redraw output either never arrives or doesn't restore the prompt.

Fix 4: Env var initial size (ZMX_INIT_COLS/ZMX_INIT_ROWS)
  Result: Made things worse (% character, wrong rendering).
  Proved: Hardcoded cell metrics are fragile. Reverted.
```

### What the pure Ghostty experiment proved

```text
Without zmx: zero prompt loss on any operation (startup, insertion, resize).
With zmx: prompt loss on startup (fixed by prompt_redraw patch) and on pane insertion (unfixed).
```

### The fundamental architecture problem

zmx sits in the middle of the PTY data path:
```text
Shell → daemon PTY → daemon reads → daemon socket → zmx client → client stdout → Ghostty PTY → Ghostty renders
```

This adds latency and complexity to every byte of shell output. Meanwhile, Ghostty's own terminal runs `prompt_redraw` clearing during resize, expecting the shell's redraw to arrive within microseconds. With zmx in the path, it arrives later or not at all.

The zmx client uses buffered I/O (`stdout_buf` ArrayList) and only flushes to stdout when `poll` indicates stdout is ready. The initial prompt output could be stuck in this buffer.

### The proposed new direction

Instead of trying to fix zmx's data path issues, remove zmx from the live terminal data path entirely:

```text
Normal operation: Ghostty spawns shell directly (pure Ghostty, no prompt issues)
Background: zmx daemon keeps a parallel PTY alive for session persistence
On app restart: query zmx daemon for terminal state, feed to Ghostty surface
```

This requires:
1. Direct zmx IPC from Swift (speaking the zmx socket protocol)
2. Separating "live terminal" from "session persistence"
3. Using zmx only for restore, not for live terminal multiplexing

### zmx IPC protocol (from DeepWiki research)

zmx exposes these IPC messages over Unix domain sockets:
```text
Tag 0: Input    — send keyboard input to PTY
Tag 1: Output   — daemon sends PTY output to client
Tag 2: Resize   — client tells daemon new terminal size
Tag 3: Detach   — client disconnects
Tag 6: Info     — query session info (pid, clients, cwd)
Tag 7: Init     — initial attach with terminal size
Tag 8: History  — get terminal scrollback content
Tag 9: Run      — send a command to the shell via PTY
Tag 10: Ack    — acknowledgment
```

These could be used for programmatic control from Swift without going through the zmx CLI.

## Debugging Epoch (2026-03-30T01:30:00Z): Complete Investigation Summary — Why We're Changing Architecture

### The journey

This debugging session spanned ~12 hours of systematic investigation. Here is what we tried, what each attempt proved, and why we arrived at an architectural change rather than a point fix.

### Problem statement

Terminal panes lose their shell prompt. The prompt never comes back until the user presses Enter. This happens on:
- App startup (session restore)
- New pane creation (split insertion)
- Tab switching

### Phase 1: Hypothesis — geometry/resize churn

We initially believed intermediate terminal resizes during layout churn caused the prompt loss. We built an "authoritative geometry" system that suppressed automatic resize paths and centralized size reporting.

**Result:** Made everything worse. Startup regressed badly. The automatic `setFrameSize → sizeDidChange` path was load-bearing for self-healing. We reverted.

**What we learned:** The automatic resize paths are necessary. Suppressing them breaks recovery.

### Phase 2: Hypothesis — SIGWINCH storm

We traced 5 independent `sizeDidChange` calls per logical resize event (init, mountView.layout, setFrameSize, forceGeometrySync, viewDidMoveToWindow). We thought duplicate SIGWINCHs were corrupting the shell's prompt state.

**Result:** Ghostty's C-level `sizeCallback` already deduplicates identical backing pixel sizes. Most of the 5 calls are no-ops. The SIGWINCH storm model was wrong.

**What we learned:** Ghostty already protects against duplicate resizes. The redundant calls are harmless.

### Phase 3: Hypothesis — 800x600 ghost grid

We found that every Ghostty surface starts at 800x600 internally (`embedded.zig:475`), producing a 14x41 grid. zmx reads this ghost size before the real size arrives. We traced this through 71/71 init events showing `currentPx={800,600}`.

**Result:** The ghost grid is real and causes a race condition, but it's a startup-specific issue. The `prompt_redraw` fix on zmx's handleInit (disabling prompt clearing during resize) fixed startup prompt loss.

**What we learned:** The 800x600 ghost grid causes a 14x41 → real size double-resize on every surface creation. Disabling `prompt_redraw` in zmx prevents the prompt clearing during this resize.

### Phase 4: Hypothesis — SwiftUI reparenting

We traced `PaneViewRepresentable.dismantleNSView` → `makeNSView` cycles. Found that:
- Startup: reparenting was caused by late `AppLifecycleStore` injection calling `replaceSplitContentView()`. Fixed by constructor injection.
- Tab switch: reparenting caused by single-NSHostingView architecture (one hosting view swaps content per tab). Identified but not yet fixed.
- Pane insertion within a tab: NO reparenting (ForEach with stable IDs works correctly).

**What we learned:** The startup reparenting was a real bug (now fixed). Tab switch reparenting is architectural (needs per-tab NSHostingView). Pane insertion is clean.

### Phase 5: Hypothesis — zmx prompt_redraw clearing

We researched Ghostty VT's `Screen.resize()` and found it clears prompt lines when `prompt_redraw` is enabled and the cursor is on a prompt/input line. This clearing happens in zmx's daemon terminal during resize.

We patched zmx to disable `prompt_redraw` before calling `term.resize()` in both `handleInit` and `handleResize`.

**Result:** Fixed startup prompt loss. Did NOT fix pane insertion prompt loss.

**What we learned:** The zmx-side `prompt_redraw` clearing was one source of startup prompt loss. But there's another source for pane insertion.

### Phase 6: Hypothesis — zmx handleResize path

We expected pane insertion to trigger zmx's `handleResize`. We skipped `term.resize()` entirely in handleResize (PTY-only resize, no daemon terminal update).

**Result:** `handleResize` never fires during pane insertion. The zmx logs show only `handleInit` events. The app creates new Ghostty surfaces for new panes, and the zmx client connects fresh — there's no mid-session resize of existing zmx sessions during pane insertion.

**What we learned:** The prompt loss on pane insertion doesn't go through zmx's handleResize at all. It goes through the Ghostty surface's own resize path.

### Phase 7: The definitive experiment — pure Ghostty without zmx

We bypassed zmx entirely by forcing all panes to use plain shell (`/bin/zsh -i -l`) instead of `zmx attach`.

**Result:** Zero prompt loss. Every operation worked perfectly — startup, pane insertion, resize, everything.

**What this proved:** The prompt loss is caused by zmx being in the live terminal data path. Pure Ghostty handles all resize/reflow scenarios correctly.

### Phase 8: Hypothesis — Ghostty's own prompt_redraw + zmx latency

With zmx in the path, the data flow is:
```text
Shell → daemon PTY → daemon socket → zmx client → client stdout_buf → Ghostty PTY → Ghostty renders
```

Ghostty's own `Screen.resize()` clears prompt lines (prompt_redraw). In pure Ghostty, the shell's SIGWINCH redraw arrives within microseconds to the same terminal. With zmx, the roundtrip adds latency, and the zmx client uses buffered I/O (`stdout_buf` ArrayList that flushes when `poll` says stdout is ready).

We tried a delayed `ghostty_surface_refresh` (150ms after resize) to let the zmx roundtrip complete.

**Result:** Prompt still missing after the delay. The shell's output either doesn't arrive or doesn't restore the prompt.

**What we learned:** The zmx client's buffered I/O and the latency through the daemon socket fundamentally break Ghostty's assumption that the shell's redraw arrives instantly to the same terminal that cleared the prompt.

### Phase 9: Why point fixes can't solve this

Each fix we tried addressed one layer but the problem spans multiple layers:

```text
Layer 1: Ghostty surface clears prompt (prompt_redraw in Screen.resize)
Layer 2: Shell sends SIGWINCH redraw through zmx roundtrip (latency)
Layer 3: zmx client buffers output (stdout_buf, poll-based flushing)
Layer 4: zmx daemon processes output through its own terminal (state divergence)
Layer 5: 800x600 ghost grid causes double-resize on surface creation
```

Fixing any single layer doesn't fix the fundamental architecture issue: zmx is a middleman in the live terminal path, adding latency and buffering to a system (Ghostty's prompt_redraw) that expects zero-latency direct PTY access.

### Phase 10: The architectural conclusion

```text
The only operation zmx provides that we actually need is session restore.

During normal operation, zmx adds:
- latency (daemon socket roundtrip)
- buffering (client stdout_buf)
- state divergence (daemon terminal vs Ghostty terminal)
- resize complexity (handleInit, handleResize, prompt_redraw interactions)
- 800x600 ghost grid race condition

During session restore, zmx provides:
- PTY persistence (shell survives app restart)
- Terminal state serialization (via ghostty_vt formatter)
- Content replay on reattach

The fix: remove zmx from the live data path. Use pure Ghostty for normal operation.
Keep zmx daemon running in parallel for session persistence only.
On app restart, query zmx for terminal state and restore.
```

### What's fixed and what remains

```text
Fixed:
- Startup reparenting (constructor injection of AppLifecycleStore)
- Binary split tree ratio drift (flat layout cutover)
- Startup prompt loss from zmx prompt_redraw (prompt_redraw=false patch)
- 800x600 ghost grid initial frame (precondition + launch gate)

Remains:
- Prompt loss on pane insertion with zmx (architectural — zmx in live path)
- Tab switch reparenting (needs per-tab NSHostingView)
- zmx prompt_redraw fix needs upstream contribution

Next step:
- Design new architecture: pure Ghostty for live terminal, zmx for session persistence only
- Build Swift-side zmx IPC client for programmatic control
- Separate live terminal operation from session restoration
```

## Debugging Epoch (2026-03-30T02:00:00Z): Bytes Reach Ghostty — The Problem Is Not zmx Buffering

### Critical finding

Added byte-flow instrumentation to zmx daemon and client:
- Daemon: logs `daemon pty_read session=X bytes=N clients=N` when shell output is read
- Client: logs `client recv_output bytes=N stdout_buf_total=N` when receiving from daemon
- Client: logs `client stdout_write bytes=N remaining=N` when flushing to Ghostty's PTY
- Client: logs `client stdout_write WOULDBLOCK pending=N` if stdout blocks

### Result

```text
Zero WOULDBLOCK events.
Every recv_output is immediately followed by stdout_write with remaining=0.
The zmx client flushes all shell output to Ghostty's PTY immediately.
No buffering stalls. No data loss. No latency.
```

### What this disproves

```text
Disproved: "zmx client buffers output and doesn't flush" — it flushes immediately
Disproved: "the shell's prompt output doesn't reach Ghostty" — it does
Disproved: "zmx latency prevents the shell redraw from arriving" — it arrives promptly
Disproved: "the zmx data path is the bottleneck" — bytes flow through without delay
```

### What this means

The prompt bytes arrive at Ghostty's PTY. Ghostty reads them and processes them through its terminal. But the prompt is not visible on screen.

This means the bug is in **Ghostty's terminal processing**, not in zmx's data path. Specifically:

```text
1. Ghostty's Screen.resize() clears prompt lines (prompt_redraw)
2. Shell output with prompt redraw arrives at Ghostty via zmx (proven by byte tracing)
3. Ghostty processes the bytes through its terminal
4. But the prompt is not visible

The bytes arrive. The terminal processes them. But the result is not visible.
```

### Possible explanations (all unproven)

```text
1. Ghostty processes the prompt bytes but they land at a wrong cursor position
   (prompt_redraw cleared rows, shell redraws at positions that don't match)

2. The prompt bytes arrive BEFORE the resize is complete, so they're processed
   at the old grid size and then lost during reflow

3. The prompt bytes are processed correctly but the viewport is scrolled
   to the wrong position (prompt is below the visible area)

4. Something about zmx's PTY (which is different from Ghostty's PTY)
   causes the shell's escape sequences to be interpreted differently
```

### Next step

Need to trace what Ghostty's terminal actually does with the bytes it receives. Specifically: what is the cursor position and screen content before and after processing the shell's prompt output?

## Debugging Epoch (2026-03-30T02:15:00Z): Ctrl-L Works — The Bug Is Viewport Scroll Position

### Definitive test

User pressed Ctrl-L on a blank pane (prompt missing). The prompt appeared immediately.

### What this proves

```text
1. The shell IS running and responsive
2. The terminal buffer HAS the prompt content (or the shell can redraw it)
3. Ghostty CAN render the prompt
4. The visible viewport is scrolled to the WRONG POSITION after resize
5. The prompt is below the visible viewport — it's there, just not visible
```

### Root cause confirmed

After a resize with prompt_redraw:
1. Ghostty's Screen.resize() clears prompt lines
2. Reflow happens at the new column count
3. The viewport position is NOT updated to follow the cursor/prompt
4. The prompt (or the shell's SIGWINCH redraw) ends up below the visible area
5. User sees blank space where the prompt should be

Ctrl-L sends form feed to the shell, which clears the screen and redraws the prompt at line 1 — bringing it into the visible viewport.

### Why pure Ghostty doesn't have this issue

In pure Ghostty, the resize + SIGWINCH + shell redraw all happen on the same terminal. Ghostty's scroll-to-bottom-on-output behavior triggers when the shell's redraw output arrives, scrolling the viewport to show the prompt.

With zmx, the roundtrip delay means the shell's output arrives later. By then, Ghostty may have already rendered the wrong viewport position, and the subsequent output might not trigger the scroll-to-bottom behavior correctly.

### Ghostty's scroll-to-bottom capability

From DeepWiki research on ghostty-org/ghostty:
- Internal `scroll_to_bottom` action exists in performBindingAction
- `scroll_to_bottom_on_output` config option auto-scrolls when new output arrives
- `terminal.scrollViewport(.bottom)` is the internal function
- No public C API to call scroll-to-bottom from the host app
- `ghostty_surface_key` exists — could potentially simulate End key to scroll

### Possible fixes

```text
Fix 1: Ensure scroll-to-bottom-on-output is enabled
  Check if this Ghostty config is active. If the shell's output
  arrives and scroll-to-bottom-on-output is enabled, the viewport
  should auto-scroll. If it's not working, that's a Ghostty bug
  worth investigating.

Fix 2: Send End key after resize
  Use ghostty_surface_key to simulate End/Cmd+End key after resize.
  Would scroll to bottom. Hacky but might work.

Fix 3: Use ghostty_surface_mouse_scroll to scroll to bottom
  Programmatic scroll via the C API.

Fix 4: Fix the viewport position in Ghostty's resize logic
  The real fix — after resize+reflow, ensure the viewport tracks
  the cursor position. This would be a Ghostty-level fix.
```

### What this means for architecture

The prompt loss is NOT a zmx data path issue (bytes flow fine).
It's NOT a zmx terminal state issue (prompt_redraw patch helped startup).
It IS a Ghostty viewport scroll position issue after resize.

This changes the fix direction: instead of removing zmx from the data path,
we might be able to fix this by ensuring the viewport scrolls to bottom
after any resize event.

## Debugging Epoch (2026-03-30T09:00:00-04:00): Latest zmx + Ghostty Patch Set — What Changed And What It Actually Means

### Files changed

Latest local changes touch:

- `vendor/zmx/src/main.zig`
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+TextInput.swift` (text input extraction only, not behavioral)

### What the zmx patch does

The zmx daemon now disables `shell_redraws_prompt` around both:

- `handleInit`
- `handleResize`

Grounded effect:

```text
zmx daemon terminal will no longer clear prompt/input lines during its own resize.
```

This is a daemon-terminal correctness fix. It reduces one known source of prompt
loss during session restore and daemon-side resize reflow.

It does **not** by itself prove that all pane-insert prompt loss is solved,
because pane insertion can still involve Ghostty-side surface resizing and
viewport behavior after bytes arrive.

### What the new zmx byte-flow instrumentation proves

The latest zmx patch also adds logging at three points:

- daemon PTY read
- client receive from daemon socket
- client write to stdout

This instrumentation is specifically testing the old hypothesis:

```text
"zmx buffering or stdout flush delay causes the prompt bytes not to reach Ghostty"
```

If the logs show:

```text
daemon pty_read -> client recv_output -> client stdout_write remaining=0
```

for the failing cases, then the old buffering/latency hypothesis becomes much weaker.

### What the Ghostty patch does

`GhosttySurfaceView.sizeDidChange(...)` now:

1. applies the resize immediately
2. detects grid-changing resizes
3. schedules a debounced `scrollToBottom()` after 200ms

`scrollToBottom()` uses:

```text
ghostty_surface_binding_action("scroll_to_bottom")
```

Grounded effect:

```text
after a grid-changing resize, Ghostty will be asked to move the viewport to bottom
once the resize burst settles.
```

### What this patch is betting on

The current app-side fix is betting on this model:

```text
prompt bytes do reach Ghostty
but after resize/reflow the viewport is left above the prompt/cursor
so scrolling to bottom after the resize burst should reveal the prompt
```

That is a much narrower hypothesis than:

```text
"zmx itself is broken as a transport"
```

### What this patch does NOT prove yet

The code change is coherent, but by itself it does not yet prove:

1. that the prompt is always below the viewport rather than absent
2. that 200ms is the right debounce window
3. that auto-scroll-after-resize is acceptable for users intentionally reading scrollback
4. that pane insertion and startup restore share the exact same viewport bug

### Current tradeoff

This Ghostty-side patch explicitly trades correctness for scrollback stability:

```text
any grid-changing resize
  -> auto-scroll to bottom after debounce
```

That likely helps prompt visibility, but it may also:

- yank the viewport to bottom after manual resize
- hide useful scrollback context during interactive resize

So this is best understood as a targeted workaround unless proven otherwise.

### Current grounded read after reviewing the latest patch set

```text
zmx patch:
  good and grounded
  removes daemon-terminal prompt clearing during resize

zmx byte-flow logs:
  good and grounded
  directly test whether bytes are actually delayed or dropped

Ghostty debounced scroll-to-bottom:
  plausible workaround
  grounded in Ghostty's public binding action API
  not yet proven as the full root fix
```

### What to verify next

For the next failing pane-insert or restore case, correlate:

1. zmx byte-flow logs
2. Ghostty grid-changing resize log
3. delayed `scroll_to_bottom` behavior
4. whether the prompt becomes visible without manual Ctrl-L / Enter

The key question is now:

```text
does the debounced viewport scroll solve the visible prompt loss
once bytes are proven to be arriving?
```

## Debugging Epoch 16 (2026-03-29 ~22:00): Root Cause Identified and Fix Implemented

### Root cause analysis

The Ghostty config `scroll-to-bottom` defaults to `keystroke=true, output=false`
(ref: `vendor/ghostty/src/config/Config.zig:10127-10132`).

This means:
- On keystroke → viewport scrolls to bottom (that's why Ctrl-L fixes it)
- On output → viewport does NOT auto-scroll

When zmx sends restored terminal content (via `handleInit` → `serializeTerminalState`
→ `Output` message → client stdout → Ghostty surface), this is treated as output.
Since `scroll_to_bottom_on_output = false`, the viewport doesn't follow the cursor.

Similarly, when existing panes are resized during pane insertion, zmx processes the
resize (SIGWINCH → shell redraw → PTY output → daemon → client → Ghostty). The
terminal reflows, but the viewport can end up above where the cursor/prompt is.

### Evidence chain

1. **Ctrl-L proves prompt is in buffer**: User confirmed pressing Ctrl-L on a blank
   pane instantly shows the prompt. This is because Ctrl-L is a keystroke, and
   `scroll_to_bottom.keystroke = true` scrolls the viewport to bottom before the
   clear-screen action runs.

2. **Byte-flow instrumentation proves data path is fine**: Logging added to zmx
   daemon (`pty_read`) and client (`recv_output`, `stdout_write`) shows bytes flow
   without delay or loss.

3. **Ghostty config traced to source**:
   - `Config.zig:935`: `@"scroll-to-bottom": ScrollToBottom = .default`
   - `Config.zig:10127-10131`: default is `keystroke=true, output=false`
   - `renderer/generic.zig:1187`: `if (self.config.scroll_to_bottom_on_output)` — guards auto-scroll on output
   - `Surface.zig:2788`: `if (self.config.scroll_to_bottom.keystroke) self.io.terminal.scrollViewport(.bottom)` — keystroke scrolls

4. **ghostty_surface_binding_action API exists**: `embedded.zig:1968-1983` exposes
   `ghostty_surface_binding_action` which takes a string action name and executes it.
   The `scroll_to_bottom` action (`Surface.zig:5528-5532`) queues a viewport scroll
   to bottom.

### Fix implemented

**Three-layer fix:**

1. **zmx prompt_redraw patch** (`vendor/zmx/src/main.zig`):
   - `handleInit` (line 530-532): Disables `shell_redraws_prompt` before `term.resize()`
     to prevent zmx daemon terminal from clearing prompt lines during session restore.
   - `handleResize` (line 554-556): Same pattern — disables prompt_redraw before resize
     to prevent clearing during pane resize events.

2. **GhosttySurfaceView.scrollToBottom()** (`GhosttySurfaceView.swift`):
   - New `scrollToBottom()` method calls `ghostty_surface_binding_action("scroll_to_bottom")`
   - Debounced scroll-to-bottom in `sizeDidChange`: after any grid-changing resize,
     waits 200ms then scrolls viewport to bottom. The delay gives zmx time to process
     the resize and send reflowed output back to the surface.

3. **SurfaceManager.scrollToBottom(forPaneId:)** (`SurfaceManager.swift`):
   - Exposes scroll-to-bottom for explicit coordinator calls if needed.

### Why 200ms delay

The zmx resize flow: `sizeDidChange` → `ghostty_surface_set_size` → SIGWINCH to PTY →
zmx client receives SIGWINCH → sends Resize to daemon → daemon resizes terminal →
shell responds to SIGWINCH → output flows through daemon → client → stdout → Ghostty.

Byte-flow instrumentation from earlier epochs showed this round-trip completes in
10-50ms typically. 200ms with debounce provides safe margin while being imperceptible
to the user.

### Risk assessment

The debounced scroll-to-bottom fires after every grid-changing resize. If a user is
reading scrollback and resizes, they'll be scrolled to bottom. This matches terminal
convention (Ghostty already does this on keystroke) and is acceptable given the
alternative (invisible prompts).

## Debugging Epoch 17 (2026-03-30 ~11:50): scroll-to-bottom Approach Did Not Fully Work

### What happened

The debounced `scrollToBottom()` approach (Epoch 16) was tested. Results: **not
always working**. Some panes still show blank after startup restore.

### Evidence

1. **No scroll-to-bottom events in logs**: Grepping `/tmp/agentstudio_debug.log` for
   "scrollToBottom" or "scroll_to_bottom" returned zero results. The debounced
   `scrollToBottom()` method had no logging, so we cannot tell if it fired or not.

2. **zmx daemons still running OLD binary**: The zmx daemon processes were spawned
   at a previous app launch (timestamps show ~9:58PM). They are long-lived forked
   processes that persist across app restarts. The `handleResize` fix (which added
   `term.resize()` back with prompt_redraw patch) was NOT active. The old code had
   `pty_only=true` in the resize log — confirmed by:
   ```
   [info] resize rows=54 cols=45 pty_only=true
   ```
   This means `term.resize()` was still being skipped in the running daemons.

3. **zmx logs location discovered**: `~/.agentstudio/z/logs/{session_name}.log`.
   Per-daemon log files with timestamps. These are the source of truth for zmx behavior.

### Why the scroll-to-bottom approach is wrong

1. **It's a workaround, not a fix.** It fights the symptom (viewport position) instead
   of understanding why the viewport is wrong.

2. **Too broad.** Fires on every grid-changing resize — would yank viewport during
   manual resize, interactive window adjustments, scrollback reading.

3. **Timing-dependent.** 200-300ms delay is a guess. No evidence it's the right window.
   If zmx round-trip takes longer on startup with many panes, it misses.

4. **Ghostty doesn't do this natively.** Ghostty's own terminal behavior does not
   auto-scroll on output by default. Fighting this default creates unexpected UX.

### What we still don't know

1. **Is the viewport actually wrong, or is the content missing?** Ctrl-L proves the
   prompt is there in the buffer for at least some cases. But we haven't verified this
   for ALL failing cases. Some panes might have genuinely missing content (zmx
   serialize/restore failure).

2. **What does zmx's handleInit actually send during session restore?** We need to
   look at the serialized terminal state — is it complete? Does it include the prompt?
   Does it position the cursor correctly?

3. **What happens to Ghostty's viewport when it receives the serialized state?** The
   content arrives as raw bytes (VT sequences). After writing these to the screen, where
   is the cursor? Where is the viewport?

### Definitive test (fresh zmx daemons + instrumented scrollToBottom)

Killed all zmx daemons and relaunched with instrumented build. Results:

```
6 surfaces got gridChanged → scheduled scrollToBottom
6 scrollToBottom calls returned result=true
Prompts STILL missing on some panes
```

zmx daemon logs confirm:
- All new daemons (no stale processes)
- `init resize ... prompt_redraw_disabled=true` on all sessions
- All first-time attaches (no serialize/restore — `has_had_client` was false)
- Byte flow clean: `stdout_write ... remaining=0` everywhere

**This definitively disproves the viewport-scroll hypothesis.** Ghostty accepted the
scroll-to-bottom action on all surfaces, and it made no difference.

### What this tells us

Since these are first-time attaches (zmx daemons just spawned, no prior client),
there is no serialized terminal state being restored. The shell is starting fresh.
Yet prompts are still missing.

This means the prompt loss is **not** caused by:
- zmx session restore (no restore happened)
- Viewport scroll position (scrollToBottom had no effect)
- zmx byte delay/buffering (bytes flow immediately)
- zmx prompt_redraw clearing (disabled and confirmed in logs)

The prompt loss is happening during **fresh shell startup through zmx**, not just
session restore. Something about the zmx client/daemon data path or the timing of
Ghostty surface creation is causing the shell's initial prompt output to not render.

### Code reverted

All scroll-to-bottom code has been reverted from GhosttySurfaceView and SurfaceManager.
The zmx prompt_redraw patches in `handleInit` and `handleResize` remain as they are
independently correct (prevent daemon terminal state corruption).

### Next investigation direction

The problem manifests during fresh shell startup through zmx. Need to investigate:

1. Race between surface creation, window attachment, and zmx shell output
2. Whether the shell prompt bytes arrive before the surface is fully initialized
3. Whether Ghostty drops or ignores input that arrives before the surface has a window
4. The timing relationship between `ghostty_surface_set_size` and when the PTY
   output actually renders
