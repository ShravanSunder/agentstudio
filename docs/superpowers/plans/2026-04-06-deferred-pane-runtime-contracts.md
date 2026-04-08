# Deferred Pane Runtime Follow-up (Terminal Event Coverage + C16) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the remaining pane-runtime follow-up work around terminal event coverage and per-pane filesystem context: (0) upgrade the bus posting mechanism for ordered, low-overhead delivery as a required prerequisite, (1) promote the remaining Ghostty/terminal runtime events onto the pane event stream, and (2) add typed per-pane filesystem context events with CWD rescoping (C16).

**Architecture:** Every event follows one path: `GhosttyActionRouter` → `GhosttyAdapter` → `TerminalRuntime.handleGhosttyEvent()` → `@Observable` state + `PaneRuntimeEventChannel.emit()` → `EventBus`. The channel uses a single `AsyncStream` continuation for ordered, zero-Task-overhead bus delivery. High-frequency events use `lossy` consolidation. Every event is a `PaneEnvelope` with `paneId` + `paneKind`, joinable to all filtering dimensions via `PaneMetadata.facets`.

**Tech Stack:** Swift 6.2, macOS 26, AppKit, GhosttyKit/libghostty, `@MainActor` stores, `EventBus<RuntimeEnvelope>`, Swift Testing (`@Suite`, `@Test`, `#expect`), mise

## Scope Alignment

This plan is intentionally narrower than the original February deferred-contract ticket text.

- **Contract 13 (Workflow Engine)** remains deferred in the architecture and is **not** implemented by this plan.
- **True Contract 15** in `docs/architecture/pane_runtime_architecture.md` is the agent/harness request-response channel (`TerminalProcessEvent`, request/response envelopes, `processSessionId`, `requestId`). This plan does **not** implement that contract.
- The terminal-event work below is a **Ghostty event coverage follow-up**, not the architecture's current Contract 15.
- **Contract 16** is only partially missing. The repo already has `PaneFilesystemProjectionStore` with CWD-subtree filtering; this plan completes the missing typed event surface and any remaining integration around that projection.

## Ticketing Note

Completing this plan alone does **not** by itself justify closing `LUNA-344` unless the ticket scope is updated to match the current architecture and the deliberate deferral of Contracts 13 and true 15.

**Branch dependency:** The `native-scrollbars` branch (worked by another agent) promotes `scrollbar`, `startSearch`, `endSearch`, `searchTotal`, `searchSelected` with typed payloads + `ScrollbarState` + `TerminalSearchState` + adapter translation. That agent is aware of this plan. After their branch merges, we rebase and Task 2 handles only the remaining 9 deferred tags. **Task 0 (AsyncStream continuation upgrade to `PaneRuntimeEventChannel`) is required and should merge before or be coordinated tightly with the scrollbar branch** — both touch the emit path, and conflicting changes to `PaneRuntimeEventChannel.swift` would be painful to resolve.

---

## The Shape — Every Event Follows This Path

```
Ghostty C API fires action callback
    │
    ▼
GhosttyActionRouter
    │ extracts typed payload from C union
    │ calls routeActionToTerminalRuntime(payload:)
    ▼
GhosttyAdapter.translate(actionTag, payload) → GhosttyEvent
    │
    ▼
TerminalRuntime.handleGhosttyEvent(event)
    │
    ├── 1. @Observable state mutation (sync, immediate — SwiftUI sees it this frame)
    │
    └── 2. channel.emit(event: .terminal(event), persistForReplay: <bool>)
           │
           ▼
       PaneRuntimeEventChannel.emit()                    ← @MainActor
           │ seq += 1 (monotonic per pane)
           │ PaneEnvelope(source: .pane(paneId), seq, ...)
           │ replayBuffer.append() if persistForReplay
           │ yield to local subscribers (sync)
           │ busContinuation.yield(envelope)              ← sync, ordered, no Task
           ▼
       Single consumer Task drains continuation → bus    ← cooperative pool
           │ for await envelope in outboundStream {
           │     await bus.post(envelope)
           │ }
           ▼
       EventBus → all subscribers
```

**Bus posting is formalized in `PaneRuntimeEventChannel`** — one `AsyncStream` continuation per channel, one consumer Task per channel lifetime. Producers call `emit()` which is sync. No `Task`-per-event. FIFO ordering guaranteed. Bounded buffer (128 events) provides backpressure detection.

**Boundary actors** (`FilesystemActor`, `GitProjector`, `ForgeActor`) are already on the cooperative pool — they call `await bus.post()` directly. No change needed for them.

### Filtering Dimensions

Every `PaneEnvelope` carries `paneId` + `paneKind`. Consumers join against `PaneMetadata.facets` for additional dimensions:

| Dimension | Source | Lookup |
|-----------|--------|--------|
| paneId | `PaneEnvelope.paneId` | Direct |
| paneKind | `PaneEnvelope.paneKind` | Direct |
| worktreeId | `PaneMetadata.facets.worktreeId` | `registry.runtime(for: paneId)?.metadata` |
| repoId | `PaneMetadata.facets.repoId` | Same |
| CWD | `PaneMetadata.facets.cwd` | Same |
| tabId | `WorkspaceTabLayoutAtom` | `atom(\.workspaceTabLayout).tabId(containingPane:)` |
| arrangementId | `WorkspaceMetadataAtom` | `atom(\.workspaceMetadata).activeArrangementId` |

