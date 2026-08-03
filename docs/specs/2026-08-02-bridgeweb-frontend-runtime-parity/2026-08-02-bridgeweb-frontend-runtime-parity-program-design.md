# BridgeWeb Frontend Runtime Parity — Program Design

Date: 2026-08-02

Governing specification:
`2026-08-02-bridgeweb-frontend-runtime-parity.md`

## Integrated design

Two environment-specific worker entries construct one comm-worker runtime.
Each entry supplies a required fetch-compatible product request executor. The
shared transport's content-response limit defaults to twelve; Vite construction
explicitly supplies four. The page entries may also supply platform-specific
worker factories. From the shared comm-worker runtime inward, no component
detects whether requests use Agent Studio URL schemes or Vite HTTP routes.

```text
packaged entry composition                 Vite entry composition
  packaged worker entry                      Vite worker entry
  URL-scheme request executor                HTTP request executor
  admission default: 12                      admission value: 4
             |                                      |
             +---- construct shared worker runtime -+
                                   |
                         shared product session
                                   |
                    shared navigation admission
                                   |
                       shared BridgeApp owners
                                   |
                     shared Files/Review/renderers
```

The design adds no controller, store, recovery coordinator, persistence owner,
or backend. It replaces implicit route substitution and direct Vite navigation
with explicit construction dependencies and one product navigation protocol.
That protocol reuses the existing 4,096-byte display-path validator and
preserves subscription sequence-zero admission.

The shared worker registrar is side-effect-free. The packaged worker asset and
Vite module-worker source are thin executable wrappers that each call that
registrar once with their request executor; Vite also supplies the existing
physical response limit of four while packaged construction uses the default
of twelve. Packaged asset building points at the packaged wrapper; the Vite
worker factory points at the Vite wrapper. This is required because importing
an entry that auto-registers a default executor would recreate hidden
environment selection.

## Current system and the structural crux

Current packaged product requests use global `fetch` with
`agentstudio://rpc/command`, `agentstudio://rpc/stream`, and
`agentstudio://rpc/content`. Vite aliases the imported route module at build
time so the same source instead compiles against `/__bridge-product/...` HTTP
routes. The transport source therefore owns both product protocol behavior and
an implicit environment-selected endpoint dependency.

Current Vite bootstrap also parses a `BridgeViewerNavigationCommand` from the
URL and passes it directly into `BridgeAppProtocolRouter`. Packaged selection
arrives as `pane.surfaceSelectionRequested`, which carries only Files or Review
through the metadata stream and comm worker.

The structural crux is where legitimate environment variation ends. It must
end at construction, before shared request and navigation behavior begins.

## Selected alternative

### Selected: environment entry constructs one shared runtime

Each worker entry constructs the same comm-worker runtime with one required
`BridgeProductRequestExecutor`:

```text
BridgeProductRequestExecutor
  execute(product route, request init) -> Response
```

This is one function and one reason to vary: which endpoint receives an
already-built product request. The shared session authority and product
transport continue to own request encoding, strict response decoding,
capability headers, sequencing, acknowledgements, retries, stream consumption,
and failure classification.

The packaged executor maps command, metadata-stream, and content-stream routes
to Agent Studio custom-scheme URLs. The Vite executor maps the same route keys
to the existing HTTP development routes. Both call `fetch`; neither owns
product policy. The packaged worker-script loader remains separate because it
loads executable assets rather than product requests.

The shared product transport retains one content-response admission mechanism.
Its construction value defaults to twelve, the accepted packaged Bridge policy.
Packaged construction omits the value and therefore uses twelve. Vite
construction explicitly supplies four, preserving capacity for its long-lived
metadata response plus observation/control traffic on the six-request HTTP/1
carrier.

The shared admission owner continues to own the queue, ranked order,
abort-before-start, pause/resume while Review is hidden, response-lifetime
release, and disposal. A waiter has not called `fetch`; once admitted, the
shared transport invokes the executor and retains the lease until response EOF,
error, or cancellation. No second queue or physical-start lifecycle exists
inside either executor.

The executor contract is deliberately fetch-shaped:

