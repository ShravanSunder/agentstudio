import Foundation

extension UserDefaults: URLHistoryStorage {
    func set(_ data: Data?, forKey key: String) {
        set(data as Any?, forKey: key)
    }
}
