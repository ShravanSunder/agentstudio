import Foundation

public enum IPCSidebarSurface: String, Codable, Equatable, Sendable {
    case repo
    case inbox
}

public enum IPCSidebarGroupingMode: String, Codable, Equatable, Sendable {
    case repo
    case pane
    case tab
    case noGrouping = "none"
}

public struct IPCSidebarGroupingSetParams: Codable, Equatable, Sendable {
    public let surface: IPCSidebarSurface
    public let mode: IPCSidebarGroupingMode
    public let correlationId: UUID?

    public init(surface: IPCSidebarSurface, mode: IPCSidebarGroupingMode, correlationId: UUID? = nil) {
        self.surface = surface
        self.mode = mode
        self.correlationId = correlationId
    }
}

public struct IPCSidebarGroupingGetParams: Codable, Equatable, Sendable {
    public let surface: IPCSidebarSurface

    public init(surface: IPCSidebarSurface) {
        self.surface = surface
    }
}

public struct IPCSidebarGroupingResult: Codable, Equatable, Sendable {
    public let surface: IPCSidebarSurface
    public let mode: IPCSidebarGroupingMode
    public let correlationId: UUID?

    public init(surface: IPCSidebarSurface, mode: IPCSidebarGroupingMode, correlationId: UUID? = nil) {
        self.surface = surface
        self.mode = mode
        self.correlationId = correlationId
    }
}

public struct IPCSidebarSurfaceSetParams: Codable, Equatable, Sendable {
    public let surface: IPCSidebarSurface
    public let correlationId: UUID?

    public init(surface: IPCSidebarSurface, correlationId: UUID? = nil) {
        self.surface = surface
        self.correlationId = correlationId
    }
}

public struct IPCSidebarSurfaceGetParams: Codable, Equatable, Sendable {
    public init() {}
}

public struct IPCSidebarSurfaceResult: Codable, Equatable, Sendable {
    public let surface: IPCSidebarSurface
    public let correlationId: UUID?

    public init(surface: IPCSidebarSurface, correlationId: UUID? = nil) {
        self.surface = surface
        self.correlationId = correlationId
    }
}
