import AgentStudioCore
import Foundation

enum BridgePaneProductFileMetadataSourceError: Error, Equatable {
    case unavailableAuthority
}

struct BridgePaneProductFileSourceAuthority: Sendable {
    let paneId: UUID
    let worktree: Worktree
}

struct BridgePaneProductFileMetadataEmission: Sendable {
    let event: BridgeProductFileMetadataEvent
    let subscriptionId: String
}

typealias BridgePaneProductFileMetadataEventSink =
    @Sendable (BridgeProductFileMetadataEvent) async throws -> Void

typealias BridgePaneProductFileSourceAcceptedObserver =
    @Sendable (BridgeProductFileSourceIdentity) async -> Void

typealias BridgePaneProductFileIgnorePolicyLoader =
    @Sendable (URL) async -> BridgeWorktreeFileIgnorePolicy

typealias BridgePaneProductFileSnapshotPreparationLoader =
    @Sendable (URL, BridgeGitReadContext) async -> BridgeSharedFileSnapshotPreparation

typealias BridgePaneProductFileSharedSnapshotBuilder =
    @Sendable (
        BridgeWorktreeFileMaterializationRequest,
        BridgeSharedFileSnapshotPreparation,
        BridgeSharedFileSnapshotPublisher
    ) async throws -> BridgeSharedFileSnapshotCompletion

typealias BridgePaneProductFileTreeRowRefresher =
    @Sendable (URL, Set<String>, Bool) async -> BridgeWorktreeRefreshedTreeRows

struct BridgeFileMetadataSourceDiagnostics: Equatable, Sendable {
    let descriptorCount: Int
    let inFlightDescriptorCount: Int
    let manifestRowCount: Int
    let subscriptionCount: Int
}

protocol BridgePaneProductFileMetadataProducing: Sendable {
    func currentSource() async -> BridgeProductFileSourceCurrentResult
    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws
    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws
    func cancel(subscriptionId: String) async
    func publish(
        status: GitWorkingTreeStatus,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> [BridgePaneProductFileMetadataEmission]
    func publish(
        changeset: FileChangeset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws -> [BridgePaneProductFileMetadataEmission]
    func authoritativePath(
        for request: BridgeProductFileContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> String?
    func contentReadPlan(
        for request: BridgeProductFileContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgePaneProductFileContentReadPlan?
    func captureWorktreeAnnotationSource(
        origin: BridgeProductWorktreeAnnotationOrigin,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationCapturedSource
    /// The annotation subjects the File surface shows now, under the key
    /// the page knows them by.
    func worktreeAnnotationScope() async throws -> WorktreeAnnotationScope
    func currentWorktreeAnnotationFingerprint(
        subject: WorktreeAnnotationSubject,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceFingerprint
    func currentWorktreeAnnotationSourceGeneration(
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> Int
    func currentWorktreeAnnotationRefresh(
        subject: WorktreeAnnotationSubject,
        requirements: [WorktreeAnnotationSourceRefreshRequirement],
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceRefreshCapture
}

extension BridgePaneProductFileMetadataProducing {
    func authoritativePath(
        for _: BridgeProductFileContentRequest,
        productAdmission _: BridgeProductAdmissionContext
    ) async -> String? { nil }

    func captureWorktreeAnnotationSource(
        origin _: BridgeProductWorktreeAnnotationOrigin,
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationCapturedSource {
        throw WorktreeAnnotationSourceResolutionError.unavailable
    }

    func worktreeAnnotationScope() async throws -> WorktreeAnnotationScope {
        throw WorktreeAnnotationSourceResolutionError.unavailable
    }

    func currentWorktreeAnnotationFingerprint(
        subject _: WorktreeAnnotationSubject,
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceFingerprint {
        throw WorktreeAnnotationSourceResolutionError.unavailable
    }

    func currentWorktreeAnnotationSourceGeneration(
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> Int {
        throw WorktreeAnnotationSourceResolutionError.unavailable
    }

    func currentWorktreeAnnotationRefresh(
        subject _: WorktreeAnnotationSubject,
        requirements _: [WorktreeAnnotationSourceRefreshRequirement],
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceRefreshCapture {
        throw WorktreeAnnotationSourceResolutionError.unavailable
    }
}

actor BridgeUnavailablePaneProductFileMetadataSource: BridgePaneProductFileMetadataProducing {
    func currentSource() -> BridgeProductFileSourceCurrentResult {
        .unavailable(.noFileSourceAuthority)
    }

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        throw BridgePaneProductFileMetadataSourceError.unavailableAuthority
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        throw BridgePaneProductFileMetadataSourceError.unavailableAuthority
    }

    func cancel(subscriptionId _: String) {}

    func publish(
        status _: GitWorkingTreeStatus,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission
    ) -> [BridgePaneProductFileMetadataEmission] { [] }

    func publish(
        changeset _: FileChangeset,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission
    ) async throws -> [BridgePaneProductFileMetadataEmission] { [] }

    func authoritativePath(
        for _: BridgeProductFileContentRequest,
        productAdmission _: BridgeProductAdmissionContext
    ) -> String? { nil }

    func contentReadPlan(
        for _: BridgeProductFileContentRequest,
        productAdmission _: BridgeProductAdmissionContext
    ) -> BridgePaneProductFileContentReadPlan? { nil }
}

extension BridgeProductDemandLane {
    static let fileMetadataPriorityOrder: [Self] = [
        .foreground, .active, .visible, .nearby, .speculative, .idle,
    ]

    var priority: Int {
        Self.fileMetadataPriorityOrder.firstIndex(of: self) ?? Int.max
    }
}
