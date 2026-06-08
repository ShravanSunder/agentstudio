# 2026-06-08 macOS 26.4 beta lifecycle crash

## Summary

AgentStudio Beta `0.0.54-beta.12` build `64` on macOS `26.4.1` wrote a Ghostty
Sentry crash envelope, but the decoded minidump points at a host-app Swift trap:
`AppDelegate.applicationDidBecomeActive(_:)` was called before workspace boot had
initialized `applicationLifecycleMonitor`.

The crash is not currently explained by SQLite restore or Ghostty Metal rendering.
Ghostty's Sentry/Breakpad integration captured the abort because the host app embeds
Ghostty.

DeepWiki context for `ghostty-org/ghostty` matches this interpretation: Ghostty
initializes process-wide Sentry native crash reporting through its startup/global state
path and writes `.ghosttycrash` Sentry envelopes under `~/.local/state/ghostty/crash`.
Because the handler is process-wide, a host app abort can be captured even when the
faulting frame is in host Swift/AppKit code rather than a Ghostty renderer frame.
DeepWiki also notes Ghostty crash reports may be generated/written on the next launch,
so the file modification time can be later than the event timestamp inside the envelope.

## Evidence

- Bundle: `/Applications/AgentStudio Beta.app`
- Bundle identifier: `com.agentstudio.app.beta`
- Version: `0.0.54-beta.12`, build `64`, channel `beta`
- Crash envelope:
  `/Users/shravansunder/.local/state/ghostty/crash/01458e07-3765-4f49-8a86-2dee85dcb0fc.ghosttycrash`
- Extracted minidump:
  `tmp/agentstudio-beta-debug-2026-06-08/minidump/ghostty-01458e07.dmp`
- Minidump exception:
  `ExceptionCode.EXCEPTION_SIGIOT`, exception address `0x100e79694`
- `atos`:
  `AppDelegate.applicationDidBecomeActive(_:) (in AgentStudio) + 236`
- Installed beta UUID:
  `8EA237D6-E0C3-33BB-B42C-6814DBD6C32B (arm64)`
- Sentry image base for the beta binary:
  `0x100e48000`
- Unslid crash address:
  `0x100031694`

Disassembly at the unslid address:

```text
00000001000315cc  ldr x19, [x20, x8]
00000001000315d0  cbz x19, 0x100031694
...
0000000100031694  brk #0x1
```

That is the nil-trap path for `applicationLifecycleMonitor` in:

```swift
func applicationDidBecomeActive(_ notification: Notification) {
    applicationLifecycleMonitor.handleApplicationDidBecomeActive()
}
```

The source ordering explains the nil:

1. `main.swift` creates the `AppDelegate`, assigns it, initializes Ghostty, then calls
   `app.activate(ignoringOtherApps: true)` before `app.run()`.
2. `applicationDidFinishLaunching` starts async `bootWorkspaceServices(...)`.
3. `applicationLifecycleMonitor` is initialized only near the end of workspace boot,
   after `await store.restoreAsync()`.
4. On macOS 26.4.1, activation ingress can arrive before step 3, so the IUO traps.

Source history:

```text
applicationDidBecomeActive -> applicationLifecycleMonitor.handleApplicationDidBecomeActive()
  introduced by 5bfabde5f on 2026-03-21

var applicationLifecycleMonitor: ApplicationLifecycleMonitor!
  introduced by cd4e47f2c on 2026-03-21

appLifecycleStore/windowLifecycleStore IUOs
  introduced by decddafcf on 2026-04-12

late applicationLifecycleMonitor initialization after async workspace restore
  current boot shape from d08e58f6c / be44db316 workspace boot work
```

The v0.0.37 source has the same unguarded lifecycle ingress:

```swift
func applicationDidBecomeActive(_ notification: Notification) {
    applicationLifecycleMonitor.handleApplicationDidBecomeActive()
}
```

Apple's AppKit docs describe `NSApplicationDelegate` as the lifecycle interface for
application state, with separate launch callbacks and active-state callbacks. The docs
also state that `applicationDidFinishLaunching(_:)` means initialization is complete
but the app has not received its first event yet; this app extends launch completion
with async workspace boot, so active-state callbacks must not assume boot-only services
exist.

The crash file mtime is `2026-06-08 17:36`, but the minidump process-create/crash
timestamp is around `2026-06-08 17:33:54` local. Treat the file mtime as the time the
report was written/flushed, not necessarily the exact original crash instant.

## Recurrence check

All local Ghostty crash envelopes under `~/.local/state/ghostty/crash` were parsed.
Every local envelope was from macOS `26.4.1` build `25E253` and reported
`ExceptionCode.EXCEPTION_SIGIOT`.

