import Foundation

struct WorkspacePaneGraphPersistenceSnapshotByteEstimator: Sendable {
    private static let dynamicAllocationOverhead = 16
    private static let collectionElementOverhead = 8

    func estimate(_ paneGraph: PaneGraphState) -> Int {
        Self.saturatedSum(
            MemoryLayout<PaneGraphState>.stride,
            Self.estimatedMetadataByteCount(paneGraph.metadata),
            Self.estimatedContentByteCount(paneGraph.content),
            Self.estimatedResidencyByteCount(paneGraph.residency),
            Self.estimatedKindByteCount(paneGraph.kind)
        )
    }

    static func saturatedSum(_ values: Int...) -> Int {
        values.reduce(into: 0) { sum, value in
            let addition = sum.addingReportingOverflow(value)
            sum = addition.overflow ? Int.max : addition.partialValue
        }
    }

    static func saturatedProduct(_ value: Int, by multiplier: Int) -> Int {
        let product = value.multipliedReportingOverflow(by: multiplier)
        return product.overflow ? Int.max : product.partialValue
    }

    private static func estimatedMetadataByteCount(_ metadata: PaneGraphMetadata) -> Int {
        saturatedSum(
            estimatedStringByteCount(metadata.title),
            estimatedOptionalStringByteCount(metadata.checkoutRef),
            estimatedOptionalStringByteCount(metadata.note),
            estimatedOptionalURLByteCount(metadata.launchDirectory),
            estimatedOptionalURLByteCount(metadata.facets.cwd),
            estimatedContentTypeByteCount(metadata.contentType),
            estimatedExecutionBackendByteCount(metadata.executionBackend)
        )
    }

    private static func estimatedContentByteCount(_ content: PaneContent) -> Int {
        switch content {
        case .terminal(let terminalState):
            return estimatedStringByteCount(terminalState.zmxSessionID.rawValue)
        case .webview(let webviewState):
            return saturatedSum(
                estimatedURLByteCount(webviewState.url),
                estimatedStringByteCount(webviewState.title)
            )
        case .bridgePanel(let bridgePaneState):
            return estimatedBridgeSourceByteCount(bridgePaneState.source)
        case .codeViewer(let codeViewerState):
            return estimatedURLByteCount(codeViewerState.filePath)
        case .unsupported(let unsupportedContent):
            return saturatedSum(
                estimatedStringByteCount(unsupportedContent.type),
                unsupportedContent.rawState.map(estimatedUnsupportedValueByteCount) ?? 0
            )
        }
    }

    private static func estimatedBridgeSourceByteCount(_ source: BridgePaneSource?) -> Int {
        guard let source else { return 0 }
        switch source {
        case .commit(let sha):
            return estimatedStringByteCount(sha)
        case .branchDiff(let head, let base):
            return saturatedSum(estimatedStringByteCount(head), estimatedStringByteCount(base))
        case .workspace(let rootPath, _):
            return estimatedStringByteCount(rootPath)
        case .agentSnapshot:
            return 0
        }
    }

    private static func estimatedResidencyByteCount(_ residency: SessionResidency) -> Int {
        guard case .orphaned(.worktreeNotFound(let path)) = residency else { return 0 }
        return estimatedStringByteCount(path)
    }

    private static func estimatedKindByteCount(_ kind: PaneGraphKind) -> Int {
        guard case .layout(let drawer) = kind else { return 0 }
        return saturatedSum(
            dynamicAllocationOverhead,
            saturatedProduct(drawer.paneIds.count, by: MemoryLayout<UUID>.stride)
        )
    }

    private static func estimatedContentTypeByteCount(_ contentType: PaneContentType) -> Int {
        guard case .plugin(let pluginType) = contentType else { return 0 }
        return estimatedStringByteCount(pluginType)
    }

