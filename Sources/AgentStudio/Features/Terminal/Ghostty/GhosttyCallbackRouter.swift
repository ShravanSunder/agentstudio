import AppKit
import Foundation
import GhosttyKit

extension Ghostty {
    /// Owns the embedded Ghostty callback table and reconstructs Swift objects
    /// from userdata for wakeup, clipboard, and close-surface callbacks before
    /// handing work back to the main actor. `action_cb` forwards the app pointer
    /// directly into `ActionRouter`.
    enum CallbackRouter {
        static func runtimeConfig(userdataPointer: UnsafeMutableRawPointer) -> ghostty_runtime_config_s {
            ghostty_runtime_config_s(
                userdata: userdataPointer,
                supports_selection_clipboard: true,
                wakeup_cb: { userdata in
                    guard let userdata else {
                        ghosttyLogger.error("Ghostty wakeup callback dropped: userdata was nil")
                        return
                    }
                    // Capture the raw pointer as integer bits before the actor hop so the
                    // closure crosses the Sendable boundary without carrying the pointer value.
                    let userdataBits = UInt(bitPattern: userdata)
                    Task { @MainActor in
                        let userdata = UnsafeMutableRawPointer(bitPattern: userdataBits)!
                        let app = Unmanaged<App>.fromOpaque(userdata).takeUnretainedValue()
                        app.tick()
                    }
                },
                action_cb: { appPtr, target, action in
                    guard let appPtr else {
                        ghosttyLogger.fault("Ghostty action callback dropped: app pointer was nil")
                        return false
                    }
                    return ActionRouter.handleAction(appPtr, target: target, action: action)
                },
                read_clipboard_cb: { userdata, location, state in
                    Self.readClipboard(userdata, location: location, state: state)
                },
                confirm_read_clipboard_cb: { userdata, str, state, request in
                    Self.confirmReadClipboard(userdata, string: str, state: state, request: request)
                },
                write_clipboard_cb: { userdata, location, content, len, confirm in
                    Self.writeClipboard(
                        userdata,
                        location: location,
                        content: content,
                        len: len,
                        confirm: confirm
                    )
                },
                close_surface_cb: { userdata, processAlive in
                    Self.closeSurface(userdata, processAlive: processAlive)
                }
            )
        }

        private static func readClipboard(
            _ userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e, state: UnsafeMutableRawPointer?
        ) -> Bool {
            guard let userdata else {
                ghosttyLogger.debug("Ghostty readClipboard callback dropped: userdata was nil")
                return false
            }
            let surfaceView = Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = surfaceView.surface else {
                ghosttyLogger.debug("Ghostty readClipboard callback dropped: surface view had no live surface")
                return false
            }

            let pasteboard = NSPasteboard.general
            let content = pasteboard.string(forType: .string) ?? ""
            content.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
            }
            return true
        }

        #if DEBUG
            static func readClipboardForTesting(
                _ userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e, state: UnsafeMutableRawPointer?
            ) -> Bool {
                Self.readClipboard(userdata, location: location, state: state)
            }
        #endif

        private static func confirmReadClipboard(
            _ userdata: UnsafeMutableRawPointer?, string: UnsafePointer<CChar>?, state: UnsafeMutableRawPointer?,
            request: ghostty_clipboard_request_e
        ) {
            guard let userdata else {
                ghosttyLogger.debug("Ghostty confirmReadClipboard callback dropped: userdata was nil")
                return
            }
            let surfaceView = Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = surfaceView.surface else {
                ghosttyLogger.debug("Ghostty confirmReadClipboard callback dropped: surface view had no live surface")
                return
            }

            if let str = string {
                ghostty_surface_complete_clipboard_request(surface, str, state, true)
            }
        }

        private static func writeClipboard(
            _ userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e,
            content: UnsafePointer<ghostty_clipboard_content_s>?, len: Int, confirm: Bool
        ) {
            guard userdata != nil else {
                ghosttyLogger.debug("Ghostty writeClipboard callback dropped: userdata was nil")
                return
            }
            guard let content, len > 0 else {
                ghosttyLogger.debug("Ghostty writeClipboard callback dropped: clipboard content was empty")
                return
            }

            let pasteboard = NSPasteboard.general
            let item = content[0]
            guard let data = item.data else { return }
            let str = String(cString: data)

            pasteboard.clearContents()
            pasteboard.setString(str, forType: .string)
        }

        private static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
            guard let userdata else {
                ghosttyLogger.debug("Ghostty closeSurface callback dropped: userdata was nil")
                return
            }
            let surfaceView = Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
            RestoreTrace.log(
                "Ghostty.CallbackRouter.closeSurface view=\(ObjectIdentifier(surfaceView)) processAlive=\(processAlive)"
            )
            let surfaceViewObjectId = ObjectIdentifier(surfaceView)
            Task { @MainActor [weak surfaceView] in
                guard let surfaceView else { return }
                RestoreTrace.log(
                    "Ghostty.CallbackRouter.closeSurface delivering direct close callback view=\(surfaceViewObjectId) processAlive=\(processAlive)"
                )
                surfaceView.handleCloseRequested(processAlive: processAlive)
            }
        }
    }
}
