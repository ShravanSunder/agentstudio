import Foundation
import Testing
import WebKit

@testable import AgentStudio

/// Round-trip integration tests for the state push stream (Swift → JS).
///
/// Verifies the full push path: Swift mutates `@Observable` → `PushPlan` fires →
/// `callJavaScript` pushes to bridge world → `applyEnvelope` dispatches `__bridge_push`
/// CustomEvent → page-world test harness captures it → reports via `testProbe.postMessage`.
///
/// All tests run under `@Suite(.serialized)` because WebKit is not safe for parallel testing.
extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    final class StatePushRoundTripTests {

        init() {
            installTestAtomRegistryIfNeeded()
        }

        // MARK: - Test: DiffStatus push reaches page world

        /// Verify the complete state push round-trip: mutate DiffState →
        /// PushPlan observation → callJavaScript → bridge world relay → page world capture.
        @Test
        func test_statePush_diffStatus_reachesPageWorld() async throws {
            let components = RoundTripTestPageBuilder.build()

            try await WebPageTestHarness.withManagedPage(components.page) { page in
                // Load the app page so bootstrap script runs in bridge world
                _ = page.load(URL(string: "agentstudio://app/index.html")!)
                let didLoad = await waitUntil { page.url?.absoluteString == "agentstudio://app/index.html" }
                #expect(didLoad, "Page should load from custom scheme")

                // Wait for test harness ready signal
                let harnessReady = await waitForProbeMessage(
                    components.testProbe,
                    channel: "ready"
                )
                #expect(harnessReady != nil, "Test harness should signal ready")

                // Set up domain state and push transport
                let diffState = DiffState()
                let clock = RevisionClock()
                let transport = WebKitPushTransport(
                    page: page,
                    bridgeWorld: WKContentWorld.world(name: "agentStudioBridge")
                )

                let plan = PushPlan(
                    state: diffState,
                    transport: transport,
                    revisions: clock,
                    epoch: { diffState.epoch },
                    slices: {
                        Slice("diffStatus", store: .diff, level: .hot) { state in
                            DiffStatusSlice(status: state.status, error: state.error, epoch: state.epoch)
                        }
                    }
                )

                plan.start()

                // Wait for the initial observation push to arrive in page world
                let initialPush = await waitForProbeMessage(
                    components.testProbe,
                    channel: "push"
                )
                #expect(initialPush != nil, "Initial observation should produce a push")

                // Act — mutate state
                diffState.setStatus(.loading)

                // Wait for mutation push to arrive in page world
                let mutationPush = await waitForProbeMessage(
                    components.testProbe,
                    channel: "push",
                    afterIndex: components.testProbe.receivedMessages.count - 1
                )
                #expect(mutationPush != nil, "State mutation should produce a push in page world")

                // Assert — verify push envelope content
                if let pushData = mutationPush {
                    #expect(pushData["op"] as? String == "replace", "DiffStatus slice uses replace op")
                    #expect(pushData["__revision"] as? Int != nil, "Push should carry a revision")

                    // Verify the payload contains the updated status
                    if let payload = pushData["data"] as? [String: Any] {
                        #expect(payload["status"] as? String == "loading", "Payload should reflect mutated status")
                    }
                }

                plan.stop()
            }
        }

        // MARK: - Test: Revision monotonicity observable in page world

        /// Verify that multiple state mutations produce pushes with strictly
        /// increasing revision numbers in the page world.
        @Test
        func test_statePush_revisionMonotonicity() async throws {
            let components = RoundTripTestPageBuilder.build()

            try await WebPageTestHarness.withManagedPage(components.page) { page in
                _ = page.load(URL(string: "agentstudio://app/index.html")!)
                let didLoad = await waitUntil { page.url?.absoluteString == "agentstudio://app/index.html" }
                #expect(didLoad)

                let harnessReady = await waitForProbeMessage(components.testProbe, channel: "ready")
                #expect(harnessReady != nil)

                let diffState = DiffState()
                let clock = RevisionClock()
                let transport = WebKitPushTransport(
                    page: page,
                    bridgeWorld: WKContentWorld.world(name: "agentStudioBridge")
                )

                let plan = PushPlan(
                    state: diffState,
                    transport: transport,
                    revisions: clock,
                    epoch: { diffState.epoch },
                    slices: {
                        Slice("diffStatus", store: .diff, level: .hot) { state in
                            DiffStatusSlice(status: state.status, error: state.error, epoch: state.epoch)
                        }
                    }
                )

                plan.start()

                // Collect initial push
                let initialPush = await waitForProbeMessage(components.testProbe, channel: "push")
                let initialRevision = initialPush?["__revision"] as? Int ?? 0

                // First mutation
                diffState.setStatus(.loading)
                let push1 = await waitForProbeMessage(
                    components.testProbe, channel: "push",
                    afterIndex: components.testProbe.receivedMessages.count - 1
                )
                let revision1 = push1?["__revision"] as? Int ?? 0

                // Second mutation
                diffState.setStatus(.ready)
                let push2 = await waitForProbeMessage(
                    components.testProbe, channel: "push",
                    afterIndex: components.testProbe.receivedMessages.count - 1
                )
                let revision2 = push2?["__revision"] as? Int ?? 0

                // Assert monotonic
                #expect(revision1 > initialRevision, "First mutation revision should exceed initial")
                #expect(revision2 > revision1, "Second mutation revision should exceed first")

                plan.stop()
            }
        }

        // MARK: - Test: Epoch propagation

        /// Verify that the epoch from DiffState propagates into push envelopes
        /// received by the page world.
        @Test
        func test_statePush_epochPropagation() async throws {
            let components = RoundTripTestPageBuilder.build()

            try await WebPageTestHarness.withManagedPage(components.page) { page in
                _ = page.load(URL(string: "agentstudio://app/index.html")!)
                let didLoad = await waitUntil { page.url?.absoluteString == "agentstudio://app/index.html" }
                #expect(didLoad)

                let harnessReady = await waitForProbeMessage(components.testProbe, channel: "ready")
                #expect(harnessReady != nil)

                let diffState = DiffState()
                let clock = RevisionClock()
                let transport = WebKitPushTransport(
                    page: page,
                    bridgeWorld: WKContentWorld.world(name: "agentStudioBridge")
                )

                let plan = PushPlan(
                    state: diffState,
                    transport: transport,
                    revisions: clock,
                    epoch: { diffState.epoch },
                    slices: {
                        Slice("diffStatus", store: .diff, level: .hot) { state in
                            DiffStatusSlice(status: state.status, error: state.error, epoch: state.epoch)
                        }
                    }
                )

                plan.start()

                // Initial push with epoch 0
                let initialPush = await waitForProbeMessage(components.testProbe, channel: "push")
                #expect(initialPush?["__epoch"] as? Int == 0, "Initial push should carry epoch 0")

                // Advance epoch and mutate
                diffState.setEpoch(42)
                diffState.setStatus(.loading)

                let push = await waitForProbeMessage(
                    components.testProbe, channel: "push",
                    afterIndex: components.testProbe.receivedMessages.count - 1
                )
                #expect(push?["__epoch"] as? Int == 42, "Push should carry updated epoch")

                plan.stop()
            }
        }

        // MARK: - Test: Push nonce validation

        /// Verify that pushes arriving in page world carry the correct push nonce.
        @Test
        func test_statePush_pushNoncePresent() async throws {
            let components = RoundTripTestPageBuilder.build()

            try await WebPageTestHarness.withManagedPage(components.page) { page in
                _ = page.load(URL(string: "agentstudio://app/index.html")!)
                let didLoad = await waitUntil { page.url?.absoluteString == "agentstudio://app/index.html" }
                #expect(didLoad)

                let harnessReady = await waitForProbeMessage(components.testProbe, channel: "ready")
                #expect(harnessReady != nil)

                let diffState = DiffState()
                let clock = RevisionClock()
                let transport = WebKitPushTransport(
                    page: page,
                    bridgeWorld: WKContentWorld.world(name: "agentStudioBridge")
                )

                let plan = PushPlan(
                    state: diffState,
                    transport: transport,
                    revisions: clock,
                    epoch: { diffState.epoch },
                    slices: {
                        Slice("diffStatus", store: .diff, level: .hot) { state in
                            DiffStatusSlice(status: state.status, error: state.error, epoch: state.epoch)
                        }
                    }
                )

                plan.start()

                let push = await waitForProbeMessage(components.testProbe, channel: "push")
                #expect(push != nil, "Should receive a push")
                #expect(
                    push?["nonce"] as? String == components.pushNonce,
                    "Push should carry the correct push nonce for page-world validation"
                )

                plan.stop()
            }
        }

        // MARK: - Helpers

        /// Wait for a probe message on the specified channel, starting after the given index.
        private func waitForProbeMessage(
            _ probe: IntegrationTestMessageHandler,
            channel: String,
            afterIndex: Int = -1
        ) async -> [String: Any]? {
            let startIndex = max(afterIndex + 1, 0)

            for _ in 0..<200_000 {
                let messages = probe.receivedMessages
                for i in startIndex..<messages.count {
                    if let jsonString = messages[i] as? String,
                        let data = jsonString.data(using: .utf8),
                        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        parsed["channel"] as? String == channel
                    {
                        return parsed["data"] as? [String: Any]
                    }
                }
                await Task.yield()
            }
            return nil
        }

        private func waitUntil(
            _ condition: @escaping () async -> Bool
        ) async -> Bool {
            for _ in 0..<200_000 {
                if await condition() {
                    return true
                }
                await Task.yield()
            }
            return await condition()
        }
    }
}

