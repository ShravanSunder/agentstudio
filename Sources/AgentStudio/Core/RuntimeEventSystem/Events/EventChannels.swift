import Foundation

enum PaneRuntimeEventBus {
    static let shared = EventBus<RuntimeEnvelope>(
        replayConfiguration: .init(
            capacityPerSource: 256,
            sourceKey: { envelope in
                envelope.source.description
            }
        )
    )
}
