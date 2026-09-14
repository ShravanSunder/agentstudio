# Historical preview boundary — superseded

Status: this WIP records an obsolete prohibition and is retained only as historical
evidence. The owner has since authorized held preview in this delivery and explicitly
allows normal restore for an existing pane. If the old zmx endpoint has ended, normal
restore may start a fresh shell under the same existing pane identity. The prohibition
against a fresh shell and the resulting attach-only/vendor decision are superseded.
No substitute pane identity, vendor change, or attach-only zmx path is required.

The initial assumption was that restoring the exact saved zmx identity also
guaranteed reuse of the existing process. Current source disproves that assumption:

```text
Saved pane -> exact session ID -> zmx attach
                                  |
                         existing daemon?
                         /             \
                       yes             no/refused
                        |                  |
                     attach           create daemon + shell
                                           ^
                                  previously forbidden; superseded
```

Parent-verified source:

- `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreRuntime.swift:33`
  forwards the exact saved identity to the standard attach-command builder.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/ZmxBackend.swift:202`
  builds `attach <id> <shell> -i -l` and documents creation on first attach.
- The shared vendor producer is linked through `vendor/zmx/zig-out` to the main
  checkout. Its zmx HEAD is `8bab1f0173b07e79835ea372d749af3dbf0d0842`.
  At that revision, `src/main.zig:1572` calls `ensureSession`, and
  `src/loop.zig:695` creates on absence or connection refusal. DeepWiki supplied
  the source pointers; the pinned code was read directly to verify the claim.

A preflight inventory or socket-existence check cannot guarantee the old
attach-only rule: the daemon could exit between that check and attachment. That
conclusion is retained as historical reasoning only; the current owner decision
allows the standard attach path and its same-identity fresh-shell behavior.

The owner decision closes the prior blocker: preview may use the existing normal
restore path and any same-identity fresh-shell behavior it entails. The existing
sidebar plan still excludes vendor changes. The current held-preview structural
realization is documented in the [Program Design](../../specs/2026-09-12-sidebar-keyboard-system/program-design.md)
and keeps the renderer/activity/geometry owners on their existing paths.

The related hidden-renderer visibility and Bridge foreground-admission paths also
need explicit preview inputs through their existing owners. Reparenting a native
view alone does not change those policies. The read-only source inventory is
`tmp/sidebar-keyboard-design/preview-mount-inventory.md`; its proposed implementation
shapes are candidates, not reviewed Program Design.

Independent sidebar focus, selection, group/digit navigation, overlays and pinned
navigation remain in scope. The general detached-drawer invariant stays deferred.
