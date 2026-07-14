import AppKit
import Foundation
import SwiftUI
import WebKit

@testable import AgentStudio

struct BridgeProductWebKitCarrierPaintCorrelation: Decodable, Equatable, Sendable {
    let descriptorId: String
    let disposition: String
    let itemId: String
    let observedSHA256: String
    let position: String
    let readableDOMSelector: String
    let readableText: String
    let requestId: String
    let role: String
    let semanticItemId: String
    let sourceGeneration: Int
    let sourceIdentity: String
    let surface: String

    private enum CodingKeys: String, CodingKey {
        case descriptorId
        case disposition
        case itemId
        case observedSHA256 = "observedSha256"
        case position
        case readableDOMSelector = "readableDomSelector"
        case readableText
        case requestId
        case role
        case semanticItemId
        case sourceGeneration
        case sourceIdentity
        case surface
    }
}

struct BridgeProductWebKitCarrierDOMSnapshot: Decodable, Equatable, Sendable {
    let correlations: [BridgeProductWebKitCarrierPaintCorrelation]
    let hasAppRoot: Bool
    let hasFileModeHost: Bool
    let hasReviewModeHost: Bool
    let hasReviewMetadataFailedShell: Bool
    let hasReviewMetadataLoadingShell: Bool
    let hasReviewShell: Bool
    let hasReviewCodeViewPanel: Bool
    let reviewSelectedContentLineCount: Int
    let reviewSelectedContentState: String?
    let reviewSelectedDisplayPath: String?
    let reviewRenderedItemId: String?

    static let unavailable = Self(
        correlations: [],
        hasAppRoot: false,
        hasFileModeHost: false,
        hasReviewModeHost: false,
        hasReviewMetadataFailedShell: false,
        hasReviewMetadataLoadingShell: false,
        hasReviewShell: false,
        hasReviewCodeViewPanel: false,
        reviewSelectedContentLineCount: 0,
        reviewSelectedContentState: nil,
        reviewSelectedDisplayPath: nil,
        reviewRenderedItemId: nil
    )
}

struct BridgeProductWebKitCarrierNativeSnapshot: Equatable, Sendable {
    let activeContentLeaseCount: Int
    let activeProducerCount: Int
    let activeProducerTaskCount: Int
    let activeSchemeTaskCount: Int
    let activeTransportLeaseCount: Int
    let inFlightControlRequestSequence: Int?
    let inFlightFrameReceiptCount: Int
    let lifecycle: String
    let nextControlRequestSequence: Int
    let nextMetadataStreamSequence: Int
    let pendingFrameWaiterCount: Int
    let pendingLifecycleAcknowledgementCount: Int
    let queuedByteCount: Int
    let queuedFrameCount: Int

    static let unavailable = Self(
        activeContentLeaseCount: 0,
        activeProducerCount: 0,
        activeProducerTaskCount: 0,
        activeSchemeTaskCount: 0,
        activeTransportLeaseCount: 0,
        inFlightControlRequestSequence: nil,
        inFlightFrameReceiptCount: 0,
        lifecycle: "unavailable",
        nextControlRequestSequence: 0,
        nextMetadataStreamSequence: 0,
        pendingFrameWaiterCount: 0,
        pendingLifecycleAcknowledgementCount: 0,
        queuedByteCount: 0,
        queuedFrameCount: 0
    )
}

struct BridgeProductWebKitCarrierTrace: Equatable, Sendable, CustomStringConvertible {
    let fileMetadataPhases: [String]
    let reviewMetadataPhases: [String]
    let reviewPublicationPhases: [String]

    var hasCanonicalEagerSubscriptions: Bool {
        fileMetadataPhases.contains("metadata_bootstrap_started")
            && reviewMetadataPhases.contains("metadata_bootstrap_started")
    }

    var hasFileMetadataWindow: Bool {
        fileMetadataPhases.contains("metadata_source_accepted_enqueued")
            && fileMetadataPhases.contains("metadata_window_enqueued")
    }

    var hasReviewMetadataPublication: Bool {
        reviewPublicationPhases.contains("review_metadata_publication_completed")
            && reviewMetadataPhases.contains("metadata_window_enqueued")
    }

    var description: String {
        "file=\(fileMetadataPhases),review=\(reviewMetadataPhases),publication=\(reviewPublicationPhases)"
    }
}

struct BridgeProductWebKitCarrierLegacyEgressSnapshot:
    Equatable,
    Sendable,
    CustomStringConvertible
{
    let attemptedIntakeByteCount: UInt64
    let attemptedIntakeCount: UInt64
    let attemptedPushByteCount: UInt64
    let attemptedPushCount: UInt64

    var description: String {
        "push=\(attemptedPushCount)/\(attemptedPushByteCount)B,intake=\(attemptedIntakeCount)/\(attemptedIntakeByteCount)B"
    }
}

