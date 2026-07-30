# Daily Beta Release

Date: 2026-07-29
Status: Accepted design

## Outcome

AgentStudio automatically publishes one installable beta per day from the
newest `main` commit when that commit has not already been beta-tagged.

The schedule runs at 12:00 PM in `America/Toronto`, including daylight-saving
time. A manual trigger provides the same behavior for urgent beta publication.
An intentional manual run may therefore publish an additional beta after a
later same-day merge.

If `main` has not changed since the beta tag already pointing at its tip, the
workflow succeeds without creating another tag or release.

## System Shape

```text
12:00 America/Toronto or manual dispatch
                  │
                  ▼
       Daily Beta Tag workflow
       ├─ fetch exact origin/main
       ├─ inspect stable and beta tags
       ├─ unchanged main ──────────────► no-op
       └─ changed main
            │
            ▼
    v<next-patch>-beta.<run-number>
            │
            ▼
       Existing Release workflow
       ├─ build AgentStudio Beta.app
       ├─ sign, notarize, and staple
       ├─ publish GitHub prerelease
       └─ update agent-studio@beta
```

## Ownership

### Daily Beta Tag workflow

A new `.github/workflows/daily-beta.yml` owns only scheduling and tag creation.

It:

- runs daily with `cron: "0 12 * * *"` and
  `timezone: "America/Toronto"`;
- supports `workflow_dispatch`;
- always resolves and tags the current `origin/main`, including when manually
  dispatched;
- has `contents: write` permission;
- checks out full tag history;
- delegates tag selection to the repository script;
- authenticates checkout and tag push with the existing
  `HOMEBREW_TAP_TOKEN` release PAT so GitHub emits the downstream tag-push
  event;
- serializes overlapping scheduled and manual runs without cancelling the
  in-progress run, so a queued run observes its tag and becomes a no-op;
- pushes one lightweight tag only when the script says publication is needed.

It does not build, sign, notarize, publish a release, or edit the Homebrew tap.
It cannot access the Apple signing or notarization secrets. The release PAT is
not printed, interpolated into shell commands, or persisted outside the
ephemeral workflow checkout.

### Tag resolver

A new `scripts/resolve-daily-beta-tag.sh` owns deterministic beta tag selection.
It accepts the candidate `main` commit and the GitHub workflow run number.

The resolver:

1. validates that the candidate commit exists and the run number is numeric;
2. returns a successful no-op when any valid beta tag already points at the
   candidate commit;
3. finds the highest stable tag matching `vMAJOR.MINOR.PATCH`;
4. increments only `PATCH`;
5. proposes
   `vMAJOR.MINOR.(PATCH+1)-beta.<GITHUB_RUN_NUMBER>`;
6. fails if that proposed tag already points at a different commit;
7. emits key-value output suitable for `$GITHUB_OUTPUT`.

The GitHub run number supplies a numeric, workflow-monotonic beta suffix without
a mutable version file, tag scan counter, or repository variable.

### Existing Release workflow

`.github/workflows/release.yml` remains unchanged. Its existing `v*` tag trigger
and beta metadata path own the complete signed release. The daily workflow
therefore cannot drift into a second packaging implementation.

The default repository `GITHUB_TOKEN` cannot be used for the tag push because
GitHub suppresses downstream workflow runs caused by that token. The existing
release PAT is required specifically to preserve the tag-driven handoff.

## Ordering Constraint

The daily-beta PR must merge after pane-toolbar hotfix PR #226. Until both are
on `main`, the scheduled workflow must not be enabled. This prevents a beta
whose version follows `v0.0.68` while its source omits the emergency hotfix.

## Failure Behavior

- No stable tag: fail without creating a tag.
- Invalid candidate or run number: fail without creating a tag.
- Candidate already beta-tagged: succeed as a no-op.
- Overlapping runs: serialize; the later run re-fetches tags and becomes a
  no-op when both selected the same `main` commit.
- Proposed tag collision on another commit: fail without moving the tag.
- Tag push failure: fail; the next scheduled or manual run may retry.
- Existing Release workflow failure after tag creation: keep the immutable tag
  and rerun that failed GitHub workflow. Do not move or recreate the tag.

No workflow force-pushes or deletes tags.

## Proof

The release-script verification lane must cover:

- stable `v0.0.68` resolves to `v0.0.69-beta.<run-number>`;
- the highest semantic stable tag wins over older tags and prereleases;
- a beta tag already pointing at the candidate produces a no-op;
- malformed run numbers and missing stable tags fail;
- a proposed tag collision on a different commit fails;
- the workflow declares the Toronto noon schedule, manual trigger, full-history
  checkout, `main` targeting, and existing tag-driven release handoff.

Required commands:

```text
bash scripts/verify-release-scripts.sh
mise run lint
```

No app build, Swift test suite, or foreground launch is required because this
change affects release automation only and does not change app source or
runtime behavior.

## Tradeoff

Daily publication reduces build, notarization, GitHub release, and Homebrew
churn compared with beta-on-every-merge. The cost is that multiple merges within
one day are represented by one beta from the latest `main` tip rather than one
artifact per merge.

GitHub's timezone-aware schedule syntax is documented at
https://docs.github.com/actions/using-workflows/events-that-trigger-workflows.
GitHub's downstream workflow token behavior is documented at
https://docs.github.com/actions/using-workflows/triggering-a-workflow.
