import AgentStudioCore
import Foundation

/// One member worktree's File source inside a receiver's collection.
struct BridgeFileCollectionMemberSource: Sendable {
    let member: BridgeFileCollectionMember
    /// The member source's own collection token (its worktree stable key).
    let memberCollectionToken: String
    let producer: any BridgePaneProductFileMetadataProducing
}

/// How one member of the collection fared in the current subscription.
enum BridgeFileCollectionMemberAvailability: Equatable, Sendable {
    case available
    /// The member's source failed; other members stay browsable (R2 partial coverage).
    case failed
}

typealias BridgeFileCollectionOpenedDocumentRowReader =
    @Sendable (BridgeDocumentLocation) async -> BridgeWorktreeTreeRowMetadata?

/// The Files source of one receiving Bridge: every member worktree plus the
/// individually opened documents outside them, published under one wire
/// collection identity.
///
/// Each member keeps its own unchanged per-worktree source, identity, ignore
/// policy and descriptor validation; this facade only re-keys their output and
/// routes requests back. An opened document authorizes exactly its own file.
actor BridgeFileCollectionSource: BridgePaneProductFileMetadataProducing {
    struct IssuedDescriptor: Sendable {
        enum Origin: Sendable {
            case member(worktreeId: UUID, memberDescriptor: BridgeProductFileContentDescriptor)
            case openedDocument(BridgeDocumentLocation)
        }

        let collectionDescriptor: BridgeProductFileContentDescriptor
        let displayPath: String
        let origin: Origin
    }

    struct SubscriptionContext: Sendable {
        let productSource: BridgeProductFileSourceIdentity
        let productAdmission: BridgeProductAdmissionContext
        let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
        let emit: BridgePaneProductFileMetadataEventSink
        var subscription: BridgeProductSubscriptionSnapshot
        /// Next positional index while the initial tree is still being
        /// enumerated; nil once the collection's final window was sent.
        var enumerationIndex: Int?
        var openedMemberIds: Set<UUID> = []
        var memberAvailability: [UUID: BridgeFileCollectionMemberAvailability] = [:]
        var emittedPathsBySource: [CollectionRowSource: Set<String>] = [:]
        var issuedDescriptorsById: [String: IssuedDescriptor] = [:]
        var openedDocumentInterestRevisionByPath: [String: Int] = [:]
    }

    let collectionToken: String
    let descriptorMaterializer: BridgePaneProductFileDescriptorMaterializer
    let openedDocumentRowReader: BridgeFileCollectionOpenedDocumentRowReader
    var sourceAcceptedObserver: BridgePaneProductFileSourceAcceptedObserver
    var layout = BridgeFileCollectionLayout.empty
    var memberSourcesById: [UUID: BridgeFileCollectionMemberSource] = [:]
    var openedDocumentLocations: [BridgeDocumentLocation] = []
    var contextBySubscriptionId: [String: SubscriptionContext] = [:]
    var nextSourceGeneration = 0

    init(
        collectionToken: String,
        members: [BridgeFileCollectionMemberSource],
        openedDocuments: [BridgeDocumentLocation],
        sourceAcceptedObserver: @escaping BridgePaneProductFileSourceAcceptedObserver = { _ in },
        descriptorMaterializer: @escaping BridgePaneProductFileDescriptorMaterializer =
            BridgePaneProductFileContentSource.materialize,
        openedDocumentRowReader: @escaping BridgeFileCollectionOpenedDocumentRowReader =
            BridgeFileCollectionSource.readOpenedDocumentRow
    ) {
        self.collectionToken = collectionToken
        self.descriptorMaterializer = descriptorMaterializer
        self.openedDocumentRowReader = openedDocumentRowReader
        self.sourceAcceptedObserver = sourceAcceptedObserver
        self.memberSourcesById = Dictionary(
            members.map { ($0.member.worktreeId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.openedDocumentLocations = openedDocuments
        self.layout = BridgeFileCollectionLayout.empty.updating(
            members: members.map(\.member),
            openedDocuments: openedDocuments
        )
    }

    func setSourceAcceptedObserver(
        _ observer: @escaping BridgePaneProductFileSourceAcceptedObserver
    ) {
        sourceAcceptedObserver = observer
    }

    func memberAvailability(subscriptionId: String) -> [UUID: BridgeFileCollectionMemberAvailability] {
        contextBySubscriptionId[subscriptionId]?.memberAvailability ?? [:]
    }

    func currentSource() -> BridgeProductFileSourceCurrentResult {
        .available(BridgeProductFileSourceSpec(currentCollectionToken: collectionToken))
    }

    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        try Task.checkCancellation()
        guard subscription.subscription.fileMetadataSource != nil,
            subscription.interestState.fileMetadataState != nil
        else { return }
        await cancel(subscriptionId: subscription.subscriptionId)
        try Task.checkCancellation()
        nextSourceGeneration += 1
        let generation = nextSourceGeneration
        let productSource = try BridgeProductFileSourceIdentity(
            collectionToken: collectionToken,
            rootRevisionToken: nil,
            sourceCursor: "collection-cursor-\(generation)",
            sourceId: "collection-source-\(generation)",
            subscriptionGeneration: generation
        )
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true,
            (productAdmission.withValidAdmission { true }) == true
        else { return }
        contextBySubscriptionId[subscription.subscriptionId] = SubscriptionContext(
            productSource: productSource,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            emit: emit,
            subscription: subscription,
            enumerationIndex: 0
        )
        do {
            try await emit(.sourceAccepted(.init(source: productSource)))
            await sourceAcceptedObserver(productSource)
            for group in layout.memberGroups {
                try await openMember(group.worktreeId, subscriptionId: subscription.subscriptionId)
            }
            try await emitOpenedDocumentRows(
                layout.openedDocuments,
                subscriptionId: subscription.subscriptionId
            )
            try await completeInitialEnumeration(subscriptionId: subscription.subscriptionId)
        } catch {
            await cancel(subscriptionId: subscription.subscriptionId)
            throw error
        }
    }

    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        guard var context = contextBySubscriptionId[subscription.subscriptionId],
            context.productAdmission.matches(productAdmission),
            subscription.interestRevision >= context.subscription.interestRevision,
            foregroundWorkAdmission.withValidAdmission({ true }) == true
        else { return }
        context.subscription = subscription
        contextBySubscriptionId[subscription.subscriptionId] = context
        for group in layout.memberGroups where context.openedMemberIds.contains(group.worktreeId) {
            try await updateMember(group.worktreeId, subscriptionId: subscription.subscriptionId)
        }
        try await publishDemandedOpenedDocumentDescriptors(subscriptionId: subscription.subscriptionId)
    }

    func cancel(subscriptionId: String) async {
        guard let context = contextBySubscriptionId.removeValue(forKey: subscriptionId) else { return }
        for worktreeId in context.openedMemberIds {
            await memberSourcesById[worktreeId]?.producer.cancel(subscriptionId: subscriptionId)
        }
    }

    func publish(
        status: GitWorkingTreeStatus,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> [BridgePaneProductFileMetadataEmission] {
        guard let statusMemberId = layout.memberGroups.first?.worktreeId else { return [] }
        return await publish(
            status: status,
            forWorktreeId: statusMemberId,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
    }

    /// Status for one member worktree. Only the first member drives the
    /// collection's branch summary; every member's path statuses apply to its rows.
    func publish(
        status: GitWorkingTreeStatus,
        forWorktreeId worktreeId: UUID,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> [BridgePaneProductFileMetadataEmission] {
        guard let memberSource = memberSourcesById[worktreeId] else { return [] }
        let emissions = await memberSource.producer.publish(
            status: status,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
        return (try? translatedEmissions(emissions, fromMember: worktreeId)) ?? []
    }

    func publish(
        changeset: FileChangeset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws -> [BridgePaneProductFileMetadataEmission] {
        guard let memberSource = memberSourcesById[changeset.worktreeId] else { return [] }
        let emissions = try await memberSource.producer.publish(
            changeset: changeset,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
        return try translatedEmissions(emissions, fromMember: changeset.worktreeId)
    }

    func authoritativePath(
        for request: BridgeProductFileContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> String? {
        // Async like the protocol requirement, so no async default outranks it.
        issuedDescriptor(for: request, productAdmission: productAdmission)?.displayPath
    }

    func contentReadPlan(
        for request: BridgeProductFileContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgePaneProductFileContentReadPlan? {
        guard let issued = issuedDescriptor(for: request, productAdmission: productAdmission) else {
            return nil
        }
        switch issued.origin {
        case .member(let worktreeId, let memberDescriptor):
            guard
                let memberPlan = await memberSourcesById[worktreeId]?.producer.contentReadPlan(
                    for: request.replacingDescriptor(memberDescriptor),
                    productAdmission: productAdmission
                )
            else { return nil }
            return BridgePaneProductFileContentReadPlan(
                descriptor: request.descriptor,
                relativePath: memberPlan.relativePath,
                rootURL: memberPlan.rootURL
            )
        case .openedDocument(let location):
            return BridgePaneProductFileContentReadPlan(
                descriptor: request.descriptor,
                relativePath: location.displayName,
                rootURL: location.fileURL.deletingLastPathComponent()
            )
        }
    }

    private func issuedDescriptor(
        for request: BridgeProductFileContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) -> IssuedDescriptor? {
        productAdmission.withValidAdmission { () -> IssuedDescriptor? in
            for context in contextBySubscriptionId.values
            where context.productSource == request.descriptor.source
                && context.productAdmission.matches(productAdmission)
            {
                guard let issued = context.issuedDescriptorsById[request.descriptor.descriptorId],
                    issued.collectionDescriptor == request.descriptor
                else { return nil }
                return issued
            }
            return nil
        }.flatMap { $0 }
    }

    static func readOpenedDocumentRow(
        _ location: BridgeDocumentLocation
    ) async -> BridgeWorktreeTreeRowMetadata? {
        await BridgeWorktreeFileMaterializer.refreshTreeRows(
            rootURL: location.fileURL.deletingLastPathComponent(),
            relativePaths: [location.displayName]
        ).rows.first { !$0.isDirectory }
    }
}