| File | Event timestamp | App | Debug ID | Exception offset |
| --- | --- | --- | --- | --- |
| `01458e07-3765-4f49-8a86-2dee85dcb0fc.ghosttycrash` | `2026-06-08T21:33:55Z` | Beta | `8ea237d6-e0c3-33bb-b42c-6814dbd6c32b` | `0x31694` |
| `6d22485b-0556-40f1-bdc3-02c9a4ef345b.ghosttycrash` | `2026-04-26T11:07:12Z` | Stable v0.0.37 | `ddf4a388-d5df-3bdb-9ed3-f307f322e459` | `0x1daac` |
| `8b9c1a3f-3337-48c9-2301-1df8e13b10b0.ghosttycrash` | `2026-04-26T23:06:51Z` | Stable v0.0.37 | `ddf4a388-d5df-3bdb-9ed3-f307f322e459` | `0x1daac` |
| `d687d7b2-3ecb-43f3-f936-8eb2e6ec2c1f.ghosttycrash` | `2026-04-26T23:07:27Z` | Stable v0.0.37 | `ddf4a388-d5df-3bdb-9ed3-f307f322e459` | `0x1daac` |
| `93fc0d75-c6cc-4f31-8b59-89b6a185af61.ghosttycrash` | `2026-04-26T23:07:34Z` | Stable v0.0.37 | `ddf4a388-d5df-3bdb-9ed3-f307f322e459` | `0x1daac` |

The installed beta binary still matches the beta crash debug ID, so `atos` can
symbolicate `0x31694` to `AppDelegate.applicationDidBecomeActive(_:) + 236`.

The installed stable binary no longer matches the older stable crash debug ID:

```text
Current /Applications/AgentStudio.app UUID:
CBADC778-B614-37F4-932F-58ABDFF51671

Older stable crash UUID:
DDF4A388-D5DF-3BDB-9ED3-F307F322E459
```

The matching old stable binary was recovered from the GitHub release artifact:

```text
gh release download v0.0.37 --pattern 'AgentStudio-*-macos.zip'
shasum -a 256 AgentStudio-v0.0.37-macos.zip
dwarfdump --uuid AgentStudio.app/Contents/MacOS/AgentStudio

UUID: DDF4A388-D5DF-3BDB-9ED3-F307F322E459 (arm64)
```

Symbolicating each older stable crash against that v0.0.37 binary:

```text
0x10042daac -> AppDelegate.applicationDidBecomeActive(_:) + 280
0x10290daac -> AppDelegate.applicationDidBecomeActive(_:) + 280
0x102de1aac -> AppDelegate.applicationDidBecomeActive(_:) + 280
0x100ac1aac -> AppDelegate.applicationDidBecomeActive(_:) + 280
```

Disassembly for v0.0.37 shows the same nil-check trap pattern:

```text
000000010001d9bc  ldr x19, [x20, x8]
000000010001d9c0  cbz x19, 0x10001daac
...
000000010001daac  brk #0x1
```

So every local crash envelope on macOS `26.4.1` that could be symbolicated points to
the same host lifecycle method and the same `applicationLifecycleMonitor` nil-trap
shape.

## Branch patch

Branch: `scratch/macos-264-ghostty-crash-debug`

Changed files:

- `Sources/AgentStudio/App/Boot/AppDelegate+LifecycleRouting.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
- `Tests/AgentStudioTests/App/AppDelegateLifecycleRoutingTests.swift`

Patch shape:

- Guard `applicationDidBecomeActive`, `applicationDidResignActive`, and
  `applicationWillTerminate` when `applicationLifecycleMonitor` is still nil.
- Add `synchronizeApplicationLifecycleStateAfterWorkspaceBoot(isApplicationActive:)`.
- After creating `ApplicationLifecycleMonitor`, seed it from `NSApp.isActive` so an
  early skipped activation still produces the correct initial `AppLifecycleAtom`
  state before Ghostty lifecycle consumers bind.
- Add regression tests for pre-boot lifecycle ingress and post-boot active-state
  synchronization.

## Verification status

Formatting:

```text
/Library/Developer/CommandLineTools/usr/bin/swift-format -i \
  Sources/AgentStudio/App/Boot/AppDelegate+LifecycleRouting.swift \
  Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift \
  Tests/AgentStudioTests/App/AppDelegateLifecycleRoutingTests.swift

exit 0
```

Focused test attempted:

```text
swift test --filter AppDelegateLifecycleRoutingTests

error: local binary target 'GhosttyKit' at
'/Users/shravansunder/Documents/dev/project-dev/agentstudio/Frameworks/GhosttyKit.xcframework'
does not contain a binary artifact.
error: fatalError