### Policy and Replay Rules

**ActionPolicy** (scheduling):
- `critical` — immediate delivery, never coalesced
- `lossy(consolidationKey)` — batched on frame boundary (16ms), deduped by key
- **Each distinct property gets its own consolidation key.** `mouseShapeChanged` → `"mouseShape"`, `mouseVisibilityChanged` → `"mouseVisibility"`. Never group unrelated state under one key.

**persistForReplay** (late-joiner catch-up):
- `true` — mutable runtime state a late-joiner needs to reconstruct current state (`readOnly`, `secureInput`, `scrollbarState`, `cellSize`, `progressReport`, `rendererHealth`, `sizeConstraints`, `colorChanged`, `configChanged`)
- `false` — one-shot actions where replay would cause side effects (`openURL`, `undo`, `desktopNotification`) or workspace commands (`newTab`)

### Test Strategy

The codebase has established test harnesses — **use them, don't reinvent patterns.**

| Harness | Location | Use for |
|---------|----------|---------|
| `EventBusHarness<Envelope>` | `Tests/.../Helpers/EventBusHarness.swift` | Create isolated bus + `RecordingSubscriber`. Provides `makeSubscriber()`, `post()`, `postAll()`. |
| `RecordingSubscriber<Envelope>` | Same file | Actor-backed buffer. `snapshot()` returns all received events. `count(where:)`, `last(where:)` for filtering. `shutdown()` for cleanup. |
| `RuntimeEnvelopeHarness` | `Tests/.../Helpers/RuntimeEnvelopeHarness.swift` | Static factories: `paneEnvelope()`, `filesystemEnvelope()`, `gitEnvelope()`, etc. Extractors: `paneEvents(from:)`, `worktreeEvents(from:)`. |
| `PaneEnvelope.test()` | `Contracts/RuntimeEnvelopeFactories.swift` | Test factory with defaults for all envelope fields. |
| `assertEventuallyAsync` | `EventBusHarness.swift` | Poll with `Task.yield()` — **no wall-clock sleeps**. Use for async bus delivery assertions. |
| `assertBusDrained` | `EventBusHarness.swift` | Verify bus has no subscribers after cleanup. |

**Test pyramid for this plan:**

| Layer | What | Count | Pattern |
|-------|------|-------|---------|
| **Unit: emit → bus** | Each promoted event reaches the bus with correct envelope shape | ~10 tests (Task 1) | `TerminalRuntime` + injected `EventBusHarness`, `assertEventuallyAsync` on subscriber |
| **Unit: adapter translation** | Each deferred tag translates to typed `GhosttyEvent` | ~9-14 tests (Task 2) | `GhosttyAdapter.translate()` assertions |
| **Unit: replay persistence** | State events replay, one-shot events don't | ~2 tests (Task 1) | `runtime.eventsSince(seq: 0)` checks |
| **Unit: CWD rescoping** | Register, update, unregister, idempotency, prune | ~4 tests (Task 4) | Direct `PaneFilesystemProjectionStore` method calls |
| **Unit: bus ordering** | Events arrive in strict seq order via AsyncStream | 1 test (Task 0) | `EventBusHarness` + `RecordingSubscriber`, verify seq ordering |
| **Coverage gate** | No deferred tags remain | 1 test (Task 2) | `GhosttyActionRouter.deferredTags.isEmpty` |

**Rules:**
- No `Task.sleep()` in tests — use `assertEventuallyAsync` or `assertEventuallyMain`
- Always `subscriber.shutdown()` + `assertBusDrained(harness.bus)` in cleanup
- Use `RuntimeEnvelopeHarness.paneEvents(from:)` to extract typed records from recorded snapshots
- Create isolated `EventBusHarness<RuntimeEnvelope>()` per test — never use `PaneRuntimeEventBus.shared` in tests

### C String Safety (Ghostty Payloads)

Some Ghostty C payloads use **length-prefixed strings**, not null-terminated. When extracting strings from the C union:
- Check the Ghostty header (`vendor/ghostty/include/ghostty.h`) for each action's struct shape
- Use `String(bytes:count:encoding:)` for length-prefixed fields
- Use `String(cString:)` only when the header guarantees null termination
- The scrollbar plan's adapter code shows the correct pattern for each payload type

---

## Event Inventory

### Already On Bus (no changes)

| Event | Policy | Replay |
|---|---|---|
| `commandFinished(exitCode, duration)` | critical | yes |
| `cwdChanged(path)` | critical | yes |
| `titleChanged(title)` | critical | yes |
| `bellRang` | critical | yes |
| `readOnlyChanged(bool)` | critical | yes |
| `secureInputChanged(bool)` | critical | yes |
| `scrollbarChanged(state)` | lossy("scroll") | yes |
| `desktopNotificationRequested(title, body)` | critical | no |
| `promptTitleRequested(scope)` | critical | no |
| 9 workspace actions | critical | no |
| `unhandled(tag)` | critical | yes |

