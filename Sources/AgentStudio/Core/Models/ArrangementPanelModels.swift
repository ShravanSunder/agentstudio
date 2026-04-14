import Foundation

struct PaneVisibilityInfo: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isMinimized: Bool
}

struct ArrangementInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isDefault: Bool
    let isActive: Bool
}
