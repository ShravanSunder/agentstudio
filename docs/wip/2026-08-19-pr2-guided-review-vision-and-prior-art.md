# PR2 Vision — Guided Review and Guided Diffs

Status: non-normative product vision and prior-art research
Date: 2026-08-19
Audience: future PR2 Requirements and guided-review design work
Authority: this document does not define current product behavior or authorize
implementation.

Companion research:
[`2026-08-19-pr2-pierre-calldiff-coordinate-and-call-graph-research.md`](./2026-08-19-pr2-pierre-calldiff-coordinate-and-call-graph-research.md)

## Vision

A large diff should not force the reviewer to reconstruct the architecture from
alphabetical file order. Guided Review should turn the exact current comparison
into a short, trustworthy review path organized around behavior:

```text
change set
  dozens of files and hunks
        |
        v
guide projection
  chapter 1: behavioral heart
  chapter 2: consequences and integration
  chapter 3: tests and proof
  support: generated, repeated, or mechanical changes
        |
        v
same live Review View
  exact current hunks
  existing Pierre navigation
  existing PR1 annotations
  explicit reviewer progress
```

Guided Review is an ordering and explanation projection over Review View. It is
not a separate viewer, a copied diff, a global comments surface, or a source of
annotation truth.

## User problem

File order is a storage/navigation order, not necessarily a comprehension
order. Large agent-authored changes commonly mix:

- the core behavior change;
- callers and downstream effects;
- adapters and wiring;
- tests and fixtures;
- generated files, lockfiles, snapshots, and mechanical edits.

A reviewer must otherwise discover the change's conceptual structure while
also checking correctness. Guided Review should reduce orientation cost without
concealing the complete changeset or replacing exact source evidence with an
agent story.

## Existing Agent Studio direction

Earlier BridgeViewer design work already separated review modes from facets:

```text
review task mode
  normal review | guided review | plans/specs

local facets
  status | tests | source | docs | folder | language | visibility | search
```

That source proposed an initially deterministic guided order:

1. unreviewed high-priority source/config changes;
2. unreviewed normal-priority source changes;
3. tests related to visible source changes;
4. docs/plans/config context;
5. generated/vendor/large/binary/hidden items last unless requested.

It also established two useful constraints:

- mode changes reuse the existing review package and remain local projections;
- future agent-guided order arrives as descriptor/group metadata or a
  Bridge-owned projection, never as a hidden side channel in the file tree.

The relevant older documents are valuable substrate, not current PR2 authority:

- `docs/superpowers/specs/2026-06-15-bridge-codeview-trees-viewer.md`;
- `docs/superpowers/specs/2026-06-18-bridgeweb-large-diff-fast-loop-spec.md`.

## Validated fit against the current Agent Studio system

This is not only conceptual prior-art alignment. Current source already carries
several load-bearing guided-review foundations.

### What exists now

- [`review-projection-models.ts`](../../BridgeWeb/src/review-viewer/models/review-projection-models.ts)
  defines strict `normalReview | guidedReview | plansAndSpecs` projection modes,
  review item provenance, projection inputs, ordered item results, and
  `{packageId, reviewGeneration, revision}` request identity;
- [`review-projection.ts`](../../BridgeWeb/src/review-viewer/navigation/review-projection.ts)
  builds guided order from current descriptor metadata, preserves the same
  review package, and freezes already-projected row order during streaming;
- [`review-projection.unit.test.ts`](../../BridgeWeb/src/review-viewer/navigation/review-projection.unit.test.ts)
  proves source-before-tests-before-docs/generated ordering and the no-reshuffle
  behavior;
- [`bridge-review-projection-menu.tsx`](../../BridgeWeb/src/review-viewer/chrome/bridge-review-projection-menu.tsx)
  already renders Normal, Guided, and Plans/Specs through the owned shadcn
  ToggleGroup, but only Normal is currently enabled;
