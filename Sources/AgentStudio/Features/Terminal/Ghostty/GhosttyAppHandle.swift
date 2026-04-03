import Foundation
import GhosttyKit

extension Ghostty {
    /// Owns the raw Ghostty app/config lifetime and exposes the minimal API
    /// needed by the host composition root.
    final class AppHandle {
        private let appHandle: ghostty_app_t
        private let configHandle: ghostty_config_t

        var app: ghostty_app_t {
            appHandle
        }

        init?(runtimeConfig: ghostty_runtime_config_s) {
            guard let config = ghostty_config_new() else {
                ghosttyLogger.error("Failed to create ghostty config")
                return nil
            }

            ghostty_config_load_default_files(config)
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
    }
}
