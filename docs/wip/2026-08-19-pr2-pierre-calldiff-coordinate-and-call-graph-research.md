# PR2 Research — Pierre Coordinates and CallDiff Call Trees

Status: non-normative research and vision input
Date: 2026-08-19
Audience: future PR2 Requirements, Program Design, and guided-review work
Authority: this document does not authorize dependencies, protocols,
implementation, or product behavior.

## Research question

Can Agent Studio combine Pierre's text/diff coordinate surface with CallDiff's
syntactic call-tree comparison to support a more useful guided review without
creating a second annotation authority or pretending syntactic analysis is
runtime truth?

## Executive finding

Yes. The two systems answer different reviewer questions and can compose:

```text
Pierre asks
  "What text changed, and where can the reviewer inspect or annotate it?"

CallDiff asks
  "Which syntactically inferred call trees changed, and which source call
   sites participate in those changed paths?"

Agent Studio guided review can ask
  "Which behavior should I understand first, which concrete hunks implement
   it, and how do those hunks alter the inferred call path?"
```

Pierre remains the source/diff presentation and located-annotation surface.
CallDiff is optional derived analysis that can group, order, and explain review
stops. A CallDiff node never becomes durable annotation truth by itself; its
source locations resolve back to the existing path/side/line-range model.

## Correction to the initial mental model

### Pierre is broader than a diff algorithm and narrower than a semantic engine

The installed `@pierre/diffs` 1.2.10 package is primarily a diff/file rendering
library. It:

- accepts old/new file contents, parsed file objects, unified patches, and Git
  patches;
- uses the `diff`/jsdiff package when it must generate a patch from old and new
  file contents;
- parses patch headers and hunks into old/new side line coordinates;
- tokenizes code with Shiki and performs character/word comparison for
  intra-line highlighting;
- virtualizes large files and diffs;
- exposes controlled selected-line ranges, gutter utilities, line-selection
  callbacks, and typed line annotations;
- renders annotations against file or diff line coordinates.

The installed jsdiff 8.0.3 dependency explicitly implements a variation of
Myers's O(ND) algorithm. It provides line, word, and character tokenizations.
Therefore "Myers text diff" is accurate for Pierre's old/new diff-generation
path, but it is not the complete ownership statement:

```text
Git/native source may already provide a unified patch
        |
        +-- Pierre parses and renders that patch; it did not calculate it
        |
old/new file contents may be supplied instead
        |
        `-- Pierre calls jsdiff to generate a patch using Myers-derived logic