- [`bridge-review-package-schema.ts`](../../BridgeWeb/src/foundation/review-package/bridge-review-package-schema.ts)
  carries item-level agent-session, prompt, and operation provenance;
- [`BridgeReviewItemDescriptor.swift`](../../Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeReviewItemDescriptor.swift)
  and the native review publication path remain the source of review item
  identity and provenance;
- [PR0 Program Design](../specs/2026-08-06-worktree-annotations/pr0-program-design.md)
  establishes `{packageId, reviewGeneration, revision}` as the trustworthy
  published-review identity;
- [PR1 Program Design](../specs/2026-08-06-worktree-annotations/pr1-program-design.md)
  establishes SQLite/service ownership for durable annotation threads and
  explicitly excludes a second UI or annotation authority.

Current deterministic guided ordering is therefore implemented substrate, not
a speculative new subsystem. What is not implemented is the complete guided
experience: guide rail, conceptual chapters/stops, complete hunk coverage,
strict agent narrative, enabled mode transition, or PR2 delivery/replies.

### Prior-art fit matrix

| Prior-art idea | Fit | Current Agent Studio anchor | Missing seam | Disposition |
| --- | --- | --- | --- | --- |
| Codiff chapter/stop/support descriptor | high | strict review projection schemas and ordered current item IDs | versioned guide descriptor, conceptual stops, support coverage | G1 after G0 activation |
| Codiff deterministic live hunk references | partial | stable review item identity plus current Pierre hunks | product-owned hunk identity/freshness contract is absent | must be designed before G1 |
| Codiff guide does not embed the diff | direct | Review package/content handles already own current diff content | none conceptually | preserve as invariant |
| Plannotator Guided Review in the same annotatable canvas | direct | existing Review View, Pierre, guided projection discriminant | guide rail and enabled mode UX | G0/G1 |
| Plannotator provider/model picker | poor | Agent Studio already owns its agent/session environment | generic provider selection would duplicate ownership | reject; use explicit current authorized agent |
| Plannotator Call Flow annotations return to source | high but deferred | PR1 located annotations and Pierre selection | CallDiff analysis owner and source-location validation | G3, after agent loop |
| Hunk reload reconciliation | direct | `reviewGeneration`, source generation, stable guided-order hint | guide/progress reconciliation rules | G0/G1 |
| Hunk hunk-level triage | partial | item-level `reviewState`; durable PR1 thread resolution | hunk identity and owner decision for progress persistence | research input only |
| Hunk session-local comment/triage store | poor | SQLite is durable annotation authority | would create a second truth | reject |
| Hunk agent navigation and notes | high | provenance IDs, Review navigation and PR1 located comments | authenticated agent-to-review command surface belongs to PR2 | G2 |
| Pierre line selection and annotation rendering | direct and present | installed `@pierre/diffs`, File/Review adapters | none for ordinary source/diff comments | reuse unchanged |
| PR2 direct feedback delivery | partial foundation | immutable PR1 output batches and agent-session provenance | provenance is not target authority; delivery command/receipt is intentionally absent | G2 owns the gap |

### Fit conclusions

Direct fits:

- Guided Review remains a projection over the current Review package;
- normal, guided, and plans/specs are already modeled as task modes;
- current item identity and generation fences can reject stale guides;
- PR1 comments can remain visible across every projection mode;
- native review authority and BridgeWeb projection ownership already match the
  desired split.

Required additions:

- a stable current-comparison hunk identity or an equally strict section
  reference that can validate Codiff-style guide coverage;
- one guide descriptor with chapter/stop/support structure;
- guide lifecycle and freshness state separate from review-package authority;
- an enabled Guided Review control and guide rail composed from existing UI
  primitives;
- G2's explicit agent target, delivery receipt, inbound reply, and verification
  contract.

Rejected transfers:

