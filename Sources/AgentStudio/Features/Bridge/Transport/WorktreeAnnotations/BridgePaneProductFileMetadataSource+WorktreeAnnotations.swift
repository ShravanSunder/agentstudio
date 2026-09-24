import AgentStudioGit
import Foundation

/// The worktree annotation source of one File worktree: its Git subject,
/// descriptor-checked captures and working-tree refresh material.
extension BridgePaneProductFileMetadataSource {
    func worktreeAnnotationAdmissionDiagnostic(
        to productAdmission: BridgeProductAdmissionContext
    ) -> BridgeWorktreeAnnotationAdmissionDiagnostic {
        let relations = contextBySubscriptionId.values.map {
            $0.productAdmission.diagnosticRelation(to: productAdmission)
        }
        return BridgeWorktreeAnnotationAdmissionDiagnostic(
            relations: relations,
            selectedGeneration: try? currentAnnotationContext(
                productAdmission: productAdmission
            ).productSource.subscriptionGeneration
        )
    }

    /// The Git subject of this source's worktree.
    var worktreeAnnotationSubject: WorktreeAnnotationSubject {
        .git(
            repositoryID: authority.worktree.repoId.uuidString.lowercased(),
            worktreeID: authority.worktree.id.uuidString.lowercased()
        )
    }

    func worktreeAnnotationRefreshImplementation(
        requirements: [WorktreeAnnotationSourceRefreshRequirement],
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceRefreshCapture {
        let context = try currentAnnotationContext(productAdmission: productAdmission)
        var candidatePaths = Set<String>(
            context.descriptorByPath.compactMap { path, payload in
                guard case .available = payload.availability else { return nil }
                return path
            }
        )
        for requirement in requirements {
            switch requirement.origin {
            case .session:
                continue
            case .wholeFile(let path, let sourceRole):
                guard sourceRole == .file || sourceRole == .reviewHead else { continue }
                candidatePaths.insert(path)
            case .located(let origin):
                guard origin.sourceRole == .file || origin.sourceRole == .reviewHead else {
                    continue
                }
                candidatePaths.insert(origin.repositoryRelativePath)
            }
        }
        let candidates = candidatePaths.sorted().map { path in
            WorktreeAnnotationSourceMaterialCandidate(
                path: path,
                sourceRole: .file,
                sourceIdentity: .currentFileDescriptor,
                target: .workingTree
            )
        }
        let provider = GitWorktreeAnnotationSourceMaterialProvider(
            client: LibGit2AgentStudioGitLocalClient()
        )
        return WorktreeAnnotationSourceRefreshCapture(
            fingerprint: annotationFingerprint(for: context.productSource),
            material: await provider.material(
                .init(repositoryPath: authority.worktree.path, candidates: candidates)
            )
        )
    }

    func captureWorktreeAnnotationSource(
        origin: BridgeProductWorktreeAnnotationOrigin,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationCapturedSource {
        let context = try currentAnnotationContext(productAdmission: productAdmission)
        let fingerprint = annotationFingerprint(for: context.productSource)
        let descriptor = try annotationContentDescriptor(
            path: origin.path,
            sourceIdentity: origin.sourceIdentity,
            context: context
        )
        let data = try await WorktreeAnnotationSourceCapture.readCompleteDescribedFile(
            BridgePaneProductFileContentReadPlan(
                descriptor: descriptor,
                relativePath: origin.path,
                rootURL: authority.worktree.path
            )
        )
        return .init(
            fingerprint: fingerprint,
            origin: .located(
                try WorktreeAnnotationSourceCapture.locatedOrigin(
                    .init(
                        data: data,
                        path: origin.path,
                        startLine: origin.startLine,
                        endLine: origin.endLine,
                        sourceRole: origin.sourceRole.domainValue,
                        diffSide: origin.diffSide?.domainValue,
                        sourceIdentity: origin.sourceIdentity
                    )
                )
            )
        )
    }

    func worktreeAnnotationFingerprintImplementation(
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceFingerprint {
        let context = try currentAnnotationContext(productAdmission: productAdmission)
        return annotationFingerprint(for: context.productSource)
    }

    func worktreeAnnotationSourceGenerationImplementation(
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> Int {
        try currentAnnotationContext(productAdmission: productAdmission)
            .productSource.subscriptionGeneration
    }

    private func currentAnnotationContext(
        productAdmission: BridgeProductAdmissionContext
    ) throws -> SubscriptionContext {
        let contexts = contextBySubscriptionId.values.filter {
            $0.productAdmission.matches(productAdmission)
        }
        guard
            let context = contexts.max(by: {
                $0.productSource.subscriptionGeneration < $1.productSource.subscriptionGeneration
            })
        else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        return context
    }

    private func annotationFingerprint(
        for productSource: BridgeProductFileSourceIdentity
    ) -> WorktreeAnnotationSourceFingerprint {
        WorktreeAnnotationSourceFingerprint(
            subject: worktreeAnnotationSubject,
            fileSourceIdentity: productSource.sourceId,
            reviewComparisonOrigin: nil
        )
    }

    private func annotationContentDescriptor(
        path: String,
        sourceIdentity: String,
        context: SubscriptionContext
    ) throws -> BridgeProductFileContentDescriptor {
        guard
            let payload = context.descriptorByPath[path],
            payload.source == context.productSource,
            case .available(let descriptor) = payload.availability,
            descriptor.descriptorId == sourceIdentity
        else {
            throw WorktreeAnnotationSourceResolutionError.invalidSource
        }
        return descriptor
    }
}
