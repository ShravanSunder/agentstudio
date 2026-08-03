# BridgeWeb Frontend Runtime Parity

Date: 2026-08-02

Governing user requirements:
`2026-08-02-bridgeweb-frontend-runtime-parity-user-requirements.md`

## Problem and outcome

The Vite and packaged entries mount the same product family, but they do not
currently enter it through one complete frontend control path. Vite injects an
initial navigation command directly into React and substitutes development
routes at build time, while packaged IPC exact-Review selection dispatches a
separate page event. Consequently, a journey can pass without proving that all
producers issue the same command or that both environments use the same request
boundary.

The required outcome is one environment-blind frontend runtime. Packaged and
Vite worker construction supply different endpoint bindings for one request
executor contract; all navigation and product behavior after construction is
identical.

## Observable system contract

```text
packaged native intent                 Vite fixture intent
          |                                  |
          +------ same navigation command ---+
                             |
                    same product session
                             |
                      same comm worker
                             |
                      same React product

transport selected only at construction:
  packaged -> Agent Studio URL-scheme requests
  Vite     -> ordinary HTTP development-server requests
```

The navigation command identifies Files or Review and may identify an exact
file or Review target. A surface-only command carries no source identity; an
exact-target command is bound to the producer's complete currently accepted
product-source identity and is admitted only while that same source remains
accepted. File identity includes source and subscription generation. Review
identity includes the accepted metadata source id, Review generation, and
package id; it deliberately excludes publication id because ordinary successor
deltas replace publications without replacing the Review source. `README.md`
is the representative exact-file case.

## Requirements

### R1 — Shared runtime

Vite and packaged construction must invoke the same React, comm-worker,
product-session, navigation, Files, Review, and renderer behavior. If a behavior
can be selected only because the frontend is running under Vite, parity fails.

Basis: U1.

### R2 — Required injected transport

Each worker construction must provide one required request executor. The
packaged implementation must issue product requests through the Agent Studio
custom URL scheme; the Vite implementation must issue the equivalent requests
to the ordinary HTTP development server.

The shared runtime must consume only the transport contract. It must not import
environment-specific route constants, inspect the environment, or select a
transport after construction.

The executor is one fetch-compatible callable value. It accepts the selected
product route and request initialization and returns a response. The shared
product owners retain bounded command handling, long-lived metadata and content
stream handling, admission, decoding, cancellation, response lifetime, and
response/error semantics. The executor owns only endpoint mapping and the
network call.

The shared transport's content-response admission limit defaults to the
packaged Bridge policy of twelve. Vite construction explicitly supplies four
because its HTTP/1 carrier must reserve capacity for metadata and control. The
same shared admission owner applies either value and retains queue order,
pause/resume, abort-before-start, response-lifetime release, and disposal. The
request executor receives no admission policy or lifecycle control.

Basis: U2, U4, U6.

### R3 — Shared typed navigation ingress

Vite query configuration and packaged Swift selection must produce the same
strict navigation command and deliver it through the product-session and comm
worker path. The command must carry the selected surface and an optional exact
target.

For a Vite URL selecting `README.md`, React must receive the command only after
the Vite entry has supplied it to the development product-session bootstrap,
the dev carrier has published it as metadata, and the comm worker has admitted
and forwarded it. Direct Vite entry props, fixture-specific React state, and
alternate navigation stores are prohibited.

Malformed commands must be rejected before React state changes. Revision
ordering and source/target compatibility continue through one shared React
admission owner in both environments. Surface-only commands must not fabricate
a source identity. Exact-target commands must carry the complete accepted File
or Review navigation-source identity, and a command whose source does not
match React's accepted navigation source must not change the active surface or
reach a target controller. Review navigation identity is the accepted Review
metadata source tuple; packaged Swift derives that source id from its query,
while Vite binds the source id actually accepted from its development backend.
It is not the native Review protocol stream identity, publication identifier,
or UI-only comparison identifier.

An admitted exact target remains eligible only while its bound source remains
accepted. Source replacement must revoke stale pending and remembered targets
before they can be restored or applied. A surface-only command may still
activate that surface after revocation, but it must not restore a target from a
different source. Replaying one binding is idempotent; rebinding the same
logical intent to a newly accepted source is a new eligible application and
must not be suppressed as an old replay. This change does not add a second
acknowledgement or new target-completion policy.

Basis: U3, U4, U6.

### R4 — Construction is the complete environment boundary

Environment-specific code may construct:

- the required request-executor binding; and
- the shared transport's physical content-response limit, with twelve as the
  default and Vite explicitly supplying four; and
