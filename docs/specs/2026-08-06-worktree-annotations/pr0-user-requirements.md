# PR0 Review Comparison — User Requirements

## Why this comes before annotations

After an agent finishes work in a repository worktree, the human reviewer needs
Review View to show the work attributable to that worktree. The current direct
comparison against the latest `main` tree can instead show changes introduced
only on `main` as reverse changes in the reviewed worktree. An annotation
created on that projection would inherit ambiguous source meaning.

PR0 makes the review projection trustworthy before PR1 stores durable
annotations against it.

```text
human reviewer [P0-U1 through P0-U7]
        │
        ├─ agent finishes work in a worktree
        │
        ├─ opens Review View
        │      current pain: direct target-tip comparison can show later
        │      target-only changes as worktree reversals
        │      evidence: current source and checkout counterexample
        │
        ├─ sees or changes the selected comparison target
        │
        └─ reviews the worktree contribution plus current local edits,
           or sees an explicit stale/unavailable result
```

## Decision authority and evidence

- Decision owner: Agent Studio owner.
- Authority: the owner's confirmed 2026-08-06 PR0 boundary, 2026-08-08
  clarification that the repository-designated integration branch is
  independent of another worktree's checkout, and 2026-08-09 correction that
  the initial target is its locally available remote-tracking ref rather than
  the same-named local branch.
- Observational evidence: current Agent Studio source and the current checkout
  demonstrate that the direct `main`-tree comparison can report target-only
  changes as reverse worktree changes.
- Advisory prior art: GitHub Pull Requests use a contribution-focused
  three-dot comparison and can calculate changed files from a different merge
  base than its Compare page. Current GitHub documentation does not define a
  public contract for permanently freezing a Pull Request's creation-time merge
  base. PR0 borrows the contribution-focused result, not a Pull Request
  lifecycle: a local Review View has no Pull Request creation event or durable
  Pull Request object, and the owner has chosen a living local review of what
  the worktree would contribute now.
- Deprecated review-comment and annotation documents are source material only.

## Affected classes

### Human reviewer

Reviews completed agent work in a local repository worktree and decides which
repository history defines the contribution under review.

### Later Worktree Annotations

PR1 is a downstream product consumer. It must be able to retain the exact
comparison origin on which an annotation was created without redefining how
Review View calculates that comparison.

External code hosts, multi-user reviewers, guided-review agents, and working
agent transport are not affected classes for PR0.

## Authorized needs

### P0-U1 — Review the contribution, not unrelated target changes

- Affected class: human reviewer.
- Need: Review View shows the work attributable to the selected worktree rather
  than treating later changes on the comparison target as worktree deletions or
  reversals.
- Why it matters: The reviewer must judge what the agent changed, not reconcile
  unrelated movement on `main`.
- Evidence: owner request for GitHub-like Pull Request behavior and current
  checkout counterexample.
- Authority: authorized.
- Priority: must for PR0, assigned by the Agent Studio owner.

```text
target advances independently
        │
        └─► target-only changes stay outside the reviewed contribution
```

### P0-U2 — Begin with the repository-designated remote-tracking branch

- Affected class: human reviewer.
- Need: When Agent Studio can identify the repository-designated integration
  branch through locally recorded remote-tracking state, Review View initially
  compares the selected worktree contribution against that remote-tracking
  branch. This designation is independent of whichever branch is currently
  checked out in the canonical main worktree.
- Why it matters: The repository-designated branch is the normal integration
  context. Its remote-tracking ref is the closest locally available meaning to
  the code host's integration branch, while the same-named local branch may be
  ahead, behind, or otherwise different. A temporary feature or hotfix checkout
  elsewhere must not silently redefine the review target.
- Evidence: owner confirmation that the repository-designated integration
  branch is the PR0 default.
- Authority: authorized.
- Priority: must for PR0, assigned by the Agent Studio owner.

```text
open Review View
        │
        ├─► initial target: identified remote-tracking integration branch
        └─► stacked work: reviewer explicitly chooses the intended base
```

PR0 does not infer a stacked branch's parent from checkout or upstream state.
When the reviewed work belongs to a stack, the reviewer chooses that stack's
intended base through the same target control required by P0-U3.

### P0-U3 — Understand the reviewed subject and comparison

- Affected class: human reviewer.
- Need: Review View identifies the worktree or branch being reviewed, visibly
  names the active comparison target, and lets the reviewer choose another
  supported local branch, remote-tracking branch, or exact commit. Branches are
  searchable separately from commit entry so the reviewer does not need to type
  or distinguish opaque Git reference syntax.
  The reviewer can also reach a plain-language explanation that the full
  worktree review starts at the latest commit shared with that target and does
  not treat target-only changes as worktree changes. The same surface exposes
  the exact target revision and shared starting point used by the displayed
  comparison and explains when either changes during the live review.
- Why it matters: A diff is not interpretable when the reviewed subject or
  comparison target is hidden, fixed, or described only as generic endpoints.
  The reviewer needs to know what work is included and why a refreshed file set
  may differ without understanding Git's three-dot terminology or guessing
  which revision a moving branch name represented.
- Evidence: direct owner corrections that Review View must allow target
  selection and clearly expose the exact resolved target, shared starting
  point, and which of those changed during a live refresh.
- Authority: authorized.
- Priority: must for PR0, assigned by the Agent Studio owner.