    private static func estimatedExecutionBackendByteCount(_ backend: ExecutionBackend) -> Int {
        switch backend {
        case .local:
            return 0
        case .docker(let image):
            return estimatedStringByteCount(image)
        case .gondolin(let policyId):
            return estimatedStringByteCount(policyId)
        case .remote(let host):
            return estimatedStringByteCount(host)
        }
    }

    private static func estimatedUnsupportedValueByteCount(_ rootValue: AnyCodableValue) -> Int {
        var pendingValues = [rootValue]
        var estimatedByteCount = 0
        while let value = pendingValues.popLast() {
            estimatedByteCount = saturatedSum(estimatedByteCount, dynamicAllocationOverhead)
            switch value {
            case .string(let string):
                estimatedByteCount = saturatedSum(estimatedByteCount, estimatedStringByteCount(string))
            case .int:
                estimatedByteCount = saturatedSum(estimatedByteCount, MemoryLayout<Int>.stride)
            case .double:
                estimatedByteCount = saturatedSum(estimatedByteCount, MemoryLayout<Double>.stride)
            case .bool:
                estimatedByteCount = saturatedSum(estimatedByteCount, MemoryLayout<Bool>.stride)
            case .array(let values):
                estimatedByteCount = saturatedSum(
                    estimatedByteCount,
                    saturatedProduct(values.count, by: collectionElementOverhead)
                )
                pendingValues.append(contentsOf: values)
            case .object(let valuesByKey):
                estimatedByteCount = saturatedSum(
                    estimatedByteCount,
                    saturatedProduct(valuesByKey.count, by: collectionElementOverhead)
                )
                for (key, childValue) in valuesByKey {
                    estimatedByteCount = saturatedSum(estimatedByteCount, estimatedStringByteCount(key))
                    pendingValues.append(childValue)
                }
            case .null:
                break
            }
        }
        return estimatedByteCount
    }

    private static func estimatedOptionalStringByteCount(_ string: String?) -> Int {
        string.map(estimatedStringByteCount) ?? 0
    }

    private static func estimatedStringByteCount(_ string: String) -> Int {
        saturatedSum(dynamicAllocationOverhead, string.utf8.count)
    }

    private static func estimatedOptionalURLByteCount(_ url: URL?) -> Int {
        url.map(estimatedURLByteCount) ?? 0
    }

    private static func estimatedURLByteCount(_ url: URL) -> Int {
        estimatedStringByteCount(url.absoluteString)
    }
}

enum WorkspaceSnapshotParticipantFactoryPolicyRejection: Error, Equatable, Sendable {
    case maximumKeyCountMustBePositive
    case maximumKeyCountMustBeFinite
    case maximumRawKeyBytesMustBePositive
    case maximumRawKeyBytesMustBeFinite
}

enum WorkspaceSnapshotParticipantFactoryPolicyResult: Equatable, Sendable {
    case constructed(WorkspaceSnapshotParticipantFactoryPolicy)
    case rejected(WorkspaceSnapshotParticipantFactoryPolicyRejection)
}

struct WorkspaceSnapshotParticipantFactoryPolicy: Equatable, Sendable {
    static let appDefault = Self(
        validatedFleetMembershipLimits: .init(
            maximumKeyCount: AppPolicies.WorkspacePersistence.snapshotMaximumKeyCount,
            maximumRawKeyBytes: AppPolicies.WorkspacePersistence.snapshotMaximumRawKeyBytes
        )
    )

    let fleetMembershipLimits: WorkspaceStateSnapshotMembershipLimits

    static func validated(
        fleetMembershipLimits: WorkspaceStateSnapshotMembershipLimits
    ) -> WorkspaceSnapshotParticipantFactoryPolicyResult {
        guard fleetMembershipLimits.maximumKeyCount > 0 else {
            return .rejected(.maximumKeyCountMustBePositive)
        }
        guard fleetMembershipLimits.maximumKeyCount < UInt64.max else {
            return .rejected(.maximumKeyCountMustBeFinite)
        }
        guard fleetMembershipLimits.maximumRawKeyBytes > 0 else {
            return .rejected(.maximumRawKeyBytesMustBePositive)
        }
        guard fleetMembershipLimits.maximumRawKeyBytes < UInt64.max else {
            return .rejected(.maximumRawKeyBytesMustBeFinite)
        }
        return .constructed(Self(validatedFleetMembershipLimits: fleetMembershipLimits))
    }