- copied patches or a guide-owned file tree;
- session-memory annotations or progress as durable truth;
- generic external annotations APIs or provider pickers;
- guide sharing/upload;
- CallDiff before the direct agent loop or as a prerequisite for basic Guided
  Review.

## Prior art

### Codiff narrative walkthroughs

Codiff 1,276-star snapshot inspected on 2026-08-19. Its walkthrough model is
the closest match to the desired product shape.

Its versioned JSON guide contains:

- one short title and review focus;
- one to six conceptual chapters;
- ordered review stops grouped by idea rather than file;
- deterministic hunk IDs from the live diff;
- concise stop narrative and importance;
- optional per-hunk notes;
- a support collection for generated, lockfile, snapshot, docs-only, or
  mechanical changes;
- optional commit metadata for working-tree review.

Important design choices:

- the guide does not embed the diff;
- Codiff resolves guide hunk IDs against the live repository diff;
- every hunk appears at most once in a stop or support;
- omitted live hunks are added to support rather than disappearing;
- cross-file hunks may share one stop when they implement one idea;
- stops are ordered by review leverage rather than path;
- generated-like sections remain whole;
- the agent narrative is constrained by a strict schema and current hunk IDs;
- session context can supply objective, decisions, risks, validation, changed
  file roles, and recent messages without making that context the diff truth.

Transferable lesson: an agent may author the narrative, but deterministic
current hunk identities control what the product displays.

Excluded Codiff behavior: walkthrough sharing/upload and commit composition are
not part of this Agent Studio vision.

### Plannotator Guided Review and Call Flow

Plannotator describes Guided Review as an agent-organized, chaptered walkthrough
with the heart of the change first, consequences next, and glue last. Each
section pairs prose with the live annotatable diffs it covers and tracks review
progress.

Its Call Flow layer adds inferred entry trees to changed files and can create a
normal source annotation from a changed call. This supports the same key
separation proposed here:

```text
semantic view helps navigation and explanation
        |
        v
comment returns to ordinary file/line annotation
```

Transferable lesson: guide prose, call-flow context, and annotations should
meet on the same live diff rather than live in separate tools.

Excluded Plannotator behavior: portable guides, share links, hosted reviews,
provider marketplace behavior, and generic external annotations HTTP APIs.

### Hunk review-first interaction

Hunk had 8,603 stars when inspected on 2026-08-19. It reinforces several
interaction principles:

- full changeset review with a navigation sidebar;
- responsive split/stack presentation;
- watch/reload while an agent changes the worktree;
- inline human and agent notes;
- live session navigation controlled by an agent;
- changeset transforms that can collapse or reorder files;
- session-local hunk triage with viewed, approved, investigate, and blocked
  states;
- reconciliation that drops decisions whose hunks no longer match after
  reload rather than transferring them silently.

Transferable lesson: guided review must remain responsive to a changing local
worktree, and progress/decisions need exact identity reconciliation.

Excluded Hunk behavior: terminal UI architecture, generic extensions, public
loopback session APIs, pager integration, and session-local-only authority.

### Null search result

GitHub repository searches for the exact phrases `guided code review
walkthrough`, `narrative diff walkthrough`, `code tour pull request review`,
and `AI code walkthrough diff` returned no additional directly relevant
repositories in this bounded pass. Codiff, Plannotator, Hunk, and Agent Studio's
existing BridgeViewer design therefore remain the primary inspected sources.

## Candidate guided-review model

### Guide identity and authority

One guide is derived from exactly one current review comparison:

```text
GuideDescriptor
  guideId
  reviewPackageId
  comparison/source generation
  author: deterministic | agent(session/turn/model provenance)
  status: ready | stale | unavailable
  focus
  ordered chapters
  support groups
```

The guide is derived navigation state. The existing review package, item
descriptors, content handles, and source generation remain authoritative.

### Chapter and stop shape