```text
feature/annotations changes    Compare: origin/master
        │                              │
        │                              └─ reviewer may choose another target
        │
        └─ current facts: origin/master at M2; review starts from B1
           refresh: target M1 → M2; base B1 → B1 or B2
```

### P0-U4 — Include the complete current worktree result

- Affected class: human reviewer.
- Need: A full-worktree review includes committed work on the selected worktree
  branch together with its staged, unstaged, and untracked changes. Existing
  staged-only and unstaged-only review behavior remains unchanged, but it is
  not part of PR0's new target-selection experience or data model.
- Why it matters: Agent work may be committed, partially staged, or still only
  present in the filesystem when review begins.
- Evidence: owner workflow and current Review comparison vocabulary.
- Authority: authorized.
- Priority: must for PR0, assigned by the Agent Studio owner.

```text
full-worktree review = committed + staged + unstaged + untracked
```

### P0-U5 — Keep the comparison meaningful as history moves

- Affected class: human reviewer.
- Need: A selected branch remains a living target meaning, while a selected
  commit remains pinned to that exact revision. Review View refreshes its
  contribution projection when the living target or reviewed worktree changes.
  If the worktree incorporates newer target history, that incorporated history
  no longer appears as part of the contribution. The reviewer can tell whether
  a refresh changed only the resolved target revision or also moved the shared
  starting point that defines the displayed comparison.
- Why it matters: Local review occurs while agents and humans continue editing,
  committing, merging, and rebasing the same worktree.
- Evidence: owner-approved living-session direction and GitHub-like
  contribution behavior.
- Authority: authorized.
- Priority: must for PR0, assigned by the Agent Studio owner.

```text
remembered target: main
        │
        ├─ main advances alone
        │     └─ contribution stays focused; main-only work stays excluded
        │
        └─ worktree merges or rebases newer main
              └─ contribution re-centres; incorporated main work disappears
```

The reviewer does not manage a separate frozen comparison base or reset it
after repository history changes. The selected target meaning remains visible;
Agent Studio determines the current contribution from current repository
history and distinguishes the previous result while that refresh is pending.

### P0-U6 — Never disguise an invalid comparison as a valid diff

- Affected class: human reviewer.
- Need: If Agent Studio cannot identify or resolve the selected target, cannot
  establish shared history, or cannot produce a current comparison, Review View
  clearly reports that condition and lets the reviewer choose another target.
  It does not silently substitute a comparison with different meaning.
- Why it matters: A plausible but wrongly based diff is more dangerous than an
  explicit unavailable state.
- Evidence: owner requirement for sensible review and source correlation.
- Authority: authorized.
- Priority: must for PR0, assigned by the Agent Studio owner.

```text
comparison cannot be established
        │
        └─► explicit unavailable or stale state; never a silently different diff
```

### P0-U7 — Preserve the origin of every comparison

- Affected classes: human reviewer and later Worktree Annotations.
- Need: Every published Review comparison retains enough immutable evidence to
  identify the selected target meaning, the exact resolved repository history,
  the reviewed worktree state, and the file-side content shown in that
  comparison.
- Why it matters: PR1 must later distinguish an annotation's original reviewed
  material from its best-effort placement after Git history or files change.
- Evidence: direct owner requirement that annotation anchors track the
  worktree, comparison, commits, and content needed for approximate placement.
- Authority: authorized.
- Priority: must for PR0, assigned by the Agent Studio owner.

```text
published comparison
        ├─► human-readable selected target
        └─► immutable origin evidence for later annotation placement
```

## Confirmed goal boundary

- Primary goal: make local worktree Review View a trustworthy,
  contribution-focused review surface before annotations are added.
- Existing foundation to reuse: Review View, persisted workspace baselines,
  current Git endpoint and content identities, current worktree diff support,
  and `agentstudio-git` as the native Git data plane.
- Missing behavior: contribution-focused comparison, a visible target chooser,
  separate branch and commit selection, honest failure behavior, and complete
  comparison-origin evidence.
- Allowed surface: Review View comparison behavior and controls, the native Git
  comparison capability, and the review data contract needed to describe the
  selected and resolved comparison.
- Protected surface: File View behavior, staged-only and unstaged-only meaning,
  existing repository/worktree identity authority, and unrelated pane or IPC
  behavior.
- Non-goals: annotations, annotation sessions, anchor placement, Markdown or
  Mermaid rendering, copy/export, comment status, agent IPC, guided review,
  delivery tracking, a Pull Request-style frozen review lifecycle or reset-base
  action, external code-host synchronization, multi-user review, a new service,
  and a new authentication or security system.
- Complexity boundary: extend the existing Review and Git path. A generalized
  comparison service for other products, an event-sourced comparison history,
  a collaboration platform, or a second Git authority requires a new owner
  decision.
- Acceptable outcome evidence: repository-history scenarios distinguish
  contribution comparison from direct target-tip comparison; Review View
  visibly selects and changes targets; invalid comparisons cannot publish as
  current valid diffs; and published comparison metadata identifies the exact
  origin needed by a later annotation consumer.

## PR0 stop line

PR0 is complete at the product boundary when the reviewer can open Review View,
understand and change the target, review the complete local worktree
contribution without unrelated target noise, and trust the displayed validity
and origin of the comparison. No annotation is created in PR0.
