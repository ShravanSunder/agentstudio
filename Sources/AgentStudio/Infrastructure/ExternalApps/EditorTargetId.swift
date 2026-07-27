import Foundation

package struct EditorTargetId: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    package let rawValue: String

    package init(rawValue: String) {
        self.rawValue = rawValue
    }

    package init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}
