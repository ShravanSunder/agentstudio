import AppKit
import Foundation

struct EditorTargetId: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

struct EditorChoiceItem: Identifiable {
    let id: EditorTargetId
    let title: String
    let appIcon: NSImage?
    let shortcutNumber: Int
}
