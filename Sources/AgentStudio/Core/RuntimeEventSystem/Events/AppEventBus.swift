package enum AppEventBus {
    package static let shared = EventBus<AppEvent>()

    @inline(__always)
    package static func post(_ event: AppEvent) {
        Task { await shared.post(event) }
    }
}