```text
chapter
  short conceptual title
  one-sentence purpose
  ordered stops

stop
  stable guide-local identity
  concise behavior-oriented title
  why this stop matters
  importance: critical | normal | context
  ordered references to current item/hunk identities
  optional CallDiff entry/tree evidence
  visited state derived for the current guide

support group
  reason
  item/hunk identities excluded from the main path
```

The guide should not carry source bodies, patches, annotation messages, or a
parallel file tree.

### Coverage rule

Every visible review hunk must have one disposition:

```text
main guided stop
support group
explicitly unavailable/non-textual item
```

Omitted hunks must fall into Support automatically. A guide may reduce
attention but may not make changed material silently disappear.

### Freshness rule

```text
review generation 10 guide ready
        |
        +-- worktree/source changes to generation 11
        v
generation 10 guide stale
  remains inspectable only as stale context
  cannot navigate or annotate as if current
        |
        v
deterministic or agent guide generation 11
```

Current source identity fences navigation, progress, semantic analysis, and
agent results. A late guide cannot reorder or clear the current review.

## Product experience

### Mode entry

Guided Review should be one quiet Review-mode choice beside Normal Review and
Plans/Specs, composed from the existing shadcn/Pierre chrome. It must not add a
full-width banner or another viewer.

### Guide rail

```text
Review focus
  Preserve durable comment Save across stale projections

Runtime
  1  Separate command completion             ✓
  2  Replace stale projection work            current

UI
  3  Retain the last complete thread          ○

Proof
  4  Exercise blocked and failed reads         ○

Support
  generated fixtures · lockfile · snapshots   ○
```

Selecting a stop projects only its exact hunks into the existing Review canvas
and keeps the normal file tree/path navigation available. The guide rail shows
orientation and progress; it does not become a comments panel.

### Stop presentation

```text
Stop 2 of 4 — Replace stale projection work

Why this matters
  A newer invalidation must cancel-and-replace the old query without
  blanking the last complete annotation state.

Exact evidence
  query-controller hunk
  projection-store hunk
  corresponding focused tests

Optional semantic context
  annotation invalidation → query → atomic install
  syntactically inferred call-flow changes, visibly labeled
```

The diff remains fully annotatable through PR1. Comments created in Guided
Review appear in Normal Review because both modes consume the same durable
threads.

## Candidate capability slices

These are research slices, not an implementation plan.

### G0 — Finish and activate deterministic local guidance

- retain the implemented descriptor-only guided ordering and streaming-order
  freeze;
- enable Guided mode only after the mode switch, current projection, selection,
  and annotation continuity are proven together;
- add the smallest guide rail/progress experience over current ordered items;
- order high-priority behavior, normal source, related tests, docs/context, and
  generated/support items without a model;
- expose guide coverage and visited state;
- no model, new backend analysis, or durable guide history required;
- prove that switching modes does not reload the review package or move
  annotations.

Purpose: validate the interaction and review-order value before paying for an
agent-authored narrative system.

### G1 — Strict agent-authored narrative

- provide the agent exact current item/hunk identities plus bounded session
  objective, decisions, risks, and validation context;
- accept only one strict versioned guide schema;
- reject unknown, duplicate, stale, missing, or cross-generation hunk IDs;
- place omitted hunks in Support;
- retain last complete guide while a replacement is generated;
- never let narrative prose override diff/source truth.

### G2 — PR2 agent loop

- send selected saved annotations from any guide stop to the explicit current
  authorized Agent Studio agent/session;
- treat existing `agentSessionIds` provenance as source evidence, not delivery
  authority;
- receive attributable replies in the same durable threads;
- regenerate or refresh the guide after the agent changes the worktree;
- keep human verification and Resolve/Reopen explicit.

### G3 — Optional CallDiff call-flow enrichment

- begin only after the G2 delivery/reply/verification loop works without
  semantic analysis;
- attach optional CallDiff entry/tree fragments and call-site locations to
  stops;
