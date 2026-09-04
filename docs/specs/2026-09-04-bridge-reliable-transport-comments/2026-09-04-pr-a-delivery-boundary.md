# PR A Delivery Boundary — Reliable Bridge Transport and Comments

Date: 2026-09-04

Status: non-normative composition index for PR #316. This file adds no product
requirements, observable contracts, or internal architecture. The linked
Requirements, Specification, and Program Design artifacts remain the authority.

## Purpose

PR A delivers one reliable Bridge foundation and its application-specific File,
Review, and worktree-annotation/comment consumers. Its terminal is PR-ready and
unmerged. Post-DOM latency measurement and optimization are a dependent PR B,
not part of PR A.

This index exists because PR A composes two separately reviewed design sets. It
does not merge them into a new specification or reinterpret either set.

## Governing authority

### Worktree annotations and comments

- [Requirements](../2026-08-06-worktree-annotations/pr1-user-requirements.md)
- [Specification](../2026-08-06-worktree-annotations/pr1-specification.md)
- [Program Design](../2026-08-06-worktree-annotations/pr1-program-design.md)

These artifacts govern durable human-authored annotations/comments, File and
Review presentation semantics, typed command results, compact invalidation,
finite demanded projection content, restart recovery, and end-to-end comment
journeys.

### Proportional Review refresh and downstream delivery

- [Requirements](../2026-09-03-incremental-review-git-refresh/2026-09-03-requirements.md)
- [Specification](../2026-09-03-incremental-review-git-refresh/2026-09-03-specification.md)
- [Program Design](../2026-09-03-incremental-review-git-refresh/2026-09-03-program-design.md)

These artifacts govern exact proportional Git calculation, complete Review
truth, conservative fallback, same-lineage Review delta delivery, demanded
content reuse, exact-publication annotation convergence, and selective
equality-checked application.

Within each set, Requirements state authorized needs, the Specification states
observable obligations, and Program Design states their structural realization.
The incremental Review design supersedes only the PR0 structural rules that it
explicitly names. This index has no authority to resolve a conflict by changing
meaning; the owning artifact must be corrected instead.

## PR A composition boundary

PR A composes the existing owners into this delivery:

```text
generic Bridge transport
  validates stream, subscription, sequence, generation, frame, reset, and end
  remains unaware of File, Review, annotation, session, path, or message meaning
                │
                ├─ File application contract
                ├─ Review application contract
                └─ worktree annotation/comment application contract
```

The PR A delivery boundary includes:

- reliable generic Bridge metadata/content transport and application-specific
  File, Review, and annotation/comment consumers;
- source-authority retirement, backend restart, reconnect, reset, worker/source
  replacement, and fresh-authority rebinding without stale retained state
  preventing recovery;
- foreground-pane liveness whenever the pane's active tab uses Bridge,
  independent of application or window foreground state;
- exact-current metadata, selection, demanded content, Review publication, and
  annotation convergence, including stale-result rejection and last-complete
  retention during replacement;
- terminal recovery from failed, partial, stale, or superseded work without a
  permanent Loading state or repeated work after the requested result settles;
- real Vite-plus-Swift development journeys and packaged WKWebView journeys for
  File, Review, transport recovery, and the required annotation/comment loop.

The generic transport owns delivery mechanics and authority fences. File,
Review, and annotations own their schemas, semantic identity, query meaning,
and application behavior. Application-specific affected-item or Review
publication facts do not become generic transport knowledge.

## PR A / PR B classification

The dependent PR B authority is:

- [Requirements](../2026-09-04-bridge-post-dom-load-performance/2026-09-04-requirements.md)
- [Specification](../2026-09-04-bridge-post-dom-load-performance/2026-09-04-specification.md)
- [Program Design](../2026-09-04-bridge-post-dom-load-performance/2026-09-04-program-design.md)

Those artifacts do not replace or broaden PR A. They classify the boundary as
follows:

| Observed result | Owner |
| --- | --- |
| The exact requested File/Review result never becomes current and usable, or transport/recovery/comments remain stuck or repeat settled work | PR A reliability/correctness |
| The exact current usable result succeeds, but its post-DOM distribution exceeds p95 600 ms or p99 1,000 ms | PR B performance |
| The product reaches an exact current usable result, but required timing evidence is missing or cannot be joined | PR B measurement/proof |

PR A proves that the system progresses correctly and reliably. PR B measures
and improves how long the successful path takes after `DOMContentLoaded` and
on File/Review switches. PR A carries no p95/p99 completion gate.

## Negative space

PR A does not include:

- PR B post-DOM stage instrumentation, percentile cohorts, accepted-baseline
  receipts, latency attribution, or performance optimization;
- a new cache, watcher, queue, worker, scheduler, service, persistence layer,
  transport route, data-delivery protocol, or generic graph/tree store;
- vendored libgit2 changes or Git semantics outside `agentstudio-git`;
- production copying or retention of source-file contents as Review refresh
  acceleration;
- a File, Review, annotation, or shared-chrome UI redesign beyond the behavior
  already required by the governing annotation artifacts;
- weakening, deleting, or bypassing required tests, currentness fences,
  conservative fallback, bounded retention, or real-runtime proof;
- unrelated concurrent UI-lane work.

PR A may use existing bounded owners exactly as their governing designs allow;
this index does not authorize a new system or extend an existing owner's
correctness authority.

## Plan authority

The prior
[`2026-09-03-proportional-review-refresh-v3.md`](../../../tmp/plan-workflows/2026-09-03-proportional-review-refresh-v3.md)
mixes PR A completion with performance work and is stale as the current PR A
delivery boundary. This index does not itself supersede that plan.

Once present and ready,
[`2026-09-04-pr-a-reliable-bridge-transport-comments.md`](../../../tmp/plan-workflows/2026-09-04-pr-a-reliable-bridge-transport-comments.md)
alone supersedes v3 for PR A execution. PR B keeps separate design authority;
no PR B implementation plan is established by this index.
