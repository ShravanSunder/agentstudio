import CryptoKit
import Foundation

enum BridgeWorktreeFileResourceBodyError: Error, Equatable, Sendable {
    case shortRead(expectedBytes: Int, actualBytes: Int)
    case integrityMismatch
}

struct BridgeWorktreeFileResourceBody: Equatable, Sendable {
    private enum Source: Equatable, Sendable {
        case data(Data)
        case file(URL)
    }

    let byteCount: Int
    let mimeType: String
    let expectedSHA256Hex: String?
    private let source: Source

    init(data: Data, mimeType: String) {
        self.byteCount = data.count
        self.mimeType = mimeType
        self.expectedSHA256Hex = Self.sha256Hex(data)
        self.source = .data(data)
    }

    init(fileURL: URL, byteCount: Int, mimeType: String, expectedSHA256Hex: String? = nil) {
        self.byteCount = byteCount
        self.mimeType = mimeType
        self.expectedSHA256Hex = expectedSHA256Hex
        self.source = .file(fileURL)
    }

    func emitChunks(
        chunkByteCount: Int,
        receive: (Data) async throws -> Bool
    ) async throws -> Bool {
        switch source {
        case .data(let data):
            return try await emitDataChunks(
                data,
                chunkByteCount: chunkByteCount,
                receive: receive
            )
        case .file(let fileURL):
            return try await emitFileChunks(
                fileURL: fileURL,
                byteCount: byteCount,
                expectedSHA256Hex: expectedSHA256Hex,
                chunkByteCount: chunkByteCount,
                receive: receive
            )
        }
    }

    private func emitDataChunks(
        _ data: Data,
        chunkByteCount: Int,
        receive: (Data) async throws -> Bool
    ) async throws -> Bool {
        var offset = 0
        while offset < data.count {
            let endOffset = min(offset + chunkByteCount, data.count)
            let chunk = data.subdata(in: offset..<endOffset)
            guard try await receive(chunk) else {
                return false
            }
            offset = endOffset
        }
        return true
    }

    private func emitFileChunks(
        fileURL: URL,
        byteCount: Int,
        expectedSHA256Hex: String?,
        chunkByteCount: Int,
        receive: (Data) async throws -> Bool
    ) async throws -> Bool {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? fileHandle.close()
        }

        var remainingBytes = byteCount
        var emittedBytes = 0
        var hasher = SHA256()
        while remainingBytes > 0 {
            try Task.checkCancellation()
            let readCount = min(chunkByteCount, remainingBytes)
            guard let chunk = try fileHandle.read(upToCount: readCount), !chunk.isEmpty else {
                throw BridgeWorktreeFileResourceBodyError.shortRead(
                    expectedBytes: byteCount,
                    actualBytes: emittedBytes
                )
            }
            emittedBytes += chunk.count
            hasher.update(data: chunk)
            guard try await receive(chunk) else {
                return false
            }
            remainingBytes -= chunk.count
        }
        guard emittedBytes == byteCount else {
            throw BridgeWorktreeFileResourceBodyError.shortRead(
                expectedBytes: byteCount,
                actualBytes: emittedBytes
            )
        }
        if let expectedSHA256Hex, expectedSHA256Hex != Self.sha256Hex(hasher.finalize()) {
            throw BridgeWorktreeFileResourceBodyError.integrityMismatch
        }
        return true
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct BridgeWorktreeTreeWindowResourceBody: Codable, Equatable, Sendable {
    struct Row: Codable, Equatable, Sendable {
        let rowId: String
        let path: String
        let name: String
        let parentPath: String?
        let kind: String
        let depth: Int
        let isDirectory: Bool
        let fileId: String?
        let sizeBytes: Int?
        let lineCount: Int?
        let changeStatus: String?
    }

    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let treeSizeFacts: BridgeWorktreeTreeVirtualizedSizeFacts
    let rows: [Row]
}

struct BridgeWorktreeStatusResourceBody: Codable, Equatable, Sendable {
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let patch: BridgeWorktreeStatusPatch
}

actor BridgeWorktreeFileResourceStore {
    private struct ResourceEntry: Sendable {
        let resource: BridgeTransportResourceURL
        let body: BridgeWorktreeFileResourceBody
    }

    private var entryByCanonicalURL: [String: ResourceEntry] = [:]

    func register(
        _ resource: BridgeTransportResourceURL,
        body: BridgeWorktreeFileResourceBody
    ) {
        entryByCanonicalURL[resource.canonicalURL] = ResourceEntry(resource: resource, body: body)
    }

    func load(_ resource: BridgeTransportResourceURL) -> BridgeWorktreeFileResourceBody? {
        entryByCanonicalURL[resource.canonicalURL]?.body
    }

    func reset(
        protocolId: String? = nil,
        resourceKind: String? = nil,
        generation: Int? = nil,
        cursor: String? = nil
    ) {
        entryByCanonicalURL = entryByCanonicalURL.filter { _, entry in
            let resource = entry.resource
            let shouldRemove =
                (protocolId.map { resource.protocolId == $0 } ?? true)
                && (resourceKind.map { resource.resourceKind == $0 } ?? true)
                && (generation.map { resource.generation == $0 } ?? true)
                && (cursor.map { resource.cursor == $0 } ?? true)
            return !shouldRemove
        }
    }
}
