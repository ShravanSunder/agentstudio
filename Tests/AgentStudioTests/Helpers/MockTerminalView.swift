import AppKit

@testable import AgentStudio

/// Minimal NSView mock satisfying SplitTree's generic constraints.
/// Used in place of AgentStudioTerminalView for pure unit tests.
@MainActor
final class MockTerminalView: NSView, Identifiable {
    let id: UUID
    let name: String

    init(id: UUID = UUID(), name: String = "mock") {
        self.id = id
        self.name = name
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
}

/// Convenience typealias for tests
typealias TestSplitTree = SplitTree<MockTerminalView>
