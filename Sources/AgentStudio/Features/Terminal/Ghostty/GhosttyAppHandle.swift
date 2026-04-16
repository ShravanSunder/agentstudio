import Foundation
import GhosttyKit

extension Ghostty {
    /// Owns the raw Ghostty app/config lifetime and exposes the minimal API
    /// needed by the host composition root.
    final class AppHandle {
        private let appHandle: ghostty_app_t
        private let configHandle: ghostty_config_t
        static let scrollBehaviorOverrideContents = """
            scroll-to-bottom = no-keystroke, no-output
            """

        var app: ghostty_app_t {
            appHandle
        }

        private static func writeGhosttyOverrideFile() throws -> URL {
            let overrideURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("agent-studio-ghostty-overrides-\(UUID().uuidString).conf")
            try scrollBehaviorOverrideContents.write(
                to: overrideURL,
                atomically: true,
                encoding: .utf8
            )
            return overrideURL
        }

        init?(runtimeConfig: ghostty_runtime_config_s) {
            guard let config = ghostty_config_new() else {
                ghosttyLogger.error("Failed to create ghostty config")
                return nil
            }

            ghostty_config_load_default_files(config)
            do {
                let overrideURL = try Self.writeGhosttyOverrideFile()
                overrideURL.path.withCString { path in
                    ghostty_config_load_file(config, path)
                }
            } catch {
                ghosttyLogger.error(
                    "Failed to write Ghostty scroll behavior override file: \(error.localizedDescription, privacy: .public). Host follow-bottom behavior may degrade."
                )
            }
            ghostty_config_finalize(config)

            var mutableRuntimeConfig = runtimeConfig
            guard let app = ghostty_app_new(&mutableRuntimeConfig, config) else {
                ghosttyLogger.error("Failed to create ghostty app")
                ghostty_config_free(config)
                return nil
            }

            self.appHandle = app
            self.configHandle = config
        }

        deinit {
            ghostty_app_free(appHandle)
            ghostty_config_free(configHandle)
        }

        @MainActor
        func tick() {
            ghostty_app_tick(appHandle)
        }

        func hostConfigSnapshot() -> GhosttyHostConfigSnapshot {
            GhosttyHostConfigSnapshot(configHandle: configHandle)
        }
    }
}
