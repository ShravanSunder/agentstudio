import Foundation

@testable import AgentStudio

/// Test double for `BridgeFileProvider` — returns pre-registered content for known file IDs.
final class MockFileProvider: BridgeFileProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: (data: Data, mimeType: String)] = [:]

    /// Register a file that the provider will serve for the given ID.
    func register(fileId: String, data: Data, mimeType: String) {
        lock.lock()
        defer { lock.unlock() }
        files[fileId] = (data, mimeType)
    }

    func fileContent(for fileId: String) async throws -> (data: Data, mimeType: String) {
        lock.lock()
        let entry = files[fileId]
        lock.unlock()
        guard let entry else {
            throw MockFileProviderError.notFound(fileId)
        }
        return entry
    }
}

enum MockFileProviderError: Error, Sendable {
    case notFound(String)
}