### Terminal Event Coverage Task 1 — Promote @Observable-Only and Dropped Events

| Event | Currently | Policy | Replay |
|---|---|---|---|
| `progressReportUpdated(state)` | @Observable only | lossy("progress") | **yes** |
| `rendererHealthChanged(healthy)` | @Observable only | critical | yes |
| `cellSizeChanged(size)` | @Observable only | lossy("cellSize") | **yes** |
| `sizeLimitChanged(constraints)` | @Observable only | critical | yes |
| `openURLRequested(url, kind)` | Dropped | critical | no |
| `undoRequested` | Dropped | critical | no |
| `redoRequested` | Dropped | critical | no |
| `copyTitleToClipboardRequested` | Dropped | critical | no |
| `initialSizeChanged(size)` | Dropped | critical | no |
| `deferred(tag)` | Dropped | lossy("deferred") | no |

### Terminal Event Coverage Task 2 — Promote Deferred Tags to Typed Events

| Deferred tag | New GhosttyEvent case | Policy | Replay |
|---|---|---|---|
| `startSearch` | `.searchStarted(query: String)` | critical | yes |
| `endSearch` | `.searchEnded` | critical | yes |
| `searchTotal` | `.searchMatchesUpdated(totalMatches: Int)` | lossy("searchTotal") | yes |
| `searchSelected` | `.searchSelectionChanged(selectedMatchIndex: Int?)` | lossy("searchSelected") | yes |
| `setTabTitle` | `.tabTitleChanged(String)` | critical | yes |
| `mouseShape` | `.mouseShapeChanged(shape: UInt32)` | lossy("mouseShape") | no |
| `mouseVisibility` | `.mouseVisibilityChanged(visible: Bool)` | lossy("mouseVisibility") | no |
| `mouseOverLink` | `.mouseLinkHovered(url: String?)` | lossy("mouseLink") | no |
| `keySequence` | `.keySequenceChanged(sequence: String)` | lossy("keySequence") | no |
| `keyTable` | `.keyTableChanged(table: String)` | lossy("keyTable") | no |
| `colorChange` | `.colorChanged(kind: UInt32, r: UInt8, g: UInt8, b: UInt8)` | critical | yes |
| `reloadConfig` | `.configReloadRequested` | critical | no |
| `configChange` | `.configChanged` | critical | yes |
| `scrollbar` | `.scrollbarChanged(ScrollbarState)` | lossy("scroll") | yes |
| `render` | Intercepted — Ghostty owns Metal rendering. Document as permanently skipped. | — | — |

### C16 Tasks 3-4 — Filesystem Context Events

| Event | Policy | Replay |
|---|---|---|
| `PaneFilesystemContextEvent.cwdSubtreeChanged(...)` | critical | no |
| `PaneFilesystemContextEvent.gitWorkingTreeInCwd(...)` | critical | no |

---

## File Structure

### Task 0 — Bus Posting Infrastructure

| File | Change |
|------|--------|
| `Core/RuntimeEventSystem/Runtime/PaneRuntimeEventChannel.swift` | Replace Task-per-event with AsyncStream continuation |
| `Tests/.../Runtime/PaneRuntimeEventChannelTests.swift` | Ordered delivery test, bounded buffer test |

### Terminal Event Coverage Tasks 1-2 — Promote Terminal Events

**Modify:**

| File | Change |
|------|--------|
| `Features/Terminal/Runtime/TerminalRuntime.swift` | Add `emit()` for 10 silent events |
| `Features/Terminal/Ghostty/GhosttyActionRouter.swift` | Move deferred tags to explicit routing |
| `Features/Terminal/Ghostty/GhosttyAdapter.swift` | Add `ActionPayload` variants + translation |
| `Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift` | New `GhosttyEvent` cases + `actionPolicy` |
| `Core/RuntimeEventSystem/Contracts/PaneKindEvent.swift` | New `EventIdentifier` cases |
| `Core/RuntimeEventSystem/Replay/EventReplayBuffer.swift` | Size estimates for replay-persisted events |

**Tests:**

| File | Change |
|------|--------|
| `Tests/.../Ghostty/GhosttyAdapterTests.swift` | Translation tests for new payloads |
| `Tests/.../Ghostty/GhosttyActionRouterTests.swift` | Coverage: no deferred tags remain |
| `Tests/.../Runtime/TerminalRuntimeTests.swift` | Bus emission + @Observable state tests |

### C16 Tasks 3-5 — Filesystem Context

**Create:**

| File | Responsibility |
|------|---------------|
| `Core/RuntimeEventSystem/Contracts/PaneFilesystemContextEvent.swift` | Typed event enum + context struct |
| `Tests/.../Projection/PaneFilesystemProjectionStoreContextTests.swift` | CWD rescoping tests |

**Modify:**

