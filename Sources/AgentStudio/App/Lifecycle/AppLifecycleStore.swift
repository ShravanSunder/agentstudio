import Foundation
import Observation

@Observable
@MainActor
final class AppLifecycleStore {
    private(set) var isActive = false
    private(set) var isTerminating = false

    func setActive(_ isActive: Bool) {
        self.isActive = isActive
    }

    func markTerminating() {
        isTerminating = true
    }
}
