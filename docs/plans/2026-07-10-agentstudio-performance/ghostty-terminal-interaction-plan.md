# Ghostty Host Boundary And Terminal Interaction Implementation Plan

Execution sequencing: product behavior and focused proof in T1–T11 precede the
late cleanup/lint gate defined by
[Performance-First Sequencing Amendment](performance-first-sequencing-amendment.md).

Parent plan: [AgentStudio Performance Boundaries Implementation Plan](implementation-plan.md)

Source contracts:

- `docs/specs/2026-07-09-ghostty-terminal-interaction-fairness/ghostty-terminal-interaction-fairness.md`
- `docs/specs/2026-07-09-ghostty-terminal-interaction-fairness/ghostty-action-admission-manifest.md`

Pinned Ghostty: `332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28`

Accepted candidate: `7e02af87980bfdaad6d393b985d35c917476878e`

## 1. Outcome

Implement CB1–CB7, GT1–GT8, GA1–GA10, TS1–TS9, AI1–AI10, SC1–SC8, SF1–SF11, and GV1–GV8 without moving ordinary AppKit input behind an actor or taking ownership of Ghostty's VT/render loop.

The final path is:

```text
AppKit key/mouse/text
  -> synchronous MainActor host-call scope
  -> libghostty

Ghostty callback
  -> stable generation-bearing control-block lease
  -> tick/action/sample/fact/command/content disposition
  -> bounded local owner or exact journal
  -> semantic fact only when a named product consumer exists
```

The user-visible blocking claims are causal typing echo, caret movement, TUI mouse, focus, hidden-to-visible reveal, loaded frame-layer publication, throughput completion/drain/publication, and scrollback memory. Bulk IO alone is not interaction proof.

## 2. Existing Owners To Preserve Or Replace

| Current owner | Planned disposition |
| --- | --- |
| `Ghostty.App`/`GhosttyAppHandle` | preserve libghostty owner; replace unretained callback storage and `deinit` free with explicit lifecycle |
| `GhosttyCallbackRouter` | preserve callback table; replace per-wakeup MainActor tasks, callback-origin AppKit access, and delayed unretained dereference |
| `GhosttyActionRouter` | preserve translation/host integration; replace delayed runtime-envelope routing with origin/Boolean-aware descriptor policy |
| `GhosttySurfaceView+Input` | preserve direct synchronous input; add host-call/user-intent scope and keep path short |
| `GhosttySurfaceView`/`SurfaceManager` | preserve surface mapping/host role; extract geometry, host state, and lifetime owners |
| `TerminalRuntime` | preserve MainActor local UI/runtime state; leave `PaneRuntimeEventChannel` and split presentation/snapshot/fact/command/activity planes |
| `TerminalActivityRouter` | replace with one fair pane-keyed `TerminalActivityProjector` |
| `InboxNotificationRouter` | preserve notification policy; consume low-rate facts/receipts rather than raw terminal samples |
| `RuntimeRegistry` | preserve registration owner; mint/invalidate `TerminalRuntimeGeneration` |
| App IPC authentication/server | preserve authenticated Unix socket/principal model; add server-generation-bound report methods |
| pane-local `isSecureInput` | retain as projection only; add one app-global `SecureInputOwner` as authority |

## 3. Task T1 — Vendor Delta And Benchmark Adapter Preparation

Requirements: GV1, GV3, GV6–GV8. This task prepares comparison artifacts; it does not switch the product vendor.

### Read/derive, do not dirty the product submodule

Use isolated disposable vendor worktrees for pinned and candidate commits. Inspect/diff:

- `vendor/ghostty/include/ghostty.h`
- `vendor/ghostty/src/App.zig`
- `vendor/ghostty/src/apprt/embedded.zig`
- `vendor/ghostty/src/Surface.zig`
- `vendor/ghostty/src/renderer/Metal.zig`
- `vendor/ghostty/src/renderer/metal/Frame.zig`
- `vendor/ghostty/src/renderer/metal/IOSurfaceLayer.zig`

Add under `scripts/ghostty-performance/`:

- `build-matrix.sh`: disposable pinned/candidate framework/resource builder;
- `build-product-cell.sh`: build-time SwiftPM adapter that links one verified staged framework/resources/probe configuration into a digest-addressed scratch executable without replacing the default framework/resources;
- `verify-build-identity.sh`: immutable header/library/resource/host/action/adaptation/probe identity verifier;
- `verify-product-probe-isolation.sh`: ordinary debug/beta/stable symbol-and-behavior negative scanner;
- `run-factorial-workload.sh`: pinned/candidate × host baseline/contracted driver plus eight probe-perturbation controls;
- `verify-quiescence.sh`: selected-build callback/surface/app teardown stress driver;
- versioned compatibility-adaptation and measurement-probe manifest/patch inputs consumed by those scripts.

`build-matrix.sh` stages each verified XCFramework, generated header, resources, compatibility adaptation, and probe configuration under a digest-addressed scratch root. `build-product-cell.sh` creates one disposable AgentStudio source/build worktree per matrix cell at the exact Swift host revision, installs the staged framework/resources only inside that disposable tree's normal static paths, and passes probe/adaptation definitions at compile time. Each cell has an isolated Swift build directory. The active product worktree's `Frameworks/GhosttyKit.xcframework`, `Sources/AgentStudio/Resources/ghostty`, and ordinary build settings are never overwritten or selected by a runtime manifest. The output manifest binds vendor commit, generated header, library/XCFramework, resources, Swift host revision, action manifest, `compatibilityAdaptationDigest`, `measurementProbeDigest`, executable hash, resource-bundle hash, disposable source/build identity, and compile-definition digest.

The required core identities are `P0` (pinned + baseline host), `N0` (candidate + baseline host), `P1` (pinned + contracted host), and `N1` (candidate + contracted host), each with its vendor-matched measurement/action adapter. When the report makes a pure-vendor claim and the pinned/candidate adapters are not semantically equivalent without candidate-specific compatibility work, `build-matrix.sh` also produces `A0`: pinned vendor plus a semantic no-op/backport-equivalent adaptation-control patch. `A0` is an isolated benchmark identity, never a product path. Its manifest digest and measured adapter overhead are mandatory inputs to the pure-vendor attribution row; without `A0`, the report must say “vendor plus mandatory adaptation.”