| File | Change |
|------|--------|
| `Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift` | `.paneFilesystemContext(...)` case |
| `Core/RuntimeEventSystem/Contracts/PaneKindEvent.swift` | 2 new identifiers |
| `Core/RuntimeEventSystem/Projection/PaneFilesystemProjectionStore.swift` | CWD context tracking |
| `App/Coordination/PaneCoordinator+ViewLifecycle.swift` | Wire lifecycle |

---

## Task 0: Upgrade PaneRuntimeEventChannel Bus Posting

Replace the per-event `Task {}` fire-and-forget with a single `AsyncStream` continuation. This is infrastructure that benefits every event — prerequisite before promoting high-frequency events.

**Why:** The current `Task { await bus.post(envelope) }` creates a new unstructured Task per event. At 60fps scrollbar events = 60 Tasks/sec. Tasks have no ordering guarantee — concurrent execution can scramble event order at the bus. The AsyncStream continuation is sync (nanoseconds), FIFO-ordered, and creates zero Tasks per event.

**Files:**
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/PaneRuntimeEventChannel.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Runtime/PaneRuntimeEventChannelTests.swift` (or existing test file)

- [ ] **Step 1: Replace Task-per-event with AsyncStream continuation**

Implement first — the ordering test references the new `busContinuation` property which must exist before the test compiles.

In `PaneRuntimeEventChannel.swift`:

```swift
@MainActor
final class PaneRuntimeEventChannel {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "PaneRuntimeEventChannel")
    private let clock: ContinuousClock
    private let replayBuffer: EventReplayBuffer

    private var sequence: UInt64 = 0
    private var nextSubscriberId: UInt64 = 0
    private var subscribers: [UInt64: AsyncStream<RuntimeEnvelope>.Continuation] = [:]

    // NEW: single ordered outbound stream to bus
    private let busContinuation: AsyncStream<RuntimeEnvelope>.Continuation
    private let busConsumerTask: Task<Void, Never>

    init(
        clock: ContinuousClock = ContinuousClock(),
        replayBuffer: EventReplayBuffer = EventReplayBuffer(),
        paneEventBus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared
    ) {
        self.clock = clock
        self.replayBuffer = replayBuffer

        // Create bounded outbound stream — single consumer drains to bus
        let (stream, continuation) = AsyncStream.makeStream(
            of: RuntimeEnvelope.self,
            bufferingPolicy: .bufferingNewest(128)
        )
        self.busContinuation = continuation

        self.busConsumerTask = Task { [weak paneEventBus] in
            guard let bus = paneEventBus else { return }
            for await envelope in stream {
                let result = await bus.post(envelope)
                if result.droppedCount > 0 {
                    PaneRuntimeEventChannel.logger.warning(
                        "Dropped bus event for \(result.droppedCount, privacy: .public) subscriber(s); seq=\(envelope.seq, privacy: .public)"
                    )
                }
            }
        }
    }

    // ... lastSequence, subscribe(), eventsSince(), snapshot() — unchanged ...

    func finishSubscribers() {
        let activeSubscribers = Array(subscribers.values)
        subscribers.removeAll(keepingCapacity: true)
        for continuation in activeSubscribers {
            continuation.finish()
        }
        busContinuation.finish()  // terminates bus consumer task
    }

    func emit(
        paneId: PaneId,
        metadata: PaneMetadata,
        paneKind: PaneContentType,
        commandId: UUID? = nil,
        correlationId: UUID? = nil,
        event: PaneRuntimeEvent,
        persistForReplay: Bool = true
    ) {
        sequence += 1
        let envelope = RuntimeEnvelope.pane(
            PaneEnvelope(
                source: .pane(paneId),
                seq: sequence,
                timestamp: clock.now,
                correlationId: correlationId,
                commandId: commandId,
                paneId: paneId,
                paneKind: paneKind,
                event: event
            )
        )

        if persistForReplay {
            replayBuffer.append(envelope)
        }

        // Local subscribers — sync, in-order
        for (subscriberId, continuation) in subscribers {
            switch continuation.yield(envelope) {
            case .enqueued: continue
            case .dropped:
                Self.logger.warning("Dropped local envelope subscriberId=\(subscriberId, privacy: .public)")
            case .terminated:
                Self.logger.debug("Skipped terminated subscriberId=\(subscriberId, privacy: .public)")
            @unknown default: continue
            }
        }

        // Global bus — sync yield to continuation, consumed by single background Task
        // FIFO ordered, no Task-per-event, bounded buffer (128)
        switch busContinuation.yield(envelope) {
        case .enqueued: break
        case .dropped(let dropped):
            Self.logger.warning(
                "Bus outbound buffer full, dropped envelope seq=\(dropped.seq, privacy: .public)"
            )
        case .terminated:
            Self.logger.debug("Bus continuation terminated, skipping seq=\(envelope.seq, privacy: .public)")
        @unknown default: break
        }

        _ = metadata
    }
}
```

- [ ] **Step 2: Write ordering test**

Use `EventBusHarness` and `RecordingSubscriber` from `Tests/AgentStudioTests/Helpers/EventBusHarness.swift`. Use `assertEventuallyAsync` (no wall-clock sleeps). Follow the pattern in `EventBusHarnessTests.swift`.

```swift
@Test("Events emitted in sequence arrive at bus in strict seq order")
@MainActor
func busReceivesEventsInOrder() async {
    // Arrange — isolated bus via harness, channel wired to it
    let harness = EventBusHarness<RuntimeEnvelope>()
    let channel = PaneRuntimeEventChannel(paneEventBus: harness.bus)
    let subscriber = await harness.makeSubscriber()
    let paneId = PaneId()
    let metadata = PaneMetadata(
        source: .floating(launchDirectory: nil, title: "Test"),
        title: "Test"
    )

    // Act — emit 10 events rapidly
    for i in 0..<10 {
        channel.emit(
            paneId: paneId, metadata: metadata, paneKind: .terminal,
            event: .terminal(.titleChanged("title-\(i)")),
            persistForReplay: false
        )
    }

    // Assert — all 10 arrive in strict seq order
    await assertEventuallyAsync("subscriber should receive all 10 events") {
        await subscriber.snapshot().count == 10
    }

    let received = await subscriber.snapshot()
    let seqs = RuntimeEnvelopeHarness.paneEvents(from: received).map(\.seq)
    #expect(seqs.count == 10)
    for i in 0..<seqs.count - 1 {
        #expect(seqs[i] < seqs[i + 1], "seq must be strictly increasing: \(seqs[i]) < \(seqs[i + 1])")
    }

    // Cleanup
    await subscriber.shutdown()
    channel.finishSubscribers()
    await assertBusDrained(harness.bus)
}
```

- [ ] **Step 3: Run ordering test**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneRuntimeEventChannel" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS — events arrive in strict seq order.

- [ ] **Step 4: Run full suite**

Run: `mise run test` (timeout 60s)
Expected: All existing tests pass. The change is internal to `PaneRuntimeEventChannel` — the `emit()` API is unchanged.

- [ ] **Step 6: Commit**

```bash
git commit -m "$(cat <<'EOF'
refactor: replace Task-per-event bus posting with AsyncStream continuation

