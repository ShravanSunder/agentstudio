import Foundation

enum PaneRuntimeEventBus {
    static let performanceReporter = RuntimeDeliveryPerformanceReporter()

    static let shared = EventBus<RuntimeEnvelope>(
        name: "paneRuntime",
        replayConfiguration: .init(
            capacityPerSource: 256,
            sourceKey: { envelope in
                envelope.source.description
            }
        ),
        performanceReporter: performanceReporter
    )
}
