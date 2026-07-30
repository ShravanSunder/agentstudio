# Daily Beta Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a signed beta from the newest `main` commit each day at noon
Toronto time, while doing nothing when that commit is already beta-tagged.

**Architecture:** A small shell resolver owns deterministic tag selection and
idempotency. A new scheduled workflow checks out `main`, calls the resolver,
and pushes the selected tag; the existing tag-driven release workflow remains
the only build, signing, notarization, publication, and Homebrew owner.

**Tech Stack:** Bash, Git, GitHub Actions.

## Global Constraints

- Schedule: `0 12 * * *` with `timezone: "America/Toronto"`.
- Support `workflow_dispatch` for urgent beta publication.
- Always resolve the current `origin/main`; never tag the dispatching branch.
- Use `vMAJOR.MINOR.(PATCH+1)-beta.<GITHUB_RUN_NUMBER>`.
- Never move, delete, or force-push a tag.
- Do not change `.github/workflows/release.yml`.
- Authenticate checkout and tag push with
  `${{ secrets.HOMEBREW_TAP_TOKEN }}`; `GITHUB_TOKEN` must not perform the push
  because it suppresses the downstream release workflow.
- Merge this PR after pane-toolbar hotfix PR #226.

---

### Task 1: Deterministic Daily Beta Tag Resolver

**Files:**

- Create: `scripts/resolve-daily-beta-tag.sh`
- Modify: `scripts/verify-release-scripts.sh`

**Interfaces:**

- Consumes: `scripts/resolve-daily-beta-tag.sh <candidate-sha> <run-number>`
  inside a Git repository with fetched tags.
- Produces on stdout:

```text
should_tag=true|false
candidate_sha=<full commit sha>
tag=<new or existing beta tag>
```

- [ ] **Step 1: Add resolver contract tests**

Extend `scripts/verify-release-scripts.sh` with a disposable Git repository.
Create three commits, stable tags `v0.0.67` and `v0.0.68`, and an older beta.
Assert:

```bash
resolver_output="$(
  GIT_DIR="$beta_repo/.git" GIT_WORK_TREE="$beta_repo" \
    "$ROOT_DIR/scripts/resolve-daily-beta-tag.sh" "$candidate_sha" 123
)"
assert_contains "$resolver_output" "should_tag=true"
assert_contains "$resolver_output" "candidate_sha=$candidate_sha"
assert_contains "$resolver_output" "tag=v0.0.69-beta.123"
```

Also assert:

- after tagging the candidate `v0.0.69-beta.122`, output contains
  `should_tag=false` and that existing tag;
- `run-number=abc` fails;
- a repository without a stable tag fails;
- `v0.0.69-beta.123` pointing at another commit causes collision failure.

- [ ] **Step 2: Verify the tests fail for the missing resolver**

Run:

```bash
bash scripts/verify-release-scripts.sh
```

Expected: non-zero exit because `scripts/resolve-daily-beta-tag.sh` does not
exist.

- [ ] **Step 3: Implement the minimal resolver**

Create an executable Bash script that:

1. validates two arguments, numeric run number, and commit existence;
2. canonicalizes the candidate with `git rev-parse "${candidate}^{commit}"`;
3. checks `git tag --points-at "$candidate_sha"` for an exact
   `v[0-9]+.[0-9]+.[0-9]+-beta.[0-9]+` tag and returns a no-op if present;
4. selects the highest exact stable tag using `git tag --sort=-v:refname`;
5. parses `MAJOR`, `MINOR`, and `PATCH`, increments `PATCH`, and composes the
   beta tag with the supplied run number;
6. rejects an existing proposed tag on another commit;
7. emits the interface keys above.

Do not fetch, create, delete, or push tags from the resolver.

- [ ] **Step 4: Verify the resolver suite passes**

Run:

```bash
bash scripts/verify-release-scripts.sh
```

Expected: `release script verification passed`, exit 0.

- [ ] **Step 5: Commit the resolver slice**

```bash
git add scripts/resolve-daily-beta-tag.sh scripts/verify-release-scripts.sh
git commit -m "build: resolve deterministic daily beta tags"
```

### Task 2: Noon Toronto Daily Beta Workflow

**Files:**

- Create: `.github/workflows/daily-beta.yml`
- Modify: `scripts/verify-release-scripts.sh`

**Interfaces:**

- Consumes: the resolver output keys from Task 1.
- Produces: one lightweight beta tag pushed to `origin`, which triggers the
  existing `.github/workflows/release.yml`.

- [ ] **Step 1: Add workflow contract tests**

Before creating the workflow, extend `scripts/verify-release-scripts.sh` to
assert that `.github/workflows/daily-beta.yml` contains:

```text
schedule:
cron: '0 12 * * *'
timezone: 'America/Toronto'
workflow_dispatch:
fetch-depth: 0
ref: main
contents: write
token: ${{ secrets.HOMEBREW_TAP_TOKEN }}
scripts/resolve-daily-beta-tag.sh
git push origin
```

Also assert the workflow does not contain Apple signing secrets, notarization
commands, Homebrew tap mutation, or `release.yml` duplication.

- [ ] **Step 2: Verify the workflow contract fails while the file is absent**

Run:

```bash
bash scripts/verify-release-scripts.sh
```

Expected: non-zero exit because `.github/workflows/daily-beta.yml` is absent.

- [ ] **Step 3: Implement the minimal workflow**

Create a workflow with:

- `schedule` and `workflow_dispatch` triggers;
- `permissions: contents: write`;
- one Ubuntu job with a short timeout;
- `actions/checkout@v4`, `ref: main`, and `fetch-depth: 0`;
- `token: ${{ secrets.HOMEBREW_TAP_TOKEN }}` on checkout so the tag push emits
  the downstream workflow event;
- an explicit `git fetch origin main --tags`;
- a resolver step writing to `$GITHUB_OUTPUT`;
- a conditional tag/push step guarded by
  `steps.beta.outputs.should_tag == 'true'`;
- a lightweight tag, matching the repository's existing release tags.

The workflow must tag the resolver's `candidate_sha`, not implicit `HEAD`.

- [ ] **Step 4: Run focused and repository quality proof**

Run:

```bash
bash scripts/verify-release-scripts.sh
actionlint .github/workflows/daily-beta.yml
mise run lint
git diff --check
```

Expected: all exit 0.

- [ ] **Step 5: Commit the workflow slice**

```bash
git add .github/workflows/daily-beta.yml scripts/verify-release-scripts.sh
git commit -m "ci: publish a daily beta at noon Toronto time"
```

### Task 3: Final Integration Proof and PR

**Files:**

- Verify only; no new implementation files.

- [ ] **Step 1: Re-read the spec and inspect the full branch diff**

Confirm every requirement in
`docs/specs/2026-07-29-daily-beta-release/2026-07-29-daily-beta-release.md`
has an implementation and proof anchor. Confirm
`.github/workflows/release.yml` is unchanged.

- [ ] **Step 2: Run final proof from a clean index**

```bash
bash scripts/verify-release-scripts.sh
mise run lint
git diff --check origin/main...HEAD
git status --short
```

Expected: release verification and lint exit 0; diff check is clean; worktree
has no uncommitted files.

- [ ] **Step 3: Push and open a PR**

Push `automation/daily-beta-release` and open a non-draft PR against `main`.
State that it must merge after PR #226. Do not merge until exact-head checks,
comments, threads, and mergeability are verified.
