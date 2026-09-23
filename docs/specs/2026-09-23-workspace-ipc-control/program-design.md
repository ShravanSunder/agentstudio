# Workspace IPC Control (A1) — Program Design

[Requirements](./requirements.md) → [Specification](./specification.md) → this
structural design.

A1 changes who may run what, not how commands run. Agent IPC v2 already
resolves every request's target before authorizing it; A1 adds one rule for
pane-bound agents at that point — the command's declared agent eligibility plus
an own-pane check of the resolved target — and gives drawer-child creation a
background variant that returns the new child. Everything else (transport,
principals, catalog execution, drawer and pane owners) stays as it is.

```mermaid
flowchart LR
  cli["Agent via bundled CLI"] --> server["AgentStudioAppIPCServer<br/>(authenticated routing)"]
  server --> reg["Method registration.invoke<br/>normalize → resolveTarget → authorize → handler"]
  reg -- "resolved target identities" --> auth{{"AppIPCMethodAuthorization<br/>+ agent eligibility rule (new)"}}
  auth -- "own-pane scope query (new port)" --> scope["OwnPaneScope reader (App)<br/>pane graph + drawer membership"]
  auth -- "allowed" --> handler["Existing handlers: command adapter,<br/>layout adapter, terminal adapter"]
  auth -- "not yet allowed / refused" --> err["New typed outcome to agent"]
  handler --> owners["Existing owners: AppCommandDispatcher,<br/>workspace actions, drawer/pane atoms"]
```

## Current system (main `18cbc3e02`)

- `registration.invoke` runs normalize → `resolveTarget` → `authorize` →
  handler, so the target pane identity is known before authorization
  (`Sources/AgentStudioAppIPC/AppIPCTypedMethodRegistration.swift:140–160`,
  `AgentStudioAppIPCServer.swift:360–368`).
- `command.execute` resolves its target in `prepareCommand`
  (`AppIPCCommandMethodRegistrations.swift:27`,
  `App/IPCComposition/AgentStudioIPCCommandAdapter.swift:87–99`); the permission
  target is only the first resolved pane identity, the drawer parent for drawer
  commands (`AgentStudioIPCCommandTargetResolution.swift:161–169, 256–261`).
- `authorize` lets the debug diagnostic principal through, requires
  `exposure == .allChannels`, then checks each required privilege against the
  pane baseline (`target == .pane(boundPaneId)`) or the grant ledger
  (`AgentStudioIPCRegistryAuthorization.swift:252–345`). Every `command.execute`
  descriptor requires `.appCommandExecute`, which is not in the baseline
  (`App/Commands/AppCommand+IPCProjection.swift:24`), so pane agents cannot run
  any catalog command today; `.layoutMutate` is never grantable
  (`AgentStudioIPCPermissionBroker.swift:106`).
- The registry drops `.debugTesting` methods on other channels
  (`AgentStudioIPCRegistryAuthorization.swift:22`).
- A drawer terminal gets its own principal bound to its own pane ID
  (`WorkspaceSurfaceCoordinator+ViewLifecycle.swift:400`,
  `AgentStudioIPCAuthentication.swift:446–462`).
- `drawer.addPane` dispatches `.addDrawerPane`; creation expands the drawer
  (`WorkspaceTerminalCreationComposition.swift:~170`) and discards the new pane
  (`WorkspaceSurfaceCoordinator+ViewHelpers.swift:80`); the result carries only
  the parent (`IPCQueryContracts.swift:317`). Browser drawer children are created
  only from the management layer (`WorkspaceSurfaceCoordinator+PaneInsertion.swift:185`).
- IPC can only address panes in the pane graph
  (`AgentStudioIPCBridgeAdapter.swift:189`); the full-screen companion Bridge is
  not in the pane graph (`WorkspaceSurfaceCoordinator+ZoomCompanion.swift:194–220`).

**Consequence for scope:** the terminal's Bridge (E-IC-3) is not addressable in
A1. Controlling it through IPC arrives with stack B, whose B1 layer gives each
terminal a stable Bridge in the pane graph. A1 designs the own-pane scope so
that Bridge joins it without a rule change.

## The structural choice

**Crux:** where does "may this agent run this command on this target?" live
for pane agents?

