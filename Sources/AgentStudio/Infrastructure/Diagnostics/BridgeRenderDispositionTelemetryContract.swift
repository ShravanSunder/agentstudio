import Foundation

enum BridgeRenderDispositionTelemetryContract {
    static let eventNames: Set<String> = [
        "performance.bridge.web.render_disposition_admission",
        "performance.bridge.worker.render_disposition_batch",
    ]

    static let numericAttributeKeys: Set<String> = [
        "agentstudio.bridge.render_disposition.accepted_count",
        "agentstudio.bridge.render_disposition.batch_receipt_count",
        "agentstudio.bridge.render_disposition.duplicate_count",
        "agentstudio.bridge.render_disposition.oldest_pending_age_ms",
        "agentstudio.bridge.render_disposition.pending_count",
        "agentstudio.bridge.render_disposition.pending_high_water_mark",
        "agentstudio.bridge.render_disposition.produced_count",
        "agentstudio.bridge.render_disposition.rejected_count",
    ]

    static let phaseValues: Set<String> = [
        "render_disposition_admission_cleared",
        "render_disposition_admission_overloaded",
        "render_disposition_batch_applied",
        "render_disposition_batch_dispatched",
        "render_disposition_batch_terminal",
    ]
}