actor BridgeProductWebKitCarrierLegacyEgressRecorder {
    private var attemptedIntakeByteCount: UInt64 = 0
    private var attemptedIntakeCount: UInt64 = 0
    private var attemptedPushByteCount: UInt64 = 0
    private var attemptedPushCount: UInt64 = 0

    func recordIntake(byteCount: Int) {
        attemptedIntakeCount = Self.saturatingAdd(attemptedIntakeCount, 1)
        attemptedIntakeByteCount = Self.saturatingAdd(
            attemptedIntakeByteCount,
            UInt64(clamping: byteCount)
        )
    }

    func recordPush(byteCount: Int) {
        attemptedPushCount = Self.saturatingAdd(attemptedPushCount, 1)
        attemptedPushByteCount = Self.saturatingAdd(
            attemptedPushByteCount,
            UInt64(clamping: byteCount)
        )
    }

    func snapshot() -> BridgeProductWebKitCarrierLegacyEgressSnapshot {
        BridgeProductWebKitCarrierLegacyEgressSnapshot(
            attemptedIntakeByteCount: attemptedIntakeByteCount,
            attemptedIntakeCount: attemptedIntakeCount,
            attemptedPushByteCount: attemptedPushByteCount,
            attemptedPushCount: attemptedPushCount
        )
    }

    private static func saturatingAdd(_ value: UInt64, _ increment: UInt64) -> UInt64 {
        let (sum, overflowed) = value.addingReportingOverflow(increment)
        return overflowed ? .max : sum
    }
}

actor BridgeProductWebKitCarrierTraceRecorder: BridgePerformanceTraceRecording {
    private var samples: [BridgeTelemetrySample] = []

    func record(sample: BridgeTelemetrySample, receivedAtUnixNano _: UInt64) {
        samples.append(sample)
    }

    func recordDrop(
        reason _: BridgeTelemetryDropReason,
        droppedCount _: Int,
        firstRejectedEventName _: String?,
        receivedAtUnixNano _: UInt64
    ) {}

    func drain() {}

    func scrubbedTrace() -> BridgeProductWebKitCarrierTrace {
        BridgeProductWebKitCarrierTrace(
            fileMetadataPhases: phases(
                eventName: "performance.bridge.swift.metadata_bootstrap_lifecycle",
                protocolName: "worktree-file"
            ),
            reviewMetadataPhases: phases(
                eventName: "performance.bridge.swift.metadata_bootstrap_lifecycle",
                protocolName: "review"
            ),
            reviewPublicationPhases: phases(
                eventName: "performance.bridge.swift.review_metadata_publication",
                protocolName: "review"
            )
        )
    }

    private func phases(eventName: String, protocolName: String) -> [String] {
        samples.compactMap { sample in
            guard sample.name == eventName,
                sample.stringAttributes["agentstudio.bridge.protocol"] == protocolName
            else { return nil }
            return sample.stringAttributes["agentstudio.bridge.phase"]
        }
    }
}

struct BridgeProductWebKitCarrierRunResult<Value> {
    let teardownSnapshot: BridgePaneProductSessionOwnerSnapshot
    let value: Value
}

@MainActor
enum BridgeProductWebKitCarrierTestSupport {
    private static var retainedPage: WebPage?

    static func withHostedController<Value>(
        _ controller: BridgePaneController,
        operation: @MainActor (BridgePaneController) async throws -> Value
    ) async throws -> BridgeProductWebKitCarrierRunResult<Value> {
        let frame = NSRect(x: 0, y: 0, width: 960, height: 720)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let mountView = BridgePaneMountView(paneId: controller.paneId, controller: controller)
        mountView.frame = frame
        window.contentView = mountView
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.orderBack(nil)

        do {
            let value = try await operation(controller)
            let teardownSnapshot = await teardown(controller: controller, window: window)
            return BridgeProductWebKitCarrierRunResult(
                teardownSnapshot: teardownSnapshot,
                value: value
            )
        } catch {
            _ = await teardown(controller: controller, window: window)
            throw error
        }
    }

    static func waitUntil(
        timeout: Duration,
        condition: @MainActor () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        return await condition()
    }

