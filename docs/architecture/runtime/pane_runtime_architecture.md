# Pane Runtime Architecture

## TL;DR

Pane runtimes own per-pane command handling and admitted fact emission.
Commands are direct (`handleCommand`). Facts are `RuntimeEnvelope` values on
`PaneRuntimeEventBus` only after source admission. High-rate Ghostty samples
never wake the bus raw. `@MainActor` on a runtime or atom is publication
ownership — not permission to derive, admit, or schedule there.

Verify protocol claims against
[`PaneRuntime.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntime.swift)
(`subscribe() -> AsyncStream<RuntimeEnvelope>`). There is no
`PaneEventEnvelope`. `RPCRouter` is retired. EventBus mechanics live in
[Pane Runtime EventBus Design](pane_runtime_eventbus_design.md).

## New signal decision tree

Do **not** default to “add a `RuntimeEnvelope` case and transform it on
MainActor.” Classify first:

```text
new signal or derived fact
  -> classify primitive   (atom / repository / local UI)
  -> classify input       (ordered / latest / burst / expensive / deadline)
  -> classify plane       (command / bus fact / topology effect / atom publish / AppKit lifecycle)
  -> admit and contract at source
  -> publish only changed semantic outcomes
```

| Step | Load |
| --- | --- |
| Primitive | [Need An Atom?](../state/atom_persistence_boundaries.md#need-an-atom), [Which primitive](../state/atom_persistence_boundaries.md#which-primitive) |
| Input class | [Selection Rule](../state/demand_driven_derived_state_refresh.md#selection-rule) |
| Plane | [Three Data Flow Planes](#three-data-flow-planes), [Command planes](../commands/command_specs.md#command-planes), [Coordination boundaries](#coordination-boundaries-quick) |
| High-rate / FFI | [Contract 7](#contract-7-typed-ghostty-source-admission-and-contraction), [Admission And Hop Shape](pane_runtime_eventbus_design.md#admission-and-hop-shape) |

Forbidden default: invent an EventBus event, then join dictionaries or derive
rows on MainActor. Publish UI from atoms; contract and derive off-main; apply
one already-admitted value on MainActor.

## Files to load

| File | Owns |
| --- | --- |
| [`PaneRuntime.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntime.swift) | Runtime protocol: `handleCommand`, `subscribe()`, lifecycle, replay, shutdown |
| [`RuntimeEnvelope.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeEnvelope.swift) | Comment pointer only — types are not in this file |
| [`RuntimeEnvelopeCore.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeEnvelopeCore.swift) | 3-tier envelope: `SystemEnvelope`, `WorktreeEnvelope`, `PaneEnvelope` |
| [`PaneRuntimeCommand.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeCommand.swift) | Inbound runtime command vocabulary |
| [`PaneRuntimeEvent.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift) | Pane-scoped event taxonomy |
| [`EventBus.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Events/EventBus.swift) | Fan-out transport: named policy subscriptions, fact-topic interest, replay diagnostics |
| [`EventChannels.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Events/EventChannels.swift) | `PaneRuntimeEventBus` handle |
| [`AppEventBus.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Events/AppEventBus.swift) | App-level notification bus (not runtime facts) |
| [`SwiftPaneRuntime.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/SwiftPaneRuntime.swift) | Native Swift pane runtime |
| [`TerminalRuntime.swift`](../../../Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift) | Terminal pane runtime |
| [`BridgeRuntime.swift`](../../../Sources/AgentStudio/Features/Bridge/Runtime/BridgeRuntime.swift) | Bridge viewer runtime |
| [`WebviewRuntime.swift`](../../../Sources/AgentStudio/Features/Webview/Runtime/WebviewRuntime.swift) | Browser pane runtime |

## Three Data Flow Planes

Source admission precedes the three planes. A source-owned exhaustive decision
first determines whether a copied raw signal becomes an exact control or fact,
enters fixed-key contraction, or is explicitly diagnostic/ignored. Only
admitted semantic facts enter a plane.

| Plane | Direction | Mechanism | Invariant |
| --- | --- | --- | --- |
| **Event plane** | Producers → EventBus → consumers | Runtimes and boundary actors post `RuntimeEnvelope`s. Subscribers supply buffer policy, stable name, and optional fact-topic interest. | One-way. Commands never flow on the bus. Bus owns delivery/replay diagnostics, not domain policy. |
| **Command plane** | User/system → coordinator → runtime | `PaneRuntimeCommand` via `RuntimeRegistry` → `runtime.handleCommand(envelope)`. | Request-response. Direct; not EventBus. |
| **UI plane** | Runtime / atom → SwiftUI | `@Observable` mutation on `@MainActor` **before** any bus post when both paths apply. | Synchronous. Bus is coordination, not UI transport. |

**Multiplexing rule:** For an admitted semantic event that needs both UI and
coordination, mutate `@Observable` first and publish the fact second. Raw
high-rate samples do not enter the bus because a view might eventually care.

Lifecycle ingress is not a fourth plane on either bus:
`ApplicationLifecycleMonitor` owns AppKit callbacks and writes
`AppLifecycleAtom` / `WindowLifecycleAtom`. The old
`AppCommand -> AppEventBus -> controller -> WorkspaceActionCommand` chain is
retired.

## Runtime taxonomy

One `@MainActor` runtime **class** per transport; one **instance** per pane.

