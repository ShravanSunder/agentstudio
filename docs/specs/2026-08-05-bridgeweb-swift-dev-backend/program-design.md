# BridgeWeb Swift Development Backend — Program Design

Requirements: [BridgeWeb Swift Development Backend — Requirements](user-requirements.md)

Specification: [BridgeWeb Swift Development Backend Specification](2026-08-05-bridgeweb-swift-dev-backend.md)

## Design Decision

Keep Vite as the BridgeWeb asset server and React hot-module-replacement
owner. Replace its live TypeScript product carrier with one loopback-only Debug
Swift executable that composes the existing `AgentStudioBridge` product
owners.

The server is a carrier, not a second backend model. It does not implement
session sequencing, Git classification, File/Review preparation, metadata
publication, content authorization, or stream acknowledgement rules. Those
remain owned by the existing Swift types used by AgentStudio.

```text
Browser + comm worker
  │
  ├── assets / HMR ───────────────► Vite
  ├── four product endpoints ─────► Vite proxy
  └── dev health probe ───────────► Vite proxy
                                      │
                                      ▼
                              Debug Swift server
                                      │ thin HTTP translation
                                      ▼
                         existing AgentStudioBridge owners
                           ├── product session/admission
                           ├── File and Review Git sources
                           ├── metadata/content producers
                           └── acknowledgement/lifecycle rules
```

## Current System

`BridgeWeb/vite.config.ts` currently installs four product routes and sends
them to `bridge-product-dev-carrier.ts`. That TypeScript carrier owns live
capability issuance, product sessions, command sequencing, metadata streams,
acknowledgements, File/Review adapters, and content production.

The packaged app already owns the corresponding behavior in Swift:

- `BridgePaneProductSessionOwner` owns installation, replacement, retirement,
  capability, and session lifetime.
- `BridgeProductSession` owns protocol admission and sequencing.
- `BridgePaneProductSchemeProvider` owns command responses and delegates
  File/Review metadata and content production to existing Swift sources.
- `BridgeProductSchemeAdapter` admits and routes command, metadata-stream, and
  content requests and emits response/data frames.
- `BridgeWorktreeProductConstructionCoordinator`, `BridgeReviewPipeline`, and
  `agentstudio-git` own real worktree construction and Git behavior.

The gap is therefore one development composition and carrier edge, not a new
product implementation.

## Components And Ownership

### Existing `AgentStudioBridge` product owners

These remain the only product authority. Their product rules do not move into
the server or Vite. Existing packaged-app composition continues to use them
without acquiring an HTTP or development-server dependency.

Production transport remains unchanged: `BridgePaneController` registers the
existing `agentstudio` WebKit URL-scheme handler, WebKit supplies the scheme
task lifecycle, and `BridgeSchemeHandler` routes product requests through the
active `BridgeProductSchemeAdapter`. The Debug design must not replace,
special-case, proxy, or route production traffic through HTTP.

There is one product execution path. Production WebKit ingress and Debug HTTP
ingress perform only their carrier conversion before converging on the same
active `BridgeProductSchemeAdapter` and the same downstream owners.

### `agentstudio-bridge-dev-server` executable

A new SwiftPM executable product depends on `AgentStudioBridge` and the chosen
HTTP serving library. It exists for local Debug development and is not linked
into or launched by the AgentStudio app.

It owns only:

- validated development input: worktree root, Review base, and loopback port;
- process startup and shutdown;
- one `BridgeDevelopmentProductHost` for the selected source; and
- binding the HTTP listener to `127.0.0.1`.

A non-Debug build refuses to serve. No daemon, watcher, persistence, service
registration, or AgentStudio application lifecycle is introduced.

### `BridgeDevelopmentProductHost`

This is a deliberately thin feature-owned composition wrapper. It creates the
existing Swift Git, construction, File/Review source, provider, session-owner,
and admission objects for one selected worktree/base, then delegates to them.
It owns no product decisions, cache, Git behavior, session state machine, or
independent lifecycle model.

It owns two host operations:

1. issue or replace a product-session bootstrap through
   `BridgePaneProductSessionOwner`; and
2. route an admitted product request through the active
   `BridgeProductSchemeAdapter`.

Those two operations form the only package-facing development API. The
executable receives an encoded bootstrap delivery or an async sequence of
response/data events; it does not receive the provider, session, admission
gate, construction coordinator, or publication owners. Existing internal
visibility remains internal instead of being widened for the server.

