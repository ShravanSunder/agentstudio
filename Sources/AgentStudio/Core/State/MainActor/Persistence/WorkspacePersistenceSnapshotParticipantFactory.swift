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
            return estimatedOptionalStringByteCount(terminalState.zmxSessionId)
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
    case constructionAlreadyAttempted
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

    private enum ConstructionState {
        case available
        case attempted
    }

    private let workspaceIdentityAtom: WorkspaceIdentityAtom
    private let workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom
    private let repositoryTopologyAtom: RepositoryTopologyAtom
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom
    private let workspaceTabShellAtom: WorkspaceTabShellAtom
    private let workspaceTabCursorAtom: WorkspaceTabCursorAtom
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let policy: WorkspaceSnapshotParticipantFactoryPolicy
    private let paneGraphByteEstimator = WorkspacePaneGraphPersistenceSnapshotByteEstimator()
    private var constructionState = ConstructionState.available

    private(set) var installedParticipantSet: WorkspacePersistenceSnapshotParticipantSet?

    init(
        workspaceIdentityAtom: WorkspaceIdentityAtom,
        workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyAtom: RepositoryTopologyAtom,
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom,
        workspaceTabShellAtom: WorkspaceTabShellAtom,
        workspaceTabCursorAtom: WorkspaceTabCursorAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        policy: WorkspaceSnapshotParticipantFactoryPolicy = .appDefault
    ) {
        self.workspaceIdentityAtom = workspaceIdentityAtom
        self.workspaceWindowMemoryAtom = workspaceWindowMemoryAtom
        self.repositoryTopologyAtom = repositoryTopologyAtom
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        self.workspaceDrawerCursorAtom = workspaceDrawerCursorAtom
        self.workspaceTabShellAtom = workspaceTabShellAtom
        self.workspaceTabCursorAtom = workspaceTabCursorAtom
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        self.policy = policy
    }

    func constructParticipantSet() -> WorkspaceSnapshotParticipantFactoryResult {
        guard case .available = constructionState else {
            return .rejected(.constructionAlreadyAttempted)
        }
        constructionState = .attempted

        var participants: [Participant] = []
        participants.reserveCapacity(WorkspacePersistenceSnapshotParticipantID.allCases.count)

        switch append(workspaceIdentityAtom.makePersistenceSnapshotParticipant(), to: &participants) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }
        switch append(workspaceWindowMemoryAtom.makePersistenceSnapshotParticipant(), to: &participants) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }

        switch appendRepositoryTopologyParticipants(to: &participants) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }

        switch append(
            workspacePaneGraphAtom.makePersistenceSnapshotParticipant(
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
        switch append(workspaceDrawerCursorAtom.makePersistenceSnapshotParticipant(), to: &participants) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }
        switch append(
            workspaceTabShellAtom.makePersistenceSnapshotParticipant(limits: policy.fleetMembershipLimits),
            to: &participants
        ) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }
        switch append(workspaceTabCursorAtom.makePersistenceSnapshotParticipant(), to: &participants) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }
        switch append(
            workspaceTabGraphAtom.makePersistenceSnapshotParticipant(limits: policy.fleetMembershipLimits),
            to: &participants
        ) {
        case .appended:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }

        switch workspaceArrangementCursorAtom.makePersistenceSnapshotParticipants(
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

        let expectedParticipantIDs = WorkspacePersistenceSnapshotParticipantID.allCases
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

        let participantSet = WorkspacePersistenceSnapshotParticipantSet(participants: participants)
        installedParticipantSet = participantSet
        return .constructed(participantSet)
    }

    private enum AppendResult {
        case appended
        case rejected(WorkspaceSnapshotParticipantFactoryRejection)
    }

    private func appendRepositoryTopologyParticipants(
        to participants: inout [Participant]
    ) -> AppendResult {
        switch repositoryTopologyAtom.makeSnapshotParticipants(
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
        let expectedParticipantIDs = WorkspacePersistenceSnapshotParticipantID.allCases
        precondition(participants.count < expectedParticipantIDs.count)
        return expectedParticipantIDs[participants.count]
    }
}
