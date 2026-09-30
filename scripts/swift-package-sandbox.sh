#!/usr/bin/env bash
# Source, then pass $(swift_package_sandbox_arguments) right after every
# `swift build` / `swift test` subcommand.
#
# On macOS, SwiftPM compiles and runs Package.swift manifests (and plugins)
# inside its own sandbox-exec profile. Agent sandboxes such as Codex's Seatbelt
# profile forbid applying a second sandbox from inside the first, so SwiftPM
# fails with "sandbox-exec: sandbox_apply: Operation not permitted" before
# anything builds. SwiftPM has no environment switch for this, only the
# --disable-sandbox flag, and it does not detect nesting itself.
#
# The probe asks the exact question SwiftPM depends on: can a sandbox be applied
# here? Only when it cannot are we already confined by an outer OS sandbox, and
# only then is --disable-sandbox passed, so manifests are still confined (by the
# outer sandbox). Developer shells and CI runners can apply one, so their builds
# keep SwiftPM's own sandbox unchanged. Linux SwiftPM has no sandbox.

swift_package_sandbox_arguments() {
  [ "$(uname -s)" = "Darwin" ] || return 0
  if ! sandbox-exec -p '(version 1)(allow default)' /usr/bin/true >/dev/null 2>&1; then
    printf '%s\n' '--disable-sandbox'
  fi
  return 0
}