- visually label results as syntactic inference;
- navigate call nodes to existing source/diff locations;
- create comments through the normal PR1 located-thread path;
- degrade unsupported languages or entries independently;
- never make CallDiff availability a prerequisite for Send, agent reply, or
  human verification.

## Architectural direction

```text
SQLite
  annotation sessions, threads, messages, delivery evidence
  not guide ordering or copied diff bodies by default

native Review authority
  exact worktree comparison and review item identities

finite guide preparation
  deterministic projection or agent-authored strict descriptor

BridgeWeb
  guide mode, rail, local visited presentation, projection switching

Pierre
  current exact diff rendering, selection, navigation, annotations

optional CallDiff
  finite derived semantic context, never annotation truth
```

Whether guides themselves require durable history is an open product decision.
The smallest first slice treats them as rebuildable projections bound to a
review generation. PR1 annotations remain durable regardless of guide lifetime.

## Boundaries

In scope for future discussion:

- behavior-oriented ordering of exact current changes;
- complete coverage through main stops plus Support;
- deterministic and later agent-authored guide variants;
- explicit progress and stale-guide behavior;
- ordinary PR1 comments inside a guided stop;
- optional CallDiff-derived explanations and navigation;
- local current-worktree agent context.

Out of scope for this vision:

- guide sharing, upload, public URLs, or teammate collaboration;
- portable hosted walkthrough files;
- GitHub/GitLab posting;
- a new global comments panel;
- guide-authored source mutation or commit creation;
- automatic approval or thread resolution;
- a hidden model call on every Review open;
- source bodies or complete patches duplicated into guide state;
- CallDiff inference presented as runtime truth;
- a generic extension marketplace or external annotation API.

## Open decisions

1. Does Guided Review begin with deterministic local order before agent
   narration, or is narrative value required for the first useful slice?
2. Is visited/progress state ephemeral per guide, durable per review session,
   or derived from existing File/Review exposure facts?
3. What exact identity names a hunk across review refresh, and when must progress
   be discarded rather than relocated?
4. Does a regenerated guide replace the old guide, or may the reviewer inspect
   a stale prior guide explicitly?
5. Which context may the guide author receive: diff only, plan/spec objectives,
   current agent conversation, validation receipts, or all under explicit
   bounded fields?
6. Can one stop span several files and hunks? Prior art strongly supports yes;
   the exact navigation and narrow-screen interaction still need design.
7. Does CallDiff analysis run through the current agent, a native-owned bounded
   tool process, or a packaged subordinate worker?
8. How are partial/unsupported CallDiff languages shown without making the
   guide unavailable?
9. May agent review findings create durable threads automatically, or must the
   human admit/save them first?
10. Which guide facts, if any, enter PR2 agent delivery and exact output history?

## Falsifiers

Split or reject the design if:

- Guided Review needs a copied diff or second review-item authority;
- guide mode requires a new viewer instead of projecting Review View;
- an agent narrative can hide current hunks without a visible Support
  disposition;
- stale guide IDs can navigate or annotate a newer comparison silently;
- CallDiff requires production TypeScript to shell out to Git;
- guide progress becomes another thread-resolution or delivery status;
- the first useful version requires link sharing, hosted collaboration, or
  multi-user state.

## Sources

- Codiff repository, README, walkthrough authoring guide, schema, view model,
  navigation, and context normalization:
  <https://github.com/nkzw-tech/codiff>
- Plannotator Code Review, Guided Review, Call Flow, and AI review docs:
  <https://github.com/backnotprop/plannotator>
- Hunk repository, agent workflow, extensions, and review-triage example:
  <https://github.com/modem-dev/hunk>
- Agent Studio prior BridgeViewer guided-review substrate:
  `docs/superpowers/specs/2026-06-15-bridge-codeview-trees-viewer.md` and
  `docs/superpowers/specs/2026-06-18-bridgeweb-large-diff-fast-loop-spec.md`.
