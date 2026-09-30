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
/// points (Program Design item 3): opening the zmx directory for
/// `EVFILT_VNODE` watching, and reading `KERN_PROCARGS2` for the handoff
/// marker. A seam so tests can inject a specific failure at the boundary
/// without provoking the real syscall into failing -- "a registration error
/// or unreadable process args, injected at the Darwin call boundary with a
/// test double of the syscall wrapper only" (S3 proof list). The real
/// zmx/process paths stay proven against real zmx and real processes
/// elsewhere; this seam exists only for the two `.unobservable` cases that
/// are otherwise unreachable in a test.
package protocol ColdStartObserverSyscalls: Sendable {
    /// Opens `path` (the zmx directory) for `EVFILT_VNODE` watching.
    /// `.failure(errno)` on failure, for `ColdStartUnobservableReason
    /// .watchRegistrationFailed`. Carries `errno` itself rather than
    /// leaving the caller to read the global `errno` later, since that
    /// value does not survive an actor hop reliably.
    func openDirectoryForWatching(path: String) -> Result<Int32, POSIXErrorNumber>

    /// Reads the raw `KERN_PROCARGS2` buffer for `pid`. `.failure(errno)`ing
    /// on any sysctl failure, mapped to `ColdStartUnobservableReason
    /// .processArgsUnreadable`.
    ///
    /// **Unverified in production** (2026-09-30): XNU's `sysctl_procargsx`
    /// (`bsd/kern/kern_sysctl.c`) includes the environment portion of this
    /// buffer only when the target is not `cs_restricted` **at runtime** (a
    /// dynamic flag, distinct from `codesign`'s static signature flags), a
    /// SIP/CSR exception applies, the target is the caller itself, or the
    /// caller holds Apple's private `com.apple.private.read-environment
    /// -variables` entitlement -- which ordinary Developer ID apps cannot
    /// obtain. Reading a freshly-`posix_spawn`'d `/bin/zsh -i -l` child
    /// (this repo's exact cold-restore shape, `ZmxBackend.swift:271`)
    /// returned argv but zero environment bytes in ad hoc-signed testing.
    /// Whether a properly signed, notarized AgentStudio.app reading its own
    /// spawned child behaves differently has not been verified against a
    /// real signed build. If it doesn't, every cold pane reads
    /// `.environmentOmitted` in production, and Program Design item 3's
    /// marker mechanism needs a different channel (see the STOP raised for
    /// this in the implementation trace).
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