- the route is one closed product-route identity: command, metadata stream, or
  content stream;
- request method, headers, encoded body, credentials, and abort signal pass
  through without reinterpretation;
- one invocation performs one host request and returns one `Response`; status,
  status text, headers, body bytes, body errors, and body cancellation are
  returned directly;
- synchronous construction errors and request rejection propagate unchanged;
  and
- the executor never retries, decodes, reads a body, opens a product session,
  classifies a product failure, queues a request, or owns admission state.

### Rejected: build-time route substitution

Keeping the Vite route alias is mechanically small, but it hides the only
legitimate environment variation inside shared transport imports and cannot be
inspected as a required construction dependency. It also permits tests to pass
against a differently compiled transport rather than two implementations of
one interface.

### Rejected: main-page request proxy

Sending every worker request to the browser page and invoking a page callback
would add a process hop, request correlation, cancellation relay, stream relay,
and another lifecycle owner. A JavaScript function cannot be transferred into
an existing worker, so environment-specific worker entry composition supplies
the executor without making the page a transport proxy.

### Rejected: multi-operation transport object or host policy

A three-method command/metadata/content port would restate distinctions already
owned by the shared product transport. A broader host service that owns retry,
decoding, navigation, or session state would create two product
implementations. The request executor ends at `Response` delivery; shared
owners retain all product semantics.

## Ownership and dependencies

| Component | Owns | Consumed by | Changes when | Must not own |
| --- | --- | --- | --- | --- |
| Packaged worker entry | Registering the shared worker runtime with the URL-scheme request executor and using the admission default of twelve | packaged worker asset | packaged endpoint binding changes | product state, retries, navigation policy |
| Vite worker entry | Registering the shared worker runtime with the HTTP request executor and explicit admission value of four | Vite module-worker factory | development endpoint or HTTP carrier capacity changes | fixture state, React navigation, product policy |
| `BridgeProductRequestExecutor` | Endpoint mapping, one request execution, and abort-signal propagation | shared session authority and product transport | the raw request carrier changes | queues, admission, schemas, sequencing, retries, stream decoding, response lifecycle, product state |
| Shared comm-worker runtime | Product session, strict protocol, constructed content-response admission, navigation schema/revision admission, replacement, failure classification | BridgeApp pane runtime | shared product protocol or admission behavior changes | environment detection, route selection, or navigation-source policy |
| Navigation producer | Creating and retaining one strict surface-plus-optional-target command and binding exact targets to the current navigation source | Vite dev carrier or Swift native owner | host navigation intent changes | React state mutation or source admission |
| `BridgeApp` composition | Active surface/target, accepted File/Review navigation-source facts, per-surface memory, and exact-target source admission | Files and Review owners | shared frontend navigation behavior changes | Vite detection, transport selection, or target application |

Allowed dependency direction:

```text
environment worker entry -> request executor + admission value -> shared worker registrar
producer -> shared navigation contract -> comm worker -> BridgeApp
```

Forbidden dependencies are enforced by imports and source-boundary tests:

- shared runtime to Vite or packaged request-executor modules;
- React to Vite fixture/query modules;
- product code to environment flags or route aliases;
- transport implementation to navigation or Files/Review state; and
- Vite producer directly to React props or stores.

## Shared navigation contract

The existing React-local `BridgeViewerNavigationCommand` becomes a shared
product-session discriminated union. Both variants carry command identity,
binding revision, surface, and the existing per-surface memory behavior:

- `activateContext` has no source and no target and restores that surface's
  existing remembered target only when it remains bound to the currently
  accepted source; and
- `activateTarget` has both a typed target and the current navigation-source
  identity to which that target belongs and replaces the remembered target for
  that surface.

The current `initialize` variant is removed from the product contract. It is a
Vite bootstrap vocabulary, not a third runtime behavior: the bootstrap emits
either `activateContext` or `activateTarget` through the same metadata path as
Swift. The redundant `restoreMemory` boolean is likewise represented by the
two variants rather than remaining an independently contradictory flag.

