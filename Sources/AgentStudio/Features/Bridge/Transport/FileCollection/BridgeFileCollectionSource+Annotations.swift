import AgentStudioCore
import Foundation

// S8: interim routing until local-file annotation subjects land; remove the
// first-member fallback in S8 before this branch becomes a PR.
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
        // The page names the collection's descriptor; the member validates and
        // stores its own descriptor identity for the same content.
        guard
            let memberDescriptor = issuedMemberDescriptor(
                collectionDescriptorId: origin.sourceIdentity,
                worktreeId: worktreeId,
                displayPath: origin.path,
                productAdmission: productAdmission
            )
        else {
            throw WorktreeAnnotationSourceResolutionError.invalidSource
        }
        return try await memberSource.producer.captureWorktreeAnnotationSource(
            origin: BridgeProductWorktreeAnnotationOrigin(
                path: relativePath,
                startLine: origin.startLine,
                endLine: origin.endLine,
                sourceRole: origin.sourceRole,
                diffSide: origin.diffSide,
                sourceIdentity: memberDescriptor.descriptorId
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

    /// The page names the collection's subscription generation, not a
    /// member's, so the generation comes from the collection's own announced
    /// subscription.
    func currentWorktreeAnnotationSourceGeneration(
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> Int {
        guard
            let generation = contextBySubscriptionId.values
                .filter({ $0.collectionSourceAccepted && $0.productAdmission.matches(productAdmission) })
                .map(\.productSource.subscriptionGeneration)
                .max()
        else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        return generation
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

    private func issuedMemberDescriptor(
        collectionDescriptorId: String,
        worktreeId: UUID,
        displayPath: String,
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgeProductFileContentDescriptor? {
        for context in contextBySubscriptionId.values where context.productAdmission.matches(productAdmission) {
            guard let issued = context.issuedDescriptorsById[collectionDescriptorId],
                issued.displayPath == displayPath,
                case .member(worktreeId, let memberDescriptor) = issued.origin
            else { continue }
            return memberDescriptor
        }
        return nil
    }

    // S8: first-member fallback for non-path annotation facts; S8 replaces it.
    private func annotationMember() throws -> BridgeFileCollectionMemberSource {
        guard let worktreeId = layout.memberGroups.first?.worktreeId,
            let memberSource = memberSourcesById[worktreeId]
        else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        return memberSource
    }
}