```

Pierre does not understand functions, call graphs, types, runtime dispatch, or
behavioral intent. Shiki tokens are lexical presentation tokens, not semantic
program entities.

### CallDiff does not discard all text coordinates

CallDiff reads each selected Git snapshot or working tree, chooses a
Tree-sitter grammar from the file extension, and uses language-specific
extractors to build function records and ordered call/branch steps. It then:

1. indexes function definitions;
2. constructs nested call trees from selected or inferred entrypoints;
3. builds reverse call edges to find changed functions and affected callers;
4. compares before/after call trees;
5. aligns sibling call nodes with an LCS dynamic-programming pass;
6. emits human-readable trees or structured JSON/YAML/Markdown/JSONL.

CallDiff deliberately abstracts away unchanged source text and visual layout,
but it retains source locations:

- roots carry their definition `file:line`;
- children carry the call site in their parent;
- branches may carry the branch-keyword/condition span;
- `--locs` exposes those coordinates for navigation and downstream consumers.

It is therefore better described as a syntactic call-tree projection over
source snapshots, not a coordinate-free mathematical graph.

### CallDiff is useful approximation, not execution truth

CallDiff's own documentation states that it is syntactic and not a full
typechecker. Its function index and local-first resolution improve practical
results, but dynamic dispatch, reflection, runtime dependency injection,
ambiguous imports, generated calls, macros, protocol witnesses, and
language-specific type resolution may be incomplete or unresolved.

It can support claims such as:

```text
"The syntactically inferred call tree rooted at boot changed this way."
```

It cannot by itself prove:

```text
"Every runtime execution starting at boot will take this exact route."
```

Guided Review must preserve that distinction in labels, tooltips, export, and
agent prompts.

## Two complementary coordinate systems

| Dimension | Pierre text/diff coordinates | CallDiff semantic projection |
| --- | --- | --- |
| Primary identity | review item/file, side, source line/range | entry symbol, call-node key, tree path |
| Input | unified patch or old/new text | before/after source snapshots |
| Core transformation | patch parse or Myers-derived text diff; Shiki tokenization | Tree-sitter extraction, function index, call-tree expansion, LCS child alignment |
| Output | renderable old/new lines, token spans, hunks, selections | added/removed/same call-tree nodes and reachability paths |
| Reviewer question | what exact text changed here? | what inferred call route changed? |
| Annotation anchor | path + side/role + line/range + source evidence | never direct; resolve node location to a Pierre/source anchor |
| Important failure | stale/invalid patch or source generation | unsupported language, missing grammar, ambiguous/unresolved call |
| Truth level | exact for the supplied text/patch | derived syntactic approximation |

Neither system eliminates the other. A guided review needs both the conceptual
relationship and the exact code that justifies it.

## Candidate Agent Studio composition

```text
PR0 Review comparison authority
  exact worktree/base/head snapshot identities
        |
        +-----------------------------------------------+
        |                                               |
        v                                               v
Pierre/source preparation                        optional CallDiff analysis
  files, hunks, sides, lines                        entrypoints, changed trees,
  and render identities                              call-site locations
        |                                               |
        +--------------------+--------------------------+
                             |
                             v
                     Guided Review projection
                       chapter / stop order
                       exact review item + hunk ids
                       optional call-flow explanation
                             |
                             v
                     existing Review View + Pierre
                       comments use PR1 annotations
```

The guided projection references existing review identities. It does not copy
patches, messages, or source bodies into another store.

## A review stop can join meaning to evidence

One candidate derived stop could contain:

```text
stop identity and narrative
  "Move session construction behind getServices"

exact text evidence
  review item ids
  ordered hunk ids
  source generation / comparison identity

optional semantic evidence
  CallDiff entrypoint
  before/after call-tree fragment
  source locations for changed call nodes

review state
  current / visited
  PR1 threads and comments remain independently durable
```

Selecting a call-tree node navigates to its file/line call site. Creating a
comment there uses the normal PR1 located-thread command. The comment does not
store the CallDiff tree path as its sole anchor.

## Production ownership options

No option is selected here.

### Option A — Agent-authored guide using CallDiff as an agent tool

The existing Agent Studio agent runs CallDiff and returns a strict guide result
referencing known review/hunk/source locations.

Gain:

- smallest product dependency;
- reuses the existing agent runtime and conversation context;
- CallDiff already offers structured output, a skill, and MCP registration.

Cost:

- availability depends on the agent/tool environment;
- product must validate every returned identity against the current review;
- results arrive later and may be stale if the comparison changes.

### Option B — Native-owned bounded CallDiff subprocess

An AgentStudioBridge owner invokes a pinned CallDiff tool against exact prepared
snapshots and exposes one finite structured result.

Gain:

- product-controlled snapshot and generation fencing;
- deterministic structured result independent of prompt quality;
- one explicit analysis lifecycle and failure surface.

Cost:

- packaging Node/native grammar dependencies and on-demand grammars;
- subprocess custody, cancellation, versioning, security, and performance work;
- production TypeScript still must not shell out to Git.

### Option C — In-process/worker syntactic analysis

BridgeWeb or a subordinate worker runs Tree-sitter analysis over prepared
source snapshots.

Gain:

- direct interaction and no external CLI dependency.

Cost:

- largest asset, grammar, memory, worker, and packaging burden;
- risks making the web renderer own source analysis and Git snapshot policy;
- duplicates a mature tool unless measurements justify it.

Initial research preference: Option A for experimental guided-review learning,
then Option B only if product demand requires deterministic built-in analysis.
Option C needs strong performance and packaging evidence before consideration.

Sequencing constraint: even the experimental Option A follows the core PR2
agent loop. Direct delivery, attributable agent replies, worktree change, and
human verification must work without CallDiff before semantic call-flow
enrichment is admitted. CallDiff is G3 optional enrichment, not a dependency of
G2 delivery or ordinary Guided Review.

## Lifecycle and consistency requirements suggested by the research

Any future design should treat CallDiff output like other finite derived reads:

```text
ready(last complete analysis)
        |
        +-- source/comparison generation changes
        v
