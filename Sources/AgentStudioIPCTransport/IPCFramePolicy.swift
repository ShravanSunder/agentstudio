import Foundation

/// The two NDJSON frame bounds, which answer different questions and therefore
/// carry different values.
///
/// The inbound bound is a resource guard: an unauthenticated peer must not be
/// able to make this process buffer without limit, so a request frame stays at
/// one mebibyte. The outbound bound is a content bound on frames this process
/// composes itself. `system.capabilities` carries every method's parameter and
/// result schema, so the honest answer is already larger than the inbound
/// guard; capping our own self-description at the hostile-peer limit turned a
/// correct response into a transport failure.
///
/// This type lives in the transport because both the app server and the client
/// core must agree on the bound without either importing the other.
public enum IPCFramePolicy {
    /// Inbound request frames. A peer that exceeds this is refused before the
    /// process commits memory to it.
    public static let maximumRequestFrameBytes = 1_048_576

    /// Outbound response and notification frames. Sized for the complete
    /// self-describing method catalog with room for it to grow.
    public static let maximumResponseFrameBytes = 16_777_216
}
