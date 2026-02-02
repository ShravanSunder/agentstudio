import AppKit
import GhosttyKit

// Initialize Ghostty library first (required before any other calls)
if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
    print("Fatal: ghostty_init failed")
    exit(1)
}

// Create NSApplication first
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Initialize Ghostty terminal engine after NSApplication exists
let ghosttyInitialized = Ghostty.initialize()
if !ghosttyInitialized {
    print("Warning: Failed to initialize Ghostty terminal engine")
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
