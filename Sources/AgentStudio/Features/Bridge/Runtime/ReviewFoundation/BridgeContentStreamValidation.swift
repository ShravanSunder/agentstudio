import CryptoKit
import Foundation

enum BridgeContentStreamHasher {
    case sha256(SHA256)
    case gitBlobSHA1(Insecure.SHA1)
    case deferredGitBlobSHA1(Data)

    init(handle: BridgeContentHandle) throws {
        switch handle.contentHashAlgorithm.lowercased() {
        case "sha256", "sha-256":
            self = .sha256(SHA256())
        case "git-blob-sha1":
            guard handle.sizeBytesIsExact else {
                self = .deferredGitBlobSHA1(Data())
                return
            }
            var hasher = Insecure.SHA1()
            hasher.update(data: Data("blob \(handle.sizeBytes)\0".utf8))
            self = .gitBlobSHA1(hasher)
        default:
            throw BridgeProviderFailure.providerFailed(
                message: "Unsupported content hash algorithm: \(handle.contentHashAlgorithm)"
            )
        }
    }

    mutating func update(data: Data) {
        switch self {
        case .sha256(var hasher):
            hasher.update(data: data)
            self = .sha256(hasher)
        case .gitBlobSHA1(var hasher):
            hasher.update(data: data)
            self = .gitBlobSHA1(hasher)
        case .deferredGitBlobSHA1(var bufferedData):
            bufferedData.append(data)
            self = .deferredGitBlobSHA1(bufferedData)
        }
    }

    mutating func finalize() -> String {
        switch self {
        case .sha256(let hasher):
            let digest = hasher.finalize()
            self = .sha256(SHA256())
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            return "sha256:\(hex)"
        case .gitBlobSHA1(let hasher):
            let digest = hasher.finalize()
            self = .gitBlobSHA1(Insecure.SHA1())
            return digest.map { String(format: "%02x", $0) }.joined()
        case .deferredGitBlobSHA1(let bufferedData):
            var hasher = Insecure.SHA1()
            hasher.update(data: Data("blob \(bufferedData.count)\0".utf8))
            hasher.update(data: bufferedData)
            let digest = hasher.finalize()
            self = .deferredGitBlobSHA1(Data())
            return digest.map { String(format: "%02x", $0) }.joined()
        }
    }
}

final class BridgeContentStreamValidationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let handleId: String
    private let maxByteCount: Int
    private var hasher: BridgeContentStreamHasher
    private var recordedByteCount = 0

    var byteCount: Int {
        lock.withLock { recordedByteCount }
    }

    init(handle: BridgeContentHandle) throws {
        self.handleId = handle.handleId
        self.maxByteCount =
            handle.sizeBytesIsExact
            ? min(handle.sizeBytes, AppPolicies.Bridge.contentMaxBytesPerItem)
            : AppPolicies.Bridge.contentMaxBytesPerItem
        self.hasher = try BridgeContentStreamHasher(handle: handle)
    }

    func record(_ chunk: Data) throws {
        try lock.withLock {
            recordedByteCount += chunk.count
            guard recordedByteCount <= maxByteCount else {
                throw BridgeProviderFailure.oversizedContent(
                    handleId: handleId,
                    sizeBytes: recordedByteCount
                )
            }
            hasher.update(data: chunk)
        }
    }

    func finalContentHash() -> String {
        lock.withLock {
            hasher.finalize()
        }
    }
}