PaneRuntimeEventChannel now uses a single bounded AsyncStream
(128 events) for bus delivery. emit() yields synchronously to
the continuation — no Task allocation per event. A single consumer
Task drains to the bus with guaranteed FIFO ordering.
EOF
)"
```

---

## Task 1: C15 — Promote Silent Terminal Events To Bus

These 10 events already have `GhosttyEvent` cases. They just don't call `emit()`. Fix: add the emit call with correct policy and replay flags.

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift` (actionPolicy for newly-emitting events)
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Replay/EventReplayBuffer.swift` (size estimates)
- Test: `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`

- [ ] **Step 1: Write failing test — every previously-silent event should emit to bus**

Use `EventBusHarness`, `RecordingSubscriber`, `assertEventuallyAsync` from `Tests/AgentStudioTests/Helpers/EventBusHarness.swift`. Follow the existing `TerminalRuntimeTests.swift` pattern: create runtime with injected `paneEventBus`, `transitionToReady()`, then verify bus reception.

```swift
@Test("All previously-silent events now emit to bus")
@MainActor
func allSilentEventsEmitToBus() async {
    // Arrange — isolated bus, recording subscriber, runtime wired to it
    let harness = EventBusHarness<RuntimeEnvelope>()
    let subscriber = await harness.makeSubscriber()
    let runtime = TerminalRuntime(
        paneId: PaneId(),
        metadata: PaneMetadata(
            source: .floating(launchDirectory: nil, title: "Test"), title: "Test"
        ),
        paneEventBus: harness.bus
    )
    runtime.transitionToReady()

    // Act — emit each previously-silent event
    let silentEvents: [GhosttyEvent] = [
        .progressReportUpdated(ProgressState(kind: .set, percent: 50)),
        .rendererHealthChanged(healthy: false),
        .cellSizeChanged(NSSize(width: 8, height: 16)),
        .sizeLimitChanged(TerminalSizeConstraints(minWidth: 10, minHeight: 5, maxWidth: 200, maxHeight: 100)),
        .openURLRequested(url: "https://example.com", kind: .text),
        .undoRequested,
        .redoRequested,
        .copyTitleToClipboardRequested,
        .initialSizeChanged(NSSize(width: 800, height: 600)),
        .deferred(tag: 999),
    ]

    for event in silentEvents {
        runtime.handleGhosttyEvent(event)
    }

    // Assert — all 10 reach the bus
    await assertEventuallyAsync("bus should receive all \(silentEvents.count) events") {
        await subscriber.snapshot().count == silentEvents.count
    }

    let received = await subscriber.snapshot()
    let paneEvents = RuntimeEnvelopeHarness.paneEvents(from: received)
    #expect(paneEvents.count == silentEvents.count)

    // Verify specific state-bearing events also updated @Observable properties
    #expect(runtime.commandProgress == ProgressState(kind: .set, percent: 50))
    #expect(runtime.rendererHealthy == false)
    #expect(runtime.cellSize == NSSize(width: 8, height: 16))

    // Cleanup
    await subscriber.shutdown()
    await assertBusDrained(harness.bus)
}