    static func domSnapshot(_ page: WebPage) async -> BridgeProductWebKitCarrierDOMSnapshot? {
        do {
            let encodedSnapshot = try await page.callJavaScript(
                """
                const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
                const codeViewPanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
                const selectedContentLineCount = Number(
                  codeViewPanel?.getAttribute('data-selected-content-line-count') ?? '0'
                );
                const sourceCellReport = globalThis.__bridgeProductSourceCellReport;
                const correlations = Array.isArray(sourceCellReport?.correlations)
                  ? sourceCellReport.correlations.map((correlation) => ({
                      ...correlation,
                      readableText:
                        typeof correlation?.readableDomSelector === 'string'
                          ? document.querySelector(correlation.readableDomSelector)?.textContent ?? ''
                          : ''
                    }))
                  : [];
                return JSON.stringify({
                  correlations,
                  hasAppRoot: document.querySelector('[data-testid="bridge-app-root"]') !== null,
                  hasFileModeHost:
                    document.querySelector('[data-testid="bridge-viewer-mode-host-file"]') !== null,
                  hasReviewModeHost:
                    document.querySelector('[data-testid="bridge-viewer-mode-host-review"]') !== null,
                  hasReviewMetadataFailedShell:
                    document.querySelector('[data-testid="bridge-review-metadata-failed-shell"]') !== null,
                  hasReviewMetadataLoadingShell:
                    document.querySelector('[data-testid="bridge-review-metadata-loading-shell"]') !== null,
                  hasReviewShell: reviewShell !== null,
                  hasReviewCodeViewPanel: codeViewPanel !== null,
                  reviewSelectedContentLineCount:
                    Number.isSafeInteger(selectedContentLineCount) && selectedContentLineCount >= 0
                      ? selectedContentLineCount
                      : 0,
                  reviewSelectedContentState:
                    reviewShell?.getAttribute('data-selected-content-state') ?? null,
                  reviewSelectedDisplayPath:
                    reviewShell?.getAttribute('data-selected-display-path') ?? null,
                  reviewRenderedItemId:
                    codeViewPanel?.getAttribute('data-review-rendered-item-id') ??
                    codeViewPanel?.getAttribute('data-selected-item-id') ??
                    null
                });
                """
            )
            guard let encodedSnapshot = encodedSnapshot as? String,
                let snapshotData = encodedSnapshot.data(using: .utf8)
            else { return nil }
            return try JSONDecoder().decode(
                BridgeProductWebKitCarrierDOMSnapshot.self,
                from: snapshotData
            )
        } catch {
            return nil
        }
    }

    static func nativeSnapshot(
        _ controller: BridgePaneController
    ) async -> BridgeProductWebKitCarrierNativeSnapshot {
        guard let installation = await controller.productSessionOwner.activeInstallation else {
            return .unavailable
        }
        let sessionSnapshot = await installation.session.snapshot
        let ownerSnapshot = await controller.productSessionOwner.snapshot()
        return BridgeProductWebKitCarrierNativeSnapshot(
            activeContentLeaseCount: ownerSnapshot.activeContentLeaseCount,
            activeProducerCount: ownerSnapshot.activeProducerCount,
            activeProducerTaskCount: ownerSnapshot.activeProducerTaskCount,
            activeSchemeTaskCount: ownerSnapshot.activeSchemeTaskCount,
            activeTransportLeaseCount: ownerSnapshot.activeTransportLeaseCount,
            inFlightControlRequestSequence: sessionSnapshot.controlReplay.inFlightRequestSequence,
            inFlightFrameReceiptCount: ownerSnapshot.inFlightFrameReceiptCount,
            lifecycle: lifecycleName(sessionSnapshot.lifecycle),
            nextControlRequestSequence: sessionSnapshot.controlReplay.nextExpectedRequestSequence,
            nextMetadataStreamSequence: ownerSnapshot.nextMetadataStreamSequence,
            pendingFrameWaiterCount: ownerSnapshot.pendingFrameWaiterCount,
            pendingLifecycleAcknowledgementCount: ownerSnapshot.pendingLifecycleAcknowledgementCount,
            queuedByteCount: ownerSnapshot.queuedByteCount,
            queuedFrameCount: ownerSnapshot.queuedFrameCount
        )
    }

    private static func teardown(
        controller: BridgePaneController,
        window: NSWindow
    ) async -> BridgePaneProductSessionOwnerSnapshot {
        let retirementTask = controller.teardown()
        _ = await retirementTask.value
        controller.page.stopLoading()
        window.orderOut(nil)
        window.contentView = nil
        await settleAsyncCallbacks()
        let snapshot = await controller.productSessionOwner.snapshot()
        retainedPage = controller.page
        return snapshot
    }

    private static func lifecycleName(_ lifecycle: BridgeProductSessionLifecycle) -> String {
        switch lifecycle {
        case .awaitingOpen:
            "awaiting_open"
        case .opening:
            "opening"
        case .active:
            "active"
        case .revoked:
            "revoked"
        }
    }

    private static func settleAsyncCallbacks(turns: Int = 40) async {
        for _ in 0..<turns {
            await Task.yield()
        }
    }
}
