# Memory-Pressure Track — Salvage Assessment Of The Abandoned Renderer-Lifecycle Branch

**Date:** 2026-09-05 · **Assessing:** `fix/renderer-lifecycle-correctness-v2` at `9af9080e7`
(worktree `agent-studio.memory-issues`, 78 files / 8,764 insertions over merge-base `5930144c5`,
plus uncommitted spec set `2026-08-29-surface-renderer-lifecycle/`, errata, and the IOSurface
investigation) · **Against:** `origin/main` at `57c49d0e3` and pinned Ghostty `v1.3.1` (`332b2aef`,
re-read from the OSS checkout this session) · **New worktree:** `agent-studio.memory-pressure`
(`fix/memory-pressure`).

Every claim marked *verified* below was re-checked this session against current `origin/main`
source, the pinned Ghostty source, or a live passive sample of production `0.0.93` (PID 2409).
The live evidence is in
[debug-investigation.md](../../tmp/debug-workflows/2026-09-05-agent-studio-fix-memory-pressure-memory-pressure/debug-investigation.md).

## Prior ground truth, re-verified item by item

The team lead's packet and the abandoned branch made these claims. Each was checked against a
file:line at `origin/main`, the pinned Ghostty source, or a VictoriaLogs query. Where the raw
source no longer exists, the row says **unverified**, not "likely".

| Claim | Check performed | Result |
| --- | --- | --- |
| `SurfaceManager.detach` removes before delivering occlusion | `SurfaceManager.swift:303` vs `:311–312` vs guards `:779–798` | **verified** |
| `updateVisibleTabHost` hides tab hosts without touching renderers | `PaneTabViewController.swift:1464–1468`; `grep setOcclusion` shows only manager-internal callers | **verified** |
| Window occlusion facts have no renderer consumer | readers of `isOccluded`: `+BridgePaneActivity.swift:130,169`, `+RepositoryFactDemand.swift:123` only | **verified** |
| `PaneHostView ↔ ManagementLayerContainerView` retain cycle; unregister only nils the slot | `PaneHostView.swift:13–21, 160–166`; `ViewRegistry.swift:217–219` | **verified** (runtime leak still unproven; no closes in the sampled run) |
| "`Ghostty.SurfaceView.deinit` is the only `ghostty_surface_free` caller" | `grep -rn ghostty_surface_free Sources/` → `GhosttySurfaceView.swift:484` and `SurfaceManager+LastOutputLine.swift:84` | **corrected**: the second site is `ghostty_surface_free_text(surface, &text)` (`include/ghostty.h:1133`), which frees the text buffer returned by `ghostty_surface_read_text` inside a `defer`; it never frees a surface. `ghostty_surface_free` (`ghostty.h:1076`) has exactly one caller. RC3 stands. |
| Pin: `setVisible(false)` stops display link only | `generic.zig:1053–1066` (v1.3.1) | **verified** |
| Pin: `Thread.drawFrame` gates on visible | `Thread.zig:494–496` | **verified**; errata E13 ("no visibility gate") is false |
| Pin: `occlusionCallback` has no equality guard and queues a render | `Surface.zig:3248–3257`; thread-side equality at `Thread.zig:353–355` | **verified** |
| Pin: `setFocus(true)` starts the display link regardless of visibility | `generic.zig:1029–1047` | **verified** |
| Pin: every drawn frame is a main-queue CA contents commit | `metal/IOSurfaceLayer.zig:49–79` | **verified** |
| 0.0.88 malloc "flat 180–200 MB" overnight 2026-08-28 | VictoriaLogs 06:00–12:00Z hourly min/max: 182–232 MB in use, 445–480 MB allocated | **verified** (max touched 232 MB at 10:00Z) |
| Final pre-reboot malloc record 12:27:45Z = 180,364,800 in use / 348,127,232 allocated / 889,048 blocks | VictoriaLogs record at `2026-08-28T12:27:45.562Z` | **verified**, byte-exact |
| `surface_size` fired ~8,575× in 6 h with two height transitions | VictoriaLogs 06:00–12:30Z: 9,564 events, 3 distinct heights | **verified** (6.5 h window) |
| "The overnight process ran 46 panes" | last `performance.tabbar.current` before the 12:20Z force-quit (12:09:03Z): `pane.count=23`, `tab.count=7`; `pane.count` sums panes over tab items (`TabBarAdapter.swift:453`) and equals today's renderer-thread count | **contradicted**: 23 panes, not 46. Every per-surface incident rate derived from 46 is off by about 2×. |
| Jetsam reports for 2026-08-27/28 (WindowServer 132 GB resident; compressor 40–47 GB; AgentStudio 2.4 GB) | `/Library/Logs/DiagnosticReports{,/Retired}/JetsamEvent-2026-08-2*.ips` | **unverified**: files no longer exist (Retired holds Sep 3–5 only) |
| pmset display sleep 04:55 / wake 06:26 on 2026-08-28 | `pmset -g log` earliest retained entry is 2026-08-29 06:14 | **unverified**: rotated out |
| "E1/E6 are the proofs" | 20+ `/private/tmp/agentstudio-renderer-lifecycle.*` roots: `data/`, env files, two `run-output.log`, no `report.json`; zmx from `590F7Q` still alive | **unverified as results**: designs and partial runs, no recorded outcome |
| Production tonight: `addGlyph/rebuildRow` hot while idle | 5 s `sample` of PID 2409: 4 of 29 renderer threads busy (456/141/55/11 of 3,032 samples); 25 idle in `kevent64` | **verified as output-driven**, not continuous |
| Production tonight: `NSHostingView` relayout every display cycle | same sample: 10 of 3,032 main-thread samples in `NSHostingView.layout()` | **verified as present, small** (~0.3% of main thread in that window) |

