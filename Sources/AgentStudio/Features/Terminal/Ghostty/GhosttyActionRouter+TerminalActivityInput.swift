import Foundation

@MainActor
private final class GhosttyTerminalActivityInputBinding {
    var id: UUID?
    var context: (@MainActor @Sendable (UUID) -> TerminalActivityProjectionContext)?
    var sink: (@MainActor @Sendable (TerminalActivitySourceInput) async -> Void)?
}

@MainActor private let ghosttyTerminalActivityInputBinding = GhosttyTerminalActivityInputBinding()

extension Ghostty.ActionRouter {
    @MainActor
    static func bindTerminalActivityInput(
        id: UUID,
        context: @escaping @MainActor @Sendable (UUID) -> TerminalActivityProjectionContext,
        sink: @escaping @MainActor @Sendable (TerminalActivitySourceInput) async -> Void
    ) {
        ghosttyTerminalActivityInputBinding.id = id
        ghosttyTerminalActivityInputBinding.context = context
        ghosttyTerminalActivityInputBinding.sink = sink
    }

    @MainActor
    static func unbindTerminalActivityInput(id: UUID) {
        guard ghosttyTerminalActivityInputBinding.id == id else { return }
        ghosttyTerminalActivityInputBinding.id = nil
        ghosttyTerminalActivityInputBinding.context = nil
        ghosttyTerminalActivityInputBinding.sink = nil
    }

    @MainActor
    static func submitTerminalActivityInput(_ input: TerminalActivitySourceInput) async {
        await ghosttyTerminalActivityInputBinding.sink?(input)
    }

    @MainActor
    static func terminalActivityProjectionContext(paneID: UUID) -> TerminalActivityProjectionContext? {
        ghosttyTerminalActivityInputBinding.context?(paneID)
    }
}
