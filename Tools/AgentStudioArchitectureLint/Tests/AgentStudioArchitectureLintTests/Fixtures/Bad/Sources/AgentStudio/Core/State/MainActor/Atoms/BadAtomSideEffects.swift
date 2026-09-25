import Foundation
import Observation

final class BadSideEffectAtom {
    private(set) var names: [String] = []

    func load() {
        _ = FileManager.default.fileExists(atPath: "/tmp")
        DispatchQueue.main.async {}
        _ = Timer(timeInterval: 1, repeats: false) { _ in }
        _ = Process()
        _ = URLSession.shared
        sqlite3_open("db", nil)
        Task { @MainActor in }
        Task.detached {}
        names = names.sorted()
        withObservationTracking {
            _ = names
        } onChange: {
        }
    }
}
