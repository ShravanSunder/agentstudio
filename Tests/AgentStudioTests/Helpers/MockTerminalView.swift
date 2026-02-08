import AppKit
@testable import AgentStudio

/// Minimal NSView mock satisfying SplitTree's generic constraints.
/// Used in place of AgentStudioTerminalView for pure unit tests.
final class MockTerminalView: NSView, Identifiable, Codable {
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

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        self.init(id: id, name: name)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
    }
}

/// Convenience typealias for tests
typealias TestSplitTree = SplitTree<MockTerminalView>
