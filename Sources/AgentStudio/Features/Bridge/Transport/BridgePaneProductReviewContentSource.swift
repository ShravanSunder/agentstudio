import Foundation

enum BridgePaneProductReviewContentSourceError: Error, Equatable {
    case unavailablePackage
    case descriptorMismatch
    case declaredByteLengthMismatch(expected: Int, actual: Int)
    case expectedSHA256Mismatch(expected: String, actual: String)
    case wholeByteLengthMismatch(expected: Int, actual: Int)
}

struct BridgePaneProductReviewContentBody: Equatable, Sendable {
    let data: Data
    let descriptor: BridgeProductReviewContentDescriptor
    let isFinalRange: Bool
    let sha256: String
    let wholeByteLength: Int
}

protocol BridgePaneProductReviewContentProducing: Sendable {
    func replaceAuthority(
        with availability: BridgePaneProductReviewMetadataAvailability
    ) async throws
    func authoritativeItemId(
        for request: BridgeProductReviewContentRequest
    ) async -> String?
    func contentBody(
        for request: BridgeProductReviewContentRequest
    ) async throws -> BridgePaneProductReviewContentBody
}

struct BridgeUnavailablePaneProductReviewContentSource: BridgePaneProductReviewContentProducing {
    func replaceAuthority(
        with _: BridgePaneProductReviewMetadataAvailability
    ) async throws {}

    func authoritativeItemId(
        for _: BridgeProductReviewContentRequest
    ) async -> String? { nil }

    func contentBody(
        for _: BridgeProductReviewContentRequest
    ) async throws -> BridgePaneProductReviewContentBody {
        throw BridgePaneProductReviewContentSourceError.unavailablePackage
    }
}

actor BridgePaneProductReviewContentSource: BridgePaneProductReviewContentProducing {
    private struct IssuedDescriptorAuthority: Equatable, Sendable {
        let handle: BridgeContentHandle
        let packageId: String
        let reviewGeneration: Int
        let sourceIdentity: String
    }

    private let contentStore: BridgeContentStore
    private var authorityByDescriptorId: [String: IssuedDescriptorAuthority] = [:]
    private var hasAvailableAuthority = false

    init(contentStore: BridgeContentStore) {
        self.contentStore = contentStore
    }

    func replaceAuthority(
        with availability: BridgePaneProductReviewMetadataAvailability
    ) async throws {
        guard case .ready(let package) = availability else {
            hasAvailableAuthority = false
            authorityByDescriptorId.removeAll(keepingCapacity: false)
            return
        }

        var replacement: [String: IssuedDescriptorAuthority] = [:]
        for itemId in package.itemsById.keys.sorted() {
            guard let item = package.itemsById[itemId] else { continue }
            for handle in item.contentRoles.allHandles {
                guard replacement[handle.handleId] == nil else {
                    hasAvailableAuthority = false
                    authorityByDescriptorId.removeAll(keepingCapacity: false)
                    throw BridgePaneProductReviewContentSourceError.descriptorMismatch
                }
                replacement[handle.handleId] = IssuedDescriptorAuthority(
                    handle: handle,
                    packageId: package.packageId,
                    reviewGeneration: package.reviewGeneration.rawValue,
                    sourceIdentity: package.query.queryId
                )
            }
        }
        authorityByDescriptorId = replacement
        hasAvailableAuthority = true
    }

    func authoritativeItemId(
        for request: BridgeProductReviewContentRequest
    ) async -> String? {
        matchingAuthority(for: request.descriptor)?.handle.itemId
    }

    func contentBody(
        for request: BridgeProductReviewContentRequest
    ) async throws -> BridgePaneProductReviewContentBody {
        guard hasAvailableAuthority else {
            throw BridgePaneProductReviewContentSourceError.unavailablePackage
        }
        let descriptor = request.descriptor
        guard let authority = matchingAuthority(for: descriptor) else {
            throw BridgePaneProductReviewContentSourceError.descriptorMismatch
        }
        let handle = authority.handle

        let range = try await contentStore.loadRangeObserved(
            handleId: handle.handleId,
            requestedGeneration: BridgeReviewGeneration(authority.reviewGeneration),
            startByte: descriptor.window.startByte,
            maximumBytes: descriptor.window.maximumBytes
        )
        try Task.checkCancellation()
        guard hasAvailableAuthority,
            authorityByDescriptorId[descriptor.descriptorId] == authority,
            range.handle == handle
        else {
            throw BridgePaneProductReviewContentSourceError.descriptorMismatch
        }
        if let declaredByteLength = descriptor.declaredByteLength,
            declaredByteLength != range.bytes.count
        {
            throw BridgePaneProductReviewContentSourceError.declaredByteLengthMismatch(
                expected: declaredByteLength,
                actual: range.bytes.count
            )
        }
        if let expectedSHA256 = descriptor.expectedSha256,
            expectedSHA256 != range.sha256
        {
            throw BridgePaneProductReviewContentSourceError.expectedSHA256Mismatch(
                expected: expectedSHA256,
                actual: range.sha256
            )
        }
        if let expectedWholeByteLength = descriptor.wholeByteLength,
            expectedWholeByteLength != range.wholeByteLength
        {
            throw BridgePaneProductReviewContentSourceError.wholeByteLengthMismatch(
                expected: expectedWholeByteLength,
                actual: range.wholeByteLength
            )
        }
        return BridgePaneProductReviewContentBody(
            data: range.bytes,
            descriptor: descriptor,
            isFinalRange: range.isFinalRange,
            sha256: range.sha256,
            wholeByteLength: range.wholeByteLength
        )
    }

    private func matchingAuthority(
        for descriptor: BridgeProductReviewContentDescriptor
    ) -> IssuedDescriptorAuthority? {
        guard hasAvailableAuthority,
            let authority = authorityByDescriptorId[descriptor.descriptorId],
            descriptor.packageId == authority.packageId,
            descriptor.reviewGeneration == authority.reviewGeneration,
            descriptor.sourceIdentity == authority.sourceIdentity,
            Self.matchesAuthority(descriptor: descriptor, handle: authority.handle)
        else { return nil }
        return authority
    }

    private static func matchesAuthority(
        descriptor: BridgeProductReviewContentDescriptor,
        handle: BridgeContentHandle
    ) -> Bool {
        descriptor.descriptorId == handle.handleId
            && descriptor.endpointId == handle.endpointId
            && descriptor.itemId == handle.itemId
            && descriptor.role == handle.role
            && descriptor.reviewGeneration == handle.reviewGeneration.rawValue
            && descriptor.source.handleId == handle.handleId
            && descriptor.source.isBinary == handle.isBinary
            && descriptor.source.language == handle.language
            && descriptor.source.mimeType == handle.mimeType
            && descriptor.source.encoding == (handle.isBinary ? nil : "utf-8")
            && descriptor.source.wholeByteLength == (handle.sizeBytesIsExact ? handle.sizeBytes : nil)
            && descriptor.contentDigest == contentDigest(for: handle)
    }

    static func contentDigest(for handle: BridgeContentHandle) -> BridgeProductReviewContentDigest {
        let normalizedAlgorithm = handle.contentHashAlgorithm.lowercased()
        if normalizedAlgorithm == "sha256" || normalizedAlgorithm == "sha-256" {
            let digest =
                handle.contentHash.hasPrefix("sha256:")
                ? String(handle.contentHash.dropFirst("sha256:".count))
                : handle.contentHash
            if digest.count == 64, digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) {
                return .authoritativeSHA256(digest)
            }
        }
        return .provisional(
            algorithm: handle.contentHashAlgorithm,
            value: handle.contentHash
        )
    }
}
