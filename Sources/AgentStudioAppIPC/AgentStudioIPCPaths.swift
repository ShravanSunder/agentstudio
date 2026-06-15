import Foundation

#if canImport(Darwin)
    import Darwin
#endif

public struct AgentStudioIPCPaths: Equatable, Sendable {
    public let rootDirectory: URL
    public let ipcDirectory: URL
    public let metadataURL: URL
    public let socketURL: URL

    public init(rootDirectory: URL, ipcDirectory: URL, metadataURL: URL, socketURL: URL) {
        self.rootDirectory = rootDirectory
        self.ipcDirectory = ipcDirectory
        self.metadataURL = metadataURL
        self.socketURL = socketURL
    }
}

public struct AgentStudioIPCPathResolver: Sendable {
    public init() {}

    public func paths(rootDirectory: URL) -> AgentStudioIPCPaths {
        let ipcDirectory = rootDirectory.appendingPathComponent("ipc", isDirectory: true)
        return AgentStudioIPCPaths(
            rootDirectory: rootDirectory,
            ipcDirectory: ipcDirectory,
            metadataURL: ipcDirectory.appendingPathComponent("runtime.json"),
            socketURL: ipcDirectory.appendingPathComponent("agentstudio.sock")
        )
    }
}

public enum AgentStudioIPCChannel: String, Codable, Equatable, Sendable {
    case stable
    case beta
    case debug
}

public struct AgentStudioIPCRuntimeMetadata: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let runtimeId: UUID
    public let processIdentifier: Int32
    public let channel: AgentStudioIPCChannel
    public let socketPath: String
    public let startedAt: Date
    public let `protocol`: String

    public init(
        runtimeId: UUID,
        processIdentifier: Int32,
        channel: AgentStudioIPCChannel,
        socketPath: String,
        startedAt: Date
    ) {
        schemaVersion = 1
        self.runtimeId = runtimeId
        self.processIdentifier = processIdentifier
        self.channel = channel
        self.socketPath = socketPath
        self.startedAt = startedAt
        self.protocol = "agentstudio-ipc-jsonrpc-2"
    }
}

public struct AgentStudioIPCFilesystemTrustError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case unsupportedPlatform
        case pathDoesNotExist
        case symlinkNotAllowed
        case notOwnedByCurrentUser
        case groupOrWorldAccessible
        case directoryCreationFailed
        case metadataEncodingFailed
        case metadataWriteFailed
    }

    public let reason: Reason
    public let path: String
    public let errnoCode: Int32

    public init(reason: Reason, path: String, errnoCode: Int32 = 0) {
        self.reason = reason
        self.path = path
        self.errnoCode = errnoCode
    }
}

public enum AgentStudioIPCFilesystem {
    public static func prepare(paths: AgentStudioIPCPaths) throws {
        try validateTrustedExistingPath(paths.rootDirectory, requireDirectory: true)

        if FileManager.default.fileExists(atPath: paths.ipcDirectory.path) {
            try validateTrustedExistingPath(paths.ipcDirectory, requireDirectory: true)
        } else {
            do {
                try FileManager.default.createDirectory(at: paths.ipcDirectory, withIntermediateDirectories: false)
                try chmodOwnerOnly(paths.ipcDirectory, mode: 0o700)
            } catch let error as AgentStudioIPCFilesystemTrustError {
                throw error
            } catch {
                throw AgentStudioIPCFilesystemTrustError(
                    reason: .directoryCreationFailed,
                    path: paths.ipcDirectory.path,
                    errnoCode: errno
                )
            }
        }

        try validateTrustedExistingPath(paths.ipcDirectory, requireDirectory: true)
    }

    public static func writeMetadata(_ metadata: AgentStudioIPCRuntimeMetadata, paths: AgentStudioIPCPaths) throws {
        try validateTrustedExistingPath(paths.ipcDirectory, requireDirectory: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(metadata)
        } catch {
            throw AgentStudioIPCFilesystemTrustError(reason: .metadataEncodingFailed, path: paths.metadataURL.path)
        }

        let temporaryURL = paths.ipcDirectory.appendingPathComponent(".runtime.\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporaryURL, options: [.atomic])
            try chmodOwnerOnly(temporaryURL, mode: 0o600)
            if rename(temporaryURL.path, paths.metadataURL.path) != 0 {
                throw AgentStudioIPCFilesystemTrustError(
                    reason: .metadataWriteFailed,
                    path: paths.metadataURL.path,
                    errnoCode: errno
                )
            }
            try chmodOwnerOnly(paths.metadataURL, mode: 0o600)
        } catch let error as AgentStudioIPCFilesystemTrustError {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw AgentStudioIPCFilesystemTrustError(
                reason: .metadataWriteFailed,
                path: paths.metadataURL.path,
                errnoCode: errno
            )
        }
    }

    private static func validateTrustedExistingPath(_ url: URL, requireDirectory: Bool) throws {
        #if canImport(Darwin)
            var statBuffer = stat()
            guard lstat(url.path, &statBuffer) == 0 else {
                throw AgentStudioIPCFilesystemTrustError(reason: .pathDoesNotExist, path: url.path, errnoCode: errno)
            }

            let mode = statBuffer.st_mode
            if (mode & S_IFMT) == S_IFLNK {
                throw AgentStudioIPCFilesystemTrustError(reason: .symlinkNotAllowed, path: url.path)
            }

            if requireDirectory, (mode & S_IFMT) != S_IFDIR {
                throw AgentStudioIPCFilesystemTrustError(reason: .pathDoesNotExist, path: url.path)
            }

            guard statBuffer.st_uid == getuid() else {
                throw AgentStudioIPCFilesystemTrustError(reason: .notOwnedByCurrentUser, path: url.path)
            }

            guard (mode & 0o077) == 0 else {
                throw AgentStudioIPCFilesystemTrustError(reason: .groupOrWorldAccessible, path: url.path)
            }
        #else
            throw AgentStudioIPCFilesystemTrustError(reason: .unsupportedPlatform, path: url.path)
        #endif
    }

    private static func chmodOwnerOnly(_ url: URL, mode: mode_t) throws {
        #if canImport(Darwin)
            guard chmod(url.path, mode) == 0 else {
                throw AgentStudioIPCFilesystemTrustError(
                    reason: .metadataWriteFailed,
                    path: url.path,
                    errnoCode: errno
                )
            }
        #else
            throw AgentStudioIPCFilesystemTrustError(reason: .unsupportedPlatform, path: url.path)
        #endif
    }
}

public enum AgentStudioIPCSocketProbeOutcome: Equatable, Sendable {
    case sameRuntime(UUID)
    case differentRuntime(UUID)
    case dead
}

public enum AgentStudioIPCStaleSocketDecision: Equatable, Sendable {
    case keepExisting
    case unlinkAndBind
    case refuseDifferentLiveRuntime
}

public struct AgentStudioIPCStaleSocketResolver: Sendable {
    public init() {}

    public func decision(
        for outcome: AgentStudioIPCSocketProbeOutcome,
        expectedRuntimeId: UUID
    ) -> AgentStudioIPCStaleSocketDecision {
        switch outcome {
        case .sameRuntime(let runtimeId):
            runtimeId == expectedRuntimeId ? .keepExisting : .refuseDifferentLiveRuntime
        case .dead:
            .unlinkAndBind
        case .differentRuntime:
            .refuseDifferentLiveRuntime
        }
    }
}
