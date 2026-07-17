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
    let pierreItemId: String
    let position: String
    let publicationId: String
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
        case pierreItemId
        case position
        case publicationId
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
    let documentVisibilityState: String
    let frameLivenessRafAlive: String
    let frameLivenessRafFiredCount: Int
    let frameLivenessRafScheduledCount: Int
    let hasAppRoot: Bool
    let hasFileModeHost: Bool
    let hasReviewModeHost: Bool
    let hasReviewMetadataFailedShell: Bool
    let hasReviewMetadataLoadingShell: Bool
    let hasReviewShell: Bool
    let paintedElementCount: Int
    let fileReadableText: String
    let hasReviewCodeViewPanel: Bool
    let reviewSelectedContentLineCount: Int
    let reviewSelectedContentState: String?
    let reviewSelectedDisplayPath: String?
    let reviewRenderedItemId: String?

    static let unavailable = Self(
        correlations: [],
        documentVisibilityState: "unavailable",
        frameLivenessRafAlive: "unavailable",
        frameLivenessRafFiredCount: 0,
        frameLivenessRafScheduledCount: 0,
        hasAppRoot: false,
        hasFileModeHost: false,
        hasReviewModeHost: false,
        hasReviewMetadataFailedShell: false,
        hasReviewMetadataLoadingShell: false,
        hasReviewShell: false,
        paintedElementCount: 0,
        fileReadableText: "",
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
    let fileWorkerDerivationEpoch: Int
    let nextControlRequestSequence: Int
    let nextMetadataStreamSequence: Int
    let pendingFrameWaiterCount: Int
    let pendingLifecycleAcknowledgementCount: Int
    let queuedByteCount: Int
    let queuedFrameCount: Int
    let reviewWorkerDerivationEpoch: Int
    let workerInstanceId: String?

    static let unavailable = Self(
        activeContentLeaseCount: 0,
        activeProducerCount: 0,
        activeProducerTaskCount: 0,
        activeSchemeTaskCount: 0,
        activeTransportLeaseCount: 0,
        inFlightControlRequestSequence: nil,
        inFlightFrameReceiptCount: 0,
        lifecycle: "unavailable",
        fileWorkerDerivationEpoch: 0,
        nextControlRequestSequence: 0,
        nextMetadataStreamSequence: 0,
        pendingFrameWaiterCount: 0,
        pendingLifecycleAcknowledgementCount: 0,
        queuedByteCount: 0,
        queuedFrameCount: 0,
        reviewWorkerDerivationEpoch: 0,
        workerInstanceId: nil
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

    var completedReviewPublicationCount: Int {
        reviewPublicationPhases.count(where: { $0 == "review_metadata_publication_completed" })
    }

    var description: String {
        "file=\(fileMetadataPhases),review=\(reviewMetadataPhases),publication=\(reviewPublicationPhases)"
    }
}

struct BridgeProductWebKitCarrierSubscriptionIdentity: Equatable, Sendable {
    let subscriptionId: String
    let workerDerivationEpoch: Int
}

struct BridgeProductWebKitCarrierFileSubscriptionSnapshot: Equatable, Sendable {
    let cancelledSubscriptionIds: [String]
    let openedSubscriptions: [BridgeProductWebKitCarrierSubscriptionIdentity]
}

actor BridgeWebKitTrackingFileMetadataSource:
    BridgePaneProductFileMetadataProducing
{
    private let source: BridgePaneProductFileMetadataSource
    private var cancelledSubscriptionIds: [String] = []
    private var openedSubscriptions: [BridgeProductWebKitCarrierSubscriptionIdentity] = []

    init(source: BridgePaneProductFileMetadataSource) {
        self.source = source
    }

    func currentSource() async -> BridgeProductFileSourceCurrentResult {
        await source.currentSource()
    }

    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        openedSubscriptions.append(Self.identity(subscription))
        try await source.open(
            subscription: subscription,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            emit: emit
        )
    }

    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        try await source.update(
            subscription: subscription,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            emit: emit
        )
    }

    func cancel(subscriptionId: String) async {
        cancelledSubscriptionIds.append(subscriptionId)
        await source.cancel(subscriptionId: subscriptionId)
    }

    func publish(
        status: GitWorkingTreeStatus,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> [BridgePaneProductFileMetadataEmission] {
        await source.publish(
            status: status,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
    }

    func publish(
        changeset: FileChangeset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws -> [BridgePaneProductFileMetadataEmission] {
        try await source.publish(
            changeset: changeset,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
    }

    func authoritativePath(
        for request: BridgeProductFileContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> String? {
        await source.authoritativePath(for: request, productAdmission: productAdmission)
    }

    func contentReadPlan(
        for request: BridgeProductFileContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgePaneProductFileContentReadPlan? {
        await source.contentReadPlan(for: request, productAdmission: productAdmission)
    }

    func snapshot() -> BridgeProductWebKitCarrierFileSubscriptionSnapshot {
        BridgeProductWebKitCarrierFileSubscriptionSnapshot(
            cancelledSubscriptionIds: cancelledSubscriptionIds,
            openedSubscriptions: openedSubscriptions
        )
    }

    private static func identity(
        _ subscription: BridgeProductSubscriptionSnapshot
    ) -> BridgeProductWebKitCarrierSubscriptionIdentity {
        BridgeProductWebKitCarrierSubscriptionIdentity(
            subscriptionId: subscription.subscriptionId,
            workerDerivationEpoch: subscription.workerDerivationEpoch
        )
    }
}

struct BridgeProductWebKitCarrierReviewDeliveryAttempt: Equatable, Sendable {
    let package: BridgeReviewPackage
    let publicationId: UUID
}

struct BridgeProductWebKitCarrierReviewMetadataSnapshot: Equatable, Sendable {
    let cancelledSubscriptionIds: [String]
    let corruptedPublicationId: UUID?
    let didCorruptFinalWindow: Bool
    let deliveryAttempts: [BridgeProductWebKitCarrierReviewDeliveryAttempt]
    let openedSubscriptions: [BridgeProductWebKitCarrierSubscriptionIdentity]
    let replayIsBlocked: Bool
}

actor BridgeWebKitFailingReviewMetadataSource:
    BridgePaneProductReviewMetadataProducing
{
    private let source = BridgePaneProductReviewMetadataSource()
    private var armedPredecessorPublicationId: UUID?
    private var cancelledSubscriptionIds: [String] = []
    private var corruptedPublicationId: UUID?
    private var didCorruptFinalWindow = false
    private var deliveryAttempts: [BridgeProductWebKitCarrierReviewDeliveryAttempt] = []
    private var openedSubscriptions: [BridgeProductWebKitCarrierSubscriptionIdentity] = []
    private var replayIsBlocked = false
    private var replayIsReleased = false
    private var replayRelease: CheckedContinuation<Void, Never>?

    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        openedSubscriptions.append(
            BridgeProductWebKitCarrierSubscriptionIdentity(
                subscriptionId: subscription.subscriptionId,
                workerDerivationEpoch: subscription.workerDerivationEpoch
            )
        )
        try await source.open(
            subscription: subscription,
            productAdmission: productAdmission
        ) { event, emittedAdmission in
            try await self.emitPossiblyCorrupted(
                event,
                productAdmission: emittedAdmission,
                emit: emit
            )
        }
    }

    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        try await source.update(
            subscription: subscription,
            productAdmission: productAdmission
        ) { event, emittedAdmission in
            try await self.emitPossiblyCorrupted(
                event,
                productAdmission: emittedAdmission,
                emit: emit
            )
        }
    }

    func reserve(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgeReviewMetadataPublicationReservation {
        try await source.reserve(
            package: package,
            publicationId: publicationId,
            productAdmission: productAdmission
        )
    }

    func deliver(
        package: BridgeReviewPackage,
        reservation: BridgeReviewMetadataPublicationReservation,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        deliveryAttempts.append(
            BridgeProductWebKitCarrierReviewDeliveryAttempt(
                package: package,
                publicationId: reservation.publicationId
            )
        )
        if corruptedPublicationId == reservation.publicationId,
            deliveryAttempts.count(where: { $0.publicationId == reservation.publicationId }) == 2
        {
            replayIsBlocked = true
            if !replayIsReleased {
                await withCheckedContinuation { continuation in
                    replayRelease = continuation
                }
            }
        } else if let armedPredecessorPublicationId,
            reservation.publicationId != armedPredecessorPublicationId,
            corruptedPublicationId == nil
        {
            corruptedPublicationId = reservation.publicationId
        }
        return try await source.deliver(
            package: package,
            reservation: reservation,
            productAdmission: productAdmission
        )
    }

    func cancel(subscriptionId: String) async {
        cancelledSubscriptionIds.append(subscriptionId)
        await source.cancel(subscriptionId: subscriptionId)
    }

    func armFailure(after publicationId: UUID) {
        armedPredecessorPublicationId = publicationId
    }

    func releaseReplay() {
        replayIsReleased = true
        replayRelease?.resume()
        replayRelease = nil
    }

    func snapshot() -> BridgeProductWebKitCarrierReviewMetadataSnapshot {
        BridgeProductWebKitCarrierReviewMetadataSnapshot(
            cancelledSubscriptionIds: cancelledSubscriptionIds,
            corruptedPublicationId: corruptedPublicationId,
            didCorruptFinalWindow: didCorruptFinalWindow,
            deliveryAttempts: deliveryAttempts,
            openedSubscriptions: openedSubscriptions,
            replayIsBlocked: replayIsBlocked
        )
    }

    private func emitPossiblyCorrupted(
        _ event: BridgeProductReviewMetadataEvent,
        productAdmission: BridgeProductAdmissionContext,
        emit: BridgePaneProductReviewMetadataEventSink
    ) async throws -> BridgeProductProducerEnqueueResult {
        guard event.publicationId == corruptedPublicationId,
            !didCorruptFinalWindow,
            case .window(let window) = event,
            window.itemWindow.finalWindow,
            window.treeWindow.finalWindow,
            window.itemMetadata.count > 1
        else {
            return try await emit(event, productAdmission)
        }
        let gappedItemWindow = try BridgeProductReviewItemWindow(
            finalWindow: true,
            itemCount: window.itemWindow.itemCount - 1,
            startIndex: window.itemWindow.startIndex + 1,
            totalItemCount: window.itemWindow.totalItemCount
        )
        let gappedFinalWindow = try BridgeProductReviewWindowEvent(
            identity: window.identity,
            contentSources: window.contentSources,
            extentFacts: window.extentFacts,
            itemMetadata: Array(window.itemMetadata.dropFirst()),
            itemWindow: gappedItemWindow,
            summary: window.summary,
            treeRows: window.treeRows,
            treeWindow: window.treeWindow
        )
        didCorruptFinalWindow = true
        return try await emit(.window(gappedFinalWindow), productAdmission)
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
    let hostSnapshot: BridgeProductWebKitCarrierHostSnapshot
    let teardownSnapshot: BridgePaneProductSessionOwnerSnapshot
    let value: Value
}

struct BridgeProductWebKitCarrierHostSnapshot: Equatable, Sendable, CustomStringConvertible {
    let applicationIsActive: Bool
    let hostingViewHasWindow: Bool
    let hostingViewHeight: Double
    let hostingViewWidth: Double
    let mountViewHasWindow: Bool
    let mountViewHeight: Double
    let mountViewWidth: Double
    let windowIsKey: Bool
    let windowIsVisible: Bool
    let windowOcclusionIsVisible: Bool

    var description: String {
        "appActive=\(applicationIsActive),windowVisible=\(windowIsVisible),windowKey=\(windowIsKey),occlusionVisible=\(windowOcclusionIsVisible),mount=\(mountViewWidth)x\(mountViewHeight)/attached=\(mountViewHasWindow),hosting=\(hostingViewWidth)x\(hostingViewHeight)/attached=\(hostingViewHasWindow)"
    }
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
            let hostSnapshot = hostSnapshot(window: window, mountView: mountView)
            let teardownSnapshot = await teardown(controller: controller, window: window)
            return BridgeProductWebKitCarrierRunResult(
                hostSnapshot: hostSnapshot,
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
                const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
                const fileModeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
                const readableTextIncludingOpenShadowRoots = (root) => {
                  const textParts = [];
                  const visit = (node) => {
                    if (node.nodeType === Node.TEXT_NODE) {
                      textParts.push(node.textContent ?? '');
                      return;
                    }
                    if (node instanceof Element && node.shadowRoot !== null) {
                      visit(node.shadowRoot);
                    }
                    for (const child of node.childNodes) visit(child);
                  };
                  visit(root);
                  return textParts.join(' ');
                };
                const paintedElements = [];
                const collectPaintedElements = (root) => {
                  for (const element of root.querySelectorAll('*')) {
                    if (element.hasAttribute('data-bridge-painted-source-correlations')) {
                      paintedElements.push(element);
                    }
                    if (element.shadowRoot !== null) collectPaintedElements(element.shadowRoot);
                  }
                };
                collectPaintedElements(document);
                const correlations = paintedElements.flatMap((element) => {
                  const publicationId =
                    element.getAttribute('data-bridge-painted-publication-id') ?? '';
                  let sourceCorrelations = [];
                  try {
                    const parsedCorrelations = JSON.parse(
                      element.getAttribute('data-bridge-painted-source-correlations') ?? '[]'
                    );
                    if (Array.isArray(parsedCorrelations)) sourceCorrelations = parsedCorrelations;
                  } catch {
                    sourceCorrelations = [];
                  }
                  const readableDomSelector =
                    `[data-bridge-painted-publication-id="${CSS.escape(publicationId)}"]`;
                  const readableText = readableTextIncludingOpenShadowRoots(element);
                  return sourceCorrelations
                    .filter((correlation) => correlation?.publicationId === publicationId)
                    .map((correlation) => ({
                      ...correlation,
                      readableDomSelector,
                      readableText
                    }));
                });
                return JSON.stringify({
                  correlations,
                  documentVisibilityState: document.visibilityState,
                  frameLivenessRafAlive:
                    globalThis.__bridgeFrameLivenessProbe?.rafAlive ?? 'missing',
                  frameLivenessRafFiredCount:
                    globalThis.__bridgeFrameLivenessProbe?.rafFiredCount ?? 0,
                  frameLivenessRafScheduledCount:
                    globalThis.__bridgeFrameLivenessProbe?.rafScheduledCount ?? 0,
                  hasAppRoot: appRoot !== null,
                  hasFileModeHost: fileModeHost !== null,
                  hasReviewModeHost:
                    document.querySelector('[data-testid="bridge-viewer-mode-host-review"]') !== null,
                  hasReviewMetadataFailedShell:
                    document.querySelector('[data-testid="bridge-review-metadata-failed-shell"]') !== null,
                  hasReviewMetadataLoadingShell:
                    document.querySelector('[data-testid="bridge-review-metadata-loading-shell"]') !== null,
                  hasReviewShell: reviewShell !== null,
                  paintedElementCount: paintedElements.length,
                  fileReadableText: readableTextIncludingOpenShadowRoots(fileModeHost ?? document.createDocumentFragment()),
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
            return try decodeDOMSnapshot(encodedSnapshot)
        } catch {
            return nil
        }
    }

    private static func decodeDOMSnapshot(
        _ encodedSnapshot: Any?
    ) throws -> BridgeProductWebKitCarrierDOMSnapshot? {
        guard let encodedSnapshot = encodedSnapshot as? String,
            let snapshotData = encodedSnapshot.data(using: .utf8)
        else { return nil }
        return try JSONDecoder().decode(
            BridgeProductWebKitCarrierDOMSnapshot.self,
            from: snapshotData
        )
    }

    static func activateFileMode(_ page: WebPage) async -> Bool {
        do {
            let didActivate = try await page.callJavaScript(
                """
                const button = document.querySelector('[data-testid="bridge-viewer-context-file"]');
                if (!(button instanceof HTMLElement)) return false;
                button.click();
                return true;
                """
            )
            return didActivate as? Bool ?? false
        } catch {
            return false
        }
    }

    static func selectFilePath(_ page: WebPage, path: String) async -> Bool {
        guard let encodedPathData = try? JSONEncoder().encode(path),
            let encodedPath = String(data: encodedPathData, encoding: .utf8)
        else { return false }
        do {
            let didSelect = try await page.callJavaScript(
                """
                const path = \(encodedPath);
                const selector =
                  `button[data-type="item"][data-item-type="file"][data-item-path="${CSS.escape(path)}"]`;
                const queryInOpenShadowRoots = (root, selector) => {
                  const directMatch = root.querySelector(selector);
                  if (directMatch !== null) return directMatch;
                  for (const element of root.querySelectorAll('*')) {
                    if (element.shadowRoot === null) continue;
                    const shadowMatch = queryInOpenShadowRoots(element.shadowRoot, selector);
                    if (shadowMatch !== null) return shadowMatch;
                  }
                  return null;
                };
                const button = queryInOpenShadowRoots(document, selector);
                if (!(button instanceof HTMLElement)) return false;
                button.click();
                return true;
                """
            )
            return didSelect as? Bool ?? false
        } catch {
            return false
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
            fileWorkerDerivationEpoch: sessionSnapshot.workerDerivationEpochBySurface[.file] ?? 0,
            nextControlRequestSequence: sessionSnapshot.controlReplay.nextExpectedRequestSequence,
            nextMetadataStreamSequence: ownerSnapshot.nextMetadataStreamSequence,
            pendingFrameWaiterCount: ownerSnapshot.pendingFrameWaiterCount,
            pendingLifecycleAcknowledgementCount: ownerSnapshot.pendingLifecycleAcknowledgementCount,
            queuedByteCount: ownerSnapshot.queuedByteCount,
            queuedFrameCount: ownerSnapshot.queuedFrameCount,
            reviewWorkerDerivationEpoch: sessionSnapshot.workerDerivationEpochBySurface[.review] ?? 0,
            workerInstanceId: installation.bootstrap.workerInstanceId
        )
    }

    private static func teardown(
        controller: BridgePaneController,
        window: NSWindow
    ) async -> BridgePaneProductSessionOwnerSnapshot {
        let retirementTask = controller.teardown()
        _ = await retirementTask.value
        controller.page.stopLoading()
        if let blankURL = URL(string: "about:blank") {
            _ = controller.page.load(blankURL)
        }
        for _ in 0..<10_000 where controller.page.isLoading {
            await Task.yield()
        }
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

    private static func hostSnapshot(
        window: NSWindow,
        mountView: BridgePaneMountView
    ) -> BridgeProductWebKitCarrierHostSnapshot {
        let hostingView = mountView.subviews.first
        return BridgeProductWebKitCarrierHostSnapshot(
            applicationIsActive: NSApp.isActive,
            hostingViewHasWindow: hostingView?.window === window,
            hostingViewHeight: Double(hostingView?.frame.height ?? 0),
            hostingViewWidth: Double(hostingView?.frame.width ?? 0),
            mountViewHasWindow: mountView.window === window,
            mountViewHeight: Double(mountView.frame.height),
            mountViewWidth: Double(mountView.frame.width),
            windowIsKey: window.isKeyWindow,
            windowIsVisible: window.isVisible,
            windowOcclusionIsVisible: window.occlusionState.contains(.visible)
        )
    }

    private static func settleAsyncCallbacks(turns: Int = 40) async {
        for _ in 0..<turns {
            await Task.yield()
        }
    }
}
