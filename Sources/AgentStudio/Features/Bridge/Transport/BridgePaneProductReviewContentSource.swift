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
    func contentBody(
        for request: BridgeProductReviewContentRequest
    ) async throws -> BridgePaneProductReviewContentBody
}

struct BridgeUnavailablePaneProductReviewContentSource: BridgePaneProductReviewContentProducing {
    func contentBody(
        for _: BridgeProductReviewContentRequest
    ) async throws -> BridgePaneProductReviewContentBody {
        throw BridgePaneProductReviewContentSourceError.unavailablePackage
    }
}

struct BridgePaneProductReviewContentSource: BridgePaneProductReviewContentProducing {
    private let contentStore: BridgeContentStore
    private let currentPackage: @MainActor @Sendable () -> BridgeReviewPackage?

    init(
        contentStore: BridgeContentStore,
        currentPackage: @escaping @MainActor @Sendable () -> BridgeReviewPackage?
    ) {
        self.contentStore = contentStore
        self.currentPackage = currentPackage
    }

    func contentBody(
        for request: BridgeProductReviewContentRequest
    ) async throws -> BridgePaneProductReviewContentBody {
        guard let package = await currentPackage() else {
            throw BridgePaneProductReviewContentSourceError.unavailablePackage
        }
        let descriptor = request.descriptor
        guard descriptor.packageId == package.packageId,
            descriptor.reviewGeneration == package.reviewGeneration.rawValue,
            descriptor.sourceIdentity == package.query.queryId,
            let item = package.itemsById[descriptor.itemId],
            let handle = item.contentRoles.allHandles.first(where: { $0.handleId == descriptor.handleId }),
            Self.matchesAuthority(descriptor: descriptor, handle: handle)
        else {
            throw BridgePaneProductReviewContentSourceError.descriptorMismatch
        }

        let range = try await contentStore.loadRangeObserved(
            handleId: handle.handleId,
            requestedGeneration: package.reviewGeneration,
            startByte: descriptor.window.startByte,
            maximumBytes: descriptor.window.maximumBytes
        )
        try Task.checkCancellation()
        guard range.handle == handle else {
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
