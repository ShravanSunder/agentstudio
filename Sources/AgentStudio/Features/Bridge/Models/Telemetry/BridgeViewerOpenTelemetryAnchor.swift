import Foundation

/// Ephemeral correlation captured when an App action begins opening a new Bridge pane.
///
/// The value travels directly through pane construction into document-start telemetry.
/// It is never persisted as pane or workspace state.
package struct BridgeViewerOpenTelemetryAnchor: Equatable, Sendable {
    package let openEpochUnixMillis: Int
    package let traceparent: String?

    package init(
        openEpochUnixMillis: Int,
        traceparent: String?
    ) {
        self.openEpochUnixMillis = openEpochUnixMillis
        self.traceparent = traceparent
    }

    package static func live() -> Self {
        Self(
            openEpochUnixMillis: Int(Date().timeIntervalSince1970 * 1000),
            traceparent: BridgeTraceContextFactory.live.makeRootContext()?.traceparent
        )
    }
}
