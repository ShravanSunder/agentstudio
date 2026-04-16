import Foundation

typealias PaneFocusTriggerHandler = @MainActor (PaneFocusTrigger) -> Void

typealias PaneFocusRefocusHandler = @MainActor (PaneRefocusRequestTrigger.Reason) -> Void
