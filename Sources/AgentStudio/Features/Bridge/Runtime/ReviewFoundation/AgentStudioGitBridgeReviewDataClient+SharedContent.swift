import AgentStudioGit
import AgentStudioInfrastructure
import Foundation

extension AgentStudioGitBridgeReviewDataClient: BridgeSharedReviewConstructionClient {
    func captureSharedContent(
        handles: [BridgeContentHandle],
        freshnessKey _: BridgeGitReadFreshnessKey
    ) async throws -> BridgeSharedReviewContentBacking {
        let registrations:
            [(
                handle: BridgeContentHandle,
                locatorIdentity: ContentLocatorIdentity,
                locator: ContentLocator
            )] = try handles.map { handle in
                let locatorIdentity = contentLocatorIdentity(for: handle)
                guard let locator = liveLocatorByIdentity[locatorIdentity] else {
                    throw BridgeSharedReviewContentBackingError.missingLocator
                }
                return (handle, locatorIdentity, locator)
            }
        defer {
            for registration in registrations
            where liveLocatorByIdentity[registration.locatorIdentity]?.registrationIdentity
                == registration.locator.registrationIdentity
            {
                liveLocatorByIdentity.removeValue(forKey: registration.locatorIdentity)
            }
        }
        var sourceByIdentity: [BridgeSharedReviewContentIdentity: BridgeSharedReviewContentSource] = [:]
        for registration in registrations {
            let handle = registration.handle
            let identity = BridgeSharedReviewContentIdentity(
                itemIdentity: handle.itemId,
                role: handle.role,
                contentHash: handle.contentHash
            )
            switch registration.locator.source {
            case .shared:
                throw BridgeSharedReviewContentBackingError.invalidated
            case .live(let target, let path):
                sourceByIdentity[identity] = .gitTarget(
                    target: target,
                    path: path,
                    declaredContentHash: handle.contentHash,
                    declaredContentHashAlgorithm: handle.contentHashAlgorithm
                )
            }
        }
        return BridgeSharedReviewContentBacking(
            artifactIdentity: UUIDv7.generate(),
            sourceByIdentity: sourceByIdentity
        )
    }

    func installSharedContent(
        backing: BridgeSharedReviewContentBacking,
        handles: [BridgeContentHandle]
    ) async throws {
        var installedLocatorIdentities: [ContentLocatorIdentity] = []
        for handle in handles {
            let identity = BridgeSharedReviewContentIdentity(
                itemIdentity: handle.itemId,
                role: handle.role,
                contentHash: handle.contentHash
            )
            _ = try backing.source(for: identity)
            let locatorIdentity = contentLocatorIdentity(for: handle)
            let locator = ContentLocator(
                registrationIdentity: backing.artifactIdentity,
                source: .shared(backing: backing, identity: identity),
                reviewGeneration: handle.reviewGeneration
            )
            // A fresh comparison registers live locators before shared
            // construction acquisition. A reused template does not collect
            // those locators again, so installing its backing must consume
            // the now-superseded live locator for this exact handle identity.
            liveLocatorByIdentity.removeValue(forKey: locatorIdentity)
            if sharedLocatorStackByIdentity[locatorIdentity]?.contains(where: {
                $0.registrationIdentity == backing.artifactIdentity
            }) != true {
                sharedLocatorStackByIdentity[locatorIdentity, default: []].append(locator)
                installedLocatorIdentities.append(locatorIdentity)
            }
        }
        guard !installedLocatorIdentities.isEmpty else { return }
        let locatorIdentitiesToUninstall = installedLocatorIdentities
        guard
            backing.registerUninstallOperation({ [weak self] in
                await self?.uninstallSharedContent(
                    backingArtifactIdentity: backing.artifactIdentity,
                    locatorIdentities: locatorIdentitiesToUninstall
                )
            })
        else {
            uninstallSharedContent(
                backingArtifactIdentity: backing.artifactIdentity,
                locatorIdentities: locatorIdentitiesToUninstall
            )
            throw BridgeSharedReviewContentBackingError.invalidated
        }
    }

    func registeredContentLocatorCount() -> Int {
        liveLocatorByIdentity.count
            + sharedLocatorStackByIdentity.values.reduce(0) { $0 + $1.count }
    }

