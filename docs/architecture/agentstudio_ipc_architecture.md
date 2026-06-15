# AgentStudio IPC Architecture

This document defines the architecture boundaries enforced by the AgentStudio
IPC lint rules. It captures the target shape for app-level programmatic control
even before all IPC targets exist on `main`.

## Boundary Model

AgentStudio IPC is split into contract, port, composition, and product-owner
layers:

```text
external client / future MCP
  -> public programmatic-control contracts
  -> AppIPC ports
  -> App/IPCComposition adapters
  -> app/workspace/runtime owners
```

The public AgentStudio API is app-level and semantic. zmx remains an internal
terminal/session backend. Do not expose public `zmx.*` methods from
AgentStudio's app IPC surface.

## Target Locations

```text
Sources/
  AgentStudioProgrammaticControl/
    Public DTOs, method names, handles, protocol envelopes.
    No AppKit, SwiftUI, AgentStudio executable imports, feature imports, or
    concrete runtime owners.

  AgentStudioAppIPC/
    Protocol ports and service contracts for query, layout, runtime, events,
    auth, permissions, and approval.
    No app executable imports, UI frameworks, feature imports, or concrete
    runtime owners.

  AgentStudio/
    App/
      IPCComposition/
        Concrete adapters from AppIPC ports to app owners such as
        PaneCoordinator, RuntimeRegistry, SessionRuntime, or SurfaceManager.
```

## Contract Rules

- Programmatic-control contracts are transport/app/UI independent.
- AppIPC exposes protocol ports and contract vocabulary, not concrete app
  owners.
- Concrete port implementations live in the app composition layer.
- IPC methods do not route commands through `EventBus`.
- IPC methods do not mutate atoms directly.
- IPC services and adapters use app/runtime owner ports for state and behavior.
- Public DTOs are scrubbed contract types. They must not expose raw atoms,
  prompts, raw terminal payloads, raw runtime payloads, raw paths, or zmx
  internal namespaces.

## Rule Mapping

| Rule ID | Enforced boundary |
| --- | --- |
| `agentstudio_ipc_programmatic_control_boundary` | `AgentStudioProgrammaticControl` must not import app/product/UI modules or reference concrete runtime owners. |
| `agentstudio_appipc_port_boundary` | `AgentStudioAppIPC` must define ports/contracts rather than importing app/product/UI modules or concrete runtime owners. |
| `agentstudio_ipc_composition_location` | Concrete AppIPC port implementations belong under `Sources/AgentStudio/App/IPCComposition`. |
| `agentstudio_ipc_public_surface_sanitization` | Public IPC surfaces must not expose zmx namespaces or raw runtime payload types. |
| `agentstudio_ipc_no_direct_atom_access` | IPC services and adapters must route through approved app/runtime owner ports instead of direct atom access. |
