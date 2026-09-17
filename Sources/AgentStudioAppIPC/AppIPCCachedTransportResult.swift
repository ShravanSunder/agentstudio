import AgentStudioIPCTransport
import Foundation

/// One immutable response, encoded for the wire once and then served.
///
/// The two catalog methods answer with a value that is fixed for a runtime and
/// a channel. Composing it already happens once, at server composition, but
/// every request still re-encoded it through the typed contract: a JSON encode,
/// a full schema normalization, a typed-encoding validation and a decode into
/// the transport's `JSONValue`, four passes over the largest document this app
/// produces. That work is identical every time, so it is done once here.
///
/// Nothing invalidates this. Round 1 registers no method or command
/// dynamically, so the catalog a runtime advertises cannot change while it is
/// running. A later round that adds dynamic registration has to replace this
/// with something that can be invalidated, not extend it.
package final class AppIPCCachedTransportResult: @unchecked Sendable {
    private let lock = NSLock()
    private let compose: @Sendable () throws -> JSONValue
    private var cachedValue: JSONValue?

    package init(compose: @escaping @Sendable () throws -> JSONValue) {
        self.compose = compose
    }

    /// Composition runs outside the lock, so two racing first requests may both
    /// encode. They encode the same immutable value and the first stored one
    /// wins, which is cheaper than holding a lock across the work.
    package func value() throws -> JSONValue {
        if let cachedValue = lock.withLock({ cachedValue }) { return cachedValue }
        let composed = try compose()
        return lock.withLock {
            if let cachedValue { return cachedValue }
            cachedValue = composed
            return composed
        }
    }

    /// Whether the encoded response has been produced yet, for tests that need
    /// to prove it happens once.
    package var hasComposedValue: Bool {
        lock.withLock { cachedValue != nil }
    }
}