@Test("State-bearing events persist for replay, one-shot events do not")
@MainActor
func replayPersistenceForPromotedEvents() async {
    // Arrange
    let runtime = TerminalRuntime(
        paneId: PaneId(),
        metadata: PaneMetadata(
            source: .floating(launchDirectory: nil, title: "Test"), title: "Test"
        )
    )
    runtime.transitionToReady()

    // Act — emit one state event (should replay) and one action event (should not)
    runtime.handleGhosttyEvent(.rendererHealthChanged(healthy: false))  // persistForReplay: true
    runtime.handleGhosttyEvent(.openURLRequested(url: "https://example.com", kind: .text))  // persistForReplay: false

    // Assert — only state event in replay buffer
    let replay = await runtime.eventsSince(seq: 0)
    #expect(replay.events.count == 1, "Only state events should persist for replay")
    guard case .pane(let envelope) = replay.events.first,
          case .terminal(.rendererHealthChanged) = envelope.event else {
        Issue.record("Expected rendererHealthChanged in replay")
        return
    }
}
```

- [ ] **Step 2: Run test to confirm it fails**

Expected: FAIL — silent events don't emit.

- [ ] **Step 3: Update handleGhosttyEvent to emit all events**

In `TerminalRuntime.swift`, change each silent case to emit:

```swift
case .progressReportUpdated(let progressState):
    commandProgress = progressState
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)

case .rendererHealthChanged(let healthy):
    rendererHealthy = healthy
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)

case .cellSizeChanged(let size):
    cellSize = size
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)

case .sizeLimitChanged(let constraints):
    sizeConstraints = constraints
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)

case .openURLRequested:
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)

case .undoRequested:
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)

case .redoRequested:
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)

case .copyTitleToClipboardRequested:
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)

case .initialSizeChanged:
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)

case .deferred:
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)
```

- [ ] **Step 4: Update GhosttyEvent.actionPolicy for lossy events**

In `PaneRuntimeEvent.swift`, find `GhosttyEvent.actionPolicy` and add:

```swift
case .progressReportUpdated: return .lossy(consolidationKey: "progress")
case .cellSizeChanged: return .lossy(consolidationKey: "cellSize")
case .deferred: return .lossy(consolidationKey: "deferred")
// All others already default to .critical
```

- [ ] **Step 5: Update EventReplayBuffer size estimates**

In `EventReplayBuffer.swift` `estimateSize(of:)`, add cases for newly replay-persisted events. **Read the existing estimates in the file first** — current code uses 40 for progress, 24 for health, 40 for cell size. Match the existing estimation methodology (lines 312-346), don't invent new values. Example pattern from existing code:

```swift
case .progressReportUpdated: return 40  // match existing estimation methodology
case .rendererHealthChanged: return 24
case .cellSizeChanged: return 40
case .sizeLimitChanged: return 48
```

**Note:** The `.secureInputChanged` case has a silent `break` at line 158-159 of `TerminalRuntime.swift`. This is intentional — Ghostty only fires `.secureInputRequested` (which the runtime converts to `.secureInputChanged` and emits). The raw `.secureInputChanged` case is never received from Ghostty directly. Don't change this behavior.

- [ ] **Step 6: Run tests**

Run: `mise run test` (timeout 60s). Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(c15): promote all silent terminal events to bus

Every GhosttyEvent now emits to the bus. No @Observable-only or
silently-dropped events remain. State events persist for replay.
High-frequency events use lossy consolidation with unique keys.
EOF
)"
```

---

## Task 2: C15 — Promote Deferred Ghostty Tags to Typed Events

Move tags from `deferredTags` to `explicitlyRoutedTags` with typed payloads. Follow the scrollbar plan pattern exactly.

