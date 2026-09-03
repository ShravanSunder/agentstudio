import AgentStudioInfrastructure
import CryptoKit
import Darwin
import Foundation

package enum DarwinSharedExactItemFingerprintAlgorithm: String, Equatable, Sendable {
    case sha256V1 = "sha256-v1"
}

package enum DarwinSharedExactItemFingerprintKind: Equatable, Sendable {
    case missing
    case regularFile
    case symbolicLink
}

package struct DarwinSharedExactItemFingerprint: Equatable, Sendable {
    let canonicalPath: String
    let kind: DarwinSharedExactItemFingerprintKind
    let algorithm: DarwinSharedExactItemFingerprintAlgorithm
    let digestHex: String
    let identity: DarwinSharedExactItemIdentity?
}

package struct DarwinSharedExactItemIdentity: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t
    let mode: mode_t
    let generation: UInt32
    let byteCount: Int64
    let birthTimeSeconds: Int
    let birthTimeNanoseconds: Int
    let changeTimeSeconds: Int
    let changeTimeNanoseconds: Int
    let modificationTimeSeconds: Int
    let modificationTimeNanoseconds: Int

    init(status: stat) {
        device = status.st_dev
        inode = status.st_ino
        mode = status.st_mode
        generation = status.st_gen
        byteCount = status.st_size
        birthTimeSeconds = status.st_birthtimespec.tv_sec
        birthTimeNanoseconds = status.st_birthtimespec.tv_nsec
        changeTimeSeconds = status.st_ctimespec.tv_sec
        changeTimeNanoseconds = status.st_ctimespec.tv_nsec
        modificationTimeSeconds = status.st_mtimespec.tv_sec
        modificationTimeNanoseconds = status.st_mtimespec.tv_nsec
    }
}

package struct DarwinSharedExactItemFingerprintSnapshot: Equatable, Sendable {
    let fingerprintsByCanonicalPath: [String: DarwinSharedExactItemFingerprint]
    let uniqueItemCount: Int
    let bytesRead: Int
}

package enum DarwinSharedExactItemFingerprintFailure: Equatable, Sendable {
    case itemByteLimitExceeded
    case itemCountLimitExceeded
    case transactionByteLimitExceeded
    case unsupportedItemType
    case unreadableItem
    case unstableItem
}

package struct DarwinSharedExactItemFingerprintOutcome: Equatable, Sendable {
    let snapshot: DarwinSharedExactItemFingerprintSnapshot?
    let failure: DarwinSharedExactItemFingerprintFailure?
    let bytesRead: Int

    static func success(
        fingerprintsByCanonicalPath: [String: DarwinSharedExactItemFingerprint],
        bytesRead: Int
    ) -> Self {
        Self(
            snapshot: DarwinSharedExactItemFingerprintSnapshot(
                fingerprintsByCanonicalPath: fingerprintsByCanonicalPath,
                uniqueItemCount: fingerprintsByCanonicalPath.count,
                bytesRead: bytesRead
            ),
            failure: nil,
            bytesRead: bytesRead
        )
    }

    static func failed(_ failure: DarwinSharedExactItemFingerprintFailure, bytesRead: Int) -> Self {
        Self(snapshot: nil, failure: failure, bytesRead: bytesRead)
    }
}

package struct DarwinSharedExactItemFingerprintPolicy: Equatable, Sendable {
    let maximumItemBytes: Int
    let maximumUniqueItems: Int
    let maximumTransactionBytes: Int

    init(
        maximumItemBytes: Int = AppPolicies.GitRefresh.sharedExactItemFingerprintMaximumItemBytes,
        maximumUniqueItems: Int = AppPolicies.GitRefresh.sharedExactItemFingerprintMaximumUniqueItems,
        maximumTransactionBytes: Int = AppPolicies.GitRefresh
            .sharedExactItemFingerprintMaximumTransactionBytes
    ) {
        self.maximumItemBytes = maximumItemBytes
        self.maximumUniqueItems = maximumUniqueItems
        self.maximumTransactionBytes = maximumTransactionBytes
    }
}

