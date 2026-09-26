import AgentStudioTestHarness
import Foundation
import Synchronization

@testable import AgentStudioIPCTransport

/// One call `stop()` made to its accept-loop join wait: whether the listener's
/// original descriptor still owned the endpoint at that moment, and the real
/// accept-queue barrier the join was given.
struct UnixSocketJoinEntry: Sendable {
    let ownedEndpoint: Bool
    let barrier: DispatchSemaphore
}

/// Tracks the listener's own descriptor so a join can report whether that
/// exact number was still bound to the endpoint when the join began.
final class UnixSocketListeningDescriptorProbe: Sendable {
    private let endpointPath: String
    private let recordedDescriptor = Mutex<Int32?>(nil)

    init(endpointPath: String) {
        self.endpointPath = endpointPath
    }

    /// Records the listening descriptor. Call while the listening socket is the
    /// only thing bound to the endpoint, so the match is unambiguous.
    func recordListeningDescriptor() throws {
        guard let descriptor = findUnixSocketDescriptor(boundTo: endpointPath) else {
            throw UnixSocketTransportError(reason: .socketCreationFailed)
        }
        recordedDescriptor.withLock { $0 = descriptor }
    }

    /// Whether the recorded descriptor number is still bound to the endpoint.
    var descriptorOwnsEndpoint: Bool {
        guard let descriptor = recordedDescriptor.withLock({ $0 }) else { return false }
        return unixSocketPath(ofDescriptor: descriptor) == endpointPath
    }
}

/// The accept-loop join wait injected into `UnixSocketListener`, scripted per
/// join. Each entry is recorded on a released `HeldStep` before the join
/// returns, so the test awaits the entry itself; blocking joins wait on the
/// real queue barrier, so success is never fabricated.
final class UnixSocketShutdownWaitController: Sendable {
    enum Mode: Sendable {
        case waitForFirstBarrier
        case timeOutFirstAndWaitForSecondBarrier
        case timeOutBothBarriers
    }

    let firstJoin = HeldStep<UnixSocketJoinEntry>("first accept-loop join")
    let secondJoin = HeldStep<UnixSocketJoinEntry>("second accept-loop join")
    private let descriptorProbe: UnixSocketListeningDescriptorProbe
    private let joinCount = Mutex(0)
    private let mode: Mode

    init(mode: Mode, descriptorProbe: UnixSocketListeningDescriptorProbe) {
        self.mode = mode
        self.descriptorProbe = descriptorProbe
        firstJoin.release()
        secondJoin.release()
    }

    var invocationCount: Int {
        joinCount.withLock { $0 }
    }

    func wait(for barrier: DispatchSemaphore) -> DispatchTimeoutResult {
        let invocation = joinCount.withLock { count in
            count += 1
            return count
        }
        let entry = UnixSocketJoinEntry(
            ownedEndpoint: descriptorProbe.descriptorOwnsEndpoint,
            barrier: barrier
        )

        switch (mode, invocation) {
        case (.waitForFirstBarrier, 1):
            try? firstJoin.arriveBlocking(entry)
            barrier.wait()
            return .success
        case (.timeOutFirstAndWaitForSecondBarrier, 1), (.timeOutBothBarriers, 1):
            try? firstJoin.arriveBlocking(entry)
            return .timedOut
        case (.timeOutFirstAndWaitForSecondBarrier, 2):
            try? secondJoin.arriveBlocking(entry)
            barrier.wait()
            return .success
        case (.timeOutBothBarriers, 2):
            try? secondJoin.arriveBlocking(entry)
            return .timedOut
        default:
            // Repeated stop and deinit are not part of the selected phase.
            // If they ever do enqueue another real barrier, drain it normally.
            barrier.wait()
            return .success
        }
    }
}

/// Reports the path a descriptor is bound to, or nil when the descriptor is
/// closed or is not a named Unix socket. `SO_ACCEPTCONN` is not available for
/// AF_UNIX on Darwin (it fails with `ENOPROTOOPT`), so the bound path is the
/// identifying fact available to a test.
func unixSocketPath(ofDescriptor descriptor: Int32) -> String? {
    #if canImport(Darwin)
        var address = sockaddr_un()
        var addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)
        let named = withUnsafeMutablePointer(to: &address) { storage in
            storage.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                getsockname(descriptor, generic, &addressLength)
            }
        }
        guard named == 0, address.sun_family == sa_family_t(AF_UNIX) else { return nil }

        let pathStorage = address.sun_path
        let boundPath = withUnsafePointer(to: pathStorage) { storage in
            storage.withMemoryRebound(
                to: CChar.self, capacity: MemoryLayout.size(ofValue: pathStorage)
            ) { characters in
                String(cString: characters)
            }
        }
        return boundPath.isEmpty ? nil : boundPath
    #else
        return nil
    #endif
}

/// Locates the listener's own descriptor. Called while the listening socket is
/// the only thing bound to `path`, so the first match is unambiguous.
func findUnixSocketDescriptor(boundTo path: String) -> Int32? {
    #if canImport(Darwin)
        for candidate in Int32(0)..<Int32(512) where unixSocketPath(ofDescriptor: candidate) == path {
            return candidate
        }
    #endif
    return nil
}
