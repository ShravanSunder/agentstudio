# BridgeWeb Swift Development Backend Specification

Requirements: [BridgeWeb Swift Development Backend — Requirements](user-requirements.md)

> **Status:** Substrate for the focused carrier and restart behavior. PR0
> Review Comparison supersedes R4's worktree/base authority and the negative
> no-persistence claim with exact persisted-pane authority in an isolated
> production Core store. Vite/HMR, loopback HTTP, and no-full-app boot remain
> current. See
> [`../2026-08-06-worktree-annotations/pr0-specification.md`](../2026-08-06-worktree-annotations/pr0-specification.md).

## Observable Outcome

BridgeWeb browser development continues to use Vite for frontend assets and
hot-module replacement, while every live Files/Review product operation is
served by development-only Swift code that shares the AgentStudio Bridge
product authority.

The browser must not need a Vite-specific Files/Review product model. The
development environment and packaged app must present the same Bridge product
protocol to the frontend and communication worker.

## Current Observable Problem

Vite currently serves two unrelated roles:

1. frontend development server and React hot reload; and
2. a TypeScript implementation of Bridge product bootstrap, control sessions,
   metadata streaming, File/Review preparation, and content delivery.

The second role duplicates behavior already owned by Swift and
`agentstudio-git`. A successful browser journey therefore proves the
TypeScript development backend, not the product backend shipped in
AgentStudio.

## Required Behavior

### R1 — Vite remains the frontend development server

While running BridgeWeb in browser-development mode, Vite MUST serve the
frontend assets and preserve React hot-module replacement. Product-backend
cutover MUST NOT require launching the full AgentStudio application.

- **Basis:** U1, U3
- **Success:** A React source change appears through the existing Vite
  development loop.
- **Failure:** Replacing Vite, disabling HMR, or requiring the full app violates
  this requirement.
- **Proof obligation:** V1 — manual browser interaction plus runtime evidence.

### R2 — Swift is the only live development product authority

For live worktree development, bootstrap, command, metadata-stream, and content
requests MUST be fulfilled by a Debug Swift backend that calls the same
existing AgentStudio Bridge product/session owners and Git authority used by
the packaged app.

No development-only implementation—whether written in TypeScript or
Swift—may independently own live product capability, session sequencing,
File/Review Git preparation, metadata publication, or content authorization
after cutover.

- **Basis:** U2
- **Success:** Files and Review render real selected-worktree results produced
  through the packaged app's existing Swift product/session owners.
- **Failure:** A live Files/Review journey can succeed through a parallel
  development product implementation while those existing owners are absent
  or bypassed.
- **Proof obligation:** V2 — browser-to-server runtime evidence and source/data
  ownership inspection.

### R3 — Browser development and the packaged app share one product contract

The Vite-served frontend and communication worker MUST consume the same Bridge
bootstrap, control, metadata-frame, and content contracts used by the packaged
app. Environment selection MAY change how requests reach their carrier; it
MUST NOT introduce a separate Files/Review command, schema, state model, or
rendering behavior.

- **Basis:** U2
- **Success:** The same valid contract fixtures and browser behaviors are
  accepted for development and packaged transports.
- **Failure:** React or worker product logic branches on Vite to interpret a
  different product model.
- **Proof obligation:** V3 — shared-contract automated behavior plus packaged
  and browser runtime evidence.

### R4 — The developer selects the worktree presented by Swift

A browser-development session MUST identify the local worktree and Review base
context it intends to inspect. Files and Review MUST be derived from that
selected source by Swift, and changing the selected source MUST require a fresh
product session rather than silently retaining results from the previous
source.

- **Basis:** U2
- **Success:** File and Review results correspond to the selected worktree and
  base context.
- **Failure:** Missing or invalid source selection produces explicit
  unavailability; it does not fall back to unrelated or fabricated data.
- **Proof obligation:** V4 — controlled-worktree browser behavior and data
  inspection.

### R5 — Backend restart has a simple recovery boundary

The Debug Swift backend SHOULD be buildable and restartable without rebuilding
or relaunching AgentStudio. If the initial bootstrap cannot reach the Swift
backend, the development page MUST wait for the restarted backend's explicit
health signal, reload exactly once, obtain a fresh product bootstrap, and
render the selected worktree again. A bootstrap request rejected by a live
Swift backend MUST remain an explicit failure and MUST NOT enter this reload
path.

