# Preview prerequisite awaiting owner decision

The confirmed preview rule remains: load an existing pane's renderer as needed,
but never start a replacement terminal session. Preview has not been removed
from this delivery. No preview or vendor implementation is authorized by this note.

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
                                  forbidden for preview
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

A preflight inventory or socket-existence check cannot guarantee this rule:
the daemon could exit between that check and attachment. A safe path must
connect to an existing session and fail if it is absent, without a create fallback.

The owner was asked whether to include an attach-only prerequisite in delivery,
or move held preview to a follow-up while completing sidebar navigation and
arrangements. No answer has been received. AGENTS.md's scope gate requires
agreement before expanding into the vendor layer; the existing sidebar core plan
explicitly excludes vendor changes and leaves preview structurally unfinished.

The related hidden-renderer visibility and Bridge foreground-admission paths also
need explicit preview inputs through their existing owners. Reparenting a native
view alone does not change those policies. The read-only source inventory is
`tmp/sidebar-keyboard-design/preview-mount-inventory.md`; its proposed implementation
shapes are candidates, not reviewed Program Design.

Independent sidebar focus, selection, group/digit navigation, overlays and pinned
navigation remain in scope. The general detached-drawer invariant stays deferred.
