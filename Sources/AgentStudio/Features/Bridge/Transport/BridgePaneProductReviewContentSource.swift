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

typealias BridgeReviewContentLeaseAcquirer =
    @MainActor @Sendable (
        _ descriptor: BridgeProductReviewContentDescriptor,
        _ productAdmission: BridgeProductAdmissionContext
    ) -> BridgeReviewContentAuthorityLease?

typealias BridgeReviewContentLeaseSettler =
    @MainActor @Sendable (_ lease: BridgeReviewContentAuthorityLease) -> Bool

protocol BridgePaneProductReviewContentProducing: Sendable {
    func authoritativeItemId(
        for request: BridgeProductReviewContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> String?

    func contentBody(
        for request: BridgeProductReviewContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewContentBody
}

struct BridgeUnavailablePaneProductReviewContentSource: BridgePaneProductReviewContentProducing {
    func authoritativeItemId(
        for _: BridgeProductReviewContentRequest,
        productAdmission _: BridgeProductAdmissionContext
    ) async -> String? { nil }

    func contentBody(
        for _: BridgeProductReviewContentRequest,
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewContentBody {
        throw BridgePaneProductReviewContentSourceError.unavailablePackage
    }
}

/// Translates coordinator-issued content leases into validated loader-cache reads.
///
/// Publication and descriptor authority remain on the MainActor coordinator. This
/// actor retains no authority snapshot across calls or suspensions.
actor BridgePaneProductReviewContentSource: BridgePaneProductReviewContentProducing {
    private let loaderCache: BridgeReviewContentLoaderCache
    private let acquireContentLease: BridgeReviewContentLeaseAcquirer
    private let settleContentLease: BridgeReviewContentLeaseSettler

    init(
        loaderCache: BridgeReviewContentLoaderCache,
        acquireContentLease: @escaping BridgeReviewContentLeaseAcquirer,
        settleContentLease: @escaping BridgeReviewContentLeaseSettler
    ) {
        self.loaderCache = loaderCache
        self.acquireContentLease = acquireContentLease
        self.settleContentLease = settleContentLease
    }

    func authoritativeItemId(
        for request: BridgeProductReviewContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> String? {
        guard (productAdmission.withValidAdmission { true }) == true,
            let lease = await acquireContentLease(request.descriptor, productAdmission)
        else {
            return nil
        }
        let itemId =
            Self.matchesAuthority(
                descriptor: request.descriptor,
                lease: lease
            ) ? lease.handle.itemId : nil
        _ = await settleContentLease(lease)
        return itemId
    }

    func contentBody(
        for request: BridgeProductReviewContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewContentBody {
        try Task.checkCancellation()
        guard (productAdmission.withValidAdmission { true }) == true else {
            throw BridgePaneProductReviewContentSourceError.unavailablePackage
        }
        let descriptor = request.descriptor
        guard let lease = await acquireContentLease(descriptor, productAdmission) else {
            throw BridgePaneProductReviewContentSourceError.unavailablePackage
        }

        let body: BridgePaneProductReviewContentBody
        do {
            guard Self.matchesAuthority(descriptor: descriptor, lease: lease) else {
                throw BridgePaneProductReviewContentSourceError.descriptorMismatch
            }
            let handle = lease.handle
            let range = try await loaderCache.loadRangeObserved(
                handle: handle,
                startByte: descriptor.window.startByte,
                maximumBytes: descriptor.window.maximumBytes,
                productAdmission: productAdmission
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
            body = BridgePaneProductReviewContentBody(
                data: range.bytes,
                descriptor: descriptor,
                isFinalRange: range.isFinalRange,
                sha256: range.sha256,
                wholeByteLength: range.wholeByteLength
            )
        } catch let failure as BridgeContentLoadObservedFailure {
            _ = await settleContentLease(lease)
            throw failure.underlyingError
        } catch {
            _ = await settleContentLease(lease)
            throw error
        }

        guard await settleContentLease(lease) else {
            throw BridgePaneProductReviewContentSourceError.unavailablePackage
        }
        return body
    }

    private static func matchesAuthority(
        descriptor: BridgeProductReviewContentDescriptor,
        lease: BridgeReviewContentAuthorityLease
    ) -> Bool {
        descriptor.packageId == lease.packageId
            && descriptor.sourceIdentity == lease.sourceIdentity
            && matchesAuthority(descriptor: descriptor, handle: lease.handle)
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
