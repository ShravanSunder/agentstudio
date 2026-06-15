import AgentStudioAppIPC
import Foundation
import Testing

@Suite("AgentStudio IPC paths and filesystem trust")
struct AgentStudioIPCPathResolverTests {
    @Test("derives runtime metadata and socket paths under the channel root")
    func derivesRuntimeMetadataAndSocketPathsUnderChannelRoot() {
        let root = URL(fileURLWithPath: "/tmp/asipc-root")
        let paths = AgentStudioIPCPathResolver().paths(rootDirectory: root)

        #expect(paths.ipcDirectory == root.appendingPathComponent("ipc", isDirectory: true))
        #expect(paths.metadataURL == root.appendingPathComponent("ipc/runtime.json"))
        #expect(paths.socketURL == root.appendingPathComponent("ipc/agentstudio.sock"))
    }

    @Test("creates owner-only ipc directory")
    func createsOwnerOnlyIPCDirectory() throws {
        let fixture = try IPCPathFixture()
        defer { fixture.cleanup() }

        let paths = AgentStudioIPCPathResolver().paths(rootDirectory: fixture.root)

        try AgentStudioIPCFilesystem.prepare(paths: paths)

        #expect(try fixture.mode(for: paths.ipcDirectory) & 0o777 == 0o700)
    }

    @Test("fails closed for group-readable roots")
    func failsClosedForGroupReadableRoots() throws {
        let fixture = try IPCPathFixture(rootMode: 0o750)
        defer { fixture.cleanup() }

        let paths = AgentStudioIPCPathResolver().paths(rootDirectory: fixture.root)

        #expect(throws: AgentStudioIPCFilesystemTrustError.self) {
            try AgentStudioIPCFilesystem.prepare(paths: paths)
        }
    }

    @Test("fails closed for symlinked ipc directories")
    func failsClosedForSymlinkedIPCDirectories() throws {
        let fixture = try IPCPathFixture()
        defer { fixture.cleanup() }

        let paths = AgentStudioIPCPathResolver().paths(rootDirectory: fixture.root)
        let target = fixture.root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: paths.ipcDirectory, withDestinationURL: target)

        #expect(throws: AgentStudioIPCFilesystemTrustError.self) {
            try AgentStudioIPCFilesystem.prepare(paths: paths)
        }
    }

    @Test("writes runtime metadata atomically without subject tokens")
    func writesRuntimeMetadataAtomicallyWithoutSubjectTokens() throws {
        let fixture = try IPCPathFixture()
        defer { fixture.cleanup() }

        let paths = AgentStudioIPCPathResolver().paths(rootDirectory: fixture.root)
        try AgentStudioIPCFilesystem.prepare(paths: paths)

        let runtimeId = UUID()
        let metadata = AgentStudioIPCRuntimeMetadata(
            runtimeId: runtimeId,
            processIdentifier: 12_345,
            channel: .debug,
            socketPath: paths.socketURL.path,
            startedAt: Date(timeIntervalSince1970: 0)
        )

        try AgentStudioIPCFilesystem.writeMetadata(metadata, paths: paths)

        let data = try Data(contentsOf: paths.metadataURL)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains(runtimeId.uuidString))
        #expect(json.contains("agentstudio-ipc-jsonrpc-2"))
        #expect(!json.localizedCaseInsensitiveContains("token"))
        #expect(try fixture.mode(for: paths.metadataURL) & 0o777 == 0o600)
    }

    @Test("classifies stale socket probe outcomes")
    func classifiesStaleSocketProbeOutcomes() throws {
        let resolver = AgentStudioIPCStaleSocketResolver()
        let runtimeId = UUID()

        #expect(resolver.decision(for: .sameRuntime(runtimeId), expectedRuntimeId: runtimeId) == .keepExisting)
        #expect(resolver.decision(for: .dead, expectedRuntimeId: runtimeId) == .unlinkAndBind)
        #expect(
            resolver.decision(for: .differentRuntime(UUID()), expectedRuntimeId: runtimeId)
                == .refuseDifferentLiveRuntime
        )
    }
}

private struct IPCPathFixture {
    let root: URL

    init(rootMode: mode_t = 0o700) throws {
        root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("asipc-path-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        chmod(root.path, rootMode)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func mode(for url: URL) throws -> mode_t {
        var statBuffer = stat()
        guard lstat(url.path, &statBuffer) == 0 else {
            throw POSIXError(.ENOENT)
        }

        return statBuffer.st_mode
    }
}