    private init(validatedFleetMembershipLimits: WorkspaceStateSnapshotMembershipLimits) {
        fleetMembershipLimits = validatedFleetMembershipLimits
    }
}

@MainActor
struct WorkspacePersistenceSnapshotParticipantSet {
    typealias Participant = WorkspaceStateSnapshotPagerParticipant<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    >

    let participants: [Participant]

    var participantIDs: [WorkspacePersistenceSnapshotParticipantID] {
        participants.map(\.participantID)
    }

    fileprivate init(participants: [Participant]) {
        self.participants = participants
    }
}

enum WorkspaceSnapshotParticipantFactoryRejection: Error, Equatable {
    case lifecycle(WorkspacePersistenceLifecycleRejection)
    case participantConstructionRejected(
        participantID: WorkspacePersistenceSnapshotParticipantID,
        rejection: WorkspaceStateSnapshotParticipantRejection
    )
    case invalidParticipantInventory(
        expected: [WorkspacePersistenceSnapshotParticipantID],
        actual: [WorkspacePersistenceSnapshotParticipantID]
    )
}

@MainActor
enum WorkspaceSnapshotParticipantFactoryResult {
    case constructed(WorkspacePersistenceSnapshotParticipantSet)
    case rejected(WorkspaceSnapshotParticipantFactoryRejection)
}

@MainActor
final class WorkspacePersistenceSnapshotParticipantFactory {
    private typealias Participant = WorkspacePersistenceSnapshotParticipantSet.Participant

    private enum InstalledDomainInventory {
        case neither
        case composition([Participant])
        case topology([Participant])
        case both(composition: [Participant], topology: [Participant])
    }

    private let adapters: WorkspacePersistenceAdapterBundle
    private let policy: WorkspaceSnapshotParticipantFactoryPolicy
    private let paneGraphByteEstimator = WorkspacePaneGraphPersistenceSnapshotByteEstimator()
    private var installedDomainInventory = InstalledDomainInventory.neither

    private(set) var installedParticipantSet: WorkspacePersistenceSnapshotParticipantSet?

    init(
        adapters: WorkspacePersistenceAdapterBundle,
        policy: WorkspaceSnapshotParticipantFactoryPolicy = .appDefault
    ) {
        self.adapters = adapters
        self.policy = policy
    }

