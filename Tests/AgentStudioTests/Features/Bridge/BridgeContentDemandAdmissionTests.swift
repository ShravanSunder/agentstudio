import Foundation
import Testing
import WebKit

@testable import AgentStudio

@Suite(.serialized)
final class BridgeContentDemandAdmissionTests {
    private actor BridgeTelemetryRecorderSpy: BridgePerformanceTraceRecording {
        private var recordedSamples: [BridgeTelemetrySample] = []

        func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
            _ = receivedAtUnixNano
            recordedSamples.append(sample)
        }

        func recordDrop(
            reason: BridgeTelemetryDropReason,
            droppedCount: Int,
            firstRejectedEventName: String?,
            receivedAtUnixNano: UInt64
        ) async {
            _ = reason
            _ = droppedCount
            _ = firstRejectedEventName
            _ = receivedAtUnixNano
        }

        func samples() -> [BridgeTelemetrySample] {
            recordedSamples
        }

        func drain() async throws {}
    }

    @Test
    func test_transportResourceURL_parsesContentInterestWithoutLeaseIdentity() throws {
        let resourceURL =
            "agentstudio://resource/review/content/content-123?generation=2&revision=4&interest=selected"
        let parsed = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))

        #expect(parsed.canonicalURL == "agentstudio://resource/review/content/content-123?generation=2&revision=4")
        #expect(BridgeContentDemandInterest.parse(resourceURL) == .selected)
    }

    @Test
    func test_contentRoute_recordsDemandInterestTelemetryFromResourceURL() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("hello bridge")
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "hello bridge")
            ]
        )
        let contentStore = BridgeContentStore(provider: provider)
        let recorder = BridgeTelemetryRecorderSpy()
        await contentStore.activate(handles: [handle], reviewGeneration: 7)
        let handler = await makeLeasedBridgeSchemeHandler(
            contentStore: contentStore,
            handle: handle,
            telemetryRecorder: recorder
        )
        let requestURL = handle.resourceUrl + "&interest=visible"
        let request = URLRequest(url: URL(string: requestURL)!)

        for try await _ in handler.reply(for: request) {}

        let sample = try #require(await recorder.samples().first)
        #expect(sample.stringAttributes["agentstudio.bridge.content.interest"] == "visible")
    }

    @Test
    func test_backgroundContentDemandYieldsUntilVisibleDemandFinishes() async {
        let admission = BridgeContentDemandAdmission()
        await admission.start(.visible)
        let backgroundWaiter = BridgeContentDemandEventRecorder()
        let backgroundTask = Task {
            await admission.waitForBackgroundTurn()
            await backgroundWaiter.recordEvent()
        }
        await Task.yield()

        #expect(await backgroundWaiter.recordedEventCount() == 0)

        await admission.finish(.visible)
        _ = await backgroundTask.result

        #expect(await backgroundWaiter.recordedEventCount() == 1)
    }

    @Test
    func test_backgroundFillCooldownEnforcesBurstBudget() async {
        let clock = TestPushClock()
        let admission = BridgeContentDemandAdmission(clock: clock)
        await admission.start(.visible)
        await admission.finish(.visible)

        for _ in 0..<AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget {
            await admission.start(.background)
        }

        let backgroundWaiter = BridgeContentDemandEventRecorder()
        let backgroundTask = Task {
            await admission.start(.background)
            await backgroundWaiter.recordEvent()
        }
        await clock.waitForPendingSleepCount()
        await Task.yield()

        #expect(await backgroundWaiter.recordedEventCount() == 0)

        clock.advance(by: AppPolicies.Bridge.contentBackgroundFillInteractiveRefillInterval)
        _ = await backgroundTask.result

        #expect(await backgroundWaiter.recordedEventCount() == 1)
    }

    @Test
    func test_backgroundFillCooldownKeepsFillPacedAfterVisibleDemandFinishes() async {
        let clock = TestPushClock()
        let admission = BridgeContentDemandAdmission(clock: clock)
        await admission.start(.visible)
        await admission.finish(.visible)

        for _ in 0..<AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget {
            await admission.start(.background)
        }

        let backgroundWaiter = BridgeContentDemandEventRecorder()
        let backgroundTask = Task {
            await admission.start(.background)
            await backgroundWaiter.recordEvent()
        }
        await clock.waitForPendingSleepCount()
        await Task.yield()

        #expect(await backgroundWaiter.recordedEventCount() == 0)

        clock.advance(by: AppPolicies.Bridge.contentBackgroundFillInteractiveCooldown)
        _ = await backgroundTask.result

        for _ in 0..<(AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget + 3) {
            await admission.start(.background)
        }

        #expect(await backgroundWaiter.recordedEventCount() == 1)
        #expect(clock.pendingSleepCount == 0)
    }

    @Test
    func test_backgroundFillIdlePathPreservesFullRateAdmission() async {
        let clock = TestPushClock()
        let admission = BridgeContentDemandAdmission(clock: clock)

        for _ in 0..<(AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget * 2) {
            await admission.start(.background)
        }

        #expect(clock.pendingSleepCount == 0)
    }

    private func makeLeasedBridgeSchemeHandler(
        contentStore: BridgeContentStore,
        handle: BridgeContentHandle,
        telemetryRecorder: (any BridgePerformanceTraceRecording)? = nil
    ) async -> BridgeSchemeHandler {
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let paneId = UUID()
        if let resource = BridgeTransportResourceURL.parse(
            handle.resourceUrl,
            allowedResourceKindsByProtocol: ["review": Set(["content"])]
        ) {
            await resourceLeaseRegistry.register(
                resource,
                paneId: paneId,
                descriptorId: resource.opaqueId,
                maxBytes: handle.sizeBytes,
                expectedRevocationRevision: 0
            )
        }
        return BridgeSchemeHandler(
            paneId: paneId,
            contentStore: contentStore,
            resourceLeaseRegistry: resourceLeaseRegistry,
            telemetryRecorder: telemetryRecorder
        )
    }
}

private actor BridgeContentDemandEventRecorder {
    private var eventCount = 0

    func recordEvent() {
        eventCount += 1
    }

    func recordedEventCount() -> Int {
        eventCount
    }
}