    func loadContent(_ request: BridgeContentLoadRequest) async throws -> BridgeContentLoadResult {
        let locators = contentLocators(for: request.handle)
        guard let firstLocator = locators.first else {
            throw BridgeProviderFailure.missingContent(handleId: request.handle.handleId)
        }
        guard firstLocator.reviewGeneration == request.requestedGeneration,
            request.handle.reviewGeneration == request.requestedGeneration
        else {
            throw BridgeProviderFailure.staleReviewGeneration(
                storedGeneration: firstLocator.reviewGeneration,
                requestedGeneration: request.requestedGeneration
            )
        }
        for locator in locators {
            do {
                let content = try await contentPayload(
                    for: locator,
                    handle: request.handle,
                    requestedGeneration: request.requestedGeneration
                )
                return BridgeContentLoadResult(
                    handle: request.handle,
                    data: content.data,
                    mimeType: request.handle.mimeType,
                    contentHash: request.handle.contentHash,
                    contentHashAlgorithm: request.handle.contentHashAlgorithm
                )
            } catch BridgeSharedReviewContentBackingError.invalidated {
                continue
            }
        }
        throw BridgeSharedReviewContentBackingError.invalidated
    }

    func contentPayload(
        for locator: ContentLocator,
        handle: BridgeContentHandle,
        requestedGeneration: BridgeReviewGeneration
    ) async throws -> GitContentPayload {
        switch locator.source {
        case .live(let target, let path):
            return try await loadGitContent(
                GitContentRequest(
                    repositoryPath: repositoryPath,
                    target: target,
                    path: path,
                    maxSizeBytes: Int64(AppPolicies.Bridge.contentMaxBytesPerItem)
                ),
                handle: handle,
                freshnessKey: gitReadFreshnessKey(for: requestedGeneration)
            )
        case .shared(let backing, let identity):
            switch try backing.source(for: identity) {
            case .gitTarget(
                let target,
                let path,
                let declaredContentHash,
                let declaredContentHashAlgorithm
            ):
                let payload = try await loadGitContent(
                    GitContentRequest(
                        repositoryPath: repositoryPath,
                        target: target,
                        path: path,
                        maxSizeBytes: Int64(AppPolicies.Bridge.contentMaxBytesPerItem)
                    ),
                    handle: handle,
                    freshnessKey: gitReadFreshnessKey(for: requestedGeneration),
                    physicalReadLease: {
                        try backing.acquireRead(for: identity)
                    }
                )
                guard handle.contentHash == declaredContentHash,
                    handle.contentHashAlgorithm == declaredContentHashAlgorithm
                else {
                    throw BridgeSharedReviewContentBackingError.digestMismatch
                }
                try Self.validate(payload: payload, handle: handle)
                return payload
            }
        }
    }

    private static func validate(
        payload: GitContentPayload,
        handle: BridgeContentHandle
    ) throws {
        let computedContentHash: String
        do {
            computedContentHash = try bridgeComputedContentHash(
                for: payload.data,
                algorithm: handle.contentHashAlgorithm
            )
        } catch {
            throw BridgeSharedReviewContentBackingError.digestMismatch
        }
        guard computedContentHash == handle.contentHash else {
            throw BridgeProviderFailure.contentHashMismatch(
                handleId: handle.handleId,
                expectedHash: handle.contentHash,
                actualHash: computedContentHash
            )
        }
        guard !handle.sizeBytesIsExact || payload.data.count == handle.sizeBytes else {
            throw BridgeSharedReviewContentBackingError.digestMismatch
        }
    }

    private func uninstallSharedContent(
        backingArtifactIdentity: UUID,
        locatorIdentities: [ContentLocatorIdentity]
    ) {
        for locatorIdentity in locatorIdentities {
            guard let locators = sharedLocatorStackByIdentity[locatorIdentity] else {
                continue
            }
            let retainedLocators = locators.filter {
                $0.registrationIdentity != backingArtifactIdentity
            }
            if retainedLocators.isEmpty {
                sharedLocatorStackByIdentity.removeValue(forKey: locatorIdentity)
            } else {
                sharedLocatorStackByIdentity[locatorIdentity] = retainedLocators
            }
        }
    }

}