If this wrapper begins interpreting product commands, retaining product data,
or recreating behavior already owned by an existing Bridge type, the design
has drifted.

It may translate the development bootstrap's selected surface/target into the
existing Swift navigation command and source models. It must not reproduce the
product state machine or Git/data preparation performed by those owners.

The host lifetime equals the server process lifetime. A server restart retires
all prior authority; a page reload asks the new process for a new bootstrap.

### Thin HTTP adapter

This is also deliberately thin. It maps the existing development endpoints to
the current Swift carrier inputs:

```text
POST /__bridge-product/bootstrap  -> host bootstrap issuance/replacement
POST /__bridge-product/command    -> agentstudio://rpc/command
POST /__bridge-product/stream     -> agentstudio://rpc/stream
POST /__bridge-product/content    -> agentstudio://rpc/content
GET  /__bridge-product/health     -> bodyless 204 readiness response
```

For the three product routes, it converts the HTTP request into the canonical
`URLRequest` accepted by the package-facing development host. The host invokes
`BridgeProductSchemeAdapter` internally and returns its response/data events;
the HTTP adapter turns those events into an HTTP response stream. Disconnect
cancellation closes the corresponding Swift stream/task. The executable does
not interpret control packages or frames and cannot reach the internal product
owners directly.

It owns no retries, session registry, capability rules, response cache, product
fallback, or protocol state. The health handler does not call the product host,
issue bootstrap, activate a session, or mint a capability. HTTP translation,
the side-effect-free readiness response, and disconnect propagation are its
complete responsibility.

The two carrier formats converge before any product behavior:

```text
WKWebView -> agentstudio URL scheme -> BridgeSchemeHandler ─┐
                                                            ├─► active BridgeProductSchemeAdapter
browser -> Vite proxy -> thin Debug HTTP translation ──────┘      │
                                                                  ▼
                                                     existing product owners
```

The upper branches are carrier ingress only, not separate product paths. They
must not interpret product commands, sessions, frames, Git data, or content.
Production continues to use the native WebKit URL-scheme carrier and task
lifecycle; Debug HTTP translates into the same adapter input/output contract.

This deliberately reuses the WebKit-shaped adapter instead of extracting a
new carrier-neutral routing layer. The cost is a small development-only
translation coupled to `URLSchemeTaskResult`; the gain is that the server
cannot quietly acquire a second copy of admission, sequencing, streaming, or
acknowledgement behavior. A neutral adapter extraction is deferred unless a
second durable carrier makes that coupling a demonstrated problem.

Hummingbird is the preferred HTTP edge because it supplies bounded routing,
async response streaming, disconnect cancellation, loopback binding, and
graceful shutdown without hand-writing an HTTP parser or SwiftNIO channel
lifecycle. It is an executable-target dependency, not an app or
`AgentStudioBridge` product dependency.

### Vite development wiring

Vite retains React, assets, HMR, and the existing browser origin. Its four
product middleware handlers and development health route become proxy rules to
the loopback Swift server.
Vite does not parse product bodies, construct Git providers, issue
capabilities, retain sessions, or synthesize product responses.

The existing browser bootstrap host and HTTP request executor remain the
frontend carrier selection. The TypeScript bootstrap decoder and test fixtures
may remain; the live TypeScript bootstrap encoder/carrier, product adapters,
session implementation, metadata writer, and content producers are removed.

The Vite-only product-session host also owns the development substitute for the
native ready acknowledgement. It acknowledges each page handshake only after
the corresponding initial Swift bootstrap resolves. When Vite reports that the
Swift upstream is unavailable, it starts one cancellable health-probe loop; the
first `204` reloads the page once. A bootstrap rejection returned by a live
Swift backend remains an explicit failure and does not start probing. This
behavior does not enter shared `BridgeApp`, packaged bootstrap, or production
transport code.

## Development Source Selection

The Swift executable receives the worktree root and Review base as startup
configuration. It validates that source before listening and constructs one
source-bound product host. Vite forwards product traffic without owning or
normalizing that selection.

The browser bootstrap request continues to carry only its surface/target
navigation intent and replacement identity. A different worktree/base requires
restarting the Swift server with the new source and reloading the page. This
keeps source authority in Swift and avoids a Vite-only product configuration
API.

## Representative Call Paths

### Initial browser session

