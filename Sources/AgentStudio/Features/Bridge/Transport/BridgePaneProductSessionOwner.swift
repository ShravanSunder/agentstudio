import Foundation
import Security

struct BridgeProductSessionInstallation: Sendable {
    let bootstrap: BridgeProductSessionBootstrap
    let capabilityBytes: [UInt8]
    let productAdmissionGate: BridgeProductAdmissionGate
    let productAdapter: BridgeProductSchemeAdapter
    let session: BridgeProductSession

    static func make(
        paneSessionId: String,
        provider: any BridgeProductSchemeProvider,
        productAdmissionGate: BridgeProductAdmissionGate,
        telemetryRecorder: (any BridgePerformanceTraceRecording)? = nil
    ) throws -> Self {
        var capabilityBytes = [UInt8](
            repeating: 0,
            count: BridgeProductWireContract.capabilityByteLength
        )
        let randomStatus = capabilityBytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
        }
        guard randomStatus == errSecSuccess else {
            throw BridgePaneProductSessionOwnerError.secureRandomGenerationFailed(randomStatus)
        }

        let bootstrap = BridgeProductSessionBootstrap(
            paneSessionId: paneSessionId,
            workerInstanceId: UUID().uuidString
        )
        let session = try BridgeProductSession(
            paneSessionId: paneSessionId,
            workerInstanceId: bootstrap.workerInstanceId,
            capabilityBytes: capabilityBytes
        )
        return Self(
            bootstrap: bootstrap,
            capabilityBytes: capabilityBytes,
            productAdmissionGate: productAdmissionGate,
            productAdapter: BridgeProductSchemeAdapter(
                session: session,
                provider: provider,
                productAdmissionGate: productAdmissionGate,
                telemetryRecorder: telemetryRecorder
            ),
            session: session
        )
    }
}

enum BridgePaneProductSessionOwnerError: Error, Equatable {
    case ownerDisposed
    case secureRandomGenerationFailed(OSStatus)
}

enum BridgePaneProductSessionActivationResult: Equatable, Sendable {
    case activated
    case invalidCandidate
    case ownerDisposed
    case revocationFailed
}

enum BridgePaneProductSessionRetirementReason: Equatable, Sendable {
    case paneDisposal
    case pageReload
    case workerReplacement
}

enum BridgePaneProductSessionRetirementResult: Equatable, Sendable {
    case retired
    case revocationFailed
}

struct BridgePaneProductSessionOwnerSnapshot: Equatable, Sendable {
    let activeSchemeTaskCount: Int
    let activeProducerCount: Int
    let activeProducerTaskCount: Int
    let activeContentLeaseCount: Int
    let activeTransportLeaseCount: Int
    let queuedFrameCount: Int
    let queuedByteCount: Int
    let pendingFrameWaiterCount: Int
    let inFlightFrameReceiptCount: Int
    let pendingLifecycleAcknowledgementCount: Int
    let preparedInstallationCount: Int
    let sessionContentAdmissionCount: Int
    let sessionProductAdmissionCount: Int
    let nextMetadataStreamSequence: Int

    var hasZeroResidue: Bool {
        activeSchemeTaskCount == 0
            && activeProducerCount == 0
            && activeProducerTaskCount == 0
            && activeContentLeaseCount == 0
            && activeTransportLeaseCount == 0
            && queuedFrameCount == 0
            && queuedByteCount == 0
            && pendingFrameWaiterCount == 0
            && inFlightFrameReceiptCount == 0
            && pendingLifecycleAcknowledgementCount == 0
            && preparedInstallationCount == 0
            && sessionContentAdmissionCount == 0
            && sessionProductAdmissionCount == 0
    }

    static let empty = Self(
        activeSchemeTaskCount: 0,
        activeProducerCount: 0,
        activeProducerTaskCount: 0,
        activeContentLeaseCount: 0,
        activeTransportLeaseCount: 0,
        queuedFrameCount: 0,
        queuedByteCount: 0,
        pendingFrameWaiterCount: 0,
        inFlightFrameReceiptCount: 0,
        pendingLifecycleAcknowledgementCount: 0,
        preparedInstallationCount: 0,
        sessionContentAdmissionCount: 0,
        sessionProductAdmissionCount: 0,
        nextMetadataStreamSequence: 0
    )
}