## Verdict in one screen

```text
KEEP (grounded, re-verified, cheap)            DROP (unverifiable, over-built, or wrong)
──────────────────────────────────────────     ──────────────────────────────────────────────
D1 detach/requeue remove-before-lookup bug     X1 "131 GB = hidden surfaces × 90 commits/s
D2 occlusion signal dead-ends in atoms            × 50 KB" — retracted by the branch itself
D3 host↔container retain cycle on close        X2 "E1/E6 are the proofs" — designed, never run
D4 pinned-renderer facts (5 items, re-read)    X3 2,100-line AppDelegate+RendererLifecycle*
D5 effective-visibility predicate =               Diagnostics startup workloads
   window facts × StoreVisibilityTierResolver  X4 soak analyzer with t-critical certification
D6 deliver-on-change at SurfaceManager         X5 dismantle→retirePaneHost (caused a live
D7 P0 lifecycle counters + orphan invariant       drawer regression on that branch)
D8 SurfaceRendererStateDelivery protocol seam  X6 isolated deinit / bareManagedSurfaceID /
D9 footprint+vmmap+vm_stat external capture       focusRequester churn on Ghostty.SurfaceView
                                               X7 undoClose→restoreClosedSurface API cutover
REWRITE (right idea, wrong shape)              X8 WorkspaceWindow.order() hook
R1 v2 requirements/spec: correct problem       X9 errata E13 "no visibility gate in pin draw
   statement, but 19 R-rows + 12 scenarios        path" — false at v1.3.1
   for a P0 fix; re-scope to 3 mechanisms      X10 "malloc exonerated / flat" — not flat in
R2 program design: 1,300 lines, observation-      0.0.93 (209→411→267 MB); still secondary
   tracked full-fleet reconciliation; keep
   the owner table, drop the machinery
```

## What the abandoned branch got right (salvage)

### D1 — detach and requeue deliver occlusion=false to nothing (verified on main)

