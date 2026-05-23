import Foundation

/// Pane identity known to belong to a tab's main arrangement layout.
struct MainPaneId: Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue.uuidString }
}

/// Pane identity known to belong to a drawer child layout.
struct DrawerPaneId: Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue.uuidString }
}

/// Drawer container identity.
///
/// This brand is intentionally lighter-weight than changing every dictionary
/// key in the first pass. Use it at API and derived-state boundaries where a
/// drawer ID could be confused with a pane ID.
struct DrawerId: Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue.uuidString }
}

extension Collection where Element == MainPaneId {
    var rawUUIDs: [UUID] { map(\.rawValue) }
}

extension Set where Element == MainPaneId {
    var rawUUIDs: Set<UUID> { Set<UUID>(map(\.rawValue)) }

    func filtering(toRawPaneIds paneIds: Set<UUID>) -> Set<MainPaneId> {
        filter { paneIds.contains($0.rawValue) }
    }
}

extension Collection where Element == DrawerPaneId {
    var rawUUIDs: [UUID] { map(\.rawValue) }
}

extension Set where Element == DrawerPaneId {
    var rawUUIDs: Set<UUID> { Set<UUID>(map(\.rawValue)) }

    func filtering(toRawPaneIds paneIds: Set<UUID>) -> Set<DrawerPaneId> {
        filter { paneIds.contains($0.rawValue) }
    }
}