**Read first:** `GhosttyActionRouter.swift` to confirm which tags are still deferred. Also read `vendor/ghostty/include/ghostty.h` for each tag's C struct shape before extracting payloads.

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAdapter.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneKindEvent.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Replay/EventReplayBuffer.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`

- [ ] **Step 1: Read deferredTags and ghostty.h**

Run: `rg "deferredTags" Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift`

List the remaining deferred tags. Check `vendor/ghostty/include/ghostty.h` for each tag's C struct (search for `GHOSTTY_ACTION_` + tag name).

- [ ] **Step 2: Write failing adapter translation tests for each deferred tag**

One test per tag. Follow existing `GhosttyAdapterTests.swift` pattern. Example:

```swift
@Test("setTabTitle maps to typed tabTitleChanged event")
@MainActor
func setTabTitleMapsToTypedEvent() {
    let event = GhosttyAdapter.shared.translate(
        actionTag: GhosttyActionTag.setTabTitle.rawTag,
        payload: .setTabTitle(title: "Agent: claude-code")
    )
    #expect(event == .tabTitleChanged("Agent: claude-code"))
}
```

**C-string safety:** For payloads with string fields, check `ghostty.h` for whether the field is null-terminated or length-prefixed. Use `String(cString:)` for null-terminated, `String(bytes:count:encoding:)` for length-prefixed. The scrollbar plan's adapter code shows the correct pattern.

- [ ] **Step 3: Run tests to confirm they fail**

Expected: FAIL — new event cases and payload variants don't exist.

- [ ] **Step 4: Add GhosttyEvent cases**

```swift
case tabTitleChanged(String)
case mouseShapeChanged(shape: UInt32)
case mouseVisibilityChanged(visible: Bool)
case mouseLinkHovered(url: String?)
case keySequenceChanged(sequence: String)
case keyTableChanged(table: String)
case colorChanged(kind: UInt32, r: UInt8, g: UInt8, b: UInt8)
case configReloadRequested
case configChanged
```

If search/scrollbar not done by native-scrollbars branch, also add those.

- [ ] **Step 5: Add EventIdentifier cases + rawValue entries**

```swift
case tabTitleChanged
case mouseShapeChanged
case mouseVisibilityChanged
case mouseLinkHovered
case keySequenceChanged
case keyTableChanged
case colorChanged
case configReloadRequested
case configChanged
```

- [ ] **Step 6: Add GhosttyEvent.actionPolicy — unique key per property**

```swift
case .mouseShapeChanged: return .lossy(consolidationKey: "mouseShape")
case .mouseVisibilityChanged: return .lossy(consolidationKey: "mouseVisibility")
case .mouseLinkHovered: return .lossy(consolidationKey: "mouseLink")
case .keySequenceChanged: return .lossy(consolidationKey: "keySequence")
case .keyTableChanged: return .lossy(consolidationKey: "keyTable")
// searchMatchesUpdated, searchSelectionChanged if present:
case .searchMatchesUpdated: return .lossy(consolidationKey: "searchTotal")
case .searchSelectionChanged: return .lossy(consolidationKey: "searchSelected")
// All others: .critical (default)
```

- [ ] **Step 7: Add ActionPayload variants and translation in GhosttyAdapter**

Extract fields from C union per `ghostty.h`. Follow scrollbar plan pattern.

- [ ] **Step 8: Move tags from deferredTags to explicitlyRoutedTags in GhosttyActionRouter**

Document `.render` as permanently intercepted (Ghostty owns Metal rendering, host never acts).

- [ ] **Step 9: Handle new events in TerminalRuntime.handleGhosttyEvent**

Each new case: update `@Observable` state if stateful, always `emit()`, set `persistForReplay` per inventory table.

- [ ] **Step 10: Fix EventReplayBuffer size estimates for replay-persisted events**

- [ ] **Step 11: Run all tests**

Run: `mise run test` (timeout 60s). Expected: All pass.

- [ ] **Step 12: Write and run coverage test — no deferred tags remain**

```swift
@Test("every ghostty tag is explicitly routed or intercepted")
@MainActor
func noDeferredTagsRemain() {
    #expect(
        GhosttyActionRouter.deferredTags.isEmpty,
        "Deferred tags still exist: \(GhosttyActionRouter.deferredTags)"
    )
}
```

- [ ] **Step 13: Run full suite + lint**

Run: `mise run test` then `mise run lint`. Expected: All pass, zero violations.

- [ ] **Step 14: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(c15): promote all deferred ghostty tags to typed bus events

Every Ghostty action tag now has a typed GhosttyEvent case with
proper payload extraction. No .deferred(tag) remains. Each property
has its own lossy consolidation key. .render is permanently intercepted.
EOF
)"
```

---

## Task 3: C16 — Typed Filesystem Context Events

**Files:**
- Create: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneFilesystemContextEvent.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneKindEvent.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift`

- [ ] **Step 1: Add EventIdentifier cases**

```swift
case cwdSubtreeChanged
case gitWorkingTreeInCwd
```

- [ ] **Step 2: Create PaneFilesystemContextEvent.swift**

```swift
import Foundation

struct PaneFilesystemContext: Sendable, Equatable {
    let paneId: PaneId
    let cwd: URL
    let worktreeId: UUID
    let repoId: UUID
}

enum PaneFilesystemContextEvent: PaneKindEvent, Sendable {
    case cwdSubtreeChanged(worktreeId: UUID, repoId: UUID, paths: Set<String>, batchSeq: UInt64)
    case gitWorkingTreeInCwd(worktreeId: UUID, repoId: UUID, staged: Int, unstaged: Int, untracked: Int)

    var actionPolicy: ActionPolicy { .critical }
    var eventName: EventIdentifier {
        switch self {
        case .cwdSubtreeChanged: return .cwdSubtreeChanged
        case .gitWorkingTreeInCwd: return .gitWorkingTreeInCwd
        }
    }
}
```

- [ ] **Step 3: Add to PaneRuntimeEvent + fix exhaustiveness**

Add `case paneFilesystemContext(PaneFilesystemContextEvent)` and `actionPolicy` delegation. Fix all switches the compiler flags.

- [ ] **Step 4: Run full test suite**

Run: `mise run test` (timeout 60s). Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(c16): add PaneFilesystemContextEvent vocabulary"
```

---

## Task 4: C16 — Projection Store CWD Context Tracking

