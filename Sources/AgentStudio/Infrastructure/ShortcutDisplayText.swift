import Foundation

package struct ShortcutDisplayText: Equatable, Sendable {
    package let value: String

    package init(value: String) {
        self.value = value
    }
}
