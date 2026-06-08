import AppKit
import GhosttyKit

// Simple file-based debug logging
let debugLogPath = "/tmp/agentstudio_debug.log"

func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"

    if let data = logMessage.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: debugLogPath) {
            if let handle = FileHandle(forWritingAtPath: debugLogPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: debugLogPath, contents: data)
        }
    }
}

let ghosttyArguments = GhosttyLaunchArguments.sanitized(CommandLine.arguments)
let ghosttyInitStatus = GhosttyLaunchArguments.withUnsafeArgv(from: ghosttyArguments) { argc, argv in
    ghostty_init(argc, argv)
}

// Initialize Ghostty library first (required before any other calls)
if ghosttyInitStatus != GHOSTTY_SUCCESS {
    print("Fatal: ghostty_init failed")
    exit(1)
}

// Create NSApplication first
let app = NSApplication.shared

// Set activation policy to make it a proper GUI app (required for CLI-launched binaries)
app.setActivationPolicy(.regular)
UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
RestoreTrace.log("main: app activation policy set, debugLogPath=\(debugLogPath)")

let delegate = AppDelegate()
app.delegate = delegate

// Initialize Ghostty terminal engine after NSApplication exists
let ghosttyInitialized = Ghostty.initialize()
if !ghosttyInitialized {
    print("Warning: Failed to initialize Ghostty terminal engine")
} else {
    RestoreTrace.log("main: Ghostty.initialize succeeded")
}

// Activate the app to bring it to front
app.activate(ignoringOtherApps: true)

app.run()
