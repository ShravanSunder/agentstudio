import AgentStudioInfrastructure
import Foundation

package enum PaneRuntimeEventBus {
    package static let performanceReporter = RuntimeDeliveryPerformanceReporter()

    package static let shared = EventBus<RuntimeEnvelope>(
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
