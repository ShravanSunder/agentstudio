import AppKit
import Foundation
import Testing
import WebKit

@testable import AgentStudio

struct BridgeProductWebKitTwoPanePositionSnapshot: Decodable, Equatable, Sendable {
    let activeMode: String?
    let fileCodeScrollTop: Double
    let fileRenderedPath: String?
    let fileSelectedPath: String?
    let fileStatusText: String?
    let fileTreeScrollTop: Double
    let hasAppRoot: Bool
    let reviewCodeScrollTop: Double
    let reviewCollapsedDirectoryExpansion: String?
    let reviewSelectedItemId: String?
    let reviewSelectedPath: String?
    let reviewStatusText: String?
    let reviewTreeScrollTop: Double
}

struct BridgeProductWebKitTwoPaneJourneyProof: Sendable {
    let dormantDefaults: BridgeProductWebKitTwoPanePositionSnapshot
    let fileStateAfterReturn: BridgeProductWebKitTwoPanePositionSnapshot
    let hiddenDirtyGeneration: UInt64?
    let hiddenMetadataSequenceAfterStorm: Int
    let hiddenMetadataSequenceBeforeStorm: Int
    let hiddenRefreshPassCountAfterStorm: Int
    let hiddenRefreshPassCountBeforeStorm: Int
    let hiddenReviewPublicationCountAfterLateRelease: Int
    let hiddenReviewPublicationCountBeforeLateRelease: Int
    let hiddenStatus: BridgeProductWebKitTwoPanePositionSnapshot
    let initialReviewState: BridgeProductWebKitTwoPanePositionSnapshot
    let paneOneFinalRefreshPassCount: Int
    let paneOneForegroundRefreshPassCount: Int
    let paneOneWorkerIdAfterReturn: String?
    let paneOneWorkerIdBeforeHide: String?
    let paneTwoActivityAfterJourney: BridgePaneActivity
    let paneTwoStateAfterJourney: BridgeProductWebKitTwoPanePositionSnapshot
    let paneTwoStateBeforeJourney: BridgeProductWebKitTwoPanePositionSnapshot
    let paneTwoWorkerIdAfterJourney: String?
    let paneTwoWorkerIdBeforeJourney: String?
    let reviewStateAfterReturn: BridgeProductWebKitTwoPanePositionSnapshot
    let staleForegroundAdmissionWasRejected: Bool
    let updatingFileStatus: BridgeProductWebKitTwoPanePositionSnapshot
    let updatingReviewStatus: BridgeProductWebKitTwoPanePositionSnapshot
}