The source identity is navigation truth rather than the current UI-local
fixture vocabulary or native protocol-stream identity. File commands carry the
accepted File source id and subscription generation. Review commands carry the
accepted metadata source id, Review generation, and package id. Packaged Bridge
derives that metadata source id from its query id; Vite binds the distinct
source id actually accepted from its loaded development metadata. Literal ids
need not match across environments—the shared tuple shape and admission rule
do. Publication id is not part of navigation-source identity because a
successor delta changes publication while retaining the same Review source.
The target carries only target-specific facts such as path, version, or Review
item id. Review comparison ids that have no cross-runtime product authority
are removed rather than normalized differently by Vite and Swift.

Every optional File or Review path reuses the existing product display-path
validator in both languages: non-empty Unicode scalar text up to 4,096 UTF-8
bytes. Vite bootstrap parsing rejects an invalid intent before a pending
session retains it. The shared TypeScript navigation schema and Swift
encoder/decoder enforce the same boundary before either producer can bind or
publish a command. No producer-side filtering system is added.

Schema refinement enforces the complete intrinsic matrix before the command
leaves the worker:

| Command surface | Required source | Permitted target | Required equality |
| --- | --- | --- | --- |
| Files context | File source id + subscription generation | File path and version | command source equals accepted File display source tuple |
| Review context | Metadata source id + Review generation + package id | Review item and/or file path/version | command source equals accepted Review source tuple; publication changes alone do not invalidate it |
| Either surface-only context | none | none | no source claim exists |

The native `pane.surfaceSelectionRequested` contract hard-cuts to the shared
navigation command rather than creating a second command. A surface-only
selection is represented truthfully with neither source nor exact target.
When Swift issues an exact file or Review selection, its existing current File
source or committed Review publication supplies the complete navigation source
before the command is retained and bound to a pane session and worker instance.
The existing Swift selection authority owns both surface-only and exact-target
intent. The current IPC Review selection path that dispatches
`__bridge_select_review_item` directly into the page is removed; it validates
the item against the committed publication, then submits the same retained
exact-target command as every other producer.

The Vite query parser remains a development-entry concern. It supplies one
strict, deterministic initial command to the existing development product-
session host, which carries the requested surface and optional target in the
typed bootstrap request. The dev carrier resolves an exact target against its
loaded File source or Review query, binds the actual navigation-source identity,
retains the resulting strict command in the current session, and
publishes the same navigation metadata frame as Swift. A replacement bootstrap
rebinds to the replacement session's accepted navigation source while
preserving the logical command identity. The Vite entry no longer passes
`navigationCommand` into the router or any React product component.

The command is explicit bootstrap data because a worker-originated HTTP
request's referrer cannot reliably identify the owning page URL or preserve its
query. The carrier therefore must not infer navigation from request headers.

When a Vite subscription opens, the existing metadata writer first receives
`subscription.accepted` sequence zero before the control response permits a
concurrent interest update to enqueue sequence one. Navigation then uses the
same serialized writer and its existing one-frame-observed-before-next pacing.
There is no commit barrier, observation bypass, second queue, or metadata
coordinator.

The Vite product entry keeps only query inputs that the current development
carrier can represent as real product behavior: surface, optional exact target,
and development backend context. Legacy query switches that disable required
workers or select frontend-only fixture/delivery behavior do not enter the
shared product. Test-only fixtures remain in their test harnesses; development
backend scenarios may remain behind the carrier when they produce the same
protocol.

The comm worker validates session identity, frame ordering, and the strict
command shape before forwarding one navigation request to the main thread.
`BridgeApp` is the single navigation-source admission owner. File already
reports its accepted display source id and generation. Review display
projection adds its accepted metadata-source, Review-generation, and package
tuple as a typed navigation-source fact; it does not expose or fabricate the
native Review protocol stream identity. A surface-only command can proceed
without a source.
`BridgeApp` retains an exact-target command until the matching surface's
accepted navigation source exists, admits it only on complete tuple equality,
and rejects a mismatch without changing the active surface or invoking the
target controller.

