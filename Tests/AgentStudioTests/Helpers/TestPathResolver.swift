import Foundation

enum TestPathResolver {
    static func projectRoot(from filePath: String) -> String {
        var current = URL(fileURLWithPath: filePath)

        for _ in 0..<20 {
            current = current.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("Package.swift").path) {
                return current.path
            }
        }

        return current.path
    }
}
