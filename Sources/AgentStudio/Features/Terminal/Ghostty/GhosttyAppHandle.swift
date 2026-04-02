import Foundation
import GhosttyKit

extension Ghostty {
    /// Owns the raw Ghostty app/config lifetime and exposes the minimal API
    /// needed by the host composition root.
    final class AppHandle {
        private var handle: (app: ghostty_app_t, config: ghostty_config_t)?

        var app: ghostty_app_t? {
            handle?.app
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

            self.handle = (app: app, config: config)
        }

        deinit {
            if let handle {
                ghostty_app_free(handle.app)
                ghostty_config_free(handle.config)
            }
        }

        func tick() {
            guard let app else { return }
            ghostty_app_tick(app)
        }
    }
}