refreshing(last complete analysis)
        |
        +-- complete current result ----------> ready(new result)
        `-- failure/stale result -------------> unavailable/stale
                                                 last complete retained
```

- the analysis input must name exact before/after snapshot identities;
- newer comparison intent cancels or stales older analysis;
- a late analysis result cannot reorder the current review;
- unsupported languages degrade only their affected entries;
- missing CallDiff analysis never makes ordinary Review View unavailable;
- current Pierre/text evidence remains usable while semantic analysis runs;
- analysis errors never fabricate unchanged call flow;
- grammar download or installation requires an explicit product decision and
  cannot happen silently inside a restricted worker.

## Annotation and agent-handoff implications

- PR1 comments remain source-line/range threads even when created from a guided
  call-flow view;
- G2 PR2 agent delivery first sends the immutable human-message/source batch
  without requiring CallDiff;
- only later G3 enrichment may include an optional derived call-flow excerpt,
  while the human-authored body and source evidence remain authoritative;
- an agent reply may cite a CallDiff node or entrypoint, but its durable message
  identity and thread membership use the normal annotation model;
- output history must record the exact semantic evidence included if later
  reproduction is promised;
- CallDiff inference must be visibly labeled so an agent does not treat it as
  verified runtime behavior.

## What this research supports

Supported:

- Pierre and CallDiff provide complementary text and structural views;
- CallDiff structured output can inform review grouping, ordering, navigation,
  and explanation;
- existing source locations allow CallDiff nodes to return to PR1 anchors;
- guided review can remain one projection over existing Review View rather than
  a new viewer or annotation system.

Refuted or corrected:

- Pierre alone does not always calculate the Git diff; it often parses a patch
  prepared elsewhere;
- CallDiff does not discard all line coordinates;
- CallDiff is not a type-aware runtime execution graph;
- CallDiff itself uses LCS to align call-tree children, so text/sequence
  algorithms are not exclusive to the Pierre side.

Unresolved:

- supported-language quality for Agent Studio's actual Swift/TypeScript mix;
- analysis latency and memory on representative large worktrees;
- grammar installation and packaged-app strategy;
- whether call-flow analysis should be product-owned or agent/tool-owned;
- which source-location identity survives file moves and comparison refresh;
- whether comments on multi-step call-flow selections need one thread with
  several located targets or several linked located threads.

## Primary sources

- Installed `@pierre/diffs` 1.2.10 package README, package metadata, generated
  source maps, type declarations, patch parser, and worker bundle under
  `BridgeWeb/node_modules/@pierre/diffs/`.
- Installed jsdiff 8.0.3 README and base implementation under
  `BridgeWeb/node_modules/.pnpm/diff@8.0.3/node_modules/diff/`.
- Pierre documentation: <https://diffs.com/docs>
- CallDiff repository and source:
  <https://github.com/tanishqkancharla/calldiff>
- CallDiff `src/extract.ts`, `src/calltree.ts`, `src/infer.ts`, `src/diff.ts`,
  and `src/types.ts` on the repository's current `main` branch.