package struct DarwinSharedExactItemFingerprintReader: Sendable {
    typealias RegularFileOpened = @Sendable (String) -> Void

    private static let regularFileReadChunkByteCount = 64 * 1024

    private let policy: DarwinSharedExactItemFingerprintPolicy
    private let regularFileOpened: RegularFileOpened

    init(
        policy: DarwinSharedExactItemFingerprintPolicy = .init(),
        regularFileOpened: @escaping RegularFileOpened = { _ in }
    ) {
        self.policy = policy
        self.regularFileOpened = regularFileOpened
    }

    @concurrent nonisolated func read(
        canonicalItemPaths: [String]
    ) async -> DarwinSharedExactItemFingerprintOutcome {
        readSynchronously(canonicalItemPaths: canonicalItemPaths)
    }

    private func readSynchronously(
        canonicalItemPaths: [String]
    ) -> DarwinSharedExactItemFingerprintOutcome {
        let uniquePaths = Array(Set(canonicalItemPaths)).sorted()
        guard uniquePaths.count <= policy.maximumUniqueItems else {
            return .failed(.itemCountLimitExceeded, bytesRead: 0)
        }

        var fingerprintsByCanonicalPath: [String: DarwinSharedExactItemFingerprint] = [:]
        fingerprintsByCanonicalPath.reserveCapacity(uniquePaths.count)
        var transactionBytesRead = 0

        for canonicalPath in uniquePaths {
            switch readItem(canonicalPath: canonicalPath, transactionBytesRead: transactionBytesRead) {
            case .success(let fingerprint, let itemBytesRead):
                fingerprintsByCanonicalPath[canonicalPath] = fingerprint
                transactionBytesRead += itemBytesRead
            case .failure(let failure, let itemBytesRead):
                return .failed(failure, bytesRead: transactionBytesRead + itemBytesRead)
            }
        }

        return .success(
            fingerprintsByCanonicalPath: fingerprintsByCanonicalPath,
            bytesRead: transactionBytesRead
        )
    }

    private func readItem(
        canonicalPath: String,
        transactionBytesRead: Int
    ) -> DarwinSharedExactItemReadResult {
        switch lstatResult(canonicalPath) {
        case .missing:
            guard case .missing = lstatResult(canonicalPath) else {
                return .failure(.unstableItem, bytesRead: 0)
            }
            return .success(
                fingerprint: DarwinSharedExactItemFingerprint(
                    canonicalPath: canonicalPath,
                    kind: .missing,
                    algorithm: .sha256V1,
                    digestHex: Self.emptySHA256,
                    identity: nil
                ),
                bytesRead: 0
            )
        case .failed:
            return .failure(.unreadableItem, bytesRead: 0)
        case .status(let status):
            let itemType = status.st_mode & mode_t(S_IFMT)
            if itemType == mode_t(S_IFREG) {
                return readRegularFile(
                    canonicalPath: canonicalPath,
                    initialStatus: status,
                    transactionBytesRead: transactionBytesRead
                )
            }
            if itemType == mode_t(S_IFLNK) {
                return readSymbolicLink(
                    canonicalPath: canonicalPath,
                    initialStatus: status,
                    transactionBytesRead: transactionBytesRead
                )
            }
            return .failure(.unsupportedItemType, bytesRead: 0)
        }
    }

    private func readRegularFile(
        canonicalPath: String,
        initialStatus: stat,
        transactionBytesRead: Int
    ) -> DarwinSharedExactItemReadResult {
        guard initialStatus.st_size >= 0,
            initialStatus.st_size <= Int64(policy.maximumItemBytes)
        else {
            return .failure(.itemByteLimitExceeded, bytesRead: 0)
        }
        let declaredByteCount = Int(initialStatus.st_size)
        guard transactionBytesRead <= policy.maximumTransactionBytes - declaredByteCount else {
            return .failure(.transactionByteLimitExceeded, bytesRead: 0)
        }

        let descriptor = canonicalPath.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            return .failure(
                errno == ENOENT || errno == ELOOP ? .unstableItem : .unreadableItem,
                bytesRead: 0
            )
        }
        defer { Darwin.close(descriptor) }

        var descriptorStatusBefore = stat()
        guard Darwin.fstat(descriptor, &descriptorStatusBefore) == 0,
            stableIdentity(initialStatus) == stableIdentity(descriptorStatusBefore)
        else {
            return .failure(.unstableItem, bytesRead: 0)
        }

        regularFileOpened(canonicalPath)

        var hasher = SHA256()
        var bytesRemaining = declaredByteCount
        var itemBytesRead = 0
        var buffer = [UInt8](
            repeating: 0,
            count: min(Self.regularFileReadChunkByteCount, max(1, declaredByteCount))
        )
        while bytesRemaining > 0 {
            let requestedByteCount = min(buffer.count, bytesRemaining)
            let observedByteCount = Darwin.read(descriptor, &buffer, requestedByteCount)
            guard observedByteCount > 0 else {
                return .failure(
                    observedByteCount == 0 ? .unstableItem : .unreadableItem,
                    bytesRead: itemBytesRead
                )
            }
            hasher.update(data: Data(buffer[0..<observedByteCount]))
            itemBytesRead += observedByteCount
            bytesRemaining -= observedByteCount
        }

        var descriptorStatusAfter = stat()
        guard Darwin.fstat(descriptor, &descriptorStatusAfter) == 0,
            case .status(let finalPathStatus) = lstatResult(canonicalPath),
            stableIdentity(initialStatus) == stableIdentity(descriptorStatusBefore),
            stableIdentity(descriptorStatusBefore) == stableIdentity(descriptorStatusAfter),
            stableIdentity(descriptorStatusAfter) == stableIdentity(finalPathStatus)
        else {
            return .failure(.unstableItem, bytesRead: itemBytesRead)
        }

        return .success(
            fingerprint: DarwinSharedExactItemFingerprint(
                canonicalPath: canonicalPath,
                kind: .regularFile,
                algorithm: .sha256V1,
                digestHex: Self.hexDigest(hasher.finalize()),
                identity: DarwinSharedExactItemIdentity(status: finalPathStatus)
            ),
            bytesRead: itemBytesRead
        )
    }

    private func readSymbolicLink(
        canonicalPath: String,
        initialStatus: stat,
        transactionBytesRead: Int
    ) -> DarwinSharedExactItemReadResult {
        guard initialStatus.st_size >= 0,
            initialStatus.st_size <= Int64(policy.maximumItemBytes)
        else {
            return .failure(.itemByteLimitExceeded, bytesRead: 0)
        }
        let declaredByteCount = Int(initialStatus.st_size)
        guard transactionBytesRead <= policy.maximumTransactionBytes - declaredByteCount else {
            return .failure(.transactionByteLimitExceeded, bytesRead: 0)
        }

        var targetBytes = [UInt8](repeating: 0, count: max(1, declaredByteCount))
        let observedByteCount = canonicalPath.withCString { pathPointer in
            targetBytes.withUnsafeMutableBytes { targetBuffer in
                Darwin.readlink(pathPointer, targetBuffer.baseAddress, targetBuffer.count)
            }
        }
        guard observedByteCount >= 0 else {
            return .failure(
                errno == ENOENT ? .unstableItem : .unreadableItem,
                bytesRead: 0
            )
        }
        guard observedByteCount == declaredByteCount,
            case .status(let finalStatus) = lstatResult(canonicalPath),
            stableIdentity(initialStatus) == stableIdentity(finalStatus)
        else {
            return .failure(.unstableItem, bytesRead: max(0, observedByteCount))
        }

        let targetData = Data(targetBytes[0..<observedByteCount])
        return .success(
            fingerprint: DarwinSharedExactItemFingerprint(
                canonicalPath: canonicalPath,
                kind: .symbolicLink,
                algorithm: .sha256V1,
                digestHex: Self.hexDigest(SHA256.hash(data: targetData)),
                identity: DarwinSharedExactItemIdentity(status: finalStatus)
            ),
            bytesRead: observedByteCount
        )
    }

    private func lstatResult(_ canonicalPath: String) -> DarwinSharedExactItemLstatResult {
        var status = stat()
        let result = canonicalPath.withCString { Darwin.lstat($0, &status) }
        if result == 0 {
            return .status(status)
        }
        if errno == ENOENT || errno == ENOTDIR {
            return .missing
        }
        return .failed
    }

    private func stableIdentity(_ status: stat) -> DarwinSharedExactItemIdentity {
        DarwinSharedExactItemIdentity(status: status)
    }

    private static var emptySHA256: String {
        hexDigest(SHA256.hash(data: Data()))
    }

    private static func hexDigest<Digest: Sequence>(_ digest: Digest) -> String
    where Digest.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

private enum DarwinSharedExactItemLstatResult {
    case missing
    case status(stat)
    case failed
}

private enum DarwinSharedExactItemReadResult {
    case success(fingerprint: DarwinSharedExactItemFingerprint, bytesRead: Int)
    case failure(DarwinSharedExactItemFingerprintFailure, bytesRead: Int)
}