actor BridgePaneProductSessionOwner {
    let schemeRouter: BridgeProductSchemeSessionRouter
    nonisolated let productAdmissionGate: BridgeProductAdmissionGate

    private(set) var activeInstallation: BridgeProductSessionInstallation?
    private var activationInFlightWorkerInstanceIds: Set<String> = []
    private var isPaneDisposalRequested = false
    private var lifecycleTransitionTail: Task<Void, Never>?
    private let paneSessionId: String
    private var preparedInstallationsByWorkerInstanceId: [String: BridgeProductSessionInstallation] = [:]
    private let provider: any BridgeProductSchemeProvider
    private let telemetryRecorder: (any BridgePerformanceTraceRecording)?
    private var installationAwaitingRetirementRetry: BridgeProductSessionInstallation?

    func activeBootstrap() -> BridgeProductSessionBootstrap? {
        activeInstallation?.bootstrap
    }

    init(
        paneSessionId: String,
        provider: any BridgeProductSchemeProvider,
        productAdmissionGate: BridgeProductAdmissionGate,
        activeInstallation: BridgeProductSessionInstallation? = nil,
        telemetryRecorder: (any BridgePerformanceTraceRecording)? = nil
    ) throws {
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: [])
        precondition(
            activeInstallation == nil
                || activeInstallation?.productAdmissionGate === productAdmissionGate
        )
        self.paneSessionId = paneSessionId
        self.provider = provider
        self.telemetryRecorder = telemetryRecorder
        self.productAdmissionGate = productAdmissionGate
        self.activeInstallation = activeInstallation
        self.schemeRouter = BridgeProductSchemeSessionRouter(
            activeInstallation: activeInstallation,
            productAdmissionGate: productAdmissionGate
        )
    }

    func prepareCandidate(
        productAdmission: BridgeProductAdmissionContext
    ) throws -> BridgeProductSessionInstallation {
        guard productAdmission.wasMinted(by: productAdmissionGate),
            let candidate = try productAdmission.withValidAdmission({
                guard !isPaneDisposalRequested else {
                    throw BridgePaneProductSessionOwnerError.ownerDisposed
                }
                let candidate = try BridgeProductSessionInstallation.make(
                    paneSessionId: paneSessionId,
                    provider: provider,
                    productAdmissionGate: productAdmissionGate,
                    telemetryRecorder: telemetryRecorder
                )
                preparedInstallationsByWorkerInstanceId[candidate.bootstrap.workerInstanceId] = candidate
                return candidate
            })
        else {
            throw BridgePaneProductSessionOwnerError.ownerDisposed
        }
        return candidate
    }

    func activatePreparedCandidate(
        _ candidate: BridgeProductSessionInstallation,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgePaneProductSessionActivationResult {
        let workerInstanceId = candidate.bootstrap.workerInstanceId
        guard
            let preparedCandidate = preparedInstallationsByWorkerInstanceId[workerInstanceId],
            preparedCandidate.bootstrap == candidate.bootstrap,
            preparedCandidate.capabilityBytes == candidate.capabilityBytes,
            !activationInFlightWorkerInstanceIds.contains(workerInstanceId)
        else {
            return .invalidCandidate
        }
        guard productAdmission.wasMinted(by: productAdmissionGate),
            (productAdmission.withValidAdmission {
                activationInFlightWorkerInstanceIds.insert(workerInstanceId)
                return true
            }) == true
        else {
            return await rejectPreparedCandidateAfterAdmissionClose(candidate)
        }
        guard !isPaneDisposalRequested else {
            return await rejectPreparedCandidateAfterAdmissionClose(preparedCandidate)
        }

        let precedingTransition = lifecycleTransitionTail
        let transition = Task { [self] in
            if let precedingTransition {
                await precedingTransition.value
            }
            return await performActivation(
                preparedCandidate,
                productAdmission: productAdmission
            )
        }
        lifecycleTransitionTail = Task {
            _ = await transition.value
        }
        return await transition.value
    }

    func retire(
        reason: BridgePaneProductSessionRetirementReason
    ) async -> BridgePaneProductSessionRetirementResult {
        if reason == .paneDisposal {
            isPaneDisposalRequested = true
        }
        let precedingTransition = lifecycleTransitionTail
        let transition = Task { [self] in
            if let precedingTransition {
                await precedingTransition.value
            }
            return await performRetirement()
        }
        lifecycleTransitionTail = Task {
            _ = await transition.value
        }
        return await transition.value
    }

    private func performActivation(
        _ candidate: BridgeProductSessionInstallation,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgePaneProductSessionActivationResult {
        let workerInstanceId = candidate.bootstrap.workerInstanceId
        defer {
            activationInFlightWorkerInstanceIds.remove(workerInstanceId)
        }
        guard !isPaneDisposalRequested,
            (productAdmission.withValidAdmission { true }) == true
        else {
            return await rejectPreparedCandidateAfterAdmissionClose(candidate)
        }

        let retiringInstallation = installationAwaitingRetirementRetry ?? activeInstallation
        guard
            (productAdmission.withValidAdmission {
                activeInstallation = nil
                return true
            }) == true
        else {
            return await rejectPreparedCandidateAfterAdmissionClose(candidate)
        }
        await schemeRouter.clear()

        if let retiringInstallation,
            retiringInstallation.bootstrap.workerInstanceId != candidate.bootstrap.workerInstanceId
        {
            installationAwaitingRetirementRetry = retiringInstallation
            let barrier = await retiringInstallation.session.revoke(
                acknowledgeLifecycle: provider.acknowledgeLifecycle
            )
            guard await barrier.wait() else {
                await schemeRouter.waitForDrain()
                return .revocationFailed
            }
        }
        await schemeRouter.waitForDrain()

        guard !isPaneDisposalRequested,
            (productAdmission.withValidAdmission { true }) == true
        else {
            return await rejectPreparedCandidateAfterAdmissionClose(candidate)
        }

        guard
            (productAdmission.withValidAdmission {
                installationAwaitingRetirementRetry = nil
                preparedInstallationsByWorkerInstanceId.removeValue(forKey: workerInstanceId)
                activeInstallation = candidate
                return true
            }) == true
        else {
            return await rejectPreparedCandidateAfterAdmissionClose(candidate)
        }
        guard
            await schemeRouter.activate(
                candidate,
                productAdmission: productAdmission
            )
        else {
            activeInstallation = nil
            return await rejectPreparedCandidateAfterAdmissionClose(candidate)
        }
        return .activated
    }

    private func rejectPreparedCandidateAfterAdmissionClose(
        _ candidate: BridgeProductSessionInstallation
    ) async -> BridgePaneProductSessionActivationResult {
        let workerInstanceId = candidate.bootstrap.workerInstanceId
        preparedInstallationsByWorkerInstanceId.removeValue(forKey: workerInstanceId)
        activationInFlightWorkerInstanceIds.remove(workerInstanceId)
        let barrier = await candidate.session.revoke(
            acknowledgeLifecycle: provider.acknowledgeLifecycle
        )
        _ = await barrier.wait()
        return .ownerDisposed
    }

    private func performRetirement() async -> BridgePaneProductSessionRetirementResult {
        let retiringInstallation = installationAwaitingRetirementRetry ?? activeInstallation
        activeInstallation = nil
        await schemeRouter.clear()
        guard let retiringInstallation else {
            await schemeRouter.waitForDrain()
            return await retirePreparedInstallationsForPaneDisposal()
                ? .retired
                : .revocationFailed
        }

        installationAwaitingRetirementRetry = retiringInstallation
        let barrier = await retiringInstallation.session.revoke(
            acknowledgeLifecycle: provider.acknowledgeLifecycle
        )
        guard await barrier.wait() else {
            await schemeRouter.waitForDrain()
            return .revocationFailed
        }
        await schemeRouter.waitForDrain()
        installationAwaitingRetirementRetry = nil
        return await retirePreparedInstallationsForPaneDisposal()
            ? .retired
            : .revocationFailed
    }

    private func retirePreparedInstallationsForPaneDisposal() async -> Bool {
        guard isPaneDisposalRequested else { return true }
        for (workerInstanceId, installation) in preparedInstallationsByWorkerInstanceId {
            let barrier = await installation.session.revoke(
                acknowledgeLifecycle: provider.acknowledgeLifecycle
            )
            guard await barrier.wait() else { return false }
            preparedInstallationsByWorkerInstanceId.removeValue(forKey: workerInstanceId)
        }
        return true
    }

    func snapshot() async -> BridgePaneProductSessionOwnerSnapshot {
        let routerSnapshot = await schemeRouter.snapshot
        let installation = installationAwaitingRetirementRetry ?? activeInstallation
        let producers = await installation?.session.producerSnapshot()
        return .init(
            activeSchemeTaskCount: routerSnapshot.activeSchemeTaskCount,
            activeProducerCount: producers?.activeProducerCount ?? 0,
            activeProducerTaskCount: producers?.activeProducerTaskCount ?? 0,
            activeContentLeaseCount: producers?.activeContentLeaseCount ?? 0,
            activeTransportLeaseCount: routerSnapshot.activeTransportClaimCount,
            queuedFrameCount: producers?.queuedFrameCount ?? 0,
            queuedByteCount: producers?.queuedByteCount ?? 0,
            pendingFrameWaiterCount: producers?.pendingFrameWaiterCount ?? 0,
            inFlightFrameReceiptCount: producers?.inFlightFrameReceiptCount ?? 0,
            pendingLifecycleAcknowledgementCount: producers?.pendingLifecycleAcknowledgementCount ?? 0,
            preparedInstallationCount: preparedInstallationsByWorkerInstanceId.count,
            sessionContentAdmissionCount: producers?.sessionContentAdmissionCount ?? 0,
            sessionProductAdmissionCount: producers?.sessionProductAdmissionCount ?? 0,
            nextMetadataStreamSequence: producers?.nextMetadataStreamSequence ?? 0
        )
    }
}
