# Bridge Post-DOM Load Performance — Requirements

Date: 2026-09-04

Decision authority: Agent Studio owner.

Reliability and semantic foundation:

- [Worktree Annotations PR1 requirements](../2026-08-06-worktree-annotations/pr1-user-requirements.md)
- [Incremental Review Git Refresh requirements](../2026-09-03-incremental-review-git-refresh/2026-09-03-requirements.md)

Observable contract:
[2026-09-04-specification.md](./2026-09-04-specification.md)

Structural realization:
[2026-09-04-program-design.md](./2026-09-04-program-design.md)

## Why this work exists

Opening File View or Review View must become useful quickly after the browser
has loaded the document. Today, the time between `DOMContentLoaded` and a
usable painted File or Review frame is not measured as one honest, decomposed
journey. Existing observations can say that the page loaded, the handshake
completed, metadata arrived, or selected content painted, but they do not yet
give one comparable distribution that explains where the post-DOM time went.

Without that breakdown, a slow load can be mistaken for a transport failure,
a transport jam can be hidden inside a timeout, and an apparent optimization
can merely move work before the chosen clock. The user experiences all of
those cases as a viewer that takes too long or never becomes useful.

This work follows the reliable transport and comments delivery described by
the current annotation and incremental Review contracts. It does not replace
that work.

## Who is affected

- Reviewers opening File View or Review View to read source, inspect a diff,
  and use annotations.
- Developers and agents switching between File View and Review View while the
  same pane remains open.
- Agent Studio maintainers who need enough timing detail to improve the real
  bottleneck without weakening transport correctness or inventing another
  runtime system.

## The two dependent delivery boundaries

```text
PR A — reliable transport and comments
  proves Vite/native source readiness
  proves bootstrap and transport can recover
  proves metadata, demanded content, and annotations converge
  proves foreground File/Review remains live
  proves failures do not remain stuck as Loading
                    │
                    │ reliable foundation
                    ▼
PR B — post-DOM File/Review performance
  measures every owned stage after DOMContentLoaded
  finds the measured bottleneck
  improves existing owners
  proves p95 and p99 usable-paint targets
  retains an end-to-end Swift-open guardrail
```

PR A owns correctness, reliability, and comments. PR B depends on that
foundation and owns latency reduction. A server-down, transport-jammed,
stale-authority, or never-painted attempt remains a PR A reliability failure
that PR B records as failed evidence; PR A still owns diagnosing and correcting
it. It is never converted into a slow-but-successful sample, omitted from the
evidence, or accepted as PR B optimization work.

## The ownership test

```text
Did the exact requested File/Review result become current and usable?
  │
  ├─ no
  │    server/source unavailable, transport jam/reset without recovery,
  │    stale or partial installation, repeated settled work, wrong content,
  │    annotation/comment delivery failure, or no usable terminal
  │
  │    → PR A reliability/correctness failure
  │    → PR B records the failed attempt but does not tune around it
  │
  └─ yes
       exact current metadata, selection, demanded content, visible paint,
       and usable controls all reached one successful terminal
       │
       ├─ within latency target → passes PR B
       └─ above latency target  → PR B performance miss and optimization work
```

The dividing question is correctness and terminal progress, not elapsed time.
A thirty-second timeout does not turn a jam into a performance problem. A load
may be reliable and still too slow; that is the case PR B owns improving.
Missing or unjoinable timing evidence alone is a PR B proof failure; it does
not become a PR A correctness failure unless product evidence also shows that
the exact current usable result failed.

## Goal boundary

The primary goal is to make an already-served File or Review page become
usable within a predictable post-DOM latency budget.

The primary clock begins at the browser's `DOMContentLoaded` boundary, after
the proof harness has established that the composition's asset host and Swift
source are ready. In development this means Vite and the Swift source server;
in the packaged app it means the embedded asset load and native operation
route. It ends only when the requested File or Review surface has real
metadata, a selected item, demanded content, a visible painted frame, and
usable controls.

```text
Not part of the primary clock
  Vite startup
  Swift source-server startup
  document download and parsing
                    │
                    ▼
DOMContentLoaded   T0
  bootstrap request and acceptance
  comm-worker readiness
  File/Review command admission
  source establishment
  metadata installation
  initial selection
  content request open and completion
  render commit
  first usable painted frame   T1

Primary duration = T1 - T0
```

The primary File and Review distributions must meet:

- p95 at or below 600 milliseconds;
- p99 at or below 1,000 milliseconds.

For a real command-bearing packaged/native path, a separate end-to-end
distribution begins at the Swift user command that opens or activates File or
Review and ends at the same usable painted frame. It is a no-regression
guardrail. A development-browser path with no Swift command reports this
guardrail as not applicable and never invents a substitute start. The post-DOM
target must not be met by moving work before `DOMContentLoaded` or making
native/WebView startup slower.

## Authorized needs

### U-PDL-001 — Reach usable File and Review quickly

- Affected class: reviewer, developer, and agent.
- Need: After `DOMContentLoaded`, an already-ready system must show a usable
  File or Review frame within p95 600 ms and p99 1,000 ms.
- Why: Waiting longer interrupts reading and makes a healthy system feel
  broken.
- Priority: must.
- Authority state: authorized by the Agent Studio owner.

### U-PDL-002 — Explain where load time is spent

- Affected class: maintainer.
- Need: Every post-DOM load must expose the elapsed time and outcome of each
  meaningful stage from bootstrap through usable paint.
