import AgentStudioCore
import Foundation

/// Worktree annotations stay per member worktree: a capture resolves its
/// collection path back to the owning member, and the remaining source facts
/// come from the collection's first member. Opened documents outside every
/// member have no worktree annotation source.
extension BridgeFileCollectionSource {
    func captureWorktreeAnnotationSource(
        origin: BridgeProductWorktreeAnnotationOrigin,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationCapturedSource {
        guard case .memberPath(let worktreeId, let relativePath) = layout.resolve(displayPath: origin.path),
            let memberSource = memberSourcesById[worktreeId]
        else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        return try await memberSource.producer.captureWorktreeAnnotationSource(
            origin: BridgeProductWorktreeAnnotationOrigin(
                path: relativePath,
                startLine: origin.startLine,
                endLine: origin.endLine,
                sourceRole: origin.sourceRole,
                diffSide: origin.diffSide,
                sourceIdentity: origin.sourceIdentity
            ),
            productAdmission: productAdmission
        )
    }

    func currentWorktreeAnnotationFingerprint(
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceFingerprint {
        try await annotationMember().producer.currentWorktreeAnnotationFingerprint(
            productAdmission: productAdmission
        )
    }

    func currentWorktreeAnnotationSourceGeneration(
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> Int {
        try await annotationMember().producer.currentWorktreeAnnotationSourceGeneration(
            productAdmission: productAdmission
        )
    }

    func currentWorktreeAnnotationRefresh(
        requirements: [WorktreeAnnotationSourceRefreshRequirement],
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceRefreshCapture {
        try await annotationMember().producer.currentWorktreeAnnotationRefresh(
            requirements: requirements,
            productAdmission: productAdmission
        )
    }

    func worktreeAnnotationRepositoryPath() async throws -> URL {
        try await annotationMember().producer.worktreeAnnotationRepositoryPath()
    }

    private func annotationMember() throws -> BridgeFileCollectionMemberSource {
        guard let worktreeId = layout.memberGroups.first?.worktreeId,
            let memberSource = memberSourcesById[worktreeId]
        else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        return memberSource
    }
}