`BridgeApp` also owns revocation. When the accepted source tuple changes, it
removes the old exact target from the child-controller input and invalidates
that source's remembered target before a surface-only restoration can use it.
The application key passed to the existing Files/Review target owner is the
already-selected command id, binding revision, and complete source tuple. The
target owner applies one key at most once. Replaying the same binding is a
no-op; a replacement that truthfully rebinds the logical intent to a new
accepted source has a newer binding revision and may apply once. A stale or
superseded binding cannot be handed to a target owner. No new store is needed:
the remembered command and accepted-source facts remain `BridgeApp` state, and
the existing target owners retain their local applied-key memory.

The existing active-viewer update remains part of the existing surface
selection lifecycle; exact-Review IPC does not repurpose it as an IPC
completion receipt. After the existing package and item validation,
`selectReviewItemForIPC` awaits only native binding and publication of the
typed command into the current product session, then returns the same
`selected: true` result as the former page-event dispatch. It does not wait for
React application or target rendering. Existing `packageUnavailable` and
`itemNotFound` results remain unchanged, and publication failure continues
through the existing generic IPC failure path. No new public failure reason,
deadline, continuation waiter, target-completion receipt, or second
acknowledgement is added.

Exact-target application remains owned by the existing Files/Review navigation
controllers. An inactive File surface remains inert unless a pending exact
File command needs its accepted source fact; only that pending-command case may
start the existing headless source reporter, and clearing the pending command
returns the inactive surface to its prior inert lifecycle.

Navigation delivery uses the existing pane/worker binding lifecycle:

| State | Owner | Transition and guard | Replacement behavior |
| --- | --- | --- | --- |
| retained | Swift selection authority or Vite product-session host | accept one strict surface and optional-target intent | Swift retains intent; Vite retains its deterministic bootstrap intent |
| bound | producer | bind the current pane session, worker instance, monotonic revision, and actual navigation source for exact targets | replacement rebinds the same logical intent; stale worker bindings cannot publish |
| delivered | metadata stream and comm worker | strict frame and revision decode | same command identity is idempotent; stale frame revisions cannot reach React |
| admitted | `BridgeApp` | surface-only commands need no source; exact-target source must match the complete accepted File or Review tuple | pending commands wait for the source fact; mismatches cannot change surface or target state |
| revoked | `BridgeApp` | accepted source tuple changes or a newer binding supersedes the command | remove stale child input and remembered target before restoration/application; no stale target mutation |
| applied | `BridgeApp` and the active Files/Review navigation owner | activate the surface, then apply one command-id + binding-revision + source-tuple key through existing policy | same key is idempotent; a newer truthful rebind may apply once; target rendering remains frontend-owned |

## Call-path delta

```text
PRODUCT REQUESTS

current packaged
  shared transport -> global fetch(packaged route constant)
                   -> Agent Studio URL scheme -> Swift provider

current Vite
  shared transport -> global fetch(aliased dev route constant)
                   -> Vite middleware -> TypeScript provider

proposed packaged
  packaged worker entry
    -> [changed] register shared runtime(URL-scheme request executor)
    -> shared transport/session [changed: admission default 12; calls executor]
    -> request executor -> Agent Studio URL scheme -> Swift provider
    <- same decoded result/error/session behavior [intentionally unchanged]

proposed Vite
  Vite worker entry
    -> [added] register shared runtime(HTTP request executor, admission 4)
    -> shared transport/session [changed: shared admission 4; calls executor]
    -> request executor -> Vite middleware -> TypeScript provider
    <- same decoded result/error/session behavior [intentionally unchanged]

NAVIGATION

current Vite
  query -> parse command -> [removed] React router prop -> BridgeApp state

current packaged
  Swift surface intent -> metadata frame(surface only)
    -> comm worker -> BridgeApp mode -> acknowledgement

current packaged exact Review target
  IPC selectReviewItemForIPC
    -> [removed] page JavaScript `__bridge_select_review_item`
    -> Review controller selection
    <- JavaScript dispatch completion, not target-render completion

proposed both
  environment producer -> [changed] shared navigation frame(surface + target?)
    -> metadata stream -> comm worker schema/revision admission
    -> BridgeApp source admission -> Files/Review target application
    <- existing surface receipt when native requested a surface

proposed packaged exact Review target
  IPC selectReviewItemForIPC
    -> [changed] Swift selection authority validates committed publication
    -> shared exact-target navigation frame
    <- native bind/publication accepted: unchanged selected=true result
    -> comm worker -> BridgeApp source/binding admission
    -> existing Review target owner
    <- render completion remains outside IPC result meaning

proposed Vite producer detail
  Vite query parser -> product-session bootstrap request(surface + target?)
    -> dev carrier binds actual File source id or Review query id
    -> shared navigation metadata frame
```