exit 1
```

Build prerequisites are not currently healthy:

```text
Frameworks/GhosttyKit.xcframework is missing
vendor/ghostty/macos/GhosttyKit.xcframework is missing
.mise.toml pins zig 0.15.2
xcode-select points at /Library/Developer/CommandLineTools
xcrun cannot find metal
/Applications/Xcode.app is Xcode 26.5, but its license is not accepted
doctor-mac reports polluted CC/CXX/CPPFLAGS/LDFLAGS environment
```

Additional setup attempts on `2026-06-08`:

```text
brew install mise

installed mise 2026.6.1 and usage 3.4.0
```

```text
mise trust .mise.toml

trusted /Users/shravansunder/Documents/dev/project-dev/agentstudio
```

Running `mise run doctor-mac` still did not reach the task body because `mise`
attempted remote Zig metadata fetches and timed out:

```text
HTTP timed out for https://mise-versions.jdx.dev/tools/zig.toml
HTTP timed out for https://ziglang.org/download/index.json
```

Direct Ghostty framework generation was attempted with compiler environment variables
scrubbed:

```text
env -u CC -u CXX -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
    -u CPATH -u LIBRARY_PATH -u SDKROOT -u DEVELOPER_DIR \
    -u MACOSX_DEPLOYMENT_TARGET \
    bash scripts/build-ghostty-local.sh
```

Because `mise` could not resolve the pinned Zig, the direct attempt used
`/opt/homebrew/bin/zig` (`0.16.0`) instead of `.mise.toml`'s pinned `0.15.2`. That
launched `/opt/homebrew/bin/zig build -Demit-xcframework=true ...` but produced no
build output and no framework. Sampling the process showed worker threads parked in
`__connect`, so this attempt was blocked on network dependency hydration rather than
active compilation. The hung build was stopped.

No full build, test suite, or debug launch has been verified yet.

Non-linking checks completed:

```text
swiftc -parse \
  Sources/AgentStudio/App/Boot/AppDelegate+LifecycleRouting.swift \
  Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift \
  Tests/AgentStudioTests/App/AppDelegateLifecycleRoutingTests.swift

exit 0
```

```text
/Library/Developer/CommandLineTools/usr/bin/swift-format lint \
  Sources/AgentStudio/App/Boot/AppDelegate+LifecycleRouting.swift \
  Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift \
  Tests/AgentStudioTests/App/AppDelegateLifecycleRoutingTests.swift

exit 0
```

Standalone lifecycle harness:

```text
tmp/macos-264-lifecycle-harness/LifecycleHarness.swift
```

This harness compiles outside SwiftPM and does not depend on `GhosttyKit`. In this
Codex shell on macOS `26.4.1`, both raw executable and bundled `.app` launches stayed
inactive even after explicit `NSApp.activate(ignoringOtherApps: true)`, so it could not
reproduce the real beta active callback. That negative result is expected in a limited
agent shell and is weaker than the beta minidump. The harness still documents the async
boot gap:

```text
main before activate isActive=false
main after activate isActive=false
applicationDidFinishLaunching begin monitorReady=false
applicationDidFinishLaunching end monitorReady=false
async boot begin monitorReady=false
async boot complete monitorReady=true
```

With a visible window and an explicit activation attempt during the gap:

```text
applicationDidFinishLaunching showed window monitorReady=false
applicationDidFinishLaunching before explicit activate monitorReady=false
applicationDidFinishLaunching after explicit activate monitorReady=false
async boot begin monitorReady=false
async boot complete monitorReady=true
```

The harness did not contradict the root-cause hypothesis; it just did not have the same
foreground activation behavior as the installed beta app.

## References

- Apple AppKit `NSApplicationDelegate`:
  `https://developer.apple.com/documentation/appkit/nsapplicationdelegate`
- Apple AppKit `NSApplication.activate(ignoringOtherApps:)`:
  `https://developer.apple.com/documentation/appkit/nsapplication/activate(ignoringotherapps:)`
- DeepWiki `ghostty-org/ghostty` answer gathered on `2026-06-08` for Ghostty
  Sentry/Breakpad crash envelope behavior.

## Next step

To finish verification, restore a working Xcode/Ghostty build environment, then run:

```bash
env -u CC -u CXX -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
    -u CPATH -u LIBRARY_PATH -u SDKROOT -u DEVELOPER_DIR \
    -u MACOSX_DEPLOYMENT_TARGET \
    bash scripts/build-ghostty-local.sh

mkdir -p Frameworks
test -d vendor/ghostty/macos/GhosttyKit.xcframework
test ! -e Frameworks/GhosttyKit.xcframework
cp -R vendor/ghostty/macos/GhosttyKit.xcframework Frameworks/

swift test --filter AppDelegateLifecycleRoutingTests
swift test
swift build
```

On a machine with Xcode 26.4/26.5, watch for the known Ghostty/Zig SDK linker hazard
documented in `AGENTS.md`. If it appears, use Xcode 26.3 for the Ghostty framework
rebuild.