- platform-specific worker factories when the browser and WKWebView require
  different loading mechanics.

That construction code must not own navigation state, Files/Review state,
filter/search/view-setting state, renderer policy, retry policy, or recovery
policy. No environment check may occur below the construction boundary.

Basis: U1, U2, U4.

### R5 — Preserve development ergonomics

The Vite surface must retain browser serving and HMR. Removing worker-disable
or fixture-only product branches is allowed and required when those branches
cannot represent packaged behavior; removing the Vite development loop is not.

Basis: U5.

### R6 — Hard cut without backend consolidation

The superseded direct-navigation and environment-selected frontend paths must
be removed in the same cutover. No compatibility branch may retain them.

The TypeScript development backend and Swift packaged backend remain separate
in this change. A Swift debug-server target and reusable-backend extraction are
outside this specification.

Basis: U7.

## Failure and compatibility contract

- A worker cannot become ready when its required request executor or worker
  factory cannot be created; existing startup failure and replacement behavior
  remains authoritative.
- Request rejection, timeout, cancellation, stream termination, replacement,
  and malformed input continue through the existing shared product-session and
  worker failure behavior.
- Packaged Bridge uses the shared admission default of twelve. Vite supplies
  four to the same shared admission owner so metadata and control retain HTTP/1
  capacity. A waiting request remains before physical `fetch`, so existing
  pause/resume, ranked order, abort-before-start, and response-lifetime rules
  remain unchanged. The executor itself contains no queue or admission state.
- Neither environment may recover by selecting a simpler frontend path or
  bypassing the comm worker.
- Worker replacement must reconstruct the same environment binding. Retained
  navigation intent may be rebound only through the existing session authority.
  An exact binding may apply once for its command, binding revision, and source
  identity; a replacement source requires a newer binding revision and cannot
  reuse stale target eligibility.
- HMR may reconstruct the Vite entry and transport; it must not introduce a
  second persistence or reconciliation owner.
- Packaged custom-scheme behavior and Vite HTTP behavior need not share platform
  error text, but they must map to the same bounded product failure classes.

## Negative space

This specification does not authorize:

- a new native or TypeScript backend;
- a Swift development server;
- controller or `WKWebView` replacement;
- changes to native registered-worktree authority;
- a Vite-only React prop, store, route, recovery path, or rendering fallback;
- a runtime `isVite`/development flag;
- durable navigation or presentation state; or
- treating browser proof as packaged native proof.

## Proof obligations

| Proof | Obligation |
| --- | --- |
| V1 — structural enforcement | Shared product sources have no environment checks, development route imports, or direct Vite navigation props. |
| V2 — request executor and admission behavior | Both endpoint bindings only map and perform requests. Shared admission defaults to twelve for packaged Bridge and uses the explicitly supplied four for Vite. With four Vite content bodies held open and another content request waiting, metadata plus observation/control traffic still progresses; hidden Review pauses the waiter before `fetch`; abort and response EOF/error/cancel release exactly once; final waiter and lease residue is zero. |
| V3 — navigation integration | Vite and packaged producers, including packaged IPC exact-Review selection, send the same strict navigation command through a real comm worker; `README.md` opens through that path; mismatched and superseded source bindings are rejected before active-surface or target state changes; source rotation revokes stale remembered/pending targets; one binding applies once while a newer valid rebind can apply once. |
| V4 — Vite browser journey | The real Vite dev server, real comm worker, and shared React product complete Files, Review, and exact-file navigation while HMR remains available. |
| V5 — packaged runtime journey | The packaged debug app drives the same command through Swift, the comm worker, and WKWebView without a development substitute. |
| V6 — cutover inspection | No compatibility path, second store, backend extraction, or PR 2 server work is present. |

## Traceability

| User need | Problem | Outcome | Requirement | Contract | Proof |
| --- | --- | --- | --- | --- | --- |
| U1, U4 | P1: frontend behavior can diverge by environment | O1: one environment-blind runtime | R1, R4 | construction is the only environment boundary | V1, V4, V5 |
| U2, U6 | P2: request selection is compiled into shared transport code | O2: explicit replaceable request boundary | R2 | equivalent command/stream/content behavior | V2, V4, V5 |
| U3 | P3: Vite and packaged IPC can bypass worker navigation | O3: one typed navigation ingress | R3 | surface plus optional exact target; strict decode and shared ordering | V3, V4, V5 |
| U5 | P4: parity could damage the fast frontend loop | O4: representative HMR development | R5 | HMR reconstructs the same binding | V4 |
| U7 | P5: backend consolidation would expand this change | O5: bounded frontend-only cutover | R6 | current backends retained | V6 |
