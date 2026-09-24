import AgentStudioCore
import Foundation

/// Annotations in a Files collection belong to their own subjects: a member
/// file to that member worktree's Git subject, a loose opened document to its
/// own local-file subject. Every read routes to the one source that owns the
/// subject and never falls back to another member. A local document is read
/// only through a descriptor that authorizes exactly that file.
extension BridgeFileCollectionSource {
    /// Every member's Git subject plus one local subject per loose opened
    /// document, under the receiver's collection token.
    func worktreeAnnotationScope() async throws -> WorktreeAnnotationScope {
        ensureInitialLayout()
        var subjects = Set(layout.openedDocuments.map { WorktreeAnnotationSubject.localFile($0.location) })
        for group in layout.memberGroups {
            guard let memberSource = memberSourcesById[group.worktreeId],
                let memberScope = try? await memberSource.producer.worktreeAnnotationScope()
            else { continue }
            subjects.formUnion(memberScope.subjects)
        }
        return WorktreeAnnotationScope(key: collectionToken, subjects: subjects)
    }

    func captureWorktreeAnnotationSource(
        origin: BridgeProductWorktreeAnnotationOrigin,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationCapturedSource {
        switch layout.resolve(displayPath: origin.path) {
        case .memberPath(let worktreeId, let relativePath):
            return try await captureMemberAnnotationSource(
                origin: origin,
                worktreeId: worktreeId,
                relativePath: relativePath,
                productAdmission: productAdmission
            )
        case .openedDocument(let location):
            return try await captureLocalAnnotationSource(
                origin: origin,
                location: location,
                productAdmission: productAdmission
            )
        case .memberGroup, .openedDocumentsGroup, nil:
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
    }

    func currentWorktreeAnnotationFingerprint(
        subject: WorktreeAnnotationSubject,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceFingerprint {
        switch subject {
        case .git:
            return try await memberSource(for: subject).producer.currentWorktreeAnnotationFingerprint(
                subject: subject,
                productAdmission: productAdmission
            )
        case .localFile(let location):
            return try await currentLocalDocument(location, productAdmission: productAdmission).fingerprint
        }
    }

    /// The page names the collection's subscription generation, not a
    /// member's, so the generation comes from the collection's own announced
    /// subscription.
    func currentWorktreeAnnotationSourceGeneration(
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> Int {
        try annotationContext(productAdmission: productAdmission).productSource.subscriptionGeneration
    }

    func currentWorktreeAnnotationRefresh(
        subject: WorktreeAnnotationSubject,
        requirements: [WorktreeAnnotationSourceRefreshRequirement],
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceRefreshCapture {
        switch subject {
        case .git:
            return try await memberSource(for: subject).producer.currentWorktreeAnnotationRefresh(
                subject: subject,
                requirements: requirements,
                productAdmission: productAdmission
            )
        case .localFile(let location):
            let current = try await currentLocalDocument(location, productAdmission: productAdmission)
            return WorktreeAnnotationSourceRefreshCapture(
                fingerprint: current.fingerprint,
                material: current.material
            )
        }
    }

    private func captureMemberAnnotationSource(
        origin: BridgeProductWorktreeAnnotationOrigin,
        worktreeId: UUID,
        relativePath: String,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationCapturedSource {
        guard let memberSource = memberSourcesById[worktreeId] else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        // The page names the collection's descriptor; the member validates and
        // stores its own descriptor identity for the same content.
        guard
            let issued = issuedAnnotationDescriptor(
                collectionDescriptorId: origin.sourceIdentity,
                displayPath: origin.path,
                productAdmission: productAdmission
            ),
            case .member(worktreeId, let memberDescriptor) = issued.origin
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

    /// A loose document's annotation names the document itself: its path is
    /// the document's name and its source identity is derived from the exact
    /// bytes the page's descriptor authorized.
    private func captureLocalAnnotationSource(
        origin: BridgeProductWorktreeAnnotationOrigin,
        location: BridgeDocumentLocation,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationCapturedSource {
        guard
            let issued = issuedAnnotationDescriptor(
                collectionDescriptorId: origin.sourceIdentity,
                displayPath: origin.path,
                productAdmission: productAdmission
            ),
            case .openedDocument(location) = issued.origin
        else {
            throw WorktreeAnnotationSourceResolutionError.invalidSource
        }
        let data = try await WorktreeAnnotationSourceCapture.readCompleteDescribedFile(
            Self.localDocumentReadPlan(location, descriptor: issued.collectionDescriptor)
        )
        let contentSHA256 = issued.collectionDescriptor.expectedSha256
        return WorktreeAnnotationCapturedSource(
            fingerprint: Self.localFingerprint(location, contentSHA256: contentSHA256),
            origin: .located(
                try WorktreeAnnotationSourceCapture.locatedOrigin(
                    .init(
                        data: data,
                        path: location.displayName,
                        startLine: origin.startLine,
                        endLine: origin.endLine,
                        sourceRole: origin.sourceRole.domainValue,
                        diffSide: origin.diffSide?.domainValue,
                        sourceIdentity: Self.localSourceIdentity(location, contentSHA256: contentSHA256)
                    )
                )
            )
        )
    }

    private struct CurrentLocalDocument {
        let fingerprint: WorktreeAnnotationSourceFingerprint
        let material: WorktreeAnnotationSourceMaterial
    }

    /// Read a loose document's current bytes under a freshly issued descriptor
    /// for exactly that file. A document that is no longer listed is not
    /// readable at all; one that is listed but unreadable, binary or changing
    /// under the read keeps its annotations with unavailable placement.
    private func currentLocalDocument(
        _ location: BridgeDocumentLocation,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> CurrentLocalDocument {
        guard let entry = layout.openedDocuments.first(where: { $0.location == location }) else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        let context = try annotationContext(productAdmission: productAdmission)
        let unavailable = CurrentLocalDocument(
            fingerprint: Self.localFingerprint(location, contentSHA256: nil),
            material: .unavailable
        )
        guard
            let payload = try? await openedDocumentPayload(entry, source: context.productSource),
            case .available(let descriptor) = payload.availability,
            let data = try? await WorktreeAnnotationSourceCapture.readCompleteDescribedFile(
                Self.localDocumentReadPlan(location, descriptor: descriptor)
            ),
            let body = String(bytes: data, encoding: .utf8)
        else {
            return unavailable
        }
        return CurrentLocalDocument(
            fingerprint: Self.localFingerprint(location, contentSHA256: descriptor.expectedSha256),
            material: .available([
                WorktreeAnnotationCurrentSourceFile(
                    path: location.displayName,
                    sourceRole: .file,
                    sourceIdentity: Self.localSourceIdentity(location, contentSHA256: descriptor.expectedSha256),
                    body: body
                )
            ])
        )
    }

    private func memberSource(for subject: WorktreeAnnotationSubject) throws -> BridgeFileCollectionMemberSource {
        guard let worktreeID = subject.gitWorktreeID.flatMap(UUID.init(uuidString:)),
            layout.memberGroup(for: worktreeID) != nil,
            let memberSource = memberSourcesById[worktreeID]
        else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        return memberSource
    }

    private func annotationContext(productAdmission: BridgeProductAdmissionContext) throws -> SubscriptionContext {
        guard
            let context = contextBySubscriptionId.values
                .filter({ $0.collectionSourceAccepted && $0.productAdmission.matches(productAdmission) })
                .max(by: { $0.productSource.subscriptionGeneration < $1.productSource.subscriptionGeneration })
        else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        return context
    }

    private func issuedAnnotationDescriptor(
        collectionDescriptorId: String,
        displayPath: String,
        productAdmission: BridgeProductAdmissionContext
    ) -> IssuedDescriptor? {
        for context in contextBySubscriptionId.values where context.productAdmission.matches(productAdmission) {
            guard let issued = context.issuedDescriptorsById[collectionDescriptorId],
                issued.displayPath == displayPath
            else { continue }
            return issued
        }
        return nil
    }

    private static func localDocumentReadPlan(
        _ location: BridgeDocumentLocation,
        descriptor: BridgeProductFileContentDescriptor
    ) -> BridgePaneProductFileContentReadPlan {
        BridgePaneProductFileContentReadPlan(
            descriptor: descriptor,
            relativePath: location.displayName,
            rootURL: location.fileURL.deletingLastPathComponent()
        )
    }

    private static func localFingerprint(
        _ location: BridgeDocumentLocation,
        contentSHA256: String?
    ) -> WorktreeAnnotationSourceFingerprint {
        WorktreeAnnotationSourceFingerprint(
            subject: .localFile(location),
            fileSourceIdentity: contentSHA256,
            reviewComparisonOrigin: nil
        )
    }

    private static func localSourceIdentity(_ location: BridgeDocumentLocation, contentSHA256: String) -> String {
        BridgePaneProductFileContentSource.stableDescriptorId(
            relativePath: location.displayName,
            sourceSHA256: contentSHA256
        )
    }
}