In-place session reconnection, zero-downtime handoff, continuous background
watching, and a numeric restart-time guarantee are not required.

- **Basis:** U3
- **Success:** Stop backend, restart backend, observe one automatic page reload,
  and complete File and Review journeys without launching AgentStudio.
- **Failure:** Recovery requires the full application, reuses a capability
  issued by the retired backend process, or reloads after a live backend
  rejects bootstrap.
- **Proof obligation:** V5 — development-process and browser runtime evidence.

### R6 — Backend absence is explicit

If the Debug Swift backend is unavailable, rejects bootstrap, or terminates an
active stream, the browser MUST converge to the existing explicit unavailable,
timeout, or retryable product state. It MUST NOT continue presenting stale
results as current or substitute fixture data.

Partial File or Review results received before failure MAY remain visible only
when the existing shared product contract already defines them as committed
state; they MUST NOT be relabeled as belonging to a new session.

- **Basis:** U2, U3
- **Success:** Backend failure is explicit and the one development-only reload
  after restart creates fresh authority.
- **Failure:** A failed backend leaves permanent loading, fabricated success,
  or cross-session data.
- **Proof obligation:** V6 — failure-path browser behavior and session/data
  inspection.

### R7 — The server is development-only and local

The Swift HTTP surface MUST exist only in Debug/development workflows and MUST
accept connections only from the local machine. Release and beta AgentStudio
artifacts MUST NOT start or expose this server.

- **Basis:** U2 boundary
- **Success:** Browser development can reach the server locally, while shipped
  app artifacts expose no development HTTP surface.
- **Failure:** A release artifact starts the server or the server accepts a
  non-local connection.
- **Proof obligation:** V7 — allowed/denied runtime evidence and release
  artifact inspection.

## Observable Development Contract

```text
Developer
  │
  ├── edits React ─────► Vite frontend + HMR
  │
  └── opens Files/Review in browser
                          │
                          ▼
                  Bridge product protocol
                          │
                          ▼
                  local Debug Swift backend
                          │
                          ▼
                  selected worktree result
```

The system inside this diagram is intentionally opaque. Component placement,
target structure, request forwarding, server framework, and lifecycle wiring
belong to Program Design.

## Compatibility And Negative Space

- Existing Bridge product schemas, session sequencing, stream framing,
  acknowledgements, and content limits remain the compatibility boundary.
- Test-only fixtures may continue to emulate inputs, malformed data, and
  failures. They are not an alternate live development backend.
- Development telemetry may remain development-specific, but it MUST NOT own
  Files/Review product behavior.
- No production HTTP API, remote access, authentication product, daemon,
  persistence layer, controller replacement, or frontend rewrite is required.
- Exact startup commands, target dependency direction, port allocation, and
  process supervision are Program Design decisions.

## Requirement And Proof Coverage

| Need | Problem | Outcome | Requirement | Contract | Proof |
| --- | --- | --- | --- | --- | --- |
| U1 | Vite is conflated with its duplicate backend | Preserve frontend loop | R1 | Vite assets and HMR remain | V1 |
| U2 | Browser proves TypeScript rather than shipped behavior | One Swift product authority | R2, R3, R4, R6, R7 | Shared protocol with Swift-produced worktree results | V2, V3, V4, V6, V7 |
| U3 | Full-app loop is too broad for focused Bridge work | Independent backend restart | R1, R5, R6 | Restart then one automatic page reload creates fresh authority | V1, V5, V6 |

## Proof Obligations

| Proof | Evidence class | Distinguishes pass from fail by observing |
| --- | --- | --- |
| V1 | Manual interaction and runtime evidence | Vite HMR works without AgentStudio running |
| V2 | Runtime evidence and source/data inspection | Live results pass through the packaged app's existing Swift product/session owners, with no parallel development implementation |
| V3 | Automated behavior plus two runtime surfaces | One frontend protocol works in browser development and packaged WebKit |
| V4 | Controlled-worktree browser behavior | File/Review data matches the selected worktree and base |
| V5 | Process and browser runtime evidence | Backend restart triggers one page reload and succeeds independently |
| V6 | Failure-path browser behavior and state inspection | Absence is explicit and retired session data is not current |
| V7 | Security/runtime and artifact inspection | Loopback Debug access succeeds; remote/release exposure does not exist |
