import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Darwin
import Foundation
import Testing

/// Isolated real terminal with FIFO-controlled output and a parsed-output
/// witness. No surface, polling, process timeout, or continuation waiter.
struct ScrollbackZmxConsole: Sendable {
    let sessionID: ZmxSessionID
    private let redrawFIFO: URL
    private let outputPipe: Pipe
    private let marker: String

    static func make(harness: ZmxTestHarness) async throws -> Self {
        let zmxPath = try #require(harness.zmxPath)
        let sessionID = ZmxSessionID.generateUUIDv7()
        let root = URL(fileURLWithPath: harness.zmxDir)
        let startFIFO = root.appending(path: "\(sessionID.rawValue)-start")
        let redrawFIFO = root.appending(path: "\(sessionID.rawValue)-redraw")
        let holdFIFO = root.appending(path: "\(sessionID.rawValue)-hold")
        try await withoutBlockingCooperativePool {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for fifo in [startFIFO, redrawFIFO, holdFIFO] {
                guard mkfifo(fifo.path, 0o600) == 0 else { throw POSIXError(.EIO) }
            }
        }
        let marker = UUIDv7.generate().uuidString
        let pipe = Pipe()
        let script = """
            read start < \(ZmxBackend.shellEscape(startFIFO.path))
            printf '\\033[2J\\033[H  screen ONE\\n\(marker)-one\\n'
            read redraw < \(ZmxBackend.shellEscape(redrawFIFO.path))
            printf '\\033[H  screen TWO\\n\(marker)-two\\n'
            read held < \(ZmxBackend.shellEscape(holdFIFO.path))
            """
        _ = try await harness.spawnZmxSession(
            zmxPath: zmxPath, sessionId: sessionID.rawValue,
            commandArgs: ["/bin/sh", "-c", script], standardOutput: pipe.fileHandleForWriting)
        let console = Self(sessionID: sessionID, redrawFIFO: redrawFIFO, outputPipe: pipe, marker: marker)
        try await console.readOutput(through: Data("\u{1B}[2J\u{1B}[H".utf8))
        try await releaseFIFO(startFIFO)
        try await console.readOutput(through: Data("\(marker)-one".utf8))
        return console
    }

    func redrawInPlace() async throws {
        try await Self.releaseFIFO(redrawFIFO)
        try await readOutput(through: Data("\(marker)-two".utf8))
    }

    func closeHandles() {
        try? outputPipe.fileHandleForReading.close()
        try? outputPipe.fileHandleForWriting.close()
    }

    private static func releaseFIFO(_ fifo: URL) async throws {
        try await withoutBlockingCooperativePool {
            let descriptor = open(fifo.path, O_WRONLY)
            guard descriptor >= 0 else { throw POSIXError(.EIO) }
            defer { _ = close(descriptor) }
            let release = [UInt8]("release\n".utf8)
            guard write(descriptor, release, release.count) == release.count else { throw POSIXError(.EIO) }
        }
    }

    private func readOutput(through marker: Data) async throws {
        let handle = outputPipe.fileHandleForReading
        try await withoutBlockingCooperativePool {
            var bytes = Data()
            var chunk = [UInt8](repeating: 0, count: 1024)
            while true {
                if let range = bytes.range(of: marker), range.count == marker.count { return }
                let count = chunk.withUnsafeMutableBytes {
                    Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count)
                }
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(.EIO) }
                bytes.append(contentsOf: chunk.prefix(count))
                guard bytes.count <= 16_384 else { throw POSIXError(.EOVERFLOW) }
            }
        }
    }
}