The benchmark-only causal fixture marker and internal frame observer compile only in the isolated performance build. Ordinary debug, beta, and stable must neither recognize the marker nor export the observer ABI. The endpoint is `frameLayerPublished`, not physical scanout.

Extend `scripts/run-debug-observability.sh` with one manifest-bound `--performance-build-manifest <absolute-path>` input used only by the performance workload. The runner does not select a framework or compile definitions at launch: it verifies and wraps the already-linked executable/resource bundle named by the manifest while preserving the standard deterministic debug app identity, data root, zmx root, trace marker, and process-discovery scheme. It rejects an unverified manifest, an executable/link/resource digest mismatch, a host-revision mismatch, or a product configuration containing the private probe.

### Test proof

Add:

- `GhosttyBenchmarkBuildIdentityTests.swift`
- `GhosttyMeasurementProbeIsolationTests.swift`
- `Tests/AgentStudioTests/Scripts/GhosttyPerformanceBuildScriptsTests.swift`

Extend `GhosttyResourcesTests.swift`, `GhosttyAppHandleTests.swift`, and `GhosttyEventRoutingCoverageTests.swift`.

RED/GREEN: candidate tag/ABI/resource inventory should fail before explicit adaptation. GREEN proves P0/N0/P1/N1 manifests, conditional A0 adaptation-control identity, exact action sets, separate adapter/probe digests, distinct linked executable hashes, isolated build directories, unchanged default framework/resources, and negative ordinary-product hook check. A pure-vendor claim without required A0 proof and a launch-time manifest swap against one prebuilt executable are explicit failing fixtures.

Replan if the pinned and candidate adapters cannot be made semantically equivalent. Label any unavoidable difference “vendor plus mandatory adaptation”; do not hide it as vendor-only.

## 4. Task T2 — Stable App/Surface Callback Control Blocks

Requirements: CB1–CB3, CB7, SF9–SF10.

### Dormant primitives and atomic integration boundary

T2 first adds the control-block/lease/host-scope types and their unit/race tests as dormant primitives. It does not independently switch product callback userdata or remove the existing destruction authority.

Add:

- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyCallbackControlBlock.swift`
  - Normative types `AppCallbackControlBlock`, `SurfaceCallbackControlBlock`, `GhosttyAppToken`, and `GhosttySurfaceToken`.
  - app/surface token, generation, open/closing/closed phase, current weak/owned host target as permitted, lease count, pending publication count, close state.
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyCallbackLease.swift`
  - Normative `CallbackLease` with synchronous acquire/release and safe default on closing/stale generation.
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyHostCallScope.swift`
  - owner/origin/generation/outermost-depth scope used by later action and cleanup tasks.

Prepare these product modifications, but land/wire them only in the atomic T11 lifetime integration gate:

- `Ghostty.swift` app userdata creation/ownership.
- `GhosttyAppHandle.swift` initialization and lifecycle; no app free in unconstrained `deinit`.
- `GhosttyCallbackRouter.swift` callback entry to reconstruct retained control block, acquire lease, copy bounded payload, then route.
- `GhosttySurfaceView.swift` surface userdata construction; no direct `ghostty_surface_free` in unconstrained `deinit`.
- `SurfaceManager.swift` lifecycle registration.

Callback payloads are owned/copied before any actor hop. Foreign callbacks do not synchronously touch AppKit or wait for MainActor. Closing/stale callbacks return the action-specific safe default.

### Test proof

Add:

- `GhosttyCallbackControlBlockTests.swift`
- `GhosttyCallbackLifetimeRaceTests.swift`
- `GhosttySurfaceLifetimeTests.swift`

Extend `GhosttyCallbackRouterTests.swift` and `GhosttyAppHandleTests.swift`.

Boundary/seam: C userdata entry and explicit close/free.

Invariants: no delayed unretained Swift dereference; callback lease protects storage; surface invalidates routing/capture/IPC before free; app frees only after all surfaces and publication/lease drains.

Oracle: explicit control-block state/lease/publication counters plus vendor completion recorder, not ARC/deinit observation alone.

RED/GREEN: required for late callback, close/recreate, foreign callback, queued layer publication, app free with live/closing surfaces, and off-main deinit free.

Candidate quiescence is a separate blocking integration gate; pinned behavior cannot prove it.

There is no accepted intermediate product commit with new callback admission and old or absent surface/app destruction. T3, T4, and T10 may develop against the dormant control-block seams and test assembly; T11 switches callback userdata, completion owners, explicit free ownership, and final release conditions together.

## 5. Task T3 — One-Pending-Turn Ghostty Tick Gate

Requirements: GT1–GT8.

### Production changes

Add `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyTickGate.swift` with explicit idle/scheduled/draining/closing state and orthogonal dirty bit. It owns current app generation, at most one pending MainActor host turn, wake counts, drain watermarks, and shutdown invalidation.

Develop the gate and host-turn adapter against the dormant T2 control block. Prepare the `GhosttyCallbackRouter.wakeup_cb` diff so it synchronously offers a wake instead of creating one `Task { @MainActor }` per callback, but wire that product callback only at T11. One `GhosttyHostTurnContext` exists only for that MainActor turn and one `ghostty_app_tick` call inside `MainActorWorkLedger`; it contracts only bounded presentation keys and committed fact-sequence ranges and never becomes the sole owner of an exact fact. A wake during drain marks dirty and schedules at most one follow-up after the current turn. The gate does not loop an unbounded vendor drain inside one host turn.

Modify `GhosttyAppHandle` shutdown to invalidate scheduled work and wait/generation-fence the active turn before app free.

### Test proof

Add:

- `GhosttyTickGateTests.swift`
- `GhosttyAppTickShutdownRaceTests.swift`
- `GhosttySustainedRefillVerifierTests.swift`

One hundred thousand wakeups before one MainActor turn must create one scheduled turn. A true sustained-refill test records producer pushes after tick entry and during draining; a preloaded-only burst is invalid. Wake/drain/shutdown races use deterministic gates, not sleeps.

Independent oracle: literal gate transition model plus producer push/tick entry/exit watermarks.

RED/GREEN: current task-per-wakeup is RED. GREEN proves bounded amplification and exact dirty follow-up.

Blocking replan: one `ghostty_app_tick` remains above the approved unpreemptible ceiling under overlapping refill. That requires a separate libghostty bounded-drain/cooperative-yield contract; host coalescing cannot conceal it.

## 6. Task T4 — Clipboard And Close Completion Tokens

Requirements: CB4–CB6, GA close semantics, SC4.

### Production changes

Add generation-bound request owners/tokens under `Features/Terminal/Ghostty/` for clipboard read/write/confirmation and close intent. Modify `GhosttyCallbackRouter`:

The request owners and callback adapter are first proven in the dormant T2 test assembly. The production callback table and completion/free interaction wire atomically at T11; T4 does not land a partial lifetime path.

- callback copies request and returns/defer semantics exactly as vendor API requires;
- MainActor pasteboard/confirmation work is asynchronous from foreign origin;
- accepted requests settle exactly once semantically before the associated C surface can free;
- completion rechecks surface generation and `SecureInputOwner` epoch;
- reentrant confirmation and teardown settle through exactly one selected vendor completion—content, confirmed-empty, or denied as the request contract permits; there is no host-only cancellation state;
- close commits canonical closing synchronously where the action Boolean requires it, but physical free waits until the outer host C call returns.

### Test proof

Add `GhosttyClipboardRequestTests.swift` and `GhosttyCloseIntentTests.swift`.

Cases: direct/foreign callback, allow/deny, reentrant confirm, secure-input epoch change, surface replacement, close during request, app shutdown, duplicate completion, malformed/oversized payload.

Oracle: independent request settlement ledger and fake vendor completion recorder. Every accepted token has exactly one terminal settlement.

RED/GREEN: required. Split from T2/T9 because completion IO and destruction have different oracles.

## 7. Task T5 — Exhaustive Action Admission And User Intent

Requirements: GA1–GA10 and the complete action manifest.

### Production changes

Add:

- `GhosttyActionAdmissionDescriptor.swift`
  - tag, selected-vendor availability, source/origin allowance, synchronous handled result, default-host/fallback policy, payload/content disposition, plane, privileged purpose, generation policy.
- `GhosttyActionAdmissionPolicy.swift`
  - exhaustive descriptor lookup generated/checked against `GhosttyActionTag.allCases` and selected headers.
- `UserIntentGate.swift`
  - starts unbound for each physical input event; first eligible workspace/URL/clipboard purpose claims and consumes it; no second purpose/action.
- `TerminalWorkspaceCommandSink.swift`
  - narrow adapter into the existing `PaneTabViewController` command resolver; no command bus.
- `Sources/AgentStudio/Features/Terminal/Runtime/TerminalNotificationAdmissionSink.swift`
  - narrow MainActor protocol plus bounded generation-bearing `TerminalNotificationAdmissionRequest` and exhaustive `TerminalNotificationAdmissionReceipt` (`accepted`, payload/policy/rate/generation denial).
- `Sources/AgentStudio/App/Coordination/TerminalNotificationAdmissionAdapter.swift`
  - App-layer adapter from the Terminal-owned protocol to the one existing `InboxNotificationRouter` instance; Terminal does not import the sibling Inbox feature.

Modify:

- `GhosttySurfaceView+Input.swift` to create `GhosttyHostCallScope` and one-use intent gate around direct key/mouse/text C calls.
- `GhosttyActionRouter.swift` and its extensions to copy descriptors, stamp current origin/generation, perform the synchronous decision, and route to the selected plane without a redundant MainActor task when already isolated.
- `WorkspaceSurfaceCoordinator.handleTerminalRuntimeEvent` to remove command routing after direct sink migration.
- `InboxNotificationRouter` to expose a synchronous MainActor `admitTerminalNotification` seam that delegates to its one private/shared `InboxPromoter` and returns the exact atom mutation receipt.
- Ghostty/terminal composition to inject `TerminalNotificationAdmissionSink` backed by that existing router instance; NS calls it synchronously on MainActor and returns `true` only when `InboxPromoter.promoteExplicit`/`InboxNotificationAtom` commits the exact current-generation occurrence.

Composition must not construct a second `InboxPromoter` or a parallel notification admission owner. Router observation, direct terminal NS admission, policy/rate limiting, dedupe, tracing, and durable inbox mutation share the same feature-owned owner instance.

Use the spec's exhaustive `GhosttyHostCallKind` vocabulary: `appTick`, `userKey`, `userMouseButton`, `userMouseMotion`, `userScroll`, `textInput`, `programmaticInput`, `bindingQuery`, `geometry`, `focusOrVisibility`, `surfaceLifecycle`, and `clipboardCompletion`. Only current-generation `userKey` and `userMouseButton` scopes create a gate; the gate's exact purposes are `workspaceCommand`, `openURL`, and `clipboardWrite`.

Authority rules:

- app tick, programmatic input, foreign callbacks, missing/stale/consumed gates, and chained second actions cannot perform privileged workspace/URL/clipboard effects;
- `OPEN_URL` denial returns the specified consuming fallback result but opens nothing;
- `SHOW_CHILD_EXITED` fact admission alone does not suppress vendor fallback;
- destructive close frees only after outer C unwind and cannot free a replacement generation;
- terminal-controlled metadata never grants authority.
- for both selected vendors, the `SA` policy for title, tab-title, and PWD has no foreign-thread success path; a future direct foreign emission is a spec replan, not a presentation-mailbox case.

### Test proof

Extend/repair:

- `GhosttyActionRouterTests.swift`
- `GhosttyAdapterTests.swift`
- `GhosttyEventRoutingCoverageTests.swift`
- `GhosttySurfaceShortcutTests.swift`

Add:

- `GhosttyActionAdmissionManifestTests.swift`
- `GhosttyActionOriginRoutingTests.swift`
- `GhosttyActionUserIntentGateTests.swift`
- `GhosttyVendorFallbackTests.swift`
- `GhosttyActionGenerationRaceTests.swift`

Mechanical proof compares both selected header tag sets, `GhosttyActionTag.allCases`, descriptors, and all 66 accepted manifest rows. Behavioral proof covers every policy and each privileged, exact, notification, fallback, command, and suppression disposition.

Oracle: literal manifest plus side-effect/fallback counters; expected values may not call production descriptor lookup.

For NS, the independent success oracle is `TerminalNotificationAdmissionReceipt` joined with the real shared `InboxPromoter`/atom mutation result. Extend `InboxPromoterTests.swift`, `GhosttyActionRouterTests.swift`, and add a Terminal→App adapter→existing-router→Inbox integration test. Assert one notification admission owner identity and exactly one inbox row when router observation and direct NS admission overlap. Oversized, rate-limited, stale-generation, or policy-denied requests return false and create neither an inbox row, raw replay, nor delayed effect. For EF/bell, test the separate manifest policy and any secondary content-free fact independently.

RED/GREEN: required for deferred-success Boolean mismatch, chained user intent, origin denial, close unwind, and candidate selection tag.

## 8. Task T6 — Terminal Signal Planes And Cutover-Ready Assembly

Requirements: TS1–TS9.

Depends on shared admission/fact contracts and T5 descriptors.

### Cutover-ready endpoint construction

Add:

- `Sources/AgentStudio/Features/Terminal/State/MainActor/TerminalPresentationState.swift`
- `Sources/AgentStudio/Features/Terminal/Runtime/TerminalPresentationMailbox.swift`
- `Sources/AgentStudio/Features/Terminal/Runtime/TerminalStateSnapshot.swift`
- `Sources/AgentStudio/Features/Terminal/Runtime/TerminalFactOwner.swift`
- terminal plane payload types: `TerminalUISample`, `TerminalActivityInput`, `TerminalDomainFact`, `TerminalCommandRequest`, `TerminalDiagnosticSample`.

Prepare the target `TerminalRuntime` assembly and exercise it in focused/integration tests:

- remove `BusPostingPaneRuntime` conformance and all terminal use of `PaneRuntimeEventChannel`;
- dispatch every Ghostty action to exactly one descriptor-selected plane;
- mutate direct local presentation state for scrollbar/search/mouse/cell/key/current metadata;
- offer foreign-only current presentation to the latest mailbox when needed;
- commit exact lifecycle/command/health current facts synchronously to `TerminalFactOwner` and route secure-input authority through `SecureInputOwner`;
- expose named semantic `RuntimeDomainFact` endpoints without wiring a second production bus before IG1;
- expose `TerminalStateSnapshot` and `facts(after:)` for IPC status/wait.

Commands use direct typed sinks. Screen content is not a plane and is not implemented.

Bell and desktop notification do not become terminal-journal authority. Bell follows the manifest's EF policy. Desktop notification follows NS through the injected `TerminalNotificationAdmissionSink` and App-layer Inbox adapter after payload/rate/generation policy; the callback reports success only after exact inbox admission. A later content-free `userNotification` fact is secondary and cannot decide the callback Boolean or replay raw notification text.

Before IG1, production remains on the complete legacy global transport. T6 tests instantiate the new terminal assembly in isolation. IG1 atomically wires this assembly, removes terminal `PaneRuntimeEventChannel`/legacy publication, and enables the one semantic fact path; no product commit publishes through both.

### Test proof

Repair legacy expectations in:

- `TerminalRuntimeTests.swift`
- `AgentStudioIPCRuntimeAdapterTests.swift`
- `RuntimeEnvelopeMemoryFootprintTests.swift`
- `PaneRuntimeEventChannelTests.swift`

Add:

- `TerminalSignalAdmissionTests.swift`
- `TerminalFactOwnerTests.swift`
- `TerminalSignalFloodTests.swift`
- `TerminalContentDispositionTests.swift`
- `Architecture/TerminalSignalPlaneArchitectureTests.swift`

Flood 100,000 scrollbar/search/mouse/cell samples interleaved with close, command-finished, renderer health, secure-input, and notification facts. Expected: bounded latest state; zero global posts/replay for samples; exact fact order or explicit non-current gap; no sample eviction of facts.

Oracle: independent latest-value map, literal ordered facts, global post counter, and snapshot model.

RED/GREEN: current tests requiring raw terminal posts/replay form RED; replace them with zero-post and snapshot/journal proof. No dual terminal pipeline is accepted.

## 9. Task T7 — Activity Projector And Inbox Semantic Parity

Requirements: AI1–AI4.

### Production changes

Add:

- `Sources/AgentStudio/Features/Terminal/Activity/TerminalActivityMailbox.swift`
- `Sources/AgentStudio/Features/Terminal/Activity/TerminalActivityProjector.swift`

The mailbox contracts row totals, pinned state, output timestamps, progress/marks, and bounded heuristic metadata before actor messages. One shared fair pane-keyed projector owns quiet/deadline/lease state; a saturated pane cannot starve another. It emits low-rate semantic activity transitions and accepted notification intents.

Build the projector/parity path in the isolated cutover-ready terminal assembly. Prepare removal of `TerminalActivityRouter` and these production changes, but wire them atomically at IG1:

- `TerminalActivityAtom` to accept typed compact mutations only.
- `InboxNotificationRouter` to consume semantic activity/notification facts and direct observed/pinned presentation inputs required for clear policy, not the global raw stream.
- `AppDelegate+InboxNotificationBoot.swift` to boot the new owner.

Before IG1, production retains only the complete legacy router. IG1 wires `TerminalActivityMailbox`/`TerminalActivityProjector`, removes the legacy router/boot subscription, and proves exactly one projector ingress. A compatibility bridge from legacy raw bus events into the new projector is forbidden.

### Test proof

Retain semantic intent but repair ingress in:

- `TerminalActivityRouterTests.swift`
- `TerminalActivityDerivedEventTests.swift`
- `TerminalActivityAgentSettledHeuristicTests.swift`
- `InboxNotificationDerivedActivityTests.swift`
- `InboxNotificationRouterObservedPaneTests.swift`
- `DerivedTerminalActivityNotificationIntegrationTests.swift`
- `DerivedTerminalActivityNotificationRegressionTests.swift`

Add `TerminalActivitySemanticParityTests.swift`, `TerminalActivityProjectorFloodTests.swift`, and the independent oracle at `Tests/AgentStudioTests/Features/Terminal/State/Helpers/TerminalActivityParityOracle.swift`. The oracle is test support and shares no production transition implementation with the projector.

Use injected clock and literal sequence oracle for pinned-to-bottom, unseen output, quiet settled, progress-error, alternate-screen/TUI, observed-pane clearing, and multi-pane deadline fairness. One hundred thousand raw inputs should produce O(bursts/transitions) semantic outputs.

RED/GREEN: required. Replan if parity requires global raw events or actor-per-pane.

## 10. Task T8 — Terminal Runtime Generation And Authenticated Agent Reports

Requirements: AI3, AI5–AI10.

### Production changes

Modify `RuntimeRegistry.swift` to mint one non-persisted `TerminalRuntimeGeneration` only after successful terminal runtime registration and invalidate it on unregister/replacement.

Add:

- `Sources/AgentStudioProgrammaticControl/IPCAgentReportContracts.swift`
  - `agent.activity.report`, `agent.notification.post`, exhaustive activity vocabulary, bounded session/task/progress/summary fields, receipts/errors.
- `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCAgentReportAdapter.swift`
  - resolve authenticated principal/current server generation and offer accepted report to projector.
- `scripts/verify-agentstudio-agent-report-smoke.sh`
- `Tests/AgentStudioTests/Scripts/AgentStudioAgentReportSmokeScriptTests.swift`

Modify:

- `AgentStudioIPCAuthentication.swift`
- `AgentStudioIPCRegistryAuthorization.swift`
- `AgentStudioAppIPCService.swift`
- `AgentStudioAppIPCServer+AuthenticatedRouting.swift`
- server connection teardown
- pane-agent launch/bootstrap wiring
- `AgentStudioIPCRuntimeAdapter.swift`

The server stamps pane and runtime generation. Caller pane/generation fields are absent or ignored/rejected as non-authoritative. Ordering/idempotency keys are principal + server generation + report-session + monotonic sequence; notification dedupe adds bounded caller key. Enforce schema/size/rate/recent-count/lease/sequence-gap policies.

Runtime close/replacement revokes tokens, grants, sockets, leases, and queued reports for the old generation. `waitingForApproval` is advisory and cannot create/resolve a permission request. No OSC/hook protocol is added.

### Test proof

Add:

- contract tests in `Tests/AgentStudioProgrammaticControlTests/`
- `Tests/AgentStudioAppIPCTests/AgentStudioIPCAgentReportTests.swift`
- `AgentStudioIPCAgentPrincipalLifecycleTests.swift`
- App adapter/projector integration tests

Use a real Unix socket/authenticated routing integration for valid report, unauthenticated/malformed/oversized/rate-limited input, spoofed pane/generation, duplicate/conflicting payload, stale/gapped sequence, expired/replaced lease, old-generation queued report, socket close, and permission separation.

The `verify-agentstudio-agent-report-smoke` mise task launches through the standard debug runner, authenticates over the real Unix socket, posts activity and notification reports, verifies server-stamped attribution plus runtime-replacement socket revocation, and queries the resulting content-safe receipt/state. Its script-contract test is not the smoke itself.

Independent oracle: server registry current generation plus accepted receipt/projector/inbox state.

RED/GREEN: required for pane-only invalidation allowing stale-generation authority.

## 11. Task T9 — App-Global Secure Input And Content Denial

Requirements: SC1–SC8.

### Production changes

Add:

- `Sources/AgentStudio/Features/Terminal/Security/SecureInputOwner.swift`
- `Sources/AgentStudio/Features/Terminal/Security/SecureInputOperatingSystemAdapter.swift`
- `scripts/verify-secure-input-native.sh`
- `Tests/AgentStudioTests/Scripts/SecureInputNativeScriptTests.swift`

The owner contains global request, scoped requests keyed by surface generation, focused surface, app active state, desired OS state, successfully applied/indeterminate state, and monotonic security epoch. The action target determines global versus scoped request; toggle resolves against that scope.

Modify action routing, app/window focus/activation lifecycle, surface teardown, terminal snapshot projection, and inbox content-free transition handling. `TerminalRuntime.isSecureInput` remains projection only.

Before attempting OS enable, advance the epoch and apply conservative capture fencing/purge. Global enabled or indeterminate denies capture. Focus/app activation/request removal/OS failure/surface teardown/app shutdown are exhaustive. Every successful enable is balanced by the same owner with disable.

Do not add a screen-capture API, atom, event, replay, persistence, or default self-pane capability.

### Test proof

Add:

- `SecureInputOwnerTests.swift`
- `SecureInputCaptureFenceTests.swift`
- IPC screen-capture denial tests
- native secure-input verifier and script contract tests

Extend `AgentStudioOTLPTraceProjectionTests.swift` with canaries for terminal text, prompts, commands, credentials, tool output, title, URL, paths, raw pane/surface IDs, clipboard tokens, and errors.

Unit/integration oracle: injected OS adapter transition log and exhaustive owner-state table must prove every activation and disable failure transition. Native smoke requires real enable, focus transfer, deactivate/reactivate, scoped removal, and balanced disable/shutdown through the exact launched app and real Carbon query. Forced native OS failure is explicitly not applicable unless the platform harness exposes a deterministic mechanism; it is never inferred from the injected adapter or treated as a silent skip.

RED/GREEN: required for pane-local toggle authority and pre-activation fencing. Native proof is not replaceable by fake adapter tests.

Any request to expose screen content requires a new accepted product spec.

## 12. Task T10 — Geometry, Visibility, Display, And Reveal Owners

Requirements: SF1–SF8.

### Production changes

Add:

- `SurfaceGeometryCommitOwner.swift`
- `GhosttySurfaceHostState.swift`

Modify:

- `GhosttySurfaceView+Input.swift` only to preserve the short direct input path and host-call scope; perform no repo/global/screen/fleet work before Ghostty.
- `GhosttySurfaceView.swift` to delegate content scale/pixel size/display ID commit to one owner.
- `TerminalSurfaceScrollView.swift` so layout does not invoke an independent geometry path.
- `SurfaceManager.swift` and mount/window lifecycle to derive mounted, selected/host-hidden, occluded/minimized, app/window active, focus, and display ID separately.

Geometry decision and redraw reason are different types. Unchanged geometry performs no refresh without a named redraw reason. Hidden/minimized surfaces remain VT/session-current but do not consume foreground frame budget; reveal publishes the latest current generation promptly. Forward current display ID across 60/120 Hz and display movement.

### Test proof

Repair/extend:

- `GhosttySurfaceViewContentScaleTests.swift`
- `GhosttySurfaceViewGeometryCommitTests.swift`
- `GhosttySurfaceViewInitialFrameTests.swift`
- terminal surface scroll/mount/display/restore tests

Add:

- `GhosttySurfaceInputPathTests.swift`
- `GhosttySurfaceVisibilityTests.swift`
- `GhosttyDisplayPacingTests.swift`

Cases: narrow/zero/finite sizes, Retina scale, split resize, reparent, alternate screen, scrollback wrapper, inactive tab, minimized/occluded, reveal, 60/120 Hz/cross-display.

Oracle: literal pixel geometry and fake libghostty call ledger plus native visible echo/caret/focus/reveal. Existing “always refresh” expectation becomes RED for SF4; GREEN refreshes only for changed geometry or named redraw.

## 13. Task T11 — Explicit Surface/App Destruction

Requirements: SF9–SF10; completes T2/T4 lifecycle and depends on T4, T8, and T9 production revocation/completion seams.

### Production changes

Add `GhosttySurfaceLifetimeOwner.swift`. It performs:

1. synchronously mark canonical closing and invalidate routing/capture/IPC admission;
2. cancel/reject new actions and tick work for the generation;
3. settle clipboard/close requests;
4. remove secure-input/runtime registrations;
5. call `ghostty_surface_free` on the required owner while host view/control-block storage remains alive through vendor thread joins;
6. drain or generation-fence in-flight callback leases and main-queue host-observing publication blocks;
7. release storage;
8. after every surface quiesces, close app wake/action admission, invalidate turns, call `ghostty_app_free`, and release app control block only when the selected vendor guarantees no later callback.

Modify `GhosttySurfaceView`, `SurfaceManager`, and `GhosttyAppHandle` to use this owner; deinit may assert/report missed explicit close but cannot be the free authority.

T11 is the atomic lifetime integration gate: it wires the dormant T2 control blocks, T3 tick gate, T4 completion tokens, T8 runtime/IPC revocation, T9 secure-input removal, current action/surface generation owners, explicit surface free, and app free in one production composition change. Before this gate the product retains the complete old lifetime path; after it there is no unretained callback userdata or deinit free authority.

T11 changes callback/tick/lifetime admission while action output continues through the complete single legacy terminal route until IG1. The tick gate/host-turn adapter must prove it can drive that legacy downstream route without constructing the new terminal fact/activity publication path. T11 structural proof finds exactly one terminal publication route. IG1 later swaps only the downstream signal/fact/activity assembly; if the tick gate cannot operate with legacy output, T11 and the terminal endpoint cut become one larger atomic gate rather than adding an adapter or dual path.

### Test proof

Add `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceLifetimeIntegrationTests.swift` plus `scripts/ghostty-performance/verify-quiescence.sh` and its cases in `Tests/AgentStudioTests/Scripts/GhosttyPerformanceBuildScriptsTests.swift`. The script interface is exactly `verify-quiescence.sh --build-manifest <absolute-verified-manifest>`. Invoke it separately for pinned and candidate manifests from T1; each invocation builds/links the matching artifact, runs the real callback/surface/app teardown harness, emits build identity and event-gated drain evidence, and fails on any post-free callback. Cover callback entry, queued IOSurface layer publication, close/recreate, clipboard confirmation, tick scheduled/draining, runtime/IPC/secure-input revocation, and app shutdown.

Oracle: join control-block lease count, pending host-observing layer-publication count, clipboard settlement, runtime/IPC/secure-input revocation, vendor surface-free return/thread join, app-free return, and a post-free callback sentinel. No ARC-only oracle.

RED/GREEN: required. Candidate cutover is blocked if quiescence cannot satisfy the contract.

## 14. Task T12 — Candidate Acceptance, Atomic Cutover, And Post-Cut Proof

Requirements: GV1–GV8, SF11, terminal benchmark/observability contract.

### Isolated candidate acceptance before product cutover

After T1–T11, the shared global bus hard cut, S6, and CG1 pass, use the isolated pinned/candidate builders from T1 to execute the complete performance, action, resource, callback-quiescence, probe-perturbation, throughput, interaction, and scrollback-memory gates below. Every performance cell consumes the immutable human-approved `PerformanceCalibrationManifest` digest from CG1 and contributes to the S6d baseline-to-candidate comparison report. The product submodule remains pinned during this comparison. Candidate failure leaves the product vendor unchanged.

T11 may execute pinned/candidate callback/surface/app quiescence before CG1 only as build-identity-bound correctness and compatibility proof. That pre-CG1 result cannot set thresholds, measure performance acceptance, approve the candidate, or substitute for the T12 post-CG1 quiescence cell.

Only after those isolated candidate gates pass and the human-approved ceilings accept the candidate:

1. update the `vendor/ghostty` submodule pointer atomically to candidate `7e02af87980bfdaad6d393b985d35c917476878e`;
2. build through `scripts/build-ghostty-local.sh`/`.mise.toml` using the supported Xcode/Zig environment;
3. regenerate/copy header, library/XCFramework, resources, and action vocabulary together;
4. apply only the reviewed mandatory compatibility adaptation;
5. keep benchmark probes out of product configurations;
6. run manifest/resource/action/lifetime proof before accepting the commit.

Generated `Frameworks/GhosttyKit.xcframework` and resource output are never hand-edited. There is no permanent pinned/candidate runtime path.

T12 owns these final artifacts and `.mise.toml` task registrations:

- `scripts/ghostty-performance/verify-vendor-manifest.sh`
- `scripts/ghostty-performance/verify-terminal-native.sh`
- `Tests/AgentStudioTests/Scripts/GhosttyVendorManifestScriptTests.swift`
- `Tests/AgentStudioTests/Scripts/GhosttyTerminalNativeScriptTests.swift`
- `verify-ghostty-vendor-manifest` and `verify-ghostty-terminal-native` mise tasks

T8 owns `verify-agentstudio-agent-report-smoke`; T9 owns `verify-secure-input-native`. One build/harness integrator serializes their `.mise.toml` edits with the shared performance task.

### Performance matrix

Use the shared standard runner/evidence ledger. Execute pinned versus candidate and baseline versus contracted host cells with semantically equivalent adapters, plus compiled-disabled/probe-enabled calibration.

Fixed workloads include ASCII, Unicode/wide, CSI/request-response, idle typing, loaded typing, cursor/caret, TUI mouse, focus, reveal, hidden/visible, watched idle/pressure, Bridge visible/background, multi-pane fairness, and scrollback fill/clear/prune. The terminal core owns 24 cells and eight probe-calibration prerequisites; the combined core matrix has 34 cells.

For every cell, the S6d report queries marker-scoped VictoriaMetrics for p50/p95/p99/max and support counts and VictoriaLogs for required stages, final-state validity, and exact build/run/calibration identity. It reports absolute values, baseline-to-candidate deltas, percentage deltas, control-relative deltas, and evidence adequacy. When the pinned/candidate adapters are not semantically equivalent, a pure-vendor row consumes the conditional A0 adaptation-control digest and reports adapter cost separately; without that proof its label is “vendor plus mandatory adaptation.” MainActor evidence keeps queue age, synchronous service time, independent heartbeat gaps/overdue counts, AppKit dispatch-to-handler, Ghostty host-call service, and input-to-current-layer publication as separate distributions; proximity alone never attributes a heartbeat gap to one operation. Missing stages, unsupported tails, stale identity, evidence loss, or a violated MainActor/interaction ceiling yields `invalidEvidence` or `validFail`, never pass.

Throughput reports separately:

- writer completion;
- terminal input drain/final sentinel;
- qualifying current-generation layer publication.

The causal frame observer rejects pre-marker, stale-generation, wrong-size, and missing-source-watermark frames. Probe loss/unequal perturbation makes evidence invalid.

Scrollback memory uses a fixed fill corpus, event-driven terminal-idle and renderer-quiescent predicates, clear/prune, and stable bounded sampling. Report resident and platform-supported compressed/page-return measures. A single RSS sample or sleep is invalid; absolute and control-relative ceilings are blocking.

### Native acceptance

Launch the exact debug app through `run-debug-observability.sh`, target its PID with Peekaboo, and verify:

- ordinary typing echo and causal layer publication;
- cursor/caret movement under watcher and output pressure;
- TUI mouse selection/drag;
- focus switching;
- hidden/minimized-to-visible reveal;
- 60/120 Hz and display movement where hardware exists;
- secure-input transition and denial behavior;
- close/recreate and shutdown without stale surface behavior.

Native unavailable hardware cells are reported as unavailable diagnostics, not fabricated passes. Core causal layer/publication and supported native cells remain blocking.

After deterministic T12 candidate acceptance, atomic vendor cutover, and post-cut proof, the shared DQ1 gate qualifies the product-selected candidate with one attended deterministic terminal while watching `/Users/shravansunder/Documents/dev/open-source` and `/Users/shravansunder/Documents/dev/project-dev`. Telemetry and portable reports use only the `open_source` and `project_dev` aliases. Initial observation is read-only; controlled churn is confined to the run-owned `.agentstudio-performance-soak/<run-token>` sentinel defined by DQ1. Run each root alone and both together while exercising terminal output pressure, typing, cursor/caret, TUI mouse, focus, reveal, Bridge background/visible transitions, and clean shutdown.

DQ1 is the blocking real-environment confirmation that MainActor availability survives the actual root shapes: queue-age and service tails remain within per-operation budgets, heartbeat gaps remain within the independent liveness budget, interaction and layer-publication tails remain within their causal budgets, exact facts have zero unresolved gaps/drops, repair debt reaches quiescence, final topology/SQLite/content state is current, and scrollback/watcher/ledger memory reaches the approved plateau. It is not evidence of vendor-only benefit; the isolated T12 factorial report remains the attribution oracle.

## 15. Existing-Test Audit

Replace or repair anti-oracles that assert forbidden behavior:

1. `TerminalRuntimeTests` requiring scrollbar/search/state samples to post/replay globally.
2. `GhosttyActionRouterTests` treating later legacy-envelope delivery as proof of the synchronous action result.
3. `AgentStudioIPCRuntimeAdapterTests` terminal waits over legacy runtime replay.
4. `GhosttySurfaceViewGeometryCommitTests` requiring every geometry commit to refresh.

Retain and adapt:

- action tag/payload translation coverage;
- injected-clock activity/inbox semantic scenarios;
- geometry math/content-scale/initial frame;
- surface shortcut and direct input behavior;
- IPC authentication/principal invalidation foundations;
- OTLP source-scrubbing tests.

No test is deleted without replacement, redundancy, or dead-contract proof.

## 16. Terminal Requirements / Proof Matrix

| Claim | Task | Public seam / boundary | Independent oracle | Layer / freshness | RED/GREEN |
| --- | --- | --- | --- | --- | --- |
| callbacks cannot outlive storage | T2/T11 | C userdata lease and explicit lifecycle | control state/lease/publication ledger + vendor recorder | unit + vendor integration; exact vendor/HEAD | required |
| wakeups contract to one turn | T3 | tick-gate offer/drain | literal transition/watermark model | unit + sustained E2E; run/probe digest | required |
| clipboard/close settle exactly | T4 | request token and vendor completion | independent settlement recorder | unit + integration; surface generation | required |
| action Boolean/authority is exhaustive | T5 | action callback return/effect | accepted manifest + effect/fallback counters | unit + vendor/native integration; header digest | required |
| UI samples never reach global bus | T6 | presentation/fact/snapshot owners | latest map + fact list + zero-post counter | unit flood + IPC integration; source inventory | required |
| activity/inbox semantics survive contraction | T7 | projector transition output | injected-clock parity sequence | unit + integration; current implementation HEAD | required |
| reports are current-principal scoped | T8 | authenticated JSON-RPC | server generation registry + receipt/state | unit + real Unix socket; fresh socket/runtime | required |
| secure input is app-global/fail-closed | T9 | owner transition API/OS adapter | state table + real OS query + canary scan | unit + native/OTLP integration; exact PID/run | required |
| input/geometry/visibility stay direct/current | T10 | AppKit-to-Ghostty calls and geometry owner | call ledger + PID-visible behavior | unit + native E2E; display capability manifest | required |
| free occurs only after quiescence | T11 | lifetime owner | vendor completion + leases/publications | pinned/candidate stress; vendor identity | required |
| candidate benefit is attributable | T1/T12 | immutable build/matrix report | action/header/resource/probe manifests + workload oracles | build + E2E; exact digests | required |
| memory does not regress | T12 | fill/quiesce/clear/prune workload | stable bounded platform samples | performance E2E; corpus/build/hardware | required |
| loaded terminal remains responsive with actual development roots | T12 + shared DQ1 | attended terminal + authorized root aliases | Victoria queue/service/heartbeat/interaction distributions + PID-targeted IPC/Peekaboo behavior + final-state/memory oracles | local qualification E2E; exact PID/run/build/root manifests | required locally; deterministic fixtures remain the portable regression oracle |

## 17. Terminal Execution Order

```text
T1 vendor delta/adapters (product remains pinned)
  |