- Why: An aggregate number cannot distinguish a slow source, serialized
  transport, unnecessary preparation, or slow paint.
- Priority: must.
- Authority state: authorized by the Agent Studio owner.

### U-PDL-003 — Keep reliability failures honest

- Affected class: reviewer and maintainer.
- Need: A load that jams, loses authority, reaches a dead server, loops, times
  out, or never paints must remain visible as a failed attempt and must not be
  removed from the measured cohort.
- Why: Fast percentiles built by dropping failed attempts do not describe a
  reliable product.
- Priority: must.
- Authority state: authorized by the Agent Studio owner and the PR A
  reliability boundary.

### U-PDL-004 — Preserve the whole user-perceived journey

- Affected class: reviewer and maintainer.
- Need: The Swift command-to-usable-paint distribution must remain visible and
  must not regress while the focused post-DOM path improves.
- Why: `DOMContentLoaded` is the correct diagnostic boundary, but it is not
  permission to hide work earlier in the user journey.
- Priority: must.
- Authority state: authorized by the Agent Studio owner.

### U-PDL-005 — Measure realistic File and Review work

- Affected class: reviewer and maintainer.
- Need: Performance evidence must use real Swift-backed transport and
  worktree data with realistic file lengths, diff counts, hunks, binary and
  structural cases, rather than one-line browser fixtures.
- Why: Tiny fixtures do not create the parsing, transfer, demand, and render
  pressure that the target is intended to bound.
- Priority: must.
- Authority state: authorized by the Agent Studio owner.

### U-PDL-006 — Improve the existing system

- Affected class: maintainer.
- Need: Optimization must simplify, overlap, or remove measured work inside
  existing owners before introducing another system.
- Why: A new cache, worker, queue, service, or scheduler adds lifecycle and
  failure modes before evidence shows it is necessary.
- Priority: must.
- Authority state: authorized by the Agent Studio owner.

### U-PDL-007 — Preserve transport, Review, and annotation truth

- Affected class: reviewer, developer, agent, and maintainer.
- Need: Latency improvements must preserve generic transport authority,
  complete File/Review metadata, demanded content, current selection,
  annotation/comment continuity, and exact usable-paint evidence.
- Why: Faster partial, stale, or non-interactive output is not success.
- Priority: must.
- Authority state: authorized by the Agent Studio owner and the governing PR A
  contracts.

### U-PDL-008 — Keep mode changes responsive

- Affected class: reviewer, developer, and agent.
- Need: In an already-open pane, Review-to-File and File-to-Review activation
  must reach a usable painted destination at p95 600 ms and p99 1,000 ms.
- Why: Switching context is part of the same review loop and should not repeat
  cold work unnecessarily.
- Priority: must.
- Authority state: authorized by the Agent Studio owner.

## Limits and non-goals

- PR B does not own Vite startup, Swift source-server startup, backend-exit
  recovery, foreground liveness, comments, annotation semantics, or transport
  correctness. Those remain PR A obligations and preconditions.
- PR B may add passive timing observations and may optimize measured work
  inside existing owners only while their PR A data, authority, recovery, and
  delivery behavior remains unchanged. A change to those correctness contracts
  belongs to PR A, even when discovered during performance measurement.
- Asset-host and Swift startup are excluded only from the primary post-DOM
  latency number. Real command-bearing packaged/native paths retain them in the
  separate end-to-end guardrail; development-browser paths without a Swift
  command report that guardrail as not applicable.
- PR B does not change the meaning of File metadata, Review metadata, demanded
  content, selection, render completion, or usable paint.
- PR B does not add a cache, watcher, queue, worker, scheduler, service,
  persistence layer, transport route, or new data-delivery protocol.
- PR B does not redesign File View, Review View, annotations, comments, or
  shared viewer chrome.
- PR B does not weaken authority fences, frame limits, bounded retention,
  demand-driven content, reset/recovery behavior, or exact paint correlation.
- PR B does not treat a warm synthetic JavaScript fixture as proof of the
  Swift-backed production path.
- If measured evidence shows that an existing boundary cannot meet the target
  without one of the prohibited systems, that is a design break requiring a
  new owner decision. It is not implicit permission to expand this design.

## Success evidence

- File first load after `DOMContentLoaded` meets p95 600 ms and p99 1,000 ms.
- Review first load after `DOMContentLoaded` meets p95 600 ms and p99 1,000 ms.
- Review-to-File and File-to-Review switches meet the same thresholds from
  activation command to usable destination paint.
- Each distribution includes at least 100 attempts per workload/runtime
  cohort, names p50/p95/p99, sample count, failure count, runtime composition,
  workload identity, and measurement window, and retains every failed attempt.
- Stage evidence accounts for bootstrap request/acceptance, worker readiness,
  command admission, source establishment, metadata installation, initial
  selection, content open/completion, render commit, and usable paint.
- The real development-server and packaged Swift/WKWebView compositions both
  exercise the actual source, generic transport, application consumers,
  demanded content, and rendered surface.
- For every real command-bearing packaged/native path, the
  Swift-command-to-usable-paint distribution is reported beside the post-DOM
  distribution and does not regress against the accepted same-workload
  baseline. Development-browser evidence explicitly reports not applicable
  when no Swift command exists.
- Existing PR A reliability and comment/annotation journeys remain green; no
  optimization introduces a stuck load, repeated settled work, stale
  installation, or hidden failure.
- Every failed reliability/correctness attempt is attributed to PR A for
  correction and retained by PR B as failed evidence; only correct successful
  terminals participate in PR B latency optimization and percentiles.
