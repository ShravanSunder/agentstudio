import Foundation

/// Central policy for deciding when deferred startup (zmx attach) is safe to run.
///
/// We delay attach until terminal geometry is resolved so restored sessions inherit
/// the correct cols/rows instead of placeholder dimensions.
enum DeferredStartupReadiness {
    static func canSchedule(
        hasSent: Bool,
        deferredStartupCommand: String?,
        hasWindow: Bool,
        contentSize: CGSize
    ) -> Bool {
        guard !hasSent else { return false }
        guard let deferredStartupCommand else { return false }
        guard !deferredStartupCommand.isEmpty else { return false }
        guard hasWindow else { return false }
        guard contentSize.width > 0 && contentSize.height > 0 else { return false }
        return true
    }

    static func canExecute(
        hasSent: Bool,
        deferredStartupCommand: String?,
        hasWindow: Bool,
        contentSize: CGSize,
        processExited: Bool
    ) -> Bool {
        guard canSchedule(
            hasSent: hasSent,
            deferredStartupCommand: deferredStartupCommand,
            hasWindow: hasWindow,
            contentSize: contentSize
        ) else { return false }
        guard !processExited else { return false }
        return true
    }
}