```text
developer starts Swift server with worktree/base
  -> Swift validates source and composes existing product owners
developer starts/opens Vite page
  -> browser requests /bootstrap through Vite proxy
  -> Swift host issues existing session bootstrap + capability
  -> Vite-only host acknowledges page readiness
  -> comm worker opens session through /command
  -> existing Swift session admits sequence 1
  -> existing Swift provider accepts the worker session
```

### File or Review data

```text
comm worker request
  -> Vite proxy (no body interpretation)
  -> HTTP adapter rewrites only the carrier route
  -> BridgeProductSchemeAdapter
  -> BridgeProductSession admission/sequencing
  -> BridgePaneProductSchemeProvider
  -> existing File/Review source + agentstudio-git
  -> existing metadata/content frames
  -> HTTP stream -> comm worker -> React
```

### Backend restart

```text
server stops
  -> listener and host terminate; old capability dies with process
  -> open browser requests fail through the existing unavailable/retry path
server restarts with selected source
  -> failure-only health probe receives 204
  -> Vite page reloads exactly once and requests a new bootstrap
  -> new capability/session; no authority is recovered from old process
```

## Failure And Concurrency Boundaries

- Invalid worktree/base: fail startup before binding; never fall back to a
  different repository or fixture.
- Backend absent during initial bootstrap: Vite reports the correlated ready
  error and probes only the development health route. Non-204 and failed probes
  do not reload; the first 204 reloads once. A live backend's bootstrap
  rejection reports failure without probing or reloading.
- Invalid method, body, capability, or sequence: existing Swift admission owns
  the rejection.
- Client disconnect: cancel only that HTTP/product stream and let existing
  retirement rules settle its leases and producers.
- Worker replacement: serialize through the existing session owner; never keep
  two active installations for one development host.
- Source change: restart and page reload, not live mutation of a host.
- Process shutdown: stop accepting requests, cancel in-flight HTTP tasks, and
  retire the active product installation through existing owner APIs.

There is no cross-process persistence, in-place reconnect, hot backend swap,
continuous watcher, or multi-worktree host registry.

## Proof Architecture

### Automated

- Swift unit tests prove source configuration rejects missing/invalid roots and
  non-loopback binding.
- Swift integration tests run the development host against a controlled real
  Git worktree and exercise bootstrap, File, Review, stream acknowledgement,
  content, replacement, disconnect, and shutdown through HTTP.
- BridgeWeb tests prove Vite proxies all four product endpoints plus the
  development health route, acknowledges bootstrap readiness, bounds recovery
  to one reload, and installs no live TypeScript carrier.
- Existing shared-contract and packaged WebKit suites remain green, proving the
  frontend protocol and existing Swift product owners were not forked.
- Release artifact inspection proves AgentStudio does not link, launch, or
  expose the development server.

### Manual

- Run the Debug Swift server and Vite while AgentStudio is not running.
- Open File and Review for a controlled worktree and verify the visible result
  matches that worktree/base.
- Edit React and observe Vite HMR without restarting Swift.
- Stop Swift and observe explicit bootstrap failure; restart it, observe one
  automatic page reload, and verify a fresh working session.

No restart-duration threshold or benchmark is a readiness gate.

## Requirement Realization

- U1 / R1: Vite continues to own assets and HMR; only its product handlers
  become proxies.
- U2 / R2–R4 / R6–R7: the loopback server composes and calls the existing Swift
  product/session/Git owners; TypeScript and server glue own no product model.
- Product execution: production URL-scheme ingress and Debug HTTP ingress
  converge on the same active `BridgeProductSchemeAdapter`; the existing
  WebKit registration and task lifecycle remain intact.
- U3 / R5: the standalone executable can be rebuilt/restarted independently;
  one development-only page reload is the complete recovery boundary.

## Rejected Alternatives

- Replace Vite with Swift: loses the accepted frontend/HMR owner and solves the
  wrong problem.
- Keep the TypeScript carrier beside Swift: preserves two live authorities.
- Reimplement the carrier state machine in a new Swift server: changes the
  language but not the duplication.
- Launch a hidden AgentStudio pane/controller: couples browser development to
  the full app loop and creates unnecessary UI lifecycle.
- Extract a generalized transport framework first: spends production
  complexity before the one development carrier demonstrates that need.
- Add a watcher, daemon, in-place reconnect protocol, or persisted sessions: not
  needed for the accepted restart-plus-single-reload workflow.
