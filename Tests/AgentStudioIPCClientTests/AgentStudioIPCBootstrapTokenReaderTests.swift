import AgentStudioIPCClientCore
import Foundation
import Testing

#if canImport(Darwin)
    import Darwin
#endif

@Suite("AgentStudio IPC bootstrap token reader", .serialized)
struct AgentStudioIPCBootstrapTokenReaderTests {
    @Test("reads bootstrap token once and closes fd")
    func readsBootstrapTokenOnceAndClosesFD() throws {
        #if canImport(Darwin)
            var fds: [Int32] = [0, 0]
            guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
                Issue.record("socketpair failed")
                return
            }
            let readFileDescriptor = fds[0]
            var peerFileDescriptor: Int32? = fds[1]
            defer {
                if let peerFileDescriptor {
                    _ = Darwin.close(peerFileDescriptor)
                }
            }
            var noSigPipe: Int32 = 1
            _ = setsockopt(
                fds[1],
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSigPipe,
                socklen_t(MemoryLayout.size(ofValue: noSigPipe))
            )

            let payload = "bootstrap-token\n"
            _ = payload.withCString { pointer in
                Darwin.write(fds[1], pointer, strlen(pointer))
            }
            _ = shutdown(fds[1], SHUT_WR)

            let token = try AgentStudioIPCBootstrapTokenReader.readTokenAndClose(
                fileDescriptor: readFileDescriptor
            )

            #expect(token == "bootstrap-token")
            var peerByte = UInt8(ascii: "x")
            let peerWrite = Darwin.write(fds[1], &peerByte, 1)
            #expect(peerWrite == -1)
            #expect(errno == EPIPE)
            _ = Darwin.close(fds[1])
            peerFileDescriptor = nil
        #endif
    }

    @Test("reads bootstrap fd from environment")
    func readsBootstrapFDFromEnvironment() throws {
        let fileDescriptor = try AgentStudioIPCBootstrapTokenReader.bootstrapFileDescriptor(
            environment: ["AGENTSTUDIO_IPC_BOOTSTRAP_FD": "57"]
        )

        #expect(fileDescriptor == 57)
        #expect(throws: AgentStudioIPCClientError.self) {
            _ = try AgentStudioIPCBootstrapTokenReader.bootstrapFileDescriptor(environment: [:])
        }
    }
}
