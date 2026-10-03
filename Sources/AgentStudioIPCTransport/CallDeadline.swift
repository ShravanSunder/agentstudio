import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// One monotonic limit shared by connect, authentication and every partial I/O.
public struct CallDeadline: Sendable {
    private let expiresAt: ContinuousClock.Instant

    public init(limit: Duration) {
        expiresAt = ContinuousClock.now.advanced(by: limit)
    }

    /// Downstream completion work shares the original limit instead of starting another one.
    package var remainingBudget: Duration {
        max(.zero, ContinuousClock.now.duration(to: expiresAt))
    }

    #if canImport(Darwin)
        func checkExpiration() throws {
            guard ContinuousClock.now < expiresAt else {
                throw UnixSocketTransportError(reason: .deadlineExceeded, errnoCode: ETIMEDOUT)
            }
        }

        func wait(fileDescriptor: Int32, events: Int16) throws {
            while true {
                let remaining = ContinuousClock.now.duration(to: expiresAt)
                guard remaining > .zero else {
                    throw UnixSocketTransportError(reason: .deadlineExceeded, errnoCode: ETIMEDOUT)
                }
                let milliseconds = remaining / .milliseconds(1)
                let timeout = Int32(min(Double(Int32.max), milliseconds.rounded(.up)))
                var descriptor = pollfd(fd: fileDescriptor, events: events, revents: 0)
                let result = Darwin.poll(&descriptor, 1, timeout)
                if result < 0 {
                    if errno == EINTR { continue }
                    throw UnixSocketTransportError(reason: .readinessFailed, errnoCode: errno)
                }
                // Recompute after an early timeout, an interrupted wait or a
                // capped poll. Nothing extends the absolute expiration.
                if result == 0 { continue }
                guard descriptor.revents & Int16(POLLNVAL) == 0 else {
                    throw UnixSocketTransportError(reason: .connectionClosed, errnoCode: EBADF)
                }
                try checkExpiration()
                // HUP/ERR also wake the actual nonblocking operation, which
                // reports its established EOF/error semantics (or SO_ERROR).
                return
            }
        }
    #endif
}
