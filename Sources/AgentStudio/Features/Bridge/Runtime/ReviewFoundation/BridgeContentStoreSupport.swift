import CryptoKit
import Foundation

enum BridgeContentStoreError: Error, Equatable, Sendable {
    case productAdmissionRejected
}

struct BridgeContentStoreDiagnosticSnapshot: Equatable, Sendable {
    let activeHandleCount: Int
    let cachedContentCount: Int
    let inFlightLoadCount: Int
    let totalCachedBytes: Int
}

func bridgeComputedContentHash(for data: Data, algorithm: String) throws -> String {
    switch algorithm.lowercased() {
    case "sha256", "sha-256":
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    case "git-blob-sha1":
        var blobData = Data("blob \(data.count)\0".utf8)
        blobData.append(data)
        let digest = Insecure.SHA1.hash(data: blobData)
        return digest.map { String(format: "%02x", $0) }.joined()
    default:
        throw BridgeProviderFailure.providerFailed(message: "Unsupported content hash algorithm: \(algorithm)")
    }
}

extension BridgeContentStore {
    func emitContentDataChunks(
        _ data: Data,
        chunkByteCount: Int,
        productAdmission: BridgeProductAdmissionContext,
        emitChunk: BridgeContentStreamEmitter
    ) async throws {
        var offset = 0
        while offset < data.count {
            let endOffset = min(offset + chunkByteCount, data.count)
            guard (productAdmission.withValidAdmission { true }) == true else {
                throw BridgeContentStoreError.productAdmissionRejected
            }
            try await emitChunk(data.subdata(in: offset..<endOffset))
            offset = endOffset
        }
    }
}
