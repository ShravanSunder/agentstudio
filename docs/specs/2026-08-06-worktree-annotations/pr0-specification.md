# PR0 Review Comparison — Specification

## Authority and scope

This Specification defines the observable PR0 contract authorized by
[`pr0-user-requirements.md`](./pr0-user-requirements.md). It covers Review View
comparison behavior and the comparison-origin contract consumed by later
Worktree Annotations. It does not specify annotation behavior or internal
component structure.

GitHub Pull Requests are prior art for contribution-focused comparison:

- [GitHub: Branches — three-dot and two-dot comparisons](https://docs.github.com/en/pull-requests/reference/branches#three-dot-and-two-dot-git-diff-comparisons)
- [GitHub: Pull requests — PR and Compare pages](https://docs.github.com/en/pull-requests/reference/pull-requests#differences-between-commits-on-compare-and-pull-request-pages)

GitHub documents contribution-focused three-dot behavior and notes that Pull
Request and Compare pages can calculate from different merge bases. The cited
current documentation does not define a permanent creation-time merge-base
contract. PR0 therefore defines its own local behavior rather than claiming
GitHub lifecycle compatibility: Review View keeps a living selected branch or
pinned selected commit and recomputes the current contribution as repository
history changes.

## The observable model

```text
human reviewer
     │ selects target                     sees target, state, and file projection
     ▼                                                ▲
┌────────────────────────────────────────────────────────────────────┐
│ PR0 Review comparison                                             │
│                                                                    │
│ selected target meaning                  current reviewed worktree │
│ branch or pinned commit                  HEAD + index + files      │
│              │                                  │                  │
│              ▼                                  ▼                  │
│        resolved target ───── shared history ─ reviewed HEAD        │
│                                   │                                │
│                                   ▼                                │
│                          contribution base                         │
│                                   │                                │
│                                   ▼                                │
│              contribution base ──► current working tree result     │
└────────────────────────────────────────────────────────────────────┘
     │ comparison snapshot and immutable origin evidence
     ▼
later Worktree Annotations consumer

outside PR0: annotation creation, placement, storage, export, and agent IPC
```

The selected target is either a living symbolic branch choice or a pinned exact
commit choice. A published comparison is an immutable result produced from one
exact resolution of that choice and one exact reviewed worktree state.

These three identities MUST remain distinct:

```text
persisted target intent       current attempt inputs       published result
"main"                        target T + HEAD H + base B   immutable snapshot S
      │                                  │                         │
      └─ survives restore               └─ recomputed             └─ may become stale
```

PR0 defines no frozen Review object, stored creation-time comparison base, or
user-facing reset-base action. Recomputing a comparison does not mutate an
already published snapshot; it produces a successor snapshot and changes which
snapshot is current.

## Terms

- **Selected target**: the reviewer-visible branch or exact commit against
  which the worktree contribution is defined. A selected branch follows that
  symbolic ref; a selected commit remains pinned to its exact object ID.
- **Repository default target**: the locally available remote-tracking branch
  named by the repository's recorded default integration-branch designation.
  It is independent of the branch currently checked out in any worktree and
  does not imply a network fetch. If the designation is absent, ambiguous, or
  does not identify a resolvable remote-tracking branch, the default target is
  unidentified.
- **Contribution comparison**: the internal comparison semantic that projects
  the complete current worktree from its current shared history with the
  selected target. `Contribution` is not a user-facing control label.
- **Resolved target revision**: the exact commit reached by the selected target
  for one comparison.
- **Reviewed HEAD revision**: the exact current worktree `HEAD` commit used to
  establish shared history.
- **Contribution base**: the current shared-history commit from which the
  reviewed branch contribution begins.
- **Working tree result**: the reviewed HEAD plus current index, tracked-file,
  and untracked-file state.
- **Comparison snapshot**: one published result containing its file projection
  and immutable origin evidence identifying its inputs and shown content.
- **Current comparison**: the latest successfully published snapshot for the
  active comparison intent and worktree state.

## Functional requirements

### P0-R1 — Open with the repository-designated remote-tracking target

When a new Review View opens for a worktree with no restored selected-target
intent, and Agent Studio can identify and resolve that repository's designated
remote-tracking integration branch, it MUST select that branch as the initial
target and MUST show its full remote-tracking name in Review View. The
identification MUST come from locally recorded repository state, MUST NOT fetch,
and MUST NOT use a same-named local branch or the branch currently checked out
in the canonical main worktree as a substitute.

If no repository default target can be identified or resolved, Review View
MUST NOT label another reference as the default. It MUST present comparison
selection as requiring attention and allow the reviewer to choose an available
target.

```text
open worktree Review View
        ├─ designated remote-tracking branch available → select and name it
        └─ unavailable                                → request target; no fallback
```

Traces to: P0-U2, P0-U3, P0-U6.

### P0-R2 — Expose and apply reviewer-selected comparison targets

For a contribution comparison, Review View MUST identify the reviewed subject
using its available worktree or branch display label, falling back to `Current
worktree` when no meaningful label is available. It MUST expose the active
selected target in its persistent review chrome. The reviewer MUST be able to
choose any local branch, remote-tracking branch, or exact commit that Agent
Studio can resolve for the selected repository.

The closed target control MUST present this action as `Compare: <target>`. Its
opened surface MUST be titled `Compare Worktree`, with separate `Branch` and
`Commit` selection modes. Branch mode MUST provide locally available local and
remote-tracking branch candidates, searchable by their displayed names. Commit
mode MUST accept and resolve an exact commit object ID without presenting it as
a moving branch. Selecting a branch candidate applies it directly; exact commit
entry MAY require an explicit confirmation after resolution.

Each branch candidate MUST show its unambiguous displayed branch name and
current abbreviated target revision while retaining the full revision for
assistive technology. The designated initial branch MUST be marked `Default`
without replacing its actual branch name. Local and remote-tracking branches
with the same short name MUST remain distinguishable. Opening or searching the
selector MUST NOT fetch from a remote.

The review title and target control MUST NOT describe a contribution comparison
as generic `Head vs Base`, use `Default` in place of an identified target, or
present `Contribution` as a navigation action or stored base.

The comparison control MUST make this plain-language meaning available:
committed and uncommitted worktree changes since the latest commit shared with
the selected target are shown, while changes only on the selected target are
excluded. This explanation MUST be reachable by keyboard and assistive
technology and MUST NOT depend on hover alone. Normal Review chrome MUST NOT
require the reviewer to understand `three-dot`, `merge base`, or revision IDs.

The same control MUST expose the exact resolved target revision and exact
shared starting-point revision used by the displayed contribution snapshot.
It MUST describe that starting point as `Review starts from <revision>` and as
the latest commit shared with the named selected branch or commit. For the
designated branch, the supporting line MUST identify it as the default branch
without hiding its actual remote-tracking name.
The surface MAY visually abbreviate revision values only when each full value
remains available through the same keyboard- and assistive-technology-reachable
details. These facts describe the displayed snapshot; a branch name alone MUST
NOT be presented as if it were an exact revision or the shared starting point.

Changing the selected target MUST request a new comparison. Until that request
publishes, Review View MUST distinguish the prior snapshot from the pending
selection. A late result for an older selection MUST NOT replace a result for a
newer selection.

PR0 MUST NOT infer a stacked branch's intended base from the reviewed
worktree's current branch, its upstream, or another worktree's checkout. The
reviewer selects the intended stack base through the same contribution-target
control.

```text
reviewed subject     active target          plain-language meaning
feature/annotations  Compare: origin/main  since shared history
         │                  │                    │
         └──────────────────┴────────────────────┘
                         one interpretable review
```

Traces to: P0-U3, P0-U5, P0-U6.

### P0-R3 — Show the contribution from shared history

For a branch or exact-commit target, Review View MUST compare the current working
tree result with the one unambiguous current shared-history commit of the
resolved target revision and reviewed HEAD revision.

The comparison MUST include changes introduced on the reviewed branch after
that shared-history commit. Changes present only on the selected target after
the histories diverged MUST NOT appear as reverse worktree changes.

```text
fork point──agent A──agent B              reviewed worktree HEAD
     \
      └──main X──main Y                   selected target

shown: agent A + agent B + current local edits
hidden: main X + main Y as reverse changes
```

Traces to: P0-U1, P0-U5.

### P0-R4 — Include the current worktree state

A contribution comparison MUST include committed changes after the
contribution base, staged changes, unstaged tracked-file changes, deletions,
renames detectable by the supported Git data plane, and untracked files.

```text
full-worktree target → base-to-current-worktree
```

Selecting, preserving, or changing staged-only and unstaged-only modes is
outside PR0. This work MUST NOT add staging-aware selector behavior or change
those pre-existing modes.

Traces to: P0-U4.

### P0-R5 — Re-centre when shared history changes

For a contribution comparison, when Agent Studio observes that a selected
branch resolves to a new revision, observes a change to the reviewed
worktree state, or the reviewer requests refresh, Review View MUST request a new
comparison. It MUST distinguish the prior snapshot from the pending result until
the new result publishes.

Every such contribution-comparison attempt MUST resolve the selected target and
reviewed HEAD again before publishing a current comparison. Resolving the same
branch name to a different revision counts as target movement. A selected exact
commit MUST continue resolving to that pinned revision or become unavailable;
it MUST NOT move to another commit.

When a live Review View replaces one contribution snapshot with a successor for
the same repository, worktree, and selected target identity, it MUST explain the
transition from the previously displayed origin by evaluating target and shared
starting-point movement independently:

- if the resolved target revision changed, identify its old and new revisions;
- if that target changed while the contribution base did not, state that the
  shared starting point is unchanged;
- if the contribution base changed, identify its old and new revisions and
  state that files may have entered or left the review; and
- if no directly preceding displayed snapshot exists, expose only the current
  exact target and shared starting point and MUST NOT invent a movement notice.

When both the resolved target and contribution base change in the same
successor, the explanation MUST include both old-to-new revision pairs.

This explanation reports the automatic living refresh. It MUST NOT imply that
the reviewer must manually update the comparison or merge or rebase the
worktree.

- If the selected target advances without becoming shared history, its
  target-only changes MUST remain outside the worktree contribution.
- If the reviewed branch merges or rebases onto newer selected-target history,
  the contribution base MUST advance to that newer shared history.
- If the selected target already contains reviewed HEAD, the committed
  contribution MUST be empty while current staged, unstaged, and untracked work
  remains visible.

The reviewer MUST NOT need to reset a stored contribution base after these
changes. Refresh operates from the selected target meaning and current
repository history.

```text
target advances alone         worktree incorporates target
          │                              │
          ▼                              ▼
same contribution base        newer contribution base
focused contribution          incorporated target work disappears
```

Traces to: P0-U1, P0-U5.

### P0-R6 — Fail without changing comparison meaning

If the selected target cannot be resolved, reviewed HEAD is unavailable, no
shared history can be established, more than one best shared-history commit
exists, required Git objects are unavailable, or an observed repository or
worktree invalidation supersedes an attempt before publication, Review View
MUST NOT present the attempted result as the current valid comparison.

Review View MUST expose an actionable unavailable, retryable, or stale state.
It MAY retain the last successful snapshot only when that snapshot is visibly
identified as stale and remains associated with its original selected and
resolved target. It MUST NOT silently switch to `HEAD`, another branch, direct
target-tip comparison, or a status-only projection with different completeness.

```text
attempted comparison fails
        ├─ last snapshot retained → visibly stale + original identity
        └─ no snapshot retained   → unavailable + choose/retry
```

Traces to: P0-U6, P0-U7.

### P0-R7 — Publish immutable comparison-origin evidence

Every contribution comparison snapshot MUST identify:

1. the repository and worktree being reviewed;
2. the contribution-base and captured-working-tree endpoint roles;
3. one snapshot identity or revision that changes when any comparison input,
   published file set, or published file-side content identity changes; and
4. for each shown file side, its repository-relative path, role or side, and
   content identity when content exists.

It MUST also identify the selected target's branch or commit identity and kind,
resolved target revision, reviewed HEAD revision, and contribution-base
revision.

The human-facing surface MUST name the selected target. Exact revision,
snapshot, endpoint, and content identities MAY remain in details or
machine-readable review metadata, but MUST be available to the later annotation
consumer without reconstructing them from labels or current mutable repository
state.

```text
human reads:     feature/annotations changes | Compare: origin/main
consumer reads: contribution origin + snapshot + file content identities
```

Traces to: P0-U3, P0-U7.

### P0-R8 — Restore comparison intent without claiming stale truth

When a saved contribution Review View is restored, Agent Studio MUST restore
the selected target meaning, including whether it is a moving branch or pinned
commit, resolve it again, and request a fresh comparison.
A previously resolved revision or snapshot MUST NOT be presented as current
merely because the pane was restored.

Restored contribution selected-target intent MUST take precedence over the
new-view repository-default behavior in P0-R1. An unresolvable restored
contribution target follows P0-R6; it MUST NOT be replaced with the current
repository default target.
Legacy saved baselines that Agent Studio automatically manufactured from the
canonical main worktree's checkout or from a literal `main` are not restored
selected-target intent. They MUST enter P0-R1's guarded
repository-designated-target selection, or its attention state when that target
cannot be identified and resolved.

```text
restore pane → restore target meaning → resolve again → fresh snapshot
```

Traces to: P0-U3, P0-U5, P0-U6, P0-U7.

## Observable scenarios

### Scenario A — `origin/main` advances independently

Given a worktree branch and remote-tracking `origin/main` share commit `F`, and
both have commits after `F`, Review View shows changes from `F` to the current
working tree. Files changed only by later `origin/main` commits are absent from
the contribution. When Agent Studio observes `origin/main` advance again under
the same symbolic name, the prior snapshot becomes pending or stale until a
newly resolved comparison publishes. If `origin/main` contains reviewed HEAD,
the committed contribution is empty while current dirty changes remain visible.

### Scenario B — The worktree incorporates newer `origin/main`

After the worktree branch merges or rebases onto newer `origin/main`, refreshing
Review View uses the newer shared history. Incorporated target changes are not
reported as agent contribution.

### Scenario C — The worktree contains every local state class

When committed, staged, unstaged, deleted, renamed, and untracked changes are
present, one contribution comparison represents all supported changes without
hiding the committed portion.

### Scenario D — The reviewer changes targets

Changing from `origin/main` to local `main` or a pinned commit visibly changes
the selected target, produces a separately identified snapshot, and prevents
an older result from publishing afterward as current. A later move of
`origin/main` updates a branch-based comparison but does not move the pinned
commit comparison.

### Scenario E — Comparison cannot be established

For an unresolved target, unrelated history, multiple best shared-history
commits, unborn reviewed HEAD, or missing required object, Review View exposes
failure and no misleading current diff. The reviewer can choose another target
or retry after repository state changes.

### Scenario G — The reviewer can interpret the active comparison

With worktree display label `feature/annotations` and selected target
`origin/main`, Review View identifies `feature/annotations changes`, presents
`Compare: origin/main`, marks that named branch `Default`, and shows `Review
starts from B1` with `Latest commit shared with default branch origin/main`.
If no meaningful worktree or branch display label is available, the title uses
`Current worktree changes`. The normal surface does not label the comparison
`Head vs Base`, use `Default` instead of the branch name, or present
`Contribution`, `three-dot`, or `merge base` as required reviewer terminology.

### Scenario H — A living comparison explains what moved

Given the displayed contribution snapshot resolves `master` to `M1` with shared
starting point `B1`, when `master` changes to `M2` and the successor snapshot
still uses `B1`, Review View reports `M1` to `M2` and states that the shared
starting point remains `B1`. When one successor changes both values, Review View
reports target `M1` to `M2` and shared starting point `B1` to `B2`, then warns
that files may have entered or left the review. On first load or restore without
a directly preceding displayed snapshot, it shows the exact current target and
shared starting point without claiming that either moved.

### Scenario I — Another worktree is temporarily on a different branch

Given the repository-designated integration branch is `origin/master` while
the canonical main worktree is checked out to `hotfix/urgent` and local
`master` differs, a new Review View with no restored target selects and names
`origin/master`. It does not select local `master` or `hotfix/urgent` as the
default. If the reviewed work is intentionally
stacked on another branch, the reviewer selects that branch through `Compare
to`; Agent Studio does not infer it from checkout or upstream state.

## Surface contracts

### Review View compare-to control

- Scope: full-worktree comparisons.
- Consumer: human reviewer.
- Input: selected worktree and one reviewer-selected branch or exact commit.
- Output: visible reviewed-subject and target labels; exact current resolved
  target and shared-starting-point revisions; an accessible plain-language
  explanation of shared-history behavior and any observed successor movement;
  plus pending, current, stale, or unavailable comparison state.
- Invariant: the target label and rendered snapshot describe the same selected
  target meaning; the reviewed-subject label identifies the worktree represented
  by that snapshot and is not comparison authority.
- Accessibility: the target control MUST be keyboard operable, expose an
  accessible name, current value, and shared-history description, and preserve
  visible focus behavior consistent with existing Review View controls. The
  explanation MUST remain available without hover.
- Undefined: PR0 does not prescribe a shortcut, automatic network fetch,
  ahead/behind display, commit-history browser, or durable comparison-change
  history, acknowledgement lifecycle, or manual comparison-update workflow.

### Comparison snapshot contract

- Consumers: Review View and later Worktree Annotations.
- Input: one selected contribution target and one reviewed worktree state.
- Output: the file projection plus P0-R7 origin evidence.
- Invariant: the snapshot is internally self-consistent; mutable labels or
  repository state are not substitutes for captured resolved identities.
- Partial success: a snapshot MUST NOT claim to be current when required
  comparison files or origin evidence are omitted. Unsupported individual
  file content MAY remain visibly unavailable under existing Review behavior
  when the file still retains its path, side, and snapshot relationship.
- Undefined: PR0 does not define annotation anchor storage, relocation, or
  delivery formats.

## Cross-cutting boundaries

- Reliability: only the newest applicable target/worktree result may become
  current; failure cannot silently change semantic meaning.
- Data lifecycle: PR0 persists the selected contribution target through the
  existing pane/workspace lifecycle. It does not add historical comparison
  retention.
- Security and privacy: PR0 introduces no new actor, privilege, network
  transport, or exported content. Existing repository and worktree access
  boundaries remain authoritative.
- Performance: PR0 adds no user-facing numeric latency promise. Target changes
  and refreshes must continue to expose existing loading/cancellation behavior
  rather than blocking the application UI.
- Compatibility: existing saved explicit branch, remote-tracking branch, exact
  commit, and Git-reference meanings remain restorable. Legacy checkout-derived defaults and literal
  `main` defaults are re-established through P0-R1 rather than promoted into
  reviewer-selected intent. PR0 creates one contribution path, not old and new
  comparison modes for the same target.

## Requirement and proof coverage

| Need | Problem | Outcome | Requirements | Contract | Proof obligation |
| --- | --- | --- | --- | --- | --- |
| P0-U1 | target-only noise obscures agent work | focused contribution | P0-R3, P0-R5 | comparison snapshot | P0-V1 |
| P0-U2 | initial comparison lacks trustworthy default meaning | repository-designated remote-tracking integration target | P0-R1 | target control | P0-V2 |
| P0-U3 | generic subject/target labels make the diff ambiguous | interpretable subject, exact target/base, and shared-history meaning | P0-R1, P0-R2, P0-R8 | target control | P0-V2, P0-V4 |
| P0-U4 | agent work spans committed and dirty state | complete worktree result | P0-R4 | comparison snapshot | P0-V1 |
| P0-U5 | Git history evolves during review | living re-centred comparison with explained movement | P0-R2, P0-R5, P0-R8 | both | P0-V1, P0-V4 |
| P0-U6 | invalid fallback can look plausible | honest unavailable/stale state | P0-R1, P0-R6, P0-R8 | both | P0-V3, P0-V4 |
| P0-U7 | later anchors need immutable origin | self-identifying snapshot | P0-R6, P0-R7, P0-R8 | comparison snapshot | P0-V3, P0-V4 |

### P0-V1 — Repository-history behavior

Automated behavior evidence MUST distinguish direct target-tip comparison from
the specified contribution projection across independent target advance,
merge, rebase, target-containing-HEAD, committed, staged, unstaged, deleted,
renamed, and untracked cases. The target-containing-HEAD case MUST show no
committed contribution while retaining current staged, unstaged, and untracked
changes.

### P0-V2 — Reviewer interaction and visual evidence

Automated interaction evidence plus manual visual evidence MUST show the
initial remote-tracking default target for a new Review View with no restored target
intent, the reviewed worktree or branch label with `Current worktree` fallback,
the visible `Compare: <target>` label and current value; `Compare Worktree`
surface; separate Branch and Commit modes; searchable, distinguishable local
and remote-tracking branch rows with target revisions; a pinned exact-commit
choice; the keyboard- and assistive-technology-reachable shared-history
explanation; exact current target and shared-starting-point revisions; target
change; pending state; and resulting projection in Review View. The same
evidence MUST show that the header remains one row and that the normal
contribution surface does not substitute `Head vs Base`, a bare `Default`,
`Contribution`, `three-dot`, or `merge base` for the required user-facing
meaning.
The initial-target evidence MUST also show that a different branch checked out
in the canonical main worktree and a divergent same-named local branch do not
replace the repository-designated remote-tracking default, and that an
intentionally stacked base can be selected explicitly through the same target
control.
Automated interaction evidence MUST also show that an unidentified or
unresolvable repository default produces an attention state, exposes no false
`Default` label, and allows the reviewer to select another target.

### P0-V3 — Snapshot and failure evidence

State or contract inspection MUST show every applicable P0-R7 common and
contribution-origin field. It MUST prove that contribution snapshots expose
truthful endpoint roles without fabricated contribution history, and that unresolved targets, unrelated
history, multiple best shared-history commits, missing required objects, and
attempts superseded by observed source invalidation do not publish a misleading
current snapshot.

Automated interaction evidence plus manual visual evidence MUST show one
representative unavailable comparison as an explicit actionable state with the
applicable choose-target or retry action. If Review View retains a prior
snapshot after a failed attempt, the same evidence MUST show that retained
content as stale and associated with its original selected target rather than
the failed pending target.

### P0-V4 — Restore and stale-result evidence

Integration evidence MUST show restoration re-resolves the branch or pinned commit target and
that stale or superseded asynchronous results cannot replace the latest
applicable comparison. A pane with no retained target uses P0-R1 when Review
View opens.

Automated transition evidence MUST hold selected target intent constant while
target history advances and while the worktree separately incorporates target
history, and prove that each changed set of resolved target, reviewed HEAD, or
contribution-base inputs publishes a distinct current successor snapshot
without mutating or restoring the prior snapshot as current. The same evidence
MUST show that the prior displayed projection remains available and associated
with its original origin while the successor is pending, then supplies the
predecessor used for the admitted successor's movement explanation.

Durability evidence MUST use file-backed workspace storage across process
termination. One process MUST commit a branch or pinned-commit comparison intent
and exit; a new process MUST restore that exact intent from the same saved workspace and
freshly resolve current Git truth. The saved pane payload MUST NOT treat a
previously resolved target, reviewed HEAD, contribution base, or comparison
snapshot as durable current truth.
Evidence MUST also restore legacy checkout-derived `localDefaultBranch` values
and the legacy literal-`main` File View value without promoting either to
selected intent: the repository-designated remote-tracking target wins when
available, and the attention state appears otherwise.

Reviewer-facing evidence MUST distinguish target-revision-only movement from
contribution-base movement, expose the applicable old and new exact revisions,
show both old-to-new pairs when both move, and avoid a movement claim when no
preceding displayed snapshot exists. It MUST separately hold those history
inputs fixed while changing only captured index,
working-tree, or untracked content, and prove that changed file-side content
identities publish a distinct current successor while the prior snapshot and
its content identities remain unchanged. It MUST also hold the history inputs
and retained file-side content identities fixed while changing only published
file membership or path/side membership, and prove a distinct current successor
without mutating the prior snapshot. This evidence does not require a historical
comparison store beyond the observed snapshots.

## Negative space

PR0 does not create annotations or store annotation origins. It does not render
Markdown or Mermaid, export feedback, contact an agent, synchronize with a code
host, retain an event history of comparisons, infer that a review is complete,
define a Pull Request-style frozen review lifecycle or reset-base action, or
define annotation-session freezing. Those behaviors remain PR1 or PR2 work.
