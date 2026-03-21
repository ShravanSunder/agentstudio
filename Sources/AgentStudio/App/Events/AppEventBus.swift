enum AppEventBus {
    static let shared = EventBus<AppEvent>()

    @inline(__always)
    static func post(_ event: AppEvent) {
        Task { await shared.post(event) }
    }
}
