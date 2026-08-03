# BridgeWeb Frontend Runtime Parity — User Requirements

Date: 2026-08-02

## Goal

A developer using the Vite BridgeWeb surface must exercise the same frontend
product runtime as the packaged Agent Studio Bridge pane. The environment may
change how product requests reach a backend, but it must not change how React,
the comm worker, navigation, Files, or Review behave.

## Affected classes

- A BridgeWeb developer using Vite and hot module replacement to work on Files
  or Review.
- A maintainer verifying that behavior exercised in Vite represents the
  packaged Bridge frontend.
- A person using the packaged Bridge pane, whose behavior must not regress when
  the development and packaged construction paths are unified.

## Authorized requirements

### U1 — One frontend product path

Priority: Must, assigned by the product owner.

Vite and packaged Bridge must run the same React product tree, comm-worker
runtime, product-session protocol, navigation handling, Files behavior, Review
behavior, rendering decisions, and failure behavior.

Evidence: the current Vite entry injects values that can select behavior the
packaged entry does not select, and the product owner requires those paths to
converge.

### U2 — Construction-time transport injection

Priority: Must, assigned by the product owner.

The frontend runtime must receive its environment-specific product-request
implementation during construction. Packaged construction uses the Agent
Studio URL-scheme request implementation; Vite construction uses ordinary HTTP
requests to its development server. After construction, shared product code
must not detect or branch on the environment.

The internal interface is one required fetch-compatible request executor. The
shared product owners continue to distinguish bounded commands, metadata
streams, and content streams; the injected function only maps an already-built
request to the environment's endpoint and performs the network call. It owns no
queue, admission, pause/resume, response-body wrapper, retry, decoding, or
product lifecycle.

The shared transport retains its existing content-response admission mechanism.
Its construction value defaults to the packaged Bridge limit of twelve; Vite
explicitly supplies four for its HTTP/1 carrier reservation.

### U3 — One navigation ingress

Priority: Must, assigned by the product owner.

Vite query selection and packaged native selection must enter through the
same typed product-session metadata, comm-worker, and React navigation
mechanism. A Vite query that asks to open `README.md` must not pass an initial
navigation prop directly to React; the Vite development carrier must publish
the same typed navigation command that packaged Swift would publish.

Exact File and Review paths use the existing Bridge product display-path
contract: non-empty Unicode scalar text up to 4,096 UTF-8 bytes. An over-limit
path is rejected before it can be retained as navigation intent, published as
metadata, or displayed.

### U4 — Environment blindness after construction

Priority: Must, assigned by the product owner.

React, Files, Review, shared controls, projections, render fulfillment, and the
shared comm-worker runtime must not contain `isVite`, development-mode, fixture,
route-alias, or equivalent environment decisions. Environment-specific entry
modules may construct the required transport and platform worker factories but
must not own product state or navigation policy.

### U5 — Preserve the development loop

Priority: Must, assigned by the product owner.

Vite must retain its browser development server and hot module replacement.
The parity change must not require packaging or launching the macOS app for
ordinary frontend iteration.

### U6 — Preserve protocol behavior and failure truth

Priority: Must, assigned by the product owner.

Both transport implementations must preserve the same strict schemas,
capability handling, sequencing, acknowledgements, cancellation, streaming,
product limits, retries, and error classifications. A transport-specific
failure or physical carrier-capacity constraint may have a different platform
cause. Physical carrier capacity is supplied at construction to the existing
shared admission owner; it must not create a queue or lifecycle inside the
injected request function. Transport failures still enter the same shared
product failure path.

The packaged Bridge contract is the compatibility baseline. Unifying the
frontend must not reduce packaged limits or otherwise weaken packaged behavior
to accommodate the Vite development carrier; Vite must exercise the packaged
frontend policy even when its browser transport physically queues work
differently to preserve metadata and control progress.

Navigation metadata must preserve the existing subscription sequence
contract. `subscription.accepted` sequence zero must precede any interest
update at sequence one, and adding navigation must preserve the metadata
writer's existing per-frame observation pacing.

### U7 — Keep backend consolidation separate

Priority: Must, assigned by the product owner.

This change retains the current TypeScript Vite development backend and the
current Swift packaged backend. Investigating or implementing a Swift debug
server that reuses `AgentStudioBridge` is a separate follow-up and must not add
backend extraction, a new server target, or AppKit/WebKit lifecycle changes to
this work.

## User-job sequence

```text
developer opens a Vite URL selecting Files/Review or an exact file
  -> Vite constructs the shared frontend with its HTTP transport
  -> the dev backend sends the same typed navigation command as packaged Swift
  -> the shared comm worker and React product apply it
  -> observed behavior is representative of the packaged frontend
```

Current pain: Vite can inject navigation directly into React and can receive
different compiled route behavior, while packaged IPC exact-Review selection
can dispatch a separate page event. A successful journey therefore does not
necessarily exercise one representative frontend control path.

Desired difference: only the constructed transport implementation differs;
the command and every subsequent frontend transition are shared.

## Goal boundary

Existing foundation to reuse:

- the shared `BridgeApp`, Files, and Review product tree;
- the comm-worker product-session protocol and strict contracts;
- the packaged Agent Studio URL-scheme backend;
- the Vite HTTP development carrier and HMR loop; and
- the existing worker health, replacement, cancellation, and rendering paths.

Missing behavior:

- one explicit construction-time transport boundary;
- one shared navigation ingress carrying surface plus optional exact target;
- strict admission of navigation paths through the existing 4,096-byte
  display-path contract;
- preservation of subscription-accepted-before-update metadata ordering;
- removal of direct Vite-to-React navigation and runtime environment branches;
  and
- parity proof that fails if either environment bypasses the shared path.

Non-goals:

- replacing the Vite development backend with Swift;
- creating a Swift debug server or extracting a new backend package;
- changing Files, Review, Filters, Search, or View Settings product meaning;
- replacing the existing controller, `WKWebView`, or product-session lifecycle;
- adding persistence, compatibility paths, fallback renderers, or a second
  navigation protocol; and
- claiming Vite evidence proves packaged native authority or WebKit behavior.

Complexity budget:

- one shared navigation contract;
- one required request-executor dependency with two constructed endpoint
  bindings;
- one existing shared-admission construction value, defaulting to twelve with
  Vite explicitly supplying four; and
- the smallest entry/factory changes needed to inject those implementations;
  and
- hard-cut removal of superseded Vite-specific frontend paths.

A new backend, controller, state store, recovery coordinator, durable setting,
or compatibility layer requires renewed approval.