Current evidence anchors include:

- `BridgeWeb/src/app/bridge-app-bootstrap.tsx`
- `BridgeWeb/src/app/bridge-app-dev-bootstrap.tsx`
- `BridgeWeb/src/app/bridge-app-dev-product-session-host.ts`
- `BridgeWeb/src/app/bridge-app-dev-fixture.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-entry.ts`
- `BridgeWeb/src/core/comm-worker/bridge-pane-comm-worker-session.ts`
- `BridgeWeb/src/core/comm-worker/bridge-product-transport.ts`
- `BridgeWeb/src/core/comm-worker/bridge-product-session-authority.ts`
- `BridgeWeb/src/core/comm-worker/bridge-product-routes.ts`
- `BridgeWeb/src/core/comm-worker/bridge-product-dev-routes.ts`
- `BridgeWeb/vite.config.ts`
- `BridgeWeb/tsdown.config.ts`
- `BridgeWeb/scripts/dev-server/bridge-product-dev-carrier.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-native-surface-selection.ts`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneSurfaceSelectionAuthority.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+IPCProjection.swift`

## Lifecycle, failure, and concurrency

The request executor has the same lifetime as one worker runtime. Worker
replacement constructs a fresh runtime and executor; disposal cancels every
in-flight operation owned by the shared product owners through their existing
abort signals and stream cancellation. An executor is immutable after
construction and cannot switch environments.

Existing session sequencing remains authoritative. The executor does not retry,
reorder, decode, or cache. Concurrent command and stream operations remain
coordinated by the current shared session/transport owners. Abort signals and
stream cancellation cross the executor boundary exactly once.

Content response admission remains one shared queue whose maximum is fixed at
runtime construction. Omitted means twelve; Vite supplies four. Admission
order, abort-before-start, pause/resume, release, and disposal remain
transport-owned. The endpoint string is no longer inspected, so the shared
transport applies the supplied value without detecting the environment. A
waiting request has not called the executor or `fetch`; Review foreground exit
can therefore withdraw or pause it through the existing start control while
retaining the logical record. Response EOF, body error, body cancellation, or
request failure releases the shared lease exactly once. Worker replacement
aborts shared waiters and active requests through their existing signals.

Failure flow:

```text
request owner encodes and admits operation
  -> injected executor selects endpoint and attempts request
     -> construction/request failure: return transport failure
     -> response/stream opens: return raw response boundary
  -> shared owner decodes/classifies
     -> existing retry/replacement policy, when eligible
     -> existing bounded product failure, otherwise