**Files:**
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Projection/PaneFilesystemProjectionStore.swift`
- Create: `Tests/AgentStudioTests/Core/PaneRuntime/Projection/PaneFilesystemProjectionStoreContextTests.swift`

- [ ] **Step 1: Write failing tests for register, unregister, CWD rescope, idempotency**

Follow existing `PaneFilesystemProjectionStoreTests.swift` patterns. Test:
- `registerPaneContext` stores, `unregisterPaneContext` removes
- `updatePaneCwd` clears stale snapshot when CWD changes
- `updatePaneCwd` is idempotent when CWD unchanged
- `prune` and `reset` clean both `snapshotsByPaneId` and `contextsByPaneId`

Both dictionaries keyed by `UUID` for consistency with existing `snapshotsByPaneId`.

- [ ] **Step 2: Run tests to confirm failure**

- [ ] **Step 3: Implement context tracking**

```swift
private(set) var contextsByPaneId: [UUID: PaneFilesystemContext] = [:]

func registerPaneContext(_ context: PaneFilesystemContext) {
    contextsByPaneId[context.paneId.uuid] = context
}

func unregisterPaneContext(_ paneUUID: UUID) {
    contextsByPaneId.removeValue(forKey: paneUUID)
    snapshotsByPaneId.removeValue(forKey: paneUUID)
}

func context(for paneUUID: UUID) -> PaneFilesystemContext? {
    contextsByPaneId[paneUUID]
}

func updatePaneCwd(paneId paneUUID: UUID, newCwd: URL) {
    guard var existing = contextsByPaneId[paneUUID] else { return }
    guard existing.cwd != newCwd else { return }
    existing = PaneFilesystemContext(
        paneId: existing.paneId, cwd: newCwd,
        worktreeId: existing.worktreeId, repoId: existing.repoId
    )
    contextsByPaneId[paneUUID] = existing
    snapshotsByPaneId.removeValue(forKey: paneUUID)
}
```

Update `prune` and `reset` to clean both dictionaries.

- [ ] **Step 4: Run tests**

Expected: PASS.

- [ ] **Step 5: Run full suite**

Run: `mise run test` (timeout 60s). Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(c16): CWD context tracking and rescoping on projection store"
```

---

## Task 5: C16 — Wire CWD Rescoping into PaneCoordinator

**Files:**
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift`

**Read first:** Find exact method names for pane creation, teardown, CWD change handling.

**Lifecycle contract:**
- **Register:** After pane created and `metadata.facets` has worktreeId + repoId. Fallback CWD = worktree root.
- **Rescope:** On `GhosttyEvent.cwdChanged` when `metadata.facets.cwd` updates.
- **Unregister:** In `teardownView(for:)` alongside `ViewRegistry.unregister()`.

- [ ] **Step 1: Wire register on creation, unregister on teardown, rescope on CWD change**
- [ ] **Step 2: Build and test**

Run: `mise run build` then `mise run test`. Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(c16): wire CWD context lifecycle into PaneCoordinator"
```

---

## Task 6: Update Architecture Docs

- [ ] **Step 1: Update C15 status in pane_runtime_architecture.md**

```markdown
> **Status:** Implemented as complete observational event system. Every Ghostty
> action tag is either explicitly routed with typed payloads and emitted to the
> bus, or permanently intercepted. No deferred/dropped tags remain. All events
> carry paneId and are joinable to all filtering dimensions via PaneMetadata.facets.
>
> Agent harness RPC (structured request/response) deferred until agent protocol
> integration has concrete requirements.
```

- [ ] **Step 2: Update C16 status**

```markdown
> **Status:** Implemented. Typed PaneFilesystemContextEvent on bus.
> PaneFilesystemProjectionStore with CWD context tracking and auto-rescoping.
```

- [ ] **Step 3: Update C13 status**

```markdown
> **Status:** Intentionally deferred (YAGNI).
```

- [ ] **Step 4: Document bus posting mechanism upgrade**

Add note to eventbus design doc about AsyncStream continuation pattern replacing Task-per-event.

- [ ] **Step 5: Commit**

```bash
git commit -m "docs: update C13/C15/C16 status, document bus posting upgrade"
```

---

## Task 7: Final Verification

- [ ] **Step 1:** `mise run build` — 0 errors, 0 warnings
- [ ] **Step 2:** `mise run test` — all pass, record counts
- [ ] **Step 3:** `mise run lint` — 0 violations
- [ ] **Step 4:** Verify no deferred tags:

```bash
rg "deferredTags" Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift
```

- [ ] **Step 5:** Verify no silent drops:

```bash
rg "case \.openURLRequested.*break|case \.undoRequested.*break|case \.deferred.*break" Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift
```

Expected: zero matches.

- [ ] **Step 6:** Verify no Task-per-event in channel:

```bash
rg "Task.*bus\.post\|Task.*paneEventBus" Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/PaneRuntimeEventChannel.swift
```

Expected: only the single consumer Task in `init`, no per-event Tasks in `emit()`.

- [ ] **Step 7: Commit verification results**

```bash
git commit -m "chore: final verification — all events on bus, ordered delivery, zero drops"
```