// MARK: - WebKitPushTransport

/// Test transport that pushes JSON envelopes to a real WebPage via `callJavaScript`.
///
/// Replicates the envelope encoding from `BridgePaneController.pushJSON` but without
/// the dedup cache or connection health side effects.
@MainActor
final class WebKitPushTransport: PushTransport {
    private let page: WebPage
    private let bridgeWorld: WKContentWorld

    init(page: WebPage, bridgeWorld: WKContentWorld) {
        self.page = page
        self.bridgeWorld = bridgeWorld
    }

    func pushJSON(
        store: StoreKey, op: PushOp, level: PushLevel,
        revision: Int, epoch: Int, json: Data
    ) async {
        do {
            let payload = try JSONSerialization.jsonObject(with: json)
            let envelope: [String: Any] = [
                "__v": 1,
                "__revision": revision,
                "__epoch": epoch,
                "__pushId": UUID().uuidString,
                "store": store.rawValue,
                "op": op.rawValue,
                "level": level.rawValue,
                "payload": payload,
            ]
            let envelopeJSON = try JSONSerialization.data(
                withJSONObject: envelope, options: [.sortedKeys])
            guard let envelopeString = String(data: envelopeJSON, encoding: .utf8) else { return }

            try await page.callJavaScript(
                "window.__bridgeInternal.applyEnvelope(JSON.parse(json))",
                arguments: ["json": envelopeString],
                contentWorld: bridgeWorld
            )
        } catch {
            // Transport failures are expected in some headless test scenarios
        }
    }
}