`SurfaceManager.detach` removes the surface from `activeSurfaces` at
[SurfaceManager.swift:303](../../Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift#L303)
and only then calls `setOcclusion(false)`/`setFocus(false)` at lines 311–312; both helpers look up
`activeSurfaces[id] ?? hiddenSurfaces[id]` at lines 779–798 and return silently. Same shape in
`requeueUndo` (lines 427–436). So `.hide`, `.close`, and `.move` never reach libghostty. The
architecture doc even encodes the buggy order as the design
([ghostty_surface_architecture.md, Tab Close flow](../architecture/runtime/ghostty_surface_architecture.md#tab-close--undo-flow)).

Salvage: the finding and the red-test intent from
`SurfaceManagerRendererStateDeliveryTests` ("detach delivers hidden while the exact surface is
still attached"). Do not salvage the branch's rewrite of `detach` (it is entangled with X7).

### D2 — window occlusion is captured and then dropped (verified on main)

`MainWindowController` writes `isOccluded`/`isMiniaturized`/`isVisible` into
`WindowLifecycleAtom` on every occlusion/miniaturize event
([MainWindowController.swift:196–200](../../Sources/AgentStudio/App/Windows/MainWindowController.swift#L196)).
The only readers are Bridge pane activity and repository-fact demand. Nothing routes it to
`SurfaceManager` or any `ghostty_surface_set_occlusion` call. Inactive tabs are hidden with
`host.isHidden` at
[PaneTabViewController.swift:1467](../../Sources/AgentStudio/App/Panes/PaneTabViewController.swift#L1467)
and never touch `SurfaceManager` at all. Net: every live surface is Ghostty-visible forever.

### D3 — closed panes keep their Ghostty.SurfaceView alive (source-verified on main, runtime-unproven)

`PaneHostView.swiftUIContainer` is a strong lazy property whose container `addSubview(self)`
([PaneHostView.swift:13–21, 160–166](../../Sources/AgentStudio/App/Panes/Hosting/PaneHostView.swift#L160));
AppKit's `subviews` retains the host, so host ↔ container is a cycle. Close goes
`teardownView → detach(.close) → unregisterHostedView → viewRegistry.unregister` which only sets
`slot.host = nil` ([ViewRegistry.swift:217–219](../../Sources/AgentStudio/App/Panes/ViewRegistry.swift#L217)).
Nothing unmounts the `TerminalPaneMountView` (which strongly holds `ghosttySurface`) or removes
the host from the container. After the 300 s undo expiry `SurfaceManager.destroy` drops its
reference and comments "Surface.deinit will clean up PTY when ARC releases it" — but ARC cannot
release it. If real, each closed terminal leaks ~58 MB of graphics memory, one renderer thread,
one io thread, one io-reader thread, and one cf_release thread, forever.

Salvage: the finding and the branch's final (third) fix shape — retire the exact host instance
inside `unregisterHostedView`/`registerHostedView` replacement — not the dismantle-based one
(X5). Needs a red test that drops external references and asserts weak host/content go nil.

### D4 — pinned Ghostty facts (all five re-read at v1.3.1 this session)

| Fact | Anchor | Consequence |
| --- | --- | --- |
| `renderer.setVisible(false)` only stops the display link; swap chain + Metal buffers stay | `generic.zig:1053–1066` | occlusion cannot reduce steady-state residency at the pin |
| `Thread.drawFrame` returns when `!visible` | `Thread.zig:494–496` | occlusion *does* stop frame draws and CA commits |
| `renderCallback` still runs `updateFrame` (cell rebuild) when invisible | `Thread.zig:596–620` | occlusion does not stop `rebuildRow/addGlyph` CPU on output |
| `Surface.occlusionCallback` has no equality guard and calls `queueRender()` every time; `Thread` drops equal `.visible` but the wakeup still renders | `Surface.zig:3248–3257`, `Thread.zig:353–355` | deliver occlusion only on change |
| `renderer.setFocus(true)` starts the display link with no visibility check; `Surface.focusCallback` is equality-guarded | `generic.zig:1029–1047`, `Surface.zig:3264–3265` | never focus a non-displayed surface |
| `IOSurfaceLayer.setSurface` dispatches to the main queue and sets `layer.contents` per frame | `metal/IOSurfaceLayer.zig:49–79` | every drawn frame of a hidden-but-visible surface is a main-thread CA commit |

### D5 — the effective-visibility predicate (verified against the resolver)

`StoreVisibilityTierResolver.tier(for:) == .p0Visible` already encodes residency, active tab,
zoom source, minimized panes, drawer expansion/layout/minimized
([TerminalRestoreScheduler.swift:41–115](../../Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift#L41))
and is what restore already uses to decide what to build. The branch's late correction (errata
E12) to `windowVisible && !miniaturized && !occluded && tier == .p0Visible` is right. Salvage the
predicate; see R2 for what not to salvage around it.

### D6 — deliver on change, recorded at the delivery point

Because of the D4 equality facts, a last-delivered record per surface at `SurfaceManager` (both
lifecycle transitions and projection reconciliation flow through it) is the right suppression
point. Salvage as a one-field addition to `ManagedSurface`, not a new cache type.

### D7 — lifecycle counters and the orphan invariant

`created`, `active`, `hidden`, `close_undo`, `released`, `freed`, with
`orphan = (created − freed) − (active + hidden + close_undo)` and "negative is a telemetry bug, not
clamped". Sound and cheap. `SurfaceManager` already owns every transition; `Ghostty.SurfaceView.deinit`
already calls `ghostty_surface_free` at
[GhosttySurfaceView.swift:472–484](../../Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift#L472).
Adding an event type is an owner decision (CLAUDE.md) — routed to the parent.

### D8 — `SurfaceRendererStateDelivery` protocol (36 lines)

A clean seam for `ghostty_surface_set_occlusion`/`set_focus` that lets tests record deliveries
without `#if DEBUG` hooks. Salvage verbatim.

### D9 — external capture shape

`footprint -p`, `vmmap`, `vm_stat`, `sysctl vm.swapusage`, WindowServer footprint alongside the
app. Salvage the idea; the branch's 382-line soak script and 315-line analyzer are replaced by the
60-line passive watcher already running (see debug artifact). Add the one cheap metric the branch
missed: **renderer-thread count = live Ghostty surfaces** (`sample`/`ps -M` thread names).

## What cannot be verified or is over-built (drop)

- **X1** The incident mechanism arithmetic. The branch's own errata (E1, E2) retracts it. Today's
  reading adds: focus *is* delivered by the responder chain
  ([GhosttySurfaceView.swift:546–552](../../Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift#L546)),
  so unfocused hidden surfaces do not run display links; they render only on terminal output.
- **X2** E1–E7 were never executed to a recorded result. Twenty-plus
  `/private/tmp/agentstudio-renderer-lifecycle.*` roots exist with `data/` and env files but no
  `report.json`; zmx processes from one root (`590F7Q`) are still alive after two days. The "E1/E6
  are the proofs" note in project memory describes a plan, not evidence.
- **X3/X4** ~2,100 lines of in-app startup diagnostic workloads plus a fail-closed statistical
  certification (12 scenarios × 20 reps, `T_CRITICAL_95_DF_178`) as a PR gate. Not proportionate;
  no green run recorded.
- **X5** Treating SwiftUI `dismantleNSView` as permanent retirement regressed drawer panes on the
  branch (errata E10) and was still live in that tree.
- **X6/X7/X8** Ghostty.SurfaceView `isolated deinit`, bare-ID initializer, focus-requester seam,
  the `undoClose`→`restoreClosedSurface(forPaneID:)` cutover, and the `WorkspaceWindow.order()`
  hook are design churn without a proven need; the existing window-delegate ingress already fires
  on occlusion and miniaturize.
- **X9** Errata E13 claims the pin has no visibility gate in the draw path; `Thread.zig:494–496`
  gates `drawFrame`. The v2 spec (R6) had already corrected this; the errata is stale.
- **X10** "Malloc flat, exonerated": production 0.0.93 grew 209→411 MB average per hour over six
  hours, then fell to ~267 MB. Not flat, but at most ~430 MB against ~1.67 GB of graphics; it is a
  secondary lane, not the driver.

## Conflicts with first-principles evidence (today, production 0.0.93, 7 h uptime)

| Branch claim | Live evidence | Reading |
| --- | --- | --- |
| 87 named IOSurfaces for 29 creations imply ~9 orphan triple-buffer sets | 29 creations, 29 panes, 29 renderer threads, 25 full swap chains (3 buffers each, 10–18.5 MB) + 4 tiny ones = exact conservation | No orphan in a run with zero closes; the leak (D3) is only testable through close/expiry |
| Hidden surfaces render "24/7" | 4 of 29 renderer threads had any CPU in a 5 s sample; the rest sat in `kevent64` | Rendering is output-driven; the cost is per-output-frame CA commits and dirty swap chains, not continuous |
| App footprint dominated by a leak | 2,177 MB = IOSurface 1,102 + owned graphics 358 + IOAccelerator 208 + malloc ~370 + other ~140; peak 2,335 | 77% is per-live-surface graphics, linear in fleet (~58 MB/surface); 913 MB of it compressed/swapped |

## Test and launch assets, item by item

Every file below was read in full on the branch at `9af9080e7`. "Reuse" means the test asserts a
behavior this track's debug artifact confirmed and its harness exists on `origin/main`; "adapt"
names the change; "replace" names why. The plan cites this table so no correct test is rewritten.

| Asset (branch path) | Disposition | Justification |
| --- | --- | --- |
| `Tests/…/Features/Terminal/Ghostty/SurfaceManagerRendererStateDeliveryTests.swift` | **adapt** | Reuse verbatim: `RecordingSurfaceRendererStateDelivery` (L205–240), `makeManager` via package init with injected delivery (L177–186), and the tests "detach delivers hidden while the exact surface is still attached" (L49–68, red on main per `SurfaceManager.swift:303`), "attach … suppresses equal delivery" (L31–47), "reattach preserves the delivered hidden cache" (L70–91), "pane visibility closure receives only exact attached pane bindings" (L93–110), "binding callback fires for identity changes" (L112–136). Keep `acceptCreatedSurface` (the seam that lets R5 be tested without libghostty, L1–29). Replace "focus true admitted only by the creating manager" (L138–159, `focusRequester`) with a `syncFocus` gate test per design Choice 5. Drop "permanentlyRelease idempotent" (L161–175; API not adopted). |
| `…/SurfaceManagerUndoRetentionTests.swift` | **replace (none)** | All three tests exercise `restoreClosedSurface(forPaneID:)`, injected `now`, and `permanentlyRelease` (L10–80) — the undo-API cutover (X7) and repair path (non-goal). Existing undo tests on main keep the 300 s grace covered. The injected-`now` idea is worth a follow-up, not this PR. |
| `…/GhosttySurfaceViewLifecycleTests.swift` | **adapt** | Keep "bare surface deinitializes without attempting native free" (L24–36) with our `package init(managedSurfaceID:appCommandDispatcher:)`. Drop the `focusRequester` weak-link test (L12–22) and the off-main `isolated deinit` test (L38–52); both belong to X6. |
| `Tests/…/App/WorkspaceSurfaceCoordinatorRendererVisibilityTests.swift` | **adapt** | The four scenario tests (active tab × window facts L19–95; miniaturize/occlude L97–150; arrangement switch with minimized set L152–207; drawer parent minimize L209–274) are exactly V1/R3 and drive a capturing mock manager through `bindRendererVisibility` — keep them and the mock (L296–353). Their helpers exist on main (`withAsyncTestCoreAtoms` at `TestSupport/TestAtomRegistry.swift:35`, `eventually` at `Helpers/WorkspaceSurfaceCoordinatorTestHelpers.swift:43`). Drop the `RendererLifecycleDeliveryValidation` test (L276–294; diagnostics type). Mock signature follows our `WorkspaceSurfaceManaging` additions. |
| `Tests/…/App/WorkspaceSurfaceCoordinatorRendererRetentionTests.swift` | **replace (none)** | All three tests assert `permanentlyRelease`/`permanentlyReleaseClosedSurface` calls from repair, undo-capacity eviction, and creation rollback (L20–95) — the disposition API this track does not adopt; repair is a non-goal. |
| `Tests/…/App/WorkspaceSurfaceCoordinatorSlotLifecycleTests.swift` (+3 tests, L87–152 of diff) | **reuse verbatim** | "registering a replacement releases the exact prior host cycle", "unregistering releases the exact current host cycle but preserves the slot", "unregistering permanently unmounts content even while SwiftUI retains the old host" are the RC3 red-first tests. They need only `peekSlotForTesting` (`ViewRegistry.swift:313` on main), a `PaneMountedContent` sentinel view, and a weak box — both defined in the diff (L233–241). Red on main because `unregisterHostedView` only calls `viewRegistry.unregister` (`+ViewLifecycle.swift:461–464`). |
| `Tests/…/Architecture/SurfaceManagerHotPathArchitectureTests.swift` (+3 tests) | **adapt** | Keep the `@ObservationIgnored` assertion for `activeSurfaces/hiddenSurfaces/undoStack/surfaceHealth/surfaceViewToId` (L86–104): the manager is `@Observable` and reconciliation reads `activeSurfaces` inside `withObservationTracking`, so without it every 2 s health write would re-arm the coordinator. Drop "attach never asserts visibility" (L106–113; our attach is fail-safe visible). Replace "native focus writes live only in the delivery owner" (L116–138) with "`ghostty_surface_set_occlusion` appears only in `LiveSurfaceRendererStateDelivery`"; the responder-owned `set_focus` calls stay in `GhosttySurfaceView.swift:538,551,582`. Drop the isolated-deinit test (L140–152). |
| `Tests/…/Features/Terminal/Restore/StoreVisibilityTierResolverTests.swift` (+4 tests) | **reuse verbatim** | `tier_marksPaneHidden_whenNoTabIsActive`, `tier_marksInactiveTabPaneHidden`, `tier_marksMinimizedDrawerChildHidden`, `tier_marksDrawerChildrenHidden_whenParentPaneIsMinimized` are pure resolver contracts. The last one is **red on main**: `TerminalRestoreScheduler.swift:74–81` requires the parent in `activePaneIds` but not absent from `activeMinimizedPaneIds`, so a drawer child of a minimized parent resolves `.p0Visible`. Adopt the one-guard fix from the branch (`!activeTab.activeMinimizedPaneIds.contains(parentPaneId)`), not its `paneStructuralFacts` narrowing. |
| `Tests/…/Infrastructure/Diagnostics/AgentStudioPerformanceTraceRecorderTests.swift` (+4 tests) | **adapt** | Keep "conservation exposes the release-to-free orphan interval" (diff L108–144) and "negative orphan is preserved rather than clamped" (L146–156) against our smaller API. Adapt the OTLP round-trip test (L38–106) to our single event and counters; drop per-surface delivery counters (we count per reconciliation). |
| `Tests/…/Infrastructure/Diagnostics/RendererLifecycleOTLPTests.swift` | **adapt** | Keep "projection exports bounded aggregates and drops exact identity" (L37–86) and "metric mapping uses counters for deltas and gauges for current values" (L88–142) with our attribute set; drop the startup-diagnostic phase test (L8–35). |
| `Tests/…/App/Lifecycle/WindowLifecycleAtomTests.swift` (+1 test) | **reuse verbatim** with its one-line guard | "equal window presentation facts do not invalidate observers" plus `guard presentationFactsByWindowId[windowId] != facts` in `recordWindowPresentation` stops become-key/resign-key resamples from re-running reconciliation. Cheap and inside the authorized "existing owners" boundary. |
| `Tests/…/App/Windows/MainWindowControllerPresentationFactsTests.swift` changes | **replace (none)** | Tied to `WorkspaceWindow.order()` (X8). The underlying claim — `orderOut`/`orderFront` do not refresh presentation facts without an occlusion callback — is **unverified** here; this track's window-off case relies on AppKit posting `didChangeOcclusionState` for an ordered-out window and proves it on the debug bundle. If that observation fails, revisit. |
| `Tests/…/App/PaneTabViewControllerTabRetentionTests.swift` changes | **replace (none)** | Removes the `#if DEBUG onDismantleForTesting` hook usage (E15). Correct cleanup but outside this track's files; leave main as is. |
| `Tests/…/App/TerminalViewCoordinatorTests.swift` changes | **replace (none)** | Signature churn for `teardownView(surfaceDisposition:)` only. |
| `Tests/…/App/RendererLifecycleDiagnosticTerminationTests.swift`, `RendererLifecycleRestartManifestPathTests.swift` | **replace (none)** | Test the in-app diagnostic driver (X3). |
| `Tests/…/Scripts/RendererLifecycleSoakAnalyzerTests.swift`, `RendererLifecycleWorkloadScriptTests.swift` | **replace** | The first tests the t-critical certifier (X4); the second is a 90-line string-contains contract over script source (brittle). Our proof script gets one `bash -n` syntax test plus a parser fixture test, same family as `ObservabilityDebugLaunchScriptsTests`. |
| `scripts/run-debug-observability.sh` (+14) and `.mise.toml` (+12) | **replace (none)** | Pass-through of `AGENTSTUDIO_RENDERER_LIFECYCLE_PHASE/RESTART_MANIFEST` for the in-app driver. Our proof launches the unchanged launcher. |
| `scripts/verify-renderer-lifecycle-continuity.sh` | **adapt (snippets)** | Reuse the launcher-state decoding (`decode_state`, L36–45), the PromQL `query_metric` helper (L58–75), and the marker+launch selector (L188–193) for PID/marker-bound metric reads. Drop the phase/restart choreography and the fixed ledger expectations (L195–309; `created=41/released=21/freed=21` encode the branch's fixture). |
| `scripts/verify-renderer-lifecycle-soak.sh` | **adapt (functions)** | Reuse `parse_footprint` (L462–489), `system_memory_values` (L491–511), `discover_windowserver_pid` (L406–408), and the `sample_row` shape (L513–593) as the sampler for the debug-bundle proof. Drop the progress/scenario protocol (L595–687) and the analyzer gate. |
| `scripts/analyze-renderer-lifecycle-soak.py` | **replace** | Fixed 180-sample OLS certification with `T_CRITICAL_95_DF_178` and 12 hard-coded scenario counts (L705–764) is disproportionate to a PR gate. Keep only the per-sample lifecycle algebra checks (L850–880) as an optional invariant check in our sampler. |
| `Sources/…/App/Boot/AppDelegate+RendererLifecycle{Transition,Startup,Restart,Retention,Soak}Diagnostics.swift` (2,104 lines) + the uncommitted edit | **replace** | An in-app startup-diagnostic driver bound to the branch's APIs (`requestManagedFocus`, `permanentlyRelease`, `rendererLifecycleSnapshot`, `teardownView(surfaceDisposition:)`), with `NSApp.activate(ignoringOtherApps: true)` (`Startup:994`, against the owner's background-launch rule), 299 s and 610 s `Task.sleep` waits inside the app (`Retention:383`, `Soak:615`), and a `.screenSaver`-level cover window (`Transition:839–852`). What is worth learning: the fixture shape (18 main panes over 2 tabs, 2 drawer children, an alternate arrangement, one minimized pane, `Startup:1076–1161`) and the hidden-output readback idea (`Transition:95–137`). Our proof drives the same shape from outside the app (IPC and the existing launcher) and observes with `sample`, `vmmap`, `footprint`, and VictoriaLogs. |

## What this track carries forward

1. Three mechanisms, each with a red test first: D1 ordering, D2 effective-visibility delivery
   (on change, via D5/D6/D8), D3 exact-host retirement on permanent unregister. Reuse the tests
   marked **reuse verbatim** above as the red assets; adapt the **adapt** rows; the two
   resolver/atom one-liners (minimized-parent guard, equal-write guard) ride along with their
   tests.
2. D7 counters plus renderer-thread-count as the external conservation check.
3. A proof recipe on the debug bundle: create N → hide (tab switch) → close N → wait 300 s →
   renderer threads and IOSurface regions return to baseline; occluded surfaces show zero
   `CA::Transaction::commit` attribution in `sample`.
4. Owner decisions routed to the parent: (a) Ghostty pin bump to include upstream `683d8db`
   (hidden-surface GPU release) as a follow-up PR — the only lever on the 58 MB/surface
   steady-state; (b) new telemetry event type (D7); (c) scope of the visibility predicate (full
   resolver vs tab+window only).