| Alternative | Gain | Cost | Falsifier |
| --- | --- | --- | --- |
| Widen privileges: add `.appCommandExecute`/`.layoutMutate` to the own-pane baseline | Smallest diff | Privileges are coarser than commands: `.layoutMutate` on the own pane would also allow split, close-self, zoom; drawer children are not the bound pane, so they would still fail | Any own-pane command whose privilege is shared with a refused command |
| **Per-command agent eligibility + own-pane target check (selected)** | Exactly the Specification's table; one declaration per command; A2 widens the same field | One new field on command and method metadata; one new authorization branch; one App port | A command whose effect depends on arguments rather than identity (handled by argument rules below) |
| A separate agent-only method set | Isolated | A second command surface beside the catalog — forbidden by the one-catalog rule | — |

For pane-bound agents, eligibility replaces the privilege/grant check. Other
principals (CLI automation, debug diagnostic) keep today's path unchanged. This
is a hard cutover for pane agents: no fallback to the baseline privilege set.

## Components and ownership

| Component | Owns | Change |
| --- | --- | --- |
| `AppCommandIPCSpec` (App) | Per-command IPC metadata | New field `agentEligibility`: `ownPane`, `anyTarget`, `notYetAllowed`. Commands marked `ownPane` or `anyTarget` are exposed on all channels. |
| Built-in method descriptors (`AgentStudioProgrammaticControl/BuiltInDescriptors`) | Per-method metadata | Same field on the method metadata; discovery (`system.capabilities`, `command.list`) reports it. |
| `AppIPCMethodAuthorization` (`AgentStudioAppIPC`) | The authorization decision | New branch for `.spawnedPaneAgent`: eligibility, then own-pane membership of every resolved target identity, then argument rules. Produces the new outcomes. |
| `AppIPCOwnPaneScopePort` (new port, declared in `AgentStudioAppIPC`, implemented in App) | Answering "is pane X inside agent pane P's own pane?" | Reads the pane graph on the main actor: P itself; if P is a main-layout pane, its drawer children; later (B1) P's stable Bridge. No I/O. |
| Layout adapter / executor (`AgentStudioIPCLayoutAdapter`, `WorkspaceSurfaceCoordinator`) | Drawer child creation | New background variant: content `terminal` or `browser(url)`, drawer expansion and focus unchanged, returns the created pane. |
| Workspace action validation (`ActionValidator`) | Drawer child content rule | Shared rule from the drawer design: terminal or webview only. |
| Error taxonomy (`AgentStudioAppIPCRequestError`, `AuthorizationError.Reason`) | Wire outcomes | New reasons `notYetAllowed` (with command name) and `refusedForAgent`, each with its own error code, distinct from `unauthorized`, `missingGrant` and `targetNotFound`. |

The port keeps `AgentStudioAppIPC` free of App imports, following the existing
port pattern (`service.ports`).

## Eligibility inventory (this layer)

