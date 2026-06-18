import Foundation

enum GhosttyStartupEnvironment {
    @discardableResult
    static func apply() -> String? {
        guard let resourcesDir = SessionConfiguration.resolveGhosttyResourcesDir() else {
            RestoreTrace.log("GHOSTTY_RESOURCES_DIR unresolved")
            return nil
        }

        setenv("GHOSTTY_RESOURCES_DIR", resourcesDir, 1)
        let terminfoDir = URL(fileURLWithPath: resourcesDir)
            .deletingLastPathComponent()
            .appendingPathComponent("terminfo")
            .path
        setenv("TERMINFO", terminfoDir, 1)

        if let executableDir = Bundle.main.executableURL?.deletingLastPathComponent().path {
            setenv("GHOSTTY_BIN_DIR", executableDir, 1)
        }

        RestoreTrace.log("GHOSTTY_RESOURCES_DIR=\(resourcesDir)")
        RestoreTrace.log("TERMINFO=\(terminfoDir)")
        return resourcesDir
    }
}