shared admission/ledger
  -> T2 dormant control-block seams
       +-> T3 tick gate
       +-> T4 clipboard/close tokens
              -> T5 action/user intent
                    -> T6 signal planes
                         -> T7 activity parity
                         -> T8 agent reports
                    -> T9 secure input
       +-> T10 geometry/visibility
  -> T11 atomic callback/completion/revocation/destruction integration
       (requires T4, T8, T9, and T10 seams)
  -> terminal cutover-ready endpoint assembly
  -> shared IG1 global bus hard cut
  -> shared S6 + CG1 human-approved immutable calibration digest
  -> T12 isolated candidate acceptance -> atomic cutover -> post-cut proof
  -> shared DQ1 real-root/MainActor qualification
  -> IG2 combined cross-pressure proof
```

T3, T4, and initial T10 owner files may develop in parallel after T2 interfaces stabilize. T7, T8, and T9 may develop in parallel after T6/T5 contracts stabilize. T12 contributes the terminal/vendor cells and accepted candidate artifact to DQ1 and IG2; it does not own either shared decision. Existing edits to `GhosttyCallbackRouter.swift`, `GhosttyAppHandle.swift`, `GhosttySurfaceView.swift`, `SurfaceManager.swift`, `GhosttyActionRouter.swift`, `TerminalRuntime.swift`, `RuntimeRegistry.swift`, IPC server/auth files, `AgentStudioOTLPTraceProjection.swift`, `.mise.toml`, and the vendor pointer use one integration owner per gate.

## 18. Validation Commands

Focused commands use exact suite names after new tests exist:

```bash
mise run test -- --filter 'GhosttyCallback'
mise run test -- --filter 'GhosttyTickGate'
mise run test -- --filter 'GhosttyAction'
mise run test -- --filter 'TerminalSignal'
mise run test -- --filter 'TerminalActivity'
mise run test -- --filter 'AgentStudioIPCAgent'
mise run test -- --filter 'SecureInputOwner'
mise run test -- --filter 'GhosttySurface'
mise run test -- --filter 'GhosttyResources'
```

Then:

```bash
mise run lint
mise run test-fast
mise run test-large
mise run test-webkit
mise run test
mise run observability:up
mise run verify-ghostty-vendor-manifest
mise run run-debug-observability -- --detach
mise run verify-debug-observability
mise run verify-agentstudio-ipc-phase-a-smoke
mise run verify-secure-input-native
mise run verify-ghostty-terminal-native
mise run stop-debug-observability
mise run verify-agentstudio-agent-report-smoke
mise run verify-agentstudio-performance-workload -- --matrix terminal-factorial-24
mise run verify-agentstudio-performance-workload -- --matrix core-34
AGENTSTUDIO_PERF_REAL_ROOT_OPEN_SOURCE=/Users/shravansunder/Documents/dev/open-source \
AGENTSTUDIO_PERF_REAL_ROOT_PROJECT_DEV=/Users/shravansunder/Documents/dev/project-dev \
  mise run verify-agentstudio-real-root-qualification