| Eligibility | Commands and methods |
| --- | --- |
| `ownPane` | `terminal.status`, `terminal.snapshot`, `terminal.send`, `terminal.wait`, `pane.snapshot`; `command.execute` for `scrollToBottom`, `scrollPageUp`, `scrollPageDown`, `scrollSmallStepUp`, `scrollSmallStepDown`, `jumpToPreviousPrompt`, `jumpToNextPrompt`, `closeDrawerPane`; `drawer.addPane` (background variant); `pane.close` only for an own drawer child (argument rule) |
| `anyTarget` | `system.ping`, `system.identify`, `system.version`, `system.capabilities`, `window.list`, `window.current`, `workspace.list`, `workspace.current`, `pane.list`, `pane.current`, `command.list`, `sidebar.grouping.get`, `sidebar.surface.get` |
| unchanged, already open to agents | `auth.*`, `events.subscribe`/`unsubscribe` (own-pane scoped as today), `session.report`/`message`/`event`/`query` |
| `notYetAllowed` | every other `command.execute` command and every other method, including all `bridge.*` methods until B1 (their target, the terminal's Bridge, is not addressable in A1) |

**Argument rules** (evaluated after eligibility, same branch):
- `pane.close`: refused when the target is the agent's bound pane; allowed only
  for its own drawer child.
- `drawer.addPane`: target must be the agent's own main-layout pane; refused for
  an agent in a drawer terminal (drawers do not nest); content must be terminal
  or browser, else refused.

## Call path: agent runs a command

```mermaid
sequenceDiagram
  participant CLI as Agent (CLI)
  participant Srv as IPC server
  participant Reg as registration.invoke
  participant Res as resolveTarget (existing)
  participant Auth as authorize
  participant Scope as OwnPaneScope port (App, main actor)
  participant H as Existing handler
  CLI->>Srv: request (authenticated pane agent P)
  Srv->>Reg: invoke
  Reg->>Res: resolve handles to pane identities (all, not only the first)
  Res-->>Reg: resolved identities
  Reg->>Auth: principal + method metadata + resolved identities
  alt eligibility notYetAllowed
    Auth-->>CLI: notYetAllowed(command)
  else ownPane
    Auth->>Scope: contains(P, each identity)?
    Scope-->>Auth: yes / no
    Auth-->>CLI: notYetAllowed(command) when any identity is outside
    Auth-->>CLI: refusedForAgent when an argument rule refuses
    Auth->>H: allowed → execute
    H-->>CLI: done / failed / existing result
  else anyTarget
    Auth->>H: allowed
  end
```

**Changed edges:** `resolveTarget` hands authorization every resolved identity,
not only the first (drawer commands currently scope to the parent); authorize
gains the pane-agent branch and the scope port call. **Unchanged:** handler
execution, `AppCommandDispatcher.dispatchHeadlessIPC`, the diagnostic path,
automation-client authorization.

## Call path: agent adds a drawer child

```mermaid
sequenceDiagram
  participant CLI as Agent (CLI)
  participant Auth as authorize
  participant L as Layout adapter
  participant X as Pane command executor
  participant V as ActionValidator
  participant W as Workspace/drawer owners
  CLI->>Auth: drawer.addPane(self, content)
  Auth->>L: allowed (own main-layout pane, terminal/browser)
  L->>X: add drawer child, background (added edge)
  X->>V: validate parent + content kind
  V-->>X: ok
  X->>W: create pane as drawer child, expansion and focus unchanged (changed edge)
  W-->>X: created pane
  X-->>L: created pane identity (added edge; today discarded)
  L-->>CLI: done (parentPaneId, childPaneId, childHandle)
```

The interactive path (human shortcut, management layer) keeps today's
behavior: expand and focus. Only the agent-originated call uses the background
variant.

## Failure and concurrency

- **Target disappears between authorization and execution:** the handler's
  existing re-validation returns its existing not-found failure; nothing
  partial is created.
- **Scope changes during a request:** the scope port and handler both run on
  the main actor in one request's turn sequence; a pane closed before the
  scope read is outside scope (not yet allowed); after the read, the handler's
  re-validation applies.
- **Principal outlives its pane:** Agent IPC v2 already invalidates the pane
  credential; the scope port also answers "no" for a missing bound pane.
- **Browser URL invalid:** validation failure, no pane created.
- **Uncertain delivery:** unchanged Agent IPC v2 semantics; a retried
  `drawer.addPane` can create a second child (no replay journal).

## Cross-cutting realization

- **Performance (U-IC-08):** authorization adds one main-actor pane-graph
  lookup per request (bounded by the agent's drawer size), no disk, network, or
  per-sample work. It runs only when an IPC request arrives, not on terminal
  output. Marker-scoped proof per the observability proof model.
- **Security:** pane agents cannot widen their own scope; eligibility is
  compiled into the catalog; the not-yet-allowed outcome names the command but
  never another pane's contents.
- **Discovery:** `command.list` and `system.capabilities` report eligibility so
  agents know what they can run without trial and error.
- **Compatibility:** automation clients and the debug diagnostic client are
  unaffected. Pane agents that relied on the (unusable) privilege baseline for
  `bridge.*` see not-yet-allowed instead of `unsupportedTarget`/`missingGrant`.

## Proof seams

| Requirement | Seam | Real / fake |
| --- | --- | --- |
| R-IC-1, R-IC-2 | IPC server integration: real registry, authorization and own-pane port backed by a real pane graph; channel set to stable and debug | Real transport and authorization; App handlers real where the requirement is execution |
| R-IC-1, R-IC-2, R-IC-4 | CLI E2E against a PID-targeted debug app and a stable-channel build: agent in a main terminal and in a drawer terminal | Real app |
| R-IC-3 | Executor integration for the background variant (created pane returned, expansion and focus unchanged) plus native check on the debug app | Real workspace owners |
| R-IC-5 | Marker-scoped main-actor held time for authorization under load | Real app |

Illegal states: a pane agent executing a `notYetAllowed` command is rejected at
the trusted entry (authorization); an agent-created drawer child that expands
the drawer is unrepresentable through the agent path (the background variant
has no expand input).

## Deletion check

No store, atom, registry, event, or persistence is added. The new field,
authorization branch, port, background creation variant and two error reasons
each serve a named requirement (R-IC-1/2, R-IC-1, R-IC-3/4, R-IC-2); removing
any one breaks that requirement.
