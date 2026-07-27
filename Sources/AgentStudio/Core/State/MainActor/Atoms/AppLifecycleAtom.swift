import Foundation
import Observation

@Observable
@MainActor
package final class AppLifecycleAtom {
    package private(set) var isActive = false
    package private(set) var isTerminating = false

    package init() {}

    package func setActive(_ isActive: Bool) {
        self.isActive = isActive
    }

    package func markTerminating() {
        isTerminating = true
    }
}