```

Malformed navigation fails strict decoding before React state changes. Frame
revision ordering is enforced in the comm worker. Exact-target source
compatibility is enforced in `BridgeApp` against the complete accepted File or
Review source tuple before the active surface or target state changes. A source
change synchronously revokes the stale child command and remembered target;
the complete application key prevents an old effect or command-id-only latch
from suppressing a newer valid binding. Existing Files/Review controllers still
own target availability and selection within the admitted source; they do not
become source authorities. This preserves target behavior without adding a new
atomicity or receipt contract.

Vite subscription open preserves the existing enqueue-order invariant:
`subscription.accepted` sequence zero is enqueued before the accepted control
response permits an update to publish sequence one. Navigation enters the same
writer afterward and does not bypass its existing per-frame observation gate.

HMR may dispose and reconstruct the Vite entry. It creates a new runtime and
executor rather than preserving executor state. A replacement bootstrap
re-sends the same deterministic logical intent. An unchanged source binding
replays the same application key idempotently; a newly accepted source receives
a newer binding revision and may apply once through the existing navigation
owner.

## Trust and authority

Capability material, strict request/response schemas, limits, and source
authority remain owned by the existing product session and backend. Transport
implementations carry capability-bearing requests but do not log, persist, or
reinterpret capabilities, paths, content, or provider errors.

The Vite backend remains development authority only. The packaged Swift backend
remains the only packaged filesystem, Git, and registered-worktree authority.
Sharing frontend commands does not make fixture facts evidence of packaged
capability.

## Cutover

The cutover is a hard replacement:

1. Shared session/transport owners require a `BridgeProductRequestExecutor`.
2. Packaged and Vite worker entries construct the executor explicitly;
   packaged uses the admission default of twelve and Vite supplies four.
3. The Vite route alias for product transport is removed.
4. The shared navigation contract replaces the surface-only worker contract.
5. Vite navigation moves from React props to dev-session metadata delivery.
6. Packaged IPC Review exact-target selection moves from its direct JavaScript
   event to the same retained shared navigation command.
7. Dev-only worker-disable and frontend-only fixture/delivery branches are
   removed from the product entry; Vite always constructs the platform worker
   factories required by the shared product.
8. File and Review paths hard-cut to the existing 4,096-byte display-path
   validator in Vite bootstrap, shared TypeScript navigation, and Swift.
9. Vite subscription opening enqueues `subscription.accepted` before returning
   open acceptance, then publishes navigation through the same observed writer.
10. Direct navigation props/events and environment-selected frontend paths are
   removed.

There is no phase in which both navigation paths or both implicit and explicit
transport selection are accepted.

## How requirements are realized and proved

| Requirement | Realization owner and seam | Proof boundary |
| --- | --- | --- |
| R1 | shared runtime constructed by both entries | shared behavior tests plus real Vite and packaged journeys |
| R2 | required simple `BridgeProductRequestExecutor`; packaged and HTTP endpoint bindings; one shared admission owner with default twelve and Vite-supplied four | executor contract proof that no queue/lifecycle exists inside either function; shared admission proof for packaged twelve and Vite four; hidden-waiter pause/resume, abort/release, and real metadata/control progress under saturated Vite content demand |
| R3 | discriminated navigation schema with the existing 4,096-byte display-path boundary, complete producer source binding for exact targets, ordered Vite metadata admission, comm-worker frame admission, accepted navigation-source facts, `BridgeApp` admission/revocation and source-bound application key, existing target owners, and hard-cut packaged IPC Review producer | 4,096/4,097 boundary proof before retention in TypeScript and Swift; deterministic subscription sequence-zero-before-one proof with existing observation pacing; inactive File lifecycle proof with and without a pending exact target; real-worker integration for Files, Review, `README.md`, pending source, mismatch, source rotation before application, stale revision, same-binding replay, newer valid rebind, and packaged IPC command journey whose selected/error vocabulary is unchanged and has no direct page event |
| R4 | entry-only imports and forbidden dependency rules | static source/import enforcement and build graph inspection |
| R5 | Vite entry/HMR reconstructs the same runtime | live Vite browser journey across an HMR update |
| R6 | hard-cut source inspection; unchanged backend authorities | final diff plus packaged native-authority journey |

Mocks may replace the external request executor for deterministic unit tests,
but integration proof must use the real Vite HTTP server and real packaged URL
scheme respectively. Browser proof cannot replace packaged WKWebView/native
proof.

## Accepted cost and revisit signal

The design adds one narrow request executor and one shared navigation contract.
It reuses the shared admission mechanism with an explicit construction value:
default twelve, Vite four. The cost is paid at worker construction and strict
contract cutover, where the variation already exists. It removes build-time
product-route substitution and direct Vite navigation without moving queues or
response lifecycle into the request function.

Revisit only if WebKit and Chromium can use one identical request
implementation and worker-loading mechanism without route substitution. In
that case the two transport implementations may collapse; product owners and
the shared runtime remain unchanged.
