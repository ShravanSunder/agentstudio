import AgentStudioInfrastructure
import Foundation

enum BridgeAnnotationProjectionSourceError: Error, Equatable, Sendable {
    case descriptorMismatch
    case invalidCursor
    case projectionCaptureUnavailable
    case initialSourceGenerationUnavailable
    case revalidatedSourceGenerationUnavailable
    case sourceRefreshUnavailable
    case staleSourceGeneration(currentSourceGeneration: Int)
    case unavailable
}

struct BridgePaneProductWorktreeAnnotationProjectionPage: Sendable {
    var cursor: BridgeProductAnnotationProjectionPageRecordCursor
    let descriptor: BridgeProductAnnotationProjectionContentDescriptor
}

actor BridgeAnnotationProjectionSource {
    typealias CurrentSourceGeneration =
        @Sendable (BridgeProductSurface, BridgeProductAdmissionContext) async throws -> Int

    private struct RequestAuthority: Equatable, Sendable {
        let paneSessionID: String
        let wireVersion: Int
        let workerDerivationEpoch: Int
        let workerInstanceID: String

        init?(issuing request: BridgeProductControlRequest) {
            guard let workerDerivationEpoch = request.workerDerivationEpoch else { return nil }
            paneSessionID = request.paneSessionId
            wireVersion = request.correlation.wireVersion
            self.workerDerivationEpoch = workerDerivationEpoch
            workerInstanceID = request.workerInstanceId
        }

        func matches(_ request: BridgeProductAnnotationProjectionContentRequest) -> Bool {
            paneSessionID == request.paneSessionID
                && wireVersion == request.wireVersion
                && workerDerivationEpoch == request.workerDerivationEpoch
                && workerInstanceID == request.workerInstanceID
        }
    }

    private struct LogicalReservation: Sendable {
        let analysis: BridgeProductAnnotationProjectionRecordAnalysis
        let authority: RequestAuthority
        let demandedSessionIDs: [UUID]
        let snapshotID: UUID
        let sourceGeneration: Int
        let surface: BridgeProductSurface
        var continuationReady: Bool
        var nextCursor: String?
        var nextPageOrdinal: Int
    }

    private struct PageReservation: Sendable {
        let authority: RequestAuthority
        let cursor: BridgeProductAnnotationProjectionPageRecordCursor
        let descriptor: BridgeProductAnnotationProjectionContentDescriptor
        let snapshotID: UUID
    }

    static let unavailable = BridgeAnnotationProjectionSource(
        service: nil,
        sourceResolver: .unavailable,
        worktreeID: "",
        currentSourceGeneration: { _, _ in
            throw BridgeAnnotationProjectionSourceError.unavailable
        }
    )

    private let currentSourceGeneration: CurrentSourceGeneration
    private let service: WorktreeAnnotationServiceActor?
    private let sourceResolver: WorktreeAnnotationSourceResolver
    private let worktreeID: String
    private var logicalReservation: LogicalReservation?
    private var pageReservationByDescriptorID: [String: PageReservation] = [:]

    init(
        service: WorktreeAnnotationServiceActor?,
        sourceResolver: WorktreeAnnotationSourceResolver,
        worktreeID: String,
        currentSourceGeneration: @escaping CurrentSourceGeneration
    ) {
        self.currentSourceGeneration = currentSourceGeneration
        self.service = service
        self.sourceResolver = sourceResolver
        self.worktreeID = worktreeID
    }

    func descriptor(
        for query: BridgeProductAnnotationProjectionQueryRequest,
        issuing request: BridgeProductControlRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgeProductAnnotationProjectionContentDescriptor {
        guard let authority = RequestAuthority(issuing: request),
            request.surface == query.surface,
            let service,
            !worktreeID.isEmpty
        else {
            throw BridgeAnnotationProjectionSourceError.unavailable
        }
        let currentGeneration: Int
        do {
            currentGeneration = try await currentSourceGeneration(query.surface, productAdmission)
        } catch {
            throw BridgeAnnotationProjectionSourceError.initialSourceGenerationUnavailable
        }
        guard currentGeneration == query.sourceGeneration else {
            throw BridgeAnnotationProjectionSourceError.staleSourceGeneration(
                currentSourceGeneration: currentGeneration
            )
        }

        if let cursor = query.cursor {
            return try issueContinuationDescriptor(
                cursor: cursor,
                authority: authority,
                demandedSessionIDs: query.sessionIDs,
                surface: query.surface,
                sourceGeneration: currentGeneration
            )
        }

        let demandedSessionIDs = query.sessionIDs.map(WorktreeAnnotationSessionID.init(rawValue:))
        let serviceCapture: WorktreeAnnotationServiceProjectionCapture
        do {
            serviceCapture = try await service.captureProjection(
                worktreeID: worktreeID,
                demandedSessionIDs: demandedSessionIDs
            )
        } catch {
            throw BridgeAnnotationProjectionSourceError.projectionCaptureUnavailable
        }
        let requirements = serviceCapture.repositorySnapshot.details.flatMap { detail in
            WorktreeAnnotationServiceActor.sourceRefreshSnapshot(from: detail).requirements
        }
        let sourceCapture: WorktreeAnnotationSourceRefreshCapture
        do {
            sourceCapture = try await sourceResolver.refresh(
                query.surface,
                productAdmission,
                requirements
            )
        } catch {
            throw BridgeAnnotationProjectionSourceError.sourceRefreshUnavailable
        }
        let revalidatedGeneration: Int
        do {
            revalidatedGeneration = try await currentSourceGeneration(
                query.surface,
                productAdmission
            )
        } catch {
            throw BridgeAnnotationProjectionSourceError.revalidatedSourceGenerationUnavailable
        }
        guard revalidatedGeneration == currentGeneration else {
            throw BridgeAnnotationProjectionSourceError.staleSourceGeneration(
                currentSourceGeneration: revalidatedGeneration
            )
        }
        let placements = try evaluatePlacements(
            details: serviceCapture.repositorySnapshot.details,
            surface: query.surface,
            sourceGeneration: currentGeneration,
            sourceCapture: sourceCapture
        )
        let capture = BridgeProductAnnotationProjectionCapture(
            worktreeID: worktreeID,
            recoveryStatus: projectionRecoveryStatus(serviceCapture.recoveryState),
            sessions: serviceCapture.repositorySnapshot.sessions,
            details: serviceCapture.repositorySnapshot.details,
            placementsByThreadID: placements,
            projectionRevision: serviceCapture.revision,
            sourceGeneration: currentGeneration
        )
        let analysis = try BridgeProductAnnotationProjectionRecordAnalysis(capture: capture)
        let snapshotID = UUIDv7.generate()
        logicalReservation = LogicalReservation(
            analysis: analysis,
            authority: authority,
            demandedSessionIDs: query.sessionIDs,
            snapshotID: snapshotID,
            sourceGeneration: currentGeneration,
            surface: query.surface,
            continuationReady: false,
            nextCursor: nil,
            nextPageOrdinal: 0
        )
        pageReservationByDescriptorID.removeAll(keepingCapacity: true)
        return try issueDescriptor(pageOrdinal: 0)
    }

    func claim(
        _ request: BridgeProductAnnotationProjectionContentRequest
    ) throws -> BridgePaneProductWorktreeAnnotationProjectionPage {
        let descriptorID = request.descriptor.descriptorID
        guard let reservation = pageReservationByDescriptorID.removeValue(forKey: descriptorID),
            reservation.descriptor == request.descriptor,
            reservation.authority.matches(request)
        else {
            throw BridgeAnnotationProjectionSourceError.descriptorMismatch
        }
        if !reservation.descriptor.page.isLastPage,
            logicalReservation?.snapshotID == reservation.snapshotID
        {
            logicalReservation?.continuationReady = true
        }
        return BridgePaneProductWorktreeAnnotationProjectionPage(
            cursor: reservation.cursor,
            descriptor: reservation.descriptor
        )
    }

    func placementsForOutput(
        sessionID: WorktreeAnnotationSessionID,
        surface: BridgeProductSurface,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection] {
        guard let service else {
            throw BridgeAnnotationProjectionSourceError.unavailable
        }
        let detail = try await service.outputSessionDetail(sessionID: sessionID)
        let sourceGeneration = try await currentSourceGeneration(surface, productAdmission)
        let requirements = WorktreeAnnotationServiceActor.sourceRefreshSnapshot(from: detail).requirements
        let sourceCapture = try await sourceResolver.refresh(
            surface,
            productAdmission,
            requirements
        )
        let revalidatedGeneration = try await currentSourceGeneration(surface, productAdmission)
        guard revalidatedGeneration == sourceGeneration else {
            throw BridgeAnnotationProjectionSourceError.staleSourceGeneration(
                currentSourceGeneration: revalidatedGeneration
            )
        }
        return try evaluatePlacements(
            details: [detail],
            surface: surface,
            sourceGeneration: sourceGeneration,
            sourceCapture: sourceCapture
        )
    }

    func close() {
        logicalReservation = nil
        pageReservationByDescriptorID.removeAll(keepingCapacity: false)
    }

    private func issueContinuationDescriptor(
        cursor: String,
        authority: RequestAuthority,
        demandedSessionIDs: [UUID],
        surface: BridgeProductSurface,
        sourceGeneration: Int
    ) throws -> BridgeProductAnnotationProjectionContentDescriptor {
        guard let reservation = logicalReservation,
            reservation.authority == authority,
            reservation.demandedSessionIDs == demandedSessionIDs,
            reservation.surface == surface,
            reservation.sourceGeneration == sourceGeneration,
            reservation.continuationReady,
            reservation.nextCursor == cursor
        else {
            throw BridgeAnnotationProjectionSourceError.invalidCursor
        }
        logicalReservation?.nextCursor = nil
        logicalReservation?.continuationReady = false
        return try issueDescriptor(pageOrdinal: reservation.nextPageOrdinal)
    }

    private func issueDescriptor(
        pageOrdinal: Int
    ) throws -> BridgeProductAnnotationProjectionContentDescriptor {
        guard var reservation = logicalReservation,
            pageOrdinal == reservation.nextPageOrdinal,
            pageOrdinal < reservation.analysis.pageCount
        else {
            throw BridgeAnnotationProjectionSourceError.invalidCursor
        }
        let isLastPage = pageOrdinal + 1 == reservation.analysis.pageCount
        let nextCursor = isLastPage ? nil : UUIDv7.generate().uuidString.lowercased()
        let pageContract = try BridgeProductAnnotationProjectionPageContract(
            aggregateSHA256: reservation.analysis.aggregateSHA256,
            expectedMessageCount: reservation.analysis.expectedMessageCount,
            expectedSessionCount: reservation.analysis.expectedSessionCount,
            expectedThreadCount: reservation.analysis.expectedThreadCount,
            isLastPage: isLastPage,
            nextCursor: nextCursor,
            pageOrdinal: pageOrdinal,
            projectionRevision: reservation.analysis.projectionRevision,
            snapshotID: reservation.snapshotID,
            sourceGeneration: reservation.sourceGeneration
        )
        let descriptor = try BridgeProductAnnotationProjectionContentDescriptor(
            descriptorID: UUIDv7.generate().uuidString.lowercased(),
            maximumBytes: reservation.analysis.pageByteCount(pageOrdinal: pageOrdinal),
            page: pageContract,
            surface: reservation.surface
        )
        pageReservationByDescriptorID[descriptor.descriptorID] = PageReservation(
            authority: reservation.authority,
            cursor: try reservation.analysis.makePageCursor(pageOrdinal: pageOrdinal),
            descriptor: descriptor,
            snapshotID: reservation.snapshotID
        )
        reservation.nextCursor = nextCursor
        reservation.nextPageOrdinal = pageOrdinal + 1
        logicalReservation = isLastPage ? nil : reservation
        return descriptor
    }

    private func evaluatePlacements(
        details: [WorktreeAnnotationSessionDetail],
        surface: BridgeProductSurface,
        sourceGeneration: Int,
        sourceCapture: WorktreeAnnotationSourceRefreshCapture
    ) throws -> [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection] {
        var placements: [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection] = [:]
        for detail in details {
            let evaluation = try WorktreeAnnotationSourceEvaluator.evaluate(
                .init(
                    session: detail.session,
                    threads: detail.threads.map(\.thread),
                    surface: surface,
                    sourceEpoch: String(sourceGeneration),
                    currentFingerprint: sourceCapture.fingerprint,
                    material: sourceCapture.material
                )
            )
            placements.merge(evaluation.placements) { _, replacement in replacement }
        }
        return placements
    }

    private func projectionRecoveryStatus(
        _ state: WorktreeAnnotationRecoveryState
    ) -> BridgeProductAnnotationProjectionRecoveryStatus {
        switch state {
        case .available: .available
        case .recoveredDegraded: .recoveredDegraded
        case .unavailable: .unavailable
        }
    }
}
