import Darwin
import Foundation

/// Wraps a raw `errno` value so it can be the failure side of a `Result`
/// (`Int32` alone does not conform to `Error`).
package struct POSIXErrorNumber: Error, Equatable, Sendable {
    package let rawValue: Int32

    package init(_ rawValue: Int32) {
        self.rawValue = rawValue
    }
}

/// The raw Darwin calls `ColdStartObserver` makes at its two register
/// points (Program Design revision 11, item 3): opening the zmx directory
/// for `EVFILT_VNODE` watching, and reading `KERN_PROCARGS2` for the
/// handoff token, which lives in the leader's **arguments** -- macOS
/// returns no environment to a third-party reader for any process
/// (confirmed against XNU's `kern_sysctl.c` and reproduced independently on
/// macOS 26.5 with SIP on), so only argv is ever read here. A seam so tests
/// can inject a specific failure at the boundary without provoking the real
/// syscall into failing -- "a registration error or unreadable process
/// args, injected at the Darwin call boundary with a test double of the
/// syscall wrapper only" (S3 proof list). The real zmx/process paths stay
/// proven against real zmx and real processes elsewhere; this seam exists
/// only for the two `.unobservable` cases that are otherwise unreachable in
/// a test.
package protocol ColdStartObserverSyscalls: Sendable {
    /// Opens `path` (the zmx directory) for `EVFILT_VNODE` watching.
    /// `.failure(errno)` on failure, for `ColdStartUnobservableReason
    /// .watchRegistrationFailed`. Carries `errno` itself rather than
    /// leaving the caller to read the global `errno` later, since that
    /// value does not survive an actor hop reliably.
    func openDirectoryForWatching(path: String) -> Result<Int32, POSIXErrorNumber>

    /// Reads the raw `KERN_PROCARGS2` buffer for `pid` -- only its argument
    /// vector is used; the buffer's environment section, if any, is never
    /// parsed. `.failure(errno)` on any sysctl failure, mapped to
    /// `ColdStartUnobservableReason.processArgsUnreadable`.
    func readProcessArgumentsBuffer(pid: Int32) -> Result<[UInt8], POSIXErrorNumber>
}

/// The real Darwin implementation. Kept separate from the protocol so a
/// specific-failure test double never has to touch `sysctl`/`open` at all.
package struct DarwinColdStartObserverSyscalls: ColdStartObserverSyscalls {
    package init() {}

    package func openDirectoryForWatching(path: String) -> Result<Int32, POSIXErrorNumber> {
        let descriptor = open(path, O_EVTONLY)
        return descriptor >= 0 ? .success(descriptor) : .failure(POSIXErrorNumber(errno))
    }

    package func readProcessArgumentsBuffer(pid: Int32) -> Result<[UInt8], POSIXErrorNumber> {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else {
            return .failure(POSIXErrorNumber(errno))
        }
        var buffer = [UInt8](repeating: 0, count: size)
        let result = buffer.withUnsafeMutableBytes { pointer -> Int32 in
            var mutableSize = size
            return sysctl(&mib, 3, pointer.baseAddress, &mutableSize, nil, 0)
        }
        guard result == 0 else { return .failure(POSIXErrorNumber(errno)) }
        return .success(buffer)
    }
}