```

`verify-ghostty-vendor-manifest` is offline. `run-debug-observability` owns one manual launch; `verify-debug-observability`, `verify-agentstudio-ipc-phase-a-smoke`, `verify-secure-input-native`, and `verify-ghostty-terminal-native` attach to that exact PID/run marker and never launch. `stop-debug-observability` confirms that exact identity exits. `verify-agentstudio-agent-report-smoke`, each performance-workload invocation, and `verify-agentstudio-real-root-qualification` are independent launch owners: they preflight idle, launch one standard debug identity, and guarantee exact-PID cleanup before the next owner. An `already_running` marker is failure. The new task surfaces must use exact current run markers and real product boundaries. The real-root verifier also proves canonical sentinel containment, raw-path scrubbing, pre/post root-manifest validity, and cleanup before it can report a result. After the atomic product switch, rerun resource/action/lifetime smoke plus the supported native cells against the product-selected candidate. Report missing higher layers separately; do not relabel unit/script tests.

## 19. Rollback And Blocking Gates

Before hard cut, dormant new owners can be removed while legacy product behavior remains authoritative. After terminal signal, lifecycle, secure-input, IPC, global-bus, or vendor cutover, rollback reverts the complete integration commit.

Never restore unretained callback userdata, task-per-wakeup, mixed sample/fact dropping capacity, legacy terminal global publication, caller-supplied report attribution, pane-local secure-input authority, screen capture, deinit-driven free, or mixed vendor artifacts.

Blocking/replan gates:

- one tick remains unpreemptibly above the approved ceiling under overlapping refill;
- candidate callback/thread-join/publication behavior cannot satisfy quiescence;
- pinned/candidate compatibility or probe adapters are not semantically equivalent;
- a manifest action lacks source-verifiable origin/Boolean/fallback semantics;
- activity parity requires raw global events;
- native secure-input state contradicts the owner model;
- causal frame hook cannot remain benchmark-only/content-free;
- scrollback memory exceeds approved absolute or control-relative ceiling;
- any request adds screen capture or an OSC/hook report protocol without a new spec.