private actor BridgeProductWebKitGatedReviewSourceProvider: BridgeReviewSourceProvider {
    private let base: any BridgeReviewSourceProvider
    private var blockedComparisonCount = 0
    private var comparisonCount = 0
    private var isNextComparisonArmed = false
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    init(base: any BridgeReviewSourceProvider) {
        self.base = base
    }

    func armNextComparison() {
        isNextComparisonArmed = true
    }

    func releaseBlockedComparisons() {
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func snapshot() -> (comparisonCount: Int, blockedComparisonCount: Int) {
        (comparisonCount, blockedComparisonCount)
    }

    func resolveEndpoint(_ request: BridgeEndpointResolutionRequest) async throws
        -> BridgeSourceEndpoint
    {
        try await base.resolveEndpoint(request)
    }

    func compareEndpoints(_ request: BridgeEndpointComparisonRequest) async throws
        -> BridgeEndpointComparison
    {
        comparisonCount += 1
        if isNextComparisonArmed {
            isNextComparisonArmed = false
            blockedComparisonCount += 1
            await withCheckedContinuation { continuation in
                releaseContinuations.append(continuation)
            }
        }
        return try await base.compareEndpoints(request)
    }

    func readTree(_ request: BridgeTreeReadRequest) async throws -> BridgeTreeReadResult {
        try await base.readTree(request)
    }

    func readReviewItemDescriptor(_ request: BridgeReviewItemDescriptorRequest) async throws
        -> BridgeReviewItemDescriptor
    {
        try await base.readReviewItemDescriptor(request)
    }

    func resolveCheckpointEndpoint(_ request: BridgeCheckpointEndpointRequest) async throws
        -> BridgeSourceEndpoint
    {
        try await base.resolveCheckpointEndpoint(request)
    }

    func loadContent(_ request: BridgeContentLoadRequest) async throws -> BridgeContentLoadResult {
        try await base.loadContent(request)
    }

    func streamContent(
        _ request: BridgeContentStreamRequest,
        chunkByteCount: Int,
        emitChunk: BridgeContentStreamEmitter
    ) async throws -> BridgeContentStreamResult {
        try await base.streamContent(request, chunkByteCount: chunkByteCount, emitChunk: emitChunk)
    }
}

@MainActor
enum BridgeProductWebKitTwoPaneJourneyTestSupport {
    private struct JourneyInput {
        let paneOne: BridgePaneController
        let paneOneRepoURL: URL
        let paneOneReviewProvider: BridgeProductWebKitGatedReviewSourceProvider
        let paneOneTrace: BridgeProductWebKitCarrierTraceRecorder
        let paneTwo: BridgePaneController
        let paneTwoReviewProvider: BridgeProductWebKitGatedReviewSourceProvider
        let paneTwoTrace: BridgeProductWebKitCarrierTraceRecorder
    }

    private struct JourneyPreparation {
        let dormantDefaults: BridgeProductWebKitTwoPanePositionSnapshot
        let initialReviewState: BridgeProductWebKitTwoPanePositionSnapshot
        let paneOneNativeBeforeHide: BridgeProductWebKitCarrierNativeSnapshot
        let paneTwoNativeBeforeJourney: BridgeProductWebKitCarrierNativeSnapshot
        let paneTwoStateBeforeJourney: BridgeProductWebKitTwoPanePositionSnapshot
        let staleForegroundAdmission: BridgePaneRefreshWorkAdmission?
    }

    private struct JourneyUpdatingState {
        let foregroundRefreshPassCount: Int
        let fileStatus: BridgeProductWebKitTwoPanePositionSnapshot
        let reviewStatus: BridgeProductWebKitTwoPanePositionSnapshot
    }

    private static let filePositionPath = "Sources/Group00/large-position.txt"
    private static var retainedPages: [WebPage] = []

    static func run() async throws -> BridgeProductWebKitTwoPaneJourneyProof {
        let paneOneRepoURL = try FilesystemTestGitRepo.create(named: "bridge-two-pane-one-webkit")
        let paneTwoRepoURL = try FilesystemTestGitRepo.create(named: "bridge-two-pane-two-webkit")
        defer {
            FilesystemTestGitRepo.destroy(paneOneRepoURL)
            FilesystemTestGitRepo.destroy(paneTwoRepoURL)
        }
        try seedPositionFixture(at: paneOneRepoURL, prefix: "pane-one")
        try seedPositionFixture(at: paneTwoRepoURL, prefix: "pane-two")

        let paneOneTrace = BridgeProductWebKitCarrierTraceRecorder()
        let paneTwoTrace = BridgeProductWebKitCarrierTraceRecorder()
        let paneOneGitReadContext = makeBridgeGitReadContext(rootURL: paneOneRepoURL)
        let paneTwoGitReadContext = makeBridgeGitReadContext(rootURL: paneTwoRepoURL)
        let paneOneReviewProvider = BridgeProductWebKitGatedReviewSourceProvider(
            base: BridgeReviewSourceProviderFactory.gitProvider(
                repositoryPath: paneOneRepoURL,
                gitReadContext: paneOneGitReadContext
            )
        )
        let paneTwoReviewProvider = BridgeProductWebKitGatedReviewSourceProvider(
            base: BridgeReviewSourceProviderFactory.gitProvider(
                repositoryPath: paneTwoRepoURL,
                gitReadContext: paneTwoGitReadContext
            )
        )
        let paneOne = makeController(
            repoURL: paneOneRepoURL,
            gitReadContext: paneOneGitReadContext,
            initialActivity: .foreground,
            reviewProvider: paneOneReviewProvider,
            traceRecorder: paneOneTrace,
            title: "Hosted Pane One"
        )
        let paneTwo = makeController(
            repoURL: paneTwoRepoURL,
            gitReadContext: paneTwoGitReadContext,
            initialActivity: .dormant,
            reviewProvider: paneTwoReviewProvider,
            traceRecorder: paneTwoTrace,
            title: "Hosted Pane Two"
        )

        return try await withHostedControllers([paneOne, paneTwo]) {
            try await exerciseJourney(
                JourneyInput(
                    paneOne: paneOne,
                    paneOneRepoURL: paneOneRepoURL,
                    paneOneReviewProvider: paneOneReviewProvider,
                    paneOneTrace: paneOneTrace,
                    paneTwo: paneTwo,
                    paneTwoReviewProvider: paneTwoReviewProvider,
                    paneTwoTrace: paneTwoTrace
                )
            )
        }
    }

    private static func prepareJourney(_ input: JourneyInput) async throws -> JourneyPreparation {
        input.paneOne.loadApp()
        input.paneTwo.loadApp()
        try await requireMountedApp(input.paneOne)
        try await requireMountedApp(input.paneTwo)

        let dormantDefaults = try await requirePositionSnapshot(input.paneTwo.page)
        let dormantNative = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(input.paneTwo)
        guard dormantNative.lifecycle == "active" else {
            throw JourneyError.conditionFailed("pane two dormant worker did not open")
        }
        guard input.paneTwo.refreshAdmissionCoordinator.diagnosticSnapshot.refreshPassCount == 0
        else {
            throw JourneyError.conditionFailed("fresh dormant pane started a refresh pass")
        }

        let paneTwoForegroundTransition = input.paneTwo.applyBridgePaneActivity(.foreground)
        await paneTwoForegroundTransition?.value
        try await requireReadyReview(
            input.paneOne,
            paneLabel: "pane one",
            reviewProvider: input.paneOneReviewProvider,
            traceRecorder: input.paneOneTrace
        )
        try await requireReadyReview(
            input.paneTwo,
            paneLabel: "pane two",
            reviewProvider: input.paneTwoReviewProvider,
            traceRecorder: input.paneTwoTrace
        )

        let initialReviewState = try await requirePositionSnapshot(input.paneOne.page)
        guard await BridgeProductWebKitCarrierTestSupport.activateFileMode(input.paneOne.page) else {
            throw JourneyError.conditionFailed("pane one File mode did not activate")
        }
        guard await activateReviewMode(input.paneOne.page) else {
            throw JourneyError.conditionFailed("pane one Review mode did not reactivate")
        }
        try await requireReadyReview(
            input.paneOne,
            paneLabel: "pane one after mode round-trip",
            reviewProvider: input.paneOneReviewProvider,
            traceRecorder: input.paneOneTrace
        )

        return JourneyPreparation(
            dormantDefaults: dormantDefaults,
            initialReviewState: initialReviewState,
            paneOneNativeBeforeHide:
                await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(input.paneOne),
            paneTwoNativeBeforeJourney:
                await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(input.paneTwo),
            paneTwoStateBeforeJourney: try await requirePositionSnapshot(input.paneTwo.page),
            staleForegroundAdmission:
                input.paneOne.refreshAdmissionCoordinator.acquireForegroundWork()
        )
    }

    private static func exerciseJourney(
        _ input: JourneyInput
    ) async throws -> BridgeProductWebKitTwoPaneJourneyProof {
        let preparation = try await prepareJourney(input)
        let updatingState = try await beginBlockedRefresh(input)

        let hiddenTransition = input.paneOne.applyBridgePaneActivity(.loadedHidden)
        await hiddenTransition?.value
        let hiddenStatus = try await requireNoUpdatingStatus(input.paneOne.page)
        let staleForegroundAdmissionWasRejected =
            preparation.staleForegroundAdmission?.withValidAdmission { true } == nil
        let hiddenBeforeStorm = input.paneOne.refreshAdmissionCoordinator.diagnosticSnapshot
        let hiddenNativeBeforeStorm =
            await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(input.paneOne)
        let hiddenTraceBeforeLateRelease = await input.paneOneTrace.scrubbedTrace()
        let hiddenComparisonCountBeforeStorm =
            await input.paneOneReviewProvider.snapshot().comparisonCount

        await input.paneOne.handleWorktreeProductInvalidation(
            .filesChanged(
                try makeChangeset(
                    for: input.paneOne,
                    paths: ["tracked.txt"],
                    batchSequence: 702
                )
            )
        )
        await input.paneOne.handleWorktreeProductInvalidation(
            .filesChanged(
                try makeChangeset(
                    for: input.paneOne,
                    paths: ["tracked.txt"],
                    batchSequence: 703
                )
            )
        )
        let hiddenAfterStorm = input.paneOne.refreshAdmissionCoordinator.diagnosticSnapshot
        let hiddenNativeAfterStorm =
            await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(input.paneOne)
        guard
            await input.paneOneReviewProvider.snapshot().comparisonCount
                == hiddenComparisonCountBeforeStorm
        else {
            throw JourneyError.conditionFailed("loaded-hidden invalidation started Review work")
        }

        await input.paneOneReviewProvider.releaseBlockedComparisons()
        try await requireHiddenRefreshSettled(input.paneOne)
        let hiddenTraceAfterLateRelease = await input.paneOneTrace.scrubbedTrace()
        let paneOneForegroundTransition = input.paneOne.applyBridgePaneActivity(.foreground)
        await paneOneForegroundTransition?.value
        try await requireRefreshIdle(input.paneOne)
        try await requireReadyReview(
            input.paneOne,
            paneLabel: "pane one after foreground return",
            reviewProvider: input.paneOneReviewProvider,
            traceRecorder: input.paneOneTrace
        )
        let reviewStateAfterReturn = try await requirePositionSnapshot(input.paneOne.page)
        guard await BridgeProductWebKitCarrierTestSupport.activateFileMode(input.paneOne.page) else {
            throw JourneyError.conditionFailed("File mode did not reactivate after foreground return")
        }
        let fileStateAfterReturn = try await requirePositionSnapshot(input.paneOne.page)
        let paneOneNativeAfterReturn =
            await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(input.paneOne)
        let paneTwoNativeAfterJourney =
            await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(input.paneTwo)
        let paneTwoStateAfterJourney = try await requirePositionSnapshot(input.paneTwo.page)

        return BridgeProductWebKitTwoPaneJourneyProof(
            dormantDefaults: preparation.dormantDefaults,
            fileStateAfterReturn: fileStateAfterReturn,
            hiddenDirtyGeneration: hiddenAfterStorm.dirtyFact?.generation,
            hiddenMetadataSequenceAfterStorm: hiddenNativeAfterStorm.nextMetadataStreamSequence,
            hiddenMetadataSequenceBeforeStorm: hiddenNativeBeforeStorm.nextMetadataStreamSequence,
            hiddenRefreshPassCountAfterStorm: hiddenAfterStorm.refreshPassCount,
            hiddenRefreshPassCountBeforeStorm: hiddenBeforeStorm.refreshPassCount,
            hiddenReviewPublicationCountAfterLateRelease:
                hiddenTraceAfterLateRelease.completedReviewPublicationCount,
            hiddenReviewPublicationCountBeforeLateRelease:
                hiddenTraceBeforeLateRelease.completedReviewPublicationCount,
            hiddenStatus: hiddenStatus,
            initialReviewState: preparation.initialReviewState,
            paneOneFinalRefreshPassCount:
                input.paneOne.refreshAdmissionCoordinator.diagnosticSnapshot.refreshPassCount,
            paneOneForegroundRefreshPassCount: updatingState.foregroundRefreshPassCount,
            paneOneWorkerIdAfterReturn: paneOneNativeAfterReturn.workerInstanceId,
            paneOneWorkerIdBeforeHide: preparation.paneOneNativeBeforeHide.workerInstanceId,
            paneTwoActivityAfterJourney:
                input.paneTwo.refreshAdmissionCoordinator.diagnosticSnapshot.activity,
            paneTwoStateAfterJourney: paneTwoStateAfterJourney,
            paneTwoStateBeforeJourney: preparation.paneTwoStateBeforeJourney,
            paneTwoWorkerIdAfterJourney: paneTwoNativeAfterJourney.workerInstanceId,
            paneTwoWorkerIdBeforeJourney: preparation.paneTwoNativeBeforeJourney.workerInstanceId,
            reviewStateAfterReturn: reviewStateAfterReturn,
            staleForegroundAdmissionWasRejected: staleForegroundAdmissionWasRejected,
            updatingFileStatus: updatingState.fileStatus,
            updatingReviewStatus: updatingState.reviewStatus
        )
    }

    private static func beginBlockedRefresh(
        _ input: JourneyInput
    ) async throws -> JourneyUpdatingState {
        await input.paneOneReviewProvider.armNextComparison()
        try appendTrackedChange(at: input.paneOneRepoURL)
        await input.paneOne.handleWorktreeProductInvalidation(
            .filesChanged(
                try makeChangeset(
                    for: input.paneOne,
                    paths: ["tracked.txt"],
                    batchSequence: 701
                )
            )
        )
        try await requireBlockedComparison(input.paneOneReviewProvider, expectedCount: 1)
        let paneOneForegroundRefreshPassCount =
            input.paneOne.refreshAdmissionCoordinator.diagnosticSnapshot.refreshPassCount
        let updatingReviewStatus = try await requireStatus(
            input.paneOne.page,
            activeMode: "review",
            expectedText: "Updating review…"
        )
        guard await BridgeProductWebKitCarrierTestSupport.activateFileMode(input.paneOne.page) else {
            throw JourneyError.conditionFailed("File mode did not activate during refresh")
        }
        let updatingFileStatus = try await requireStatus(
            input.paneOne.page,
            activeMode: "file",
            expectedText: "Updating files…"
        )
        let nativeBeforeReviewActivation =
            await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(input.paneOne)
        guard await activateReviewMode(input.paneOne.page) else {
            throw JourneyError.conditionFailed("Review mode did not reactivate during refresh")
        }
        try await requireNativeControlQuiescence(
            input.paneOne,
            afterRequestSequence: nativeBeforeReviewActivation.nextControlRequestSequence
        )
        return JourneyUpdatingState(
            foregroundRefreshPassCount: paneOneForegroundRefreshPassCount,
            fileStatus: updatingFileStatus,
            reviewStatus: updatingReviewStatus
        )
    }

    private static func withHostedControllers<Value>(
        _ controllers: [BridgePaneController],
        operation: @MainActor () async throws -> Value
    ) async throws -> Value {
        let frame = NSRect(x: 0, y: 0, width: 960, height: 720)
        let hosts = controllers.enumerated().map { index, controller in
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
            window.setFrameOrigin(NSPoint(x: index * 12, y: index * 12))
            window.orderBack(nil)
            return window
        }
        do {
            let value = try await operation()
            try await teardown(controllers: controllers, windows: hosts)
            return value
        } catch {
            try? await teardown(controllers: controllers, windows: hosts)
            throw error
        }
    }

    private static func teardown(
        controllers: [BridgePaneController],
        windows: [NSWindow]
    ) async throws {
        for controller in controllers {
            _ = await controller.teardown().value
            controller.page.stopLoading()
        }
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        for _ in 0..<80 {
            await Task.yield()
        }
        for controller in controllers {
            let snapshot = await controller.productSessionOwner.snapshot()
            guard snapshot.hasZeroResidue else {
                throw JourneyError.conditionFailed("two-pane teardown retained residue: \(snapshot)")
            }
        }
        retainedPages = controllers.map(\.page)
    }

    private static func makeController(
        repoURL: URL,
        gitReadContext: BridgeGitReadContext,
        initialActivity: BridgePaneActivity,
        reviewProvider: any BridgeReviewSourceProvider,
        traceRecorder: BridgeProductWebKitCarrierTraceRecorder,
        title: String
    ) -> BridgePaneController {
        let paneId = UUIDv7.generate()
        return BridgePaneController(
            paneId: paneId,
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(
                    rootPath: repoURL.path,
                    baseline: .localDefaultBranch(branchName: "main")
                )
            ),
            metadata: PaneMetadata(
                paneId: PaneId(uuid: paneId),
                contentType: .diff,
                launchDirectory: repoURL,
                title: title,
                facets: PaneContextFacets(
                    repoId: UUIDv7.generate(),
                    worktreeId: UUIDv7.generate(),
                    worktreeName: title,
                    cwd: repoURL
                )
            ),
            reviewSourceProvider: reviewProvider,
            gitReadContext: gitReadContext,
            telemetryRuntimePolicy: .live,
            telemetryScopeGate: BridgeTelemetryScopeGate(enabledScopes: []),
            telemetryRecorder: traceRecorder,
            initialPaneActivity: initialActivity
        )
    }

    private static func seedPositionFixture(at repoURL: URL, prefix: String) throws {
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)
        for index in 0..<36 {
            let directory = repoURL.appending(path: String(format: "Sources/Group%02d", index / 9))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appending(path: String(format: "item-%03d.txt", index))
            try "\(prefix) review item \(index)\n".write(
                to: fileURL,
                atomically: true,
                encoding: .utf8
            )
        }
        let largeBody = (0..<520).map { "\(prefix) large line \($0)" }.joined(separator: "\n")
        try "\(largeBody)\n".write(
            to: repoURL.appending(path: filePositionPath),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func appendTrackedChange(at repoURL: URL) throws {
        let trackedURL = repoURL.appending(path: "tracked.txt")
        let current = try String(contentsOf: trackedURL, encoding: .utf8)
        try "\(current)hosted hidden refresh\n".write(
            to: trackedURL,
            atomically: true,
            encoding: .utf8
        )
    }

    private static func makeChangeset(
        for controller: BridgePaneController,
        paths: [String],
        batchSequence: UInt64
    ) throws -> FileChangeset {
        let worktreeId = try #require(controller.runtime.metadata.worktreeId)
        let rootPath = try #require(controller.runtime.metadata.cwd)
        return FileChangeset(
            worktreeId: worktreeId,
            repoId: controller.runtime.metadata.repoId,
            rootPath: rootPath,
            paths: paths,
            timestamp: .now,
            batchSeq: batchSequence
        )
    }

    private static func requireMountedApp(_ controller: BridgePaneController) async throws {
        let mounted = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
            let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
            let native = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(controller)
            return dom?.hasAppRoot == true && native.lifecycle == "active"
        }
        guard mounted else { throw JourneyError.conditionFailed("bundled app did not mount") }
    }

    private static func requireReadyReview(
        _ controller: BridgePaneController,
        paneLabel: String,
        reviewProvider: BridgeProductWebKitGatedReviewSourceProvider,
        traceRecorder: BridgeProductWebKitCarrierTraceRecorder
    ) async throws {
        let ready = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(20)) {
            let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
            let trace = await traceRecorder.scrubbedTrace()
            return trace.hasCanonicalEagerSubscriptions
                && trace.hasFileMetadataWindow
                && trace.hasReviewMetadataPublication
                && dom?.reviewSelectedContentState == "ready"
        }
        guard ready else {
            let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
            let native = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(controller)
            let providerSnapshot = await reviewProvider.snapshot()
            let trace = await traceRecorder.scrubbedTrace()
            throw JourneyError.conditionFailed(
                "\(paneLabel) real-git Review did not become ready; appRoot=\(dom?.hasAppRoot == true), canonicalSubscriptions=\(trace.hasCanonicalEagerSubscriptions), fileMetadata=\(trace.hasFileMetadataWindow), reviewPublication=\(trace.hasReviewMetadataPublication), reviewState=\(dom?.reviewSelectedContentState ?? "missing"), comparisons=\(providerSnapshot.comparisonCount), blockedComparisons=\(providerSnapshot.blockedComparisonCount), native=\(native)"
            )
        }
    }

    private static func requireBlockedComparison(
        _ provider: BridgeProductWebKitGatedReviewSourceProvider,
        expectedCount: Int
    ) async throws {
        let blocked = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(10)) {
            await provider.snapshot().blockedComparisonCount == expectedCount
        }
        guard blocked else { throw JourneyError.conditionFailed("real-git comparison did not block") }
    }

    private static func requireNativeControlQuiescence(
        _ controller: BridgePaneController,
        afterRequestSequence: Int
    ) async throws {
        let settled = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(10)) {
            let native = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(controller)
            return native.nextControlRequestSequence > afterRequestSequence
                && native.inFlightControlRequestSequence == nil
                && native.inFlightFrameReceiptCount == 0
                && native.queuedFrameCount == 0
        }
        guard settled else {
            throw JourneyError.conditionFailed(
                "native Review activation did not reach a quiescent control boundary"
            )
        }
    }

    private static func requireHiddenRefreshSettled(
        _ controller: BridgePaneController
    ) async throws {
        let settled = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(10)) {
            let snapshot = controller.refreshAdmissionCoordinator.diagnosticSnapshot
            return snapshot.activity == .loadedHidden
                && snapshot.activeRefreshPass == nil
                && snapshot.dirtyFact != nil
                && controller.activeReviewRefreshTask == nil
        }
        guard settled else { throw JourneyError.conditionFailed("hidden refresh did not settle") }
    }

    private static func requireRefreshIdle(_ controller: BridgePaneController) async throws {
        let idle = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(20)) {
            let snapshot = controller.refreshAdmissionCoordinator.diagnosticSnapshot
            return snapshot.activity == .foreground
                && snapshot.activeRefreshPass == nil
                && snapshot.dirtyFact == nil
                && controller.activeReviewRefreshTask == nil
        }
        guard idle else { throw JourneyError.conditionFailed("foreground catch-up did not settle") }
    }

    private static func requireStatus(
        _ page: WebPage,
        activeMode: String,
        expectedText: String
    ) async throws -> BridgeProductWebKitTwoPanePositionSnapshot {
        var observed: BridgeProductWebKitTwoPanePositionSnapshot?
        let found = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(10)) {
            observed = try? await positionSnapshot(page)
            guard let observed else { return false }
            let activeText = activeMode == "file" ? observed.fileStatusText : observed.reviewStatusText
            let inactiveText = activeMode == "file" ? observed.reviewStatusText : observed.fileStatusText
            return observed.activeMode == activeMode
                && activeText == expectedText
                && inactiveText == nil
        }
        guard found, let observed else {
            throw JourneyError.conditionFailed("active-surface updating chrome was not isolated")
        }
        return observed
    }

    private static func requireNoUpdatingStatus(
        _ page: WebPage
    ) async throws -> BridgeProductWebKitTwoPanePositionSnapshot {
        var observed: BridgeProductWebKitTwoPanePositionSnapshot?
        let found = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(10)) {
            observed = try? await positionSnapshot(page)
            return observed?.fileStatusText == nil && observed?.reviewStatusText == nil
        }
        guard found, let observed else {
            throw JourneyError.conditionFailed("loaded-hidden pane retained updating chrome")
        }
        return observed
    }

    private static func requirePositionSnapshot(
        _ page: WebPage
    ) async throws -> BridgeProductWebKitTwoPanePositionSnapshot {
        guard let snapshot = try await positionSnapshot(page) else {
            throw JourneyError.conditionFailed("WebKit position snapshot was unavailable")
        }
        return snapshot
    }

    private static func positionSnapshot(
        _ page: WebPage
    ) async throws -> BridgeProductWebKitTwoPanePositionSnapshot? {
        let encoded = try await page.callJavaScript(
            """
            const queryOpen = (root, selector) => {
              const direct = root.querySelector(selector);
              if (direct !== null) return direct;
              for (const element of root.querySelectorAll('*')) {
                if (element.shadowRoot === null) continue;
                const nested = queryOpen(element.shadowRoot, selector);
                if (nested !== null) return nested;
              }
              return null;
            };
            const fileHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
            const reviewHost = document.querySelector('[data-testid="bridge-viewer-mode-host-review"]');
            const fileShell = fileHost?.querySelector('[data-testid="bridge-file-viewer-shell"]');
            const fileCanvas = fileHost?.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
            const reviewShell = reviewHost?.querySelector('[data-testid="review-viewer-shell"]');
            const fileTreeScroll = fileHost === null ? null : queryOpen(fileHost, '[data-file-tree-virtualized-scroll="true"]');
            const reviewTreeScroll = reviewHost === null ? null : queryOpen(reviewHost, '[data-file-tree-virtualized-scroll="true"]');
            const fileCodeScroll = fileHost?.querySelector('.bridge-code-view-scroll-owner');
            const reviewCodeScroll = reviewHost?.querySelector('.bridge-code-view-scroll-owner');
            const collapsedDirectory = reviewHost === null
              ? null
              : queryOpen(reviewHost, '[data-item-path="Sources/Group00"][aria-expanded]');
            const activeHost = document.querySelector('[data-bridge-viewer-mode-active="true"]');
            return JSON.stringify({
              activeMode: activeHost?.getAttribute('data-bridge-viewer-mode-host') ?? null,
              fileCodeScrollTop: fileCodeScroll?.scrollTop ?? 0,
              fileRenderedPath: fileCanvas?.getAttribute('data-worktree-rendered-file-path') ?? null,
              fileSelectedPath: fileShell?.getAttribute('data-selected-display-path') ?? null,
              fileStatusText: fileHost?.querySelector('[data-testid="bridge-viewer-content-status"]')?.textContent ?? null,
              fileTreeScrollTop: fileTreeScroll?.scrollTop ?? 0,
              hasAppRoot: document.querySelector('[data-testid="bridge-app-root"]') !== null,
              reviewCodeScrollTop: reviewCodeScroll?.scrollTop ?? 0,
              reviewCollapsedDirectoryExpansion: collapsedDirectory?.getAttribute('aria-expanded') ?? null,
              reviewSelectedItemId: reviewHost?.querySelector('[data-testid="bridge-code-view-panel"]')?.getAttribute('data-selected-item-id') ?? null,
              reviewSelectedPath: reviewShell?.getAttribute('data-selected-display-path') ?? null,
              reviewStatusText: reviewHost?.querySelector('[data-testid="bridge-viewer-content-status"]')?.textContent ?? null,
              reviewTreeScrollTop: reviewTreeScroll?.scrollTop ?? 0
            });
            """
        )
        guard let encoded = encoded as? String,
            let data = encoded.data(using: .utf8)
        else { return nil }
        return try JSONDecoder().decode(BridgeProductWebKitTwoPanePositionSnapshot.self, from: data)
    }

    private static func activateReviewMode(_ page: WebPage) async -> Bool {
        (try? await page.callJavaScript(
            """
            const button = document.querySelector('[data-testid="bridge-viewer-context-review"]');
            if (!(button instanceof HTMLElement)) return false;
            button.click();
            return true;
            """
        )) as? Bool ?? false
    }

    private enum JourneyError: Error {
        case conditionFailed(String)
    }
}
