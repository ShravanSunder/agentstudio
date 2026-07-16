import Foundation

/// The one pane-admission claim minted at a product or native-job ingress.
///
/// The context carries the original epoch through suspension. Mutation owners
/// validate it synchronously at the mutation boundary; no downstream owner may
/// reacquire admission after work has started.
struct BridgeProductAdmissionContext: Sendable {
    fileprivate let gate: BridgeProductAdmissionGate
    fileprivate let token: BridgeProductAdmissionGate.Token

    func withValidAdmission<MutationResult>(
        _ mutation: () throws -> MutationResult
    ) rethrows -> MutationResult? {
        try gate.withValidAdmission(token, perform: mutation)
    }

    func matches(_ other: Self) -> Bool {
        gate === other.gate && token.matches(other.token)
    }

    func wasMinted(by expectedGate: BridgeProductAdmissionGate) -> Bool {
        gate === expectedGate
    }
}

/// Synchronously linearizes pane admission with terminal pane teardown.
///
/// Callers carry the original token across suspension, then perform each visible
/// mutation through ``withValidAdmission(_:perform:)``. The mutation closure is
/// synchronous so the gate never holds its lock across an `await`.
final class BridgeProductAdmissionGate: @unchecked Sendable {
    fileprivate final class Identity: Sendable {}

    struct Token: Sendable {
        fileprivate let gateIdentity: Identity
        fileprivate let epoch: UInt64

        fileprivate func matches(_ other: Self) -> Bool {
            gateIdentity === other.gateIdentity && epoch == other.epoch
        }
    }

    struct DiagnosticSnapshot: Equatable, Sendable {
        let isOpen: Bool
        let epoch: UInt64
    }

    private let lock = NSLock()
    private let identity = Identity()
    private var isOpen = true
    private var epoch: UInt64 = 0

    var diagnosticSnapshot: DiagnosticSnapshot {
        lock.withLock {
            DiagnosticSnapshot(isOpen: isOpen, epoch: epoch)
        }
    }

    func acquire() -> BridgeProductAdmissionContext? {
        lock.withLock {
            guard isOpen else { return nil }
            return BridgeProductAdmissionContext(
                gate: self,
                token: Token(gateIdentity: identity, epoch: epoch)
            )
        }
    }

    func withValidAdmission<MutationResult>(
        _ token: Token,
        perform mutation: () throws -> MutationResult
    ) rethrows -> MutationResult? {
        try lock.withLock {
            guard
                isOpen,
                token.gateIdentity === identity,
                token.epoch == epoch
            else {
                return nil
            }
            return try mutation()
        }
    }

    func close() {
        lock.withLock {
            guard isOpen else { return }
            isOpen = false
            epoch += 1
        }
    }
}