| Runtime class | Content types |
| --- | --- |
| `TerminalRuntime` | `.terminal` |
| `BridgeRuntime` | `.diff`, `.review`, `.editor` (no `.file` content type) |
| `WebviewRuntime` | `.browser` |
| `SwiftPaneRuntime` | Native panes such as `.codeViewer` |

Protocol is `async` for command and shutdown so an actor upgrade path stays
open; instances today share MainActor.

## Named current contracts

### PaneRuntime protocol

[`PaneRuntime`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntime.swift)
requires: `paneId`, `metadata`, `lifecycle`, `capabilities`,
`handleCommand(_:)`, `subscribe() -> AsyncStream<RuntimeEnvelope>`,
`snapshot()`, `eventsSince(seq:)`, `shutdown(timeout:)`.

`BusPostingPaneRuntime` marks runtimes that post directly onto
`PaneRuntimeEventBus`. Legacy/fake runtimes that only support `subscribe()`
are bridged by `WorkspaceSurfaceCoordinator`.

### Contract 3: Event Envelope

<a id="contract-3-event-envelope"></a>

Payload of the event plane. Three tiers:

- `SystemEnvelope` — system-scoped (`repoDiscovered` / `repoRemoved` before a
  repo id exists, etc.)
- `WorktreeEnvelope` — always has `repoId`; optional `worktreeId`
- `PaneEnvelope` — always has `paneId` and pane kind

Live shape:
[`RuntimeEnvelopeCore.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeEnvelopeCore.swift).
Do not invent a fourth envelope type for convenience DTOs.

### Contract 7: Typed Ghostty Source Admission And Contraction

<a id="contract-7-typed-ghostty-source-admission-and-contraction"></a>

Normative Terminal source contract. `GhosttyEvent` membership alone does not
authorize EventBus use.

```text
raw input
  -> exhaustive typed source admission
  -> fixed-key coalescing or bounded sufficient-statistics aggregation
  -> semantic projection
  -> low-volume facts
```

`GhosttyActionDisposition` is the exhaustive six-way admission decision
(before MainActor routing):

| Disposition | Publication rule |
| --- | --- |
| Exact fact | May produce a runtime envelope when coordination needs the exact fact |
| Latest presentation | Apply latest compact value locally; do not publish the raw sample |
| Latest semantic metadata | Contract title by surface lifetime; publish only changed latest value |
| Activity evidence | Project off-main; publish only changed semantic activity outcomes |
| Exact local lifecycle | Ordered local apply; no envelope/bus |
| Diagnostic | Never fall through into semantic publication |

One compact MainActor drain applies local state, then hands bounded activity
input to `TerminalActivityProjector`. Only changed outcomes return through a
thin MainActor adapter to the bus. Independent `.immediate` and `.title` drain
lanes; CWD is an exact fact with publication admission state, not a third timed
drain. Equality against a committed value suppresses work before MainActor
scheduling.

How the hop is built:
[Typed Admission](pane_runtime_eventbus_design.md#typed-admission-before-multiplexing)
and
[Admission And Hop Shape](pane_runtime_eventbus_design.md#admission-and-hop-shape).

### Direct command dispatch and registry

Commands travel opposite to events. Coordinator resolves a target runtime and
calls `handleCommand`. Do not post commands on `PaneRuntimeEventBus` or
`AppEventBus`. Capability checks use the runtime's declared `capabilities`.

### Attach, restart, filesystem, Git

- Attach readiness and zmx restore/sizing:
  [Session Lifecycle](session_lifecycle.md),
  [Zmx Restore and Sizing](zmx_restore_and_sizing.md)
- Filesystem/Git worktree facts and pane-projection admission:
  [Workspace Data Architecture](../state/workspace_data_architecture.md)
- Expensive derived refresh vocabulary:
  [Demand-Driven Derived-State Refresh](../state/demand_driven_derived_state_refresh.md)

Those owners keep batching, replay policy for topology, and projection index
detail. This document does not restate them.

## Coordination boundaries (quick)

| Change shape | Boundary |
| --- | --- |
| Workspace mutation | `WorkspaceActionCommand` |
| Runtime command | `PaneRuntimeCommand` |
| Runtime or topology fact | `PaneRuntimeEventBus` |
| Ordered post-topology effects | `TopologyEffectHandler` (not via bus) |
| App-level notification (not a command) | `AppEventBus` |
| AppKit/macOS lifecycle ingress | `ApplicationLifecycleMonitor` → `AppLifecycleAtom` / `WindowLifecycleAtom` |
| UI-only local state | Local `@Observable` |

## Sharp edges

1. **Raw samples on the bus** — Contract 7 failed; MainActor and subscribers wake on noise.
2. **Commands on the bus** — breaks request-response and mixes planes.
3. **`@MainActor` as derivation license** — atoms and runtimes publish there; admit/contract/derive off-main.
4. **Catch-all event cases** — active runtime disposition must stay exhaustive
   without silent defaults. Inbox classification is not an active runtime contract.
   Retained Inbox reducer and router source is dormant historical implementation
   and must not be reconnected to App or runtime-bus
   composition without a new product decision.
5. **God-bus domain policy** — EventBus matches topics and accounts for drops; it does not decide product meaning.

## Related

- [Pane Runtime EventBus Design](pane_runtime_eventbus_design.md) — how admission, actors, and hop shape work
- [Command Specs](../commands/command_specs.md) — interactive + IPC command identity (not runtime commands)
- [Atom Persistence Boundaries](../state/atom_persistence_boundaries.md) — when to use an atom at all
- [Architecture Overview](../README.md) — routing index