    func constructParticipantSet() -> WorkspaceSnapshotParticipantFactoryResult {
        switch constructCompositionParticipantSet() {
        case .constructed:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }
        switch constructTopologyParticipantSet() {
        case .constructed:
            return makeInstalledParticipantSet()
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func constructCompositionParticipantSet() -> WorkspaceSnapshotParticipantFactoryResult {
        switch adapters.beginCompositionParticipantInstallation() {
        case .rejected(let rejection):
            return .rejected(.lifecycle(rejection))
        case .started(let attemptID):
            let result = buildCompositionParticipantSet()
            return finalizeComposition(result, attemptID: attemptID)
        }
    }

    func constructTopologyParticipantSet() -> WorkspaceSnapshotParticipantFactoryResult {
        switch adapters.beginTopologyParticipantInstallation() {
        case .rejected(let rejection):
            return .rejected(.lifecycle(rejection))
        case .started(let attemptID):
            let result = buildTopologyParticipantSet()
            return finalizeTopology(result, attemptID: attemptID)
        }
    }

    private func buildCompositionParticipantSet() -> WorkspaceSnapshotParticipantFactoryResult {
        var participants: [Participant] = []
        participants.reserveCapacity(10)

        switch append(adapters.workspaceIdentity.makePersistenceSnapshotParticipant(), to: &participants) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }
        switch append(adapters.workspaceWindowMemory.makePersistenceSnapshotParticipant(), to: &participants) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }

        switch append(
            adapters.workspacePaneGraph.makeSnapshotParticipant(
                membershipLimits: policy.fleetMembershipLimits,
                estimatedByteCount: { [paneGraphByteEstimator] paneGraph in
                    paneGraphByteEstimator.estimate(paneGraph)
                }
            ),
            to: &participants
        ) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }
        switch append(adapters.workspaceDrawerCursor.makePersistenceSnapshotParticipant(), to: &participants) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }
        switch append(
            adapters.workspaceTabShell.makeSnapshotParticipant(limits: policy.fleetMembershipLimits),
            to: &participants
        ) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }
        switch append(adapters.workspaceTabCursor.makePersistenceSnapshotParticipant(), to: &participants) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }
        switch append(
            adapters.workspaceTabGraph.makeSnapshotParticipant(limits: policy.fleetMembershipLimits),
            to: &participants
        ) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }

        switch adapters.workspaceArrangementCursor.makeSnapshotParticipants(
            limits: policy.fleetMembershipLimits
        ) {
        case .constructed(let cursorParticipants):
            participants.append(cursorParticipants.activeArrangements)
            participants.append(cursorParticipants.activePanes)
            participants.append(cursorParticipants.activeDrawerChildren)
        case .rejected(let rejection):
            return .rejected(
                .participantConstructionRejected(
                    participantID: .activeArrangements,
                    rejection: rejection
                ))
        }

        let expectedParticipantIDs = Self.compositionParticipantIDs
        let actualParticipantIDs = participants.map(\.participantID)
        guard
            Set(actualParticipantIDs).count == actualParticipantIDs.count,
            actualParticipantIDs == expectedParticipantIDs
        else {
            return .rejected(
                .invalidParticipantInventory(
                    expected: expectedParticipantIDs,
                    actual: actualParticipantIDs
                ))
        }

        return .constructed(WorkspacePersistenceSnapshotParticipantSet(participants: participants))
    }

    private func buildTopologyParticipantSet() -> WorkspaceSnapshotParticipantFactoryResult {
        var participants: [Participant] = []
        participants.reserveCapacity(Self.topologyParticipantIDs.count)
        switch appendRepositoryTopologyParticipants(to: &participants) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }
        guard participants.map(\.participantID) == Self.topologyParticipantIDs else {
            return .rejected(
                .invalidParticipantInventory(
                    expected: Self.topologyParticipantIDs,
                    actual: participants.map(\.participantID)
                ))
        }
        return .constructed(WorkspacePersistenceSnapshotParticipantSet(participants: participants))
    }

    private func finalizeComposition(
        _ result: WorkspaceSnapshotParticipantFactoryResult,
        attemptID: WorkspacePersistenceInstallationAttemptID
    ) -> WorkspaceSnapshotParticipantFactoryResult {
        switch result {
        case .constructed(let participantSet):
            guard case .completed = adapters.completeCompositionParticipantInstallation(attemptID) else {
                preconditionFailure("composition installation attempt changed during synchronous construction")
            }
            installCompositionInventory(participantSet.participants)
            installCombinedParticipantSetIfReady()
            return .constructed(participantSet)
        case .rejected:
            guard case .completed = adapters.failCompositionParticipantInstallation(attemptID) else {
                preconditionFailure("composition installation attempt changed during synchronous failure")
            }
            return result
        }
    }

    private func finalizeTopology(
        _ result: WorkspaceSnapshotParticipantFactoryResult,
        attemptID: WorkspacePersistenceInstallationAttemptID
    ) -> WorkspaceSnapshotParticipantFactoryResult {
        switch result {
        case .constructed(let participantSet):
            guard case .completed = adapters.completeTopologyParticipantInstallation(attemptID) else {
                preconditionFailure("topology installation attempt changed during synchronous construction")
            }
            installTopologyInventory(participantSet.participants)
            installCombinedParticipantSetIfReady()
            return .constructed(participantSet)
        case .rejected:
            guard case .completed = adapters.failTopologyParticipantInstallation(attemptID) else {
                preconditionFailure("topology installation attempt changed during synchronous failure")
            }
            return result
        }
    }

    private func makeInstalledParticipantSet() -> WorkspaceSnapshotParticipantFactoryResult {
        installCombinedParticipantSetIfReady()
        guard let installedParticipantSet else {
            preconditionFailure("combined participant installation requires both domains")
        }
        return .constructed(installedParticipantSet)
    }

    private func installCombinedParticipantSetIfReady() {
        guard case .both(let compositionParticipants, let topologyParticipants) = installedDomainInventory else {
            return
        }
        let participantsByID = Dictionary(
            uniqueKeysWithValues: (compositionParticipants + topologyParticipants).map { ($0.participantID, $0) }
        )
        let expectedParticipantIDs = WorkspacePersistenceSnapshotParticipantID.allCases
        let participants = expectedParticipantIDs.compactMap { participantsByID[$0] }
        guard participants.map(\.participantID) == expectedParticipantIDs else {
            preconditionFailure("domain participant inventories do not form the canonical combined inventory")
        }
        installedParticipantSet = WorkspacePersistenceSnapshotParticipantSet(participants: participants)
    }

    private func installCompositionInventory(_ participants: [Participant]) {
        switch installedDomainInventory {
        case .neither:
            installedDomainInventory = .composition(participants)
        case .topology(let topologyParticipants):
            installedDomainInventory = .both(composition: participants, topology: topologyParticipants)
        case .composition, .both:
            preconditionFailure("composition participant inventory installed more than once")
        }
    }

    private func installTopologyInventory(_ participants: [Participant]) {
        switch installedDomainInventory {
        case .neither:
            installedDomainInventory = .topology(participants)
        case .composition(let compositionParticipants):
            installedDomainInventory = .both(composition: compositionParticipants, topology: participants)
        case .topology, .both:
            preconditionFailure("topology participant inventory installed more than once")
        }
    }

    private static let topologyParticipantIDs: [WorkspacePersistenceSnapshotParticipantID] = [
        .repositories, .worktrees, .watchedPaths, .unavailableRepositories,
    ]

    private static let compositionParticipantIDs = WorkspacePersistenceSnapshotParticipantID.allCases.filter {
        !topologyParticipantIDs.contains($0)
    }

    private enum AppendResult {
        case appended
        case rejected(WorkspaceSnapshotParticipantFactoryRejection)
    }

    private func appendRepositoryTopologyParticipants(
        to participants: inout [Participant]
    ) -> AppendResult {
        switch adapters.repositoryTopology.makeParticipants(
            membershipLimits: policy.fleetMembershipLimits
        ) {
        case .constructed(let repositoryTopologyParticipants):
            participants.append(contentsOf: repositoryTopologyParticipants)
            return .appended
        case .rejected(let participantID, let rejection):
            return .rejected(
                .participantConstructionRejected(
                    participantID: participantID,
                    rejection: rejection
                ))
        }
    }

    private func append(
        _ result: SnapshotPagerParticipantConstructionResult<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >,
        to participants: inout [Participant]
    ) -> AppendResult {
        switch result {
        case .constructed(let participant):
            participants.append(participant)
            return .appended
        case .rejected(let rejection):
            return .rejected(
                .participantConstructionRejected(
                    participantID: expectedNextParticipantID(for: participants),
                    rejection: rejection
                ))
        }
    }

    private func expectedNextParticipantID(
        for participants: [Participant]
    ) -> WorkspacePersistenceSnapshotParticipantID {
        precondition(participants.count < Self.compositionParticipantIDs.count)
        return Self.compositionParticipantIDs[participants.count]
    }
}
