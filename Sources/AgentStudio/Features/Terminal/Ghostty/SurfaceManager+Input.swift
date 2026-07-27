import Foundation
import GhosttyKit

extension SurfaceManager {
    func sendInput(_ input: String, toPaneId paneId: UUID) -> Result<Void, SurfaceError> {
        guard let surfaceId = surfaceId(forPaneId: paneId) else {
            return .failure(.surfaceNotFound)
        }

        return withSurface(surfaceId) { surface in
            sendInputAsText(input, to: surface)
        }.map { _ in () }
    }

    func clearScrollback(forPaneId paneId: UUID) -> Result<Void, SurfaceError> {
        guard let surfaceId = surfaceId(forPaneId: paneId) else {
            return .failure(.surfaceNotFound)
        }

        let clearScreenAction = "clear_screen"
        let didPerform = withSurface(surfaceId) { surface in
            clearScreenAction.withCString { ptr in
                ghostty_surface_binding_action(surface, ptr, UInt(clearScreenAction.utf8.count))
            }
        }

        switch didPerform {
        case .success(true):
            return .success(())
        case .success(false):
            return .failure(.operationFailed("Ghostty rejected clear_screen binding action"))
        case .failure(let error):
            return .failure(error)
        }
    }

    private func sendInputAsText(_ input: String, to surface: ghostty_surface_t) {
        var textChunk = ""
        for character in input {
            if character == "\n" || character == "\r" {
                sendTextChunk(textChunk, to: surface)
                textChunk.removeAll(keepingCapacity: true)
                sendEnterKeyEvent(to: surface)
            } else {
                textChunk.append(character)
            }
        }

        sendTextChunk(textChunk, to: surface)
    }

    private func sendTextChunk(_ text: String, to surface: ghostty_surface_t) {
        let length = text.utf8.count
        guard length > 0 else { return }

        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(length))
        }
    }

    private func sendEnterKeyEvent(to surface: ghostty_surface_t) {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.mods = GHOSTTY_MODS_NONE
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.keycode = 36
        keyEvent.text = nil
        keyEvent.unshifted_codepoint = 13
        keyEvent.composing = false
        ghostty_surface_key(surface, keyEvent)
    }
}
