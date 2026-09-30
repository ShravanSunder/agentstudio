import Foundation

/// SR2a; Program Design item 5: "For warm and unverified panes, one
/// off-main observe after the attach settles is compared by identity with
/// the warm baseline from item 1: a different identity means zmx recreated
/// the session ... a missing baseline or a failed observation means
/// 'couldn't check.' A PID or a clock is never a substitute for identity."
///
/// A pure comparison over two already-opaque identity blobs
/// (`TerminalRestoreKind.warm(identity: Data)`'s own shape,
/// `ZmxSessionIdentity.encoded()`'s deterministic `.sortedKeys` JSON) — no
/// decoding needed, since two encodings of the same logical identity are
/// byte-identical and two different identities are not. This is
/// deliberately only the detection half: how a `.recreated`/`.couldNotCheck`
/// result reaches the person is an open presentation question (Program
/// Design's own S4 stop — "presenting a notice over a live warm surface
/// needs a new UI mechanism" — and `InboxNotificationRouter`'s "intentionally
/// retired... do not reconnect without a new product decision" both apply;
/// see the implementation trace).
package enum PaneRecreationCheckResult: Equatable, Sendable {
    /// The post-attach observation matches the warm baseline exactly.
    case unchanged
    /// A different session now answers where the baseline was observed —
    /// zmx recreated the session under the same name (SR2a).
    case recreated
    /// No baseline existed to compare against (an unverified pane never had
    /// one), or the post-attach observation itself failed. Never presented
    /// as `.recreated` on a mere absence of proof.
    case couldNotCheck
}

package enum PaneRecreationChecker {
    /// `baselineIdentity` is `TerminalRestoreKind.warm(identity:)`'s stored
    /// value for a warm pane, or `nil` for an unverified one (which never
    /// had a baseline to begin with). `observedIdentity` is the result of
    /// one more `ZmxSessionRestoreProbing.observeSessionIdentity(_:)` call
    /// made after the attach settles — `nil` on any observation failure,
    /// matching that API's existing `nil`-on-failure convention. "A PID or
    /// a clock is never a substitute for identity": this compares only the
    /// identity blobs themselves.
    package static func checkForRecreation(
        baselineIdentity: Data?,
        observedIdentity: Data?
    ) -> PaneRecreationCheckResult {
        guard let baselineIdentity, let observedIdentity else {
            return .couldNotCheck
        }
        return baselineIdentity == observedIdentity ? .unchanged : .recreated
    }
}
