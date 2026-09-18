# BridgeWeb CI lane flakes — root-cause investigation

Date: 2026-09-17. Read-only. No repo edits, no builds, no test runs, no git-state changes.
Repo: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.issues-perf-again` (branch `fix/ci-reliability`).
Evidence: `…/scratchpad/flake-inventory/real/*.log`, plus current source at working-tree HEAD.

Every claim below is tagged **VERIFIED** (with `file:line` or a log line) or **UNVERIFIED**.

---

## 0. Method note that matters for anyone re-reading these logs

**VERIFIED:** the downloaded logs contain **no real ANSI ESC bytes**. The colour codes are the literal
two-character sequence `^[` followed by `[<n>m`. `sed -E 's/\x1b\[[0-9;]*m//g'` is therefore a **no-op**
on these files. Use `sed -E 's/\^\[\[[0-9;]*m//g'`. Confirmed by observing surviving `^[[31m` markers in
the output of the suggested command, and independently by a byte scan (0 occurrences of `0x1b`,
~2 560 occurrences of literal `^[` per file).

Also **VERIFIED:** GitHub interleaves the `##[error]` annotation block with the vitest summary block, so
consecutive lines in these transcripts are *not* in causal order (see the `34588581240` timeout block,
where `Test Files`/`Tests`/`Duration` lines are woven between source-frame lines). Read by content, not
by adjacency.

---

## 1. Headline

Eight investigated failures, **five distinct root causes**, only one of which is a budget problem.

| # | Family | Test | Root-cause class | Budget or defect |
|---|---|---|---|---|
| A1 | validation / browser | `preserves All membership but disables output until viewed projection convergence` (×2, 60 000 ms) | unbounded, uncaught `animation.finished` await in a test helper; no inner diagnostic survives | **defect (missing join)** |
| A2 | validation / browser | same test (×1, locator) | 1 000 ms *undeclared* `expect.poll` default standing in for a real convergence join | **defect (insufficient join)** |
| A3 | validation / browser | `orders nonzero New and Pending counts and reveals their exact messages` | base-ui `CollapsiblePanel` `flushSync` landing outside `act()`; `IS_REACT_ACT_ENVIRONMENT` pinned true for the whole run turns it into a hard failure | **defect (unawaited state update)** |
| B1 | Swift backend / E2E | `keeps a committed File comment visible through projection handoff and reload` | the `source.refresh` annotation command response never arrives on the File surface; 120 s vs ~1 s normal | **defect (ordering), not budget** |
| B2 | Swift backend / E2E | `paints complete final File bytes after deep scroll…` | painted correlation declares a different `observedSha256` than the fixture's file | **genuine content-identity defect** |
| C | Swift backend / integration | `opens typed File data and drains every verifier-owned metadata stream` | the test deliberately opens a **second** `reason:'initial'` bootstrap while the first session is open; 409 is the host's retirement-barrier race | **defect (contract mismatch)** |
| D | — | two "unclassified" logs | **not failures.** Attempt-2 (green) transcripts fetched against attempt-1 failing job IDs | **inventory artifact** |

The single most under-appreciated cross-cutting fact: **the browser lane's real fragile budget is not
`testTimeout: 60_000`. It is the undeclared vitest `expect.poll` default of 1 000 ms**, which governs
every `expect.element(...)` and `expect.poll(...)` in 89 browser test files. The workflow comment about
load-dependent timeouts points at the wrong knob.

---

## 2. Family A — BridgeWeb validation, browser integration lane

### 2.1 The workflow comment the brief asked about

**VERIFIED** — `.github/workflows/ci.yml:126-135`:

```yaml
      - name: Run BridgeWeb lanes
        run: |
          # Keep the CPU-heavy unit lane separate from browser integration/E2E.
          # They already run concurrently with the code-quality and Swift test jobs; sharing
          # this runner causes Vitest's per-test timeout to become load-dependent.
          pnpm --dir BridgeWeb run check
          pnpm --dir BridgeWeb run test:unit
          pnpm --dir BridgeWeb run test:browser:integration
          pnpm --dir BridgeWeb run build
          test -f Sources/AgentStudio/Resources/BridgeWeb/app/index.html
```

**What it did (VERIFIED):** introduced by `f1bfedc28 ci: shorten PR gate critical path (#234)`. That
commit created the `bridge-web-validation` job (`ci.yml:98-100`, `runs-on: macos-26`), lifting BridgeWeb
lanes off the Swift job onto their own runner, and replaced `mise run bridge-web-*` with direct `pnpm`
invocations. At that commit the step also ran `test:integration` and `test:e2e`; those have since moved
to the third job `bridge-web-swift-backend` (`ci.yml:137`, steps at `:252` and `:255`).

The "separation" the comment claims is **temporal, inside one job**: the lanes are four sequential shell
commands rather than one `pnpm test` that would overlap them. That mitigation is real and still in force.

**Three gaps the comment leaves open:**

1. **VERIFIED — intra-lane concurrency is untouched.** `vitest.browser.config.ts:41` sets
   `maxWorkers: '50%'`. `test:browser:integration` therefore runs several browser test files
   concurrently, each driving a real Chrome page, on the one runner. The comment addresses lane-to-lane
   overlap and says nothing about this. (Runner core count: **UNVERIFIED**.)
2. **VERIFIED — the named knob is not the fragile one.** `vitest.browser.config.ts:68` is
   `testTimeout: 60_000`. There is **no** `expect.poll` override in any BridgeWeb vitest config, so
   vitest 4.1.10's defaults apply: `interval = 50`, `timeout = 1e3`
   (`node_modules/.pnpm/vitest@4.1.10…/vitest/dist/chunks/test.DNmyFkvJ.js:3714`). Every
   `await expect.element(...)` in the browser suite has a **one-second** budget on a runner whose
   sibling tests routinely take 600-1 200 ms each (e.g. `34764766262-103743666617.log:1373-1378`,
   passing tests at 931/607/766/696/800/816 ms).
3. **VERIFIED — the stated reason is partly wrong.** GitHub-hosted jobs each get their own runner VM, so
   `bridge-web-validation` does **not** share a machine with `code-quality` or `swift-test-suite`. The
   sentence "They already run concurrently with the code-quality and Swift test jobs; sharing this
   runner…" conflates job-level and step-level sharing. The mitigation is still correct; the rationale
   recorded next to it is not, which is why nobody has revisited `maxWorkers`.

### 2.2 A1 — `preserves All membership…` timing out at 60 000 ms (2 runs)

**Occurrences (VERIFIED):**

| Run · log line | Date / branch | Signature | Reported duration |
|---|---|---|---|
| `34588581240-103228380516.log:1068,1339-1341` | 2026-09-11 feat/zmx-update | `Error: Test timed out in 60000ms.` | 60 305 ms |
| `34638380829-103391776788.log:1062,1325-1327` | 2026-09-11 feat/zmx-update | same | 60 318 ms |

Both stacks resolve only to the `test(...)` **registration** line
(`…share-surface.browser.test.tsx:201:1` at that commit), i.e. vitest could not attribute the hang to an
inner frame. Suite name at that commit was `worktree annotation Share comments integrated surface`; at
HEAD it is `worktree annotation Annotations integrated surface`
(`src/worktree-annotations/worktree-annotation-share-surface.browser.test.tsx:70`). Same file, same test.

**Root cause (VERIFIED, mechanism; UNVERIFIED, which await):** the test body contains exactly one wait
with **no timeout, no iteration cap and no rejection handling**:

`src/worktree-annotations/worktree-annotation-share-browser-test-support.ts:69-72`

```ts
export async function waitForShareShelfOpeningMotion(shelf: HTMLElement): Promise<void> {
	await expect.poll(() => shelf.hasAttribute('data-starting-style')).toBe(false);   // 1 000 ms default
	await Promise.all(shelf.getAnimations().map((animation) => animation.finished));  // unbounded, uncaught
}
```

Called from the failing test at `…share-surface.browser.test.tsx:245-247`, i.e. *before* the step that
fails in the third run.

The decisive comparison is the sibling helper written for the same problem in the same package,
`src/worktree-annotations/worktree-annotation-thread.browser.test-support.tsx:180-208`:

```ts
	await act(async (): Promise<void> => {
		await Promise.all(
			panel.getAnimations({ subtree: true }).map(async (animation): Promise<void> => {
				try { await animation.finished; }
				catch { /* Reversing an in-flight transition cancels its predecessor. */ }
			}),
		);
		// Base UI probes animations on a later frame, then clears its measured
		// dimensions in flushSync. Visual completion alone does not join that update.
		await new Promise<void>((resolve): void => { /* MutationObserver on the panel */ });
	});
```

That helper (a) catches the cancel-rejection, (b) wraps the await in `act`, and (c) joins base-ui's
*later* `flushSync` through a `MutationObserver`. `waitForShareShelfOpeningMotion` does none of the
three. It is the older, less careful version of the same idea, and it is the only unbounded await on the
failing path. When the shelf's opening transition is interrupted or never reaches `finished`, the test
hangs to the 60 s wall with no inner frame — which is exactly the observed signature.

**Ruled out with evidence (so nobody re-derives it):**
- **Chromium background-tab throttling of rAF / CSS animations — NO. VERIFIED.** Playwright 1.61.0's
  default chromium switches already include `--disable-background-timer-throttling`,
  `--disable-backgrounding-occluded-windows` and `--disable-renderer-backgrounding`
  (`node_modules/.pnpm/playwright-core@1.61.0/…/lib/coreBundle.js:34433-34459`). Concurrent pages under
  `maxWorkers: '50%'` are not throttled; they are merely CPU-contended. CPU contention delays rAF ticks
  but does not stop a time-driven CSS transition from reaching `finished` inside 60 s, so starvation
  alone does not explain a 60 s hang. A **never-settling or cancelled** animation does.

**UNVERIFIED:** which of `waitForShareShelfOpeningMotion` vs one of the `await act(...)` blocks actually
hung. The test currently cannot tell us — see §5 F-A1.

### 2.3 A2 — `VitestBrowserElementError: Cannot find element with locator: page.getByRole('region', { name: 'Share comments' })`

**Occurrence (VERIFIED):** `34665779346-103477245478.log:1336-1344, 1381`, 2026-09-12, branch `main`.
Failure site `…share-surface.browser.test.tsx:250:81`, `Caused by: Error: Matcher did not succeed in time.`
Test-file summary `1 failed | 87 passed | 1 skipped (89)`; whole run `Duration 212.06s`.

**What that region is (VERIFIED):** `src/worktree-annotations/worktree-annotation-share-mode.tsx:86-89`
renders `<section aria-label="Annotations" … data-testid="worktree-annotation-share-mode">`. A `<section>`
with an accessible name has the implicit ARIA role `region`. At the failing commit the label was
`Share comments`; HEAD line 250 now reads `getByRole('region', { name: 'Annotations' })` — the label was
renamed, the assertion is otherwise unchanged. The section lives inside the drawer, so the assertion is
"the Annotations shelf is still open after an incoming viewed command".

**The awaited step and its budget (VERIFIED):**

```ts
248		expect(viewedControl.current).not.toBeNull();
249		await performBrowserAction(() => viewedControl.current?.markViewed());
250		await expect.element(rendered.getByRole('region', { name: 'Annotations' })).toBeVisible();
```

`performBrowserAction` (`…share-browser-test-support.ts:56-61`) is `act(async () => { await action(); await settleInteraction(); })`, and `settleInteraction` (`:63-67`) is
`Promise.resolve → one requestAnimationFrame → Promise.resolve`. So the only join between dispatching a
viewed command and asserting the drawer state is **one animation frame**. Line 250 then polls for
**1 000 ms** (vitest default, §2.1 gap 2).

`markViewed` (`worktree-annotation-viewed-command.test-support.tsx:20-27`) fires
`viewedController.markMessagesViewed(sessionId, messages)` — an async surface operation whose completion
the test never joins. Its own comment says the control exists to "Model an incoming viewed command
without generating an outside press that legitimately dismisses the Share drawer", i.e. the author was
already fighting drawer dismissal on this exact path.

**Root cause:** a fixed-shape wait (one rAF) plus a 1 000 ms poll standing in for an unjoined async
projection round-trip and a base-ui drawer transition. Load-dependent by construction.

**UNVERIFIED:** whether the drawer had actually *closed* at that moment or was merely not yet
re-rendered. The printed DOM is the truncated Playwright form
(`<header … />`, `<section … />`, trailing `...`), so absence cannot be read off it. Note the
`<div data-base-ui-inert="" hidden="">` with two buttons in that dump is the fixture's own
`OverlayCommandTestControl` (`…share-surface.browser.test.tsx:719-727` renders `<div hidden>` with
buttons) — **not** evidence of an unmounted shelf. The failure screenshot referenced at
`34665779346-103477245478.log:1344` would settle it and is not in this inventory.

Candidate dismissal paths worth checking when someone fixes this, both **UNVERIFIED**:
`worktree-annotation-output-controls.tsx:65-71` closes the share mode from a `useLayoutEffect` on any new
`navigation.request.requestId`; and the drawer is `modal={false}` (`:83`) with `autoFocus` on the Pending
toggle item (`worktree-annotation-share-mode.tsx:123`), so a focus move during the viewed re-render could
trigger base-ui dismiss-on-focus-out.

### 2.4 A3 — `orders nonzero New and Pending counts…` with `act(...)` warnings

**Occurrence (VERIFIED):** `34764766262-103743666617.log:1052, 1379-1390`, 2026-09-13.
File `src/worktree-annotations/worktree-annotation-thread.browser.test.tsx`, test at `:541`.

**This is not a timeout and not an assertion. VERIFIED:**
- The test's own reported duration is **955 ms** (`:1052`) — the body completed.
- The thrown error is `Bridge viewer browser test failure guard tripped:` raised at
  `tests/vitest-browser-setup.ts:54:8` — i.e. in the **global `afterEach`**, not from any `expect`.
- The captured message is React's `An update to %s inside a test was not wrapped in act(...)`, naming
  component **`CollapsiblePanel`**.

**Mechanism (VERIFIED):**

1. `tests/vitest-browser-setup.ts:19-28` pins `IS_REACT_ACT_ENVIRONMENT` to `true` for the entire browser
   run by intercepting writes. Consequence: React emits the act warning for **any** state update that
   lands outside an `act()` scope, for the whole file, for the whole run.
2. `tests/vitest-browser-setup.ts:60-68` replaces `console.error` and pushes every non-allowlisted message
   into `browserFailureMessages`; `:53-57` throws if that array is non-empty at `afterEach`. So one stray
   async state update is a hard test failure.
3. `CollapsiblePanel` is `@base-ui/react@1.6.0`'s collapsible Panel
   (`src/components/ui/collapsible.tsx:3,47`), used by the thread history panel
   (`src/worktree-annotations/worktree-annotation-compact-thread.tsx:454-513`).
4. base-ui schedules panel state updates from **non-React async sources**:
   `node_modules/@base-ui/react/internals/useAnimationsFinished.js:37-53` does
   `Promise.all(el.getAnimations().map(a => a.finished)).then(() => ReactDOM.flushSync(fnToExecute))`,
   driving `onComplete() { setDimensions(EMPTY_DIMENSIONS, false) }` at
   `collapsible/panel/useCollapsiblePanel.js:220-231`; plus a rAF-deferred closing path at `:238-265`
   (`AnimationFrame.request(...)` → `runOnceCloseAnimationsFinish` → `setMounted(false)` +
   `setDimensions(...)`), and `AnimationFrame.request(restoreLayoutStyles)` at `:385`. The closing path is
   constructed with `treatAbortedAsFinished = false` (`:65`), so an aborted animation makes
   `useAnimationsFinished` **re-arm `exec()`**, pushing the `flushSync` to an arbitrarily later frame.
5. Corroboration that this family is already known here: `tests/vitest-browser-setup.ts:30-32` allowlists
   exactly one console error — `'flushSync was called from inside a lifecycle method'` — base-ui's other
   escaping-`flushSync` symptom. The act warning is the same family and is **not** allowlisted.

**Why load-dependent:** the test's own join (`settleThreadMotion`,
`…thread.browser.test-support.tsx:168-209`) is genuinely event-based and normally absorbs the opening
`flushSync` inside `act`. It resolves on `--collapsible-panel-height: auto` via `MutationObserver`. A
later base-ui frame callback — the re-armed `exec()`, or the closing path during the file-local
`afterEach` cleanup — lands after that observer resolved and outside every `act` scope. The test then
does `await page.screenshot(...)` (`…thread.browser.test.tsx:592`), a long yield to the browser with no
act scope open, which widens the window.

**UNVERIFIED:** which specific base-ui deferred update escaped. The guard records the message but not a
stack into base-ui, and it is thrown from `afterEach`, so the attribution to *this* test is itself only
"the test that was current when `console.error` fired" — `browserFailureMessages` is reset in `beforeEach`
(`:40`) and drained in `afterEach` (`:53`), which cannot distinguish this test's own late update from a
previous test's.

---

## 3. Family B — BridgeWeb Swift backend E2E

### 3.1 B1 — `annotation.e2e` 180 000 ms timeout

**Occurrence (VERIFIED):** `34665779346-103477245350.log:5451-5525`, 2026-09-12, branch `main`,
step `Test BridgeWeb Swift E2E` (lane `test:e2e:prepared:ordinary`).
File-level line: `❯ tests/e2e/bridge-viewer-vite-annotation.e2e.test.tsx (2 tests | 1 failed) 352684ms`.
Failing case: `× keeps a committed File comment visible through projection handoff and reload 304803ms (retry x1)`.
Its Review sibling **passed in 46 818 ms** in the same file, same run (`:5453`).

Two attempts, two different signatures:

- **[1/2]** `Error: Test timed out in 180000ms.` — stack resolves only to the `test.each` registration
  (`…annotation.e2e.test.tsx:38:13`). No inner frame.
- **[2/2]**
  `Error: Annotation Save journey failed: cause={"kind":"TimeoutError","message":"page.waitForResponse: Timeout 120000ms exceeded while waiting for event \"response\""}`
  thrown at `tests/e2e/bridge-viewer-vite-annotation-save-journey.ts:416:9`, caused by
  `waitForCommittedAnnotationCommand` at `…save-journey.ts:727:30`, created at `…save-journey.ts:220:7`.

**The failing phase (VERIFIED):** `…save-journey.ts:218-221` is the **`source.refresh`** waiter, File
surface only:

```ts
218		const sourceRefreshCommitted =
219			props.surface === 'file'
220				? waitForCommittedAnnotationCommand(page, 'source.refresh', 'file')
221				: null;
```

`waitForCommittedAnnotationCommand` (`…save-journey.ts:721-726`) is
`page.waitForResponse(candidate => isAnnotationCommandResponse(candidate, operationKind, surface), { timeout: annotationSaveJourneyTimeoutMilliseconds })`,
and `annotationSaveJourneyTimeoutMilliseconds = 120_000` (`…save-journey.ts:48`).

**Is it a budget?  No. VERIFIED.** The waiter is installed at line 220, in the same synchronous block as
the `root.create` waiter at `:213-217`, and both are awaited later at `:238-239` — so no listener is
installed after its own action, and `root.create` did resolve (the rejection is attributed to the `:220`
waiter, not the `:213` one). 120 000 ms is ~120× the normal latency of this command; the passing Review
variant of the same `test.each` completed its whole journey in 46 818 ms. The awaited event simply never
happened.

The `browser=[...]` diagnostic in the same record shows traffic was flowing throughout
(`response:/__bridge-product/command:204:stream.frameObserved:-:-:-`,
`response:/__bridge-product/command:200:subscription.open:-:-:7`, …), so this is not a dead transport.

**Verdict:** genuine ordering/emission defect on the File surface — the committed `source.refresh`
command response the journey requires did not occur. Not a timing budget.

**Second, independent finding in the same record (VERIFIED):**
`Vitest caught 2 unhandled errors during the test run. This might cause false positive tests.`
One is `AssertionError: expected false to be true // Object.is equality` from
`waitForDemandedAnnotationProjectionContent` at
`tests/e2e/bridge-viewer-vite-annotation-projection-test-support.ts:187:5` — an `expect.poll` with
`timeout: annotationProjectionResponseTimeoutMilliseconds` (30 000,
`…annotation-projection-test-support.ts:4`) whose rejection landed **after** the test had already failed.
It is created at `…save-journey.ts:222-230` from promises derived from `sourceRefreshCommitted`, so when
`source.refresh` never lands, that poll is orphaned and rejects into the runner. Vitest's own warning is
correct: this can corrupt neighbouring results.

### 3.2 B2 — `product.e2e` deep-scroll `AssertionError`

**Occurrence (VERIFIED):** `34717790889-103618023338.log:42, 115-176`, 2026-09-12, step
`Test BridgeWeb Swift E2E`.
`× paints complete final File bytes after deep scroll with descriptor, role, request, source, and disposition correlation 128536ms (retry x1)`.
File-level: `1 failed | 14 passed (15)`, `Tests 1 failed | 25 passed (26)`, `Duration 993.83s`.

Two attempts:

- **[1/2]** `TimeoutError: page.waitForFunction: Timeout 120000ms exceeded.` at
  `waitForSelectedFileContentReady` (`tests/e2e/bridge-viewer-vite-product.e2e.test.tsx:505:19`) called
  from `:303:10`. `Serialized Error: { log: [] }`. Line 303 is the readiness wait for the **mutated**
  large file after `fixture.mutateLargeFile()` (`:300`) and `page.reload()` (`:301-303`).
  `waitForSelectedFileContentReady` (`:522-535`) is a `page.waitForFunction` predicate over
  `expectedLineCount`, `expectedSha256` and `path`, read from the
  `diffs-container[data-bridge-painted-source-correlations]` attribute inside
  `[data-testid="bridge-file-viewer-code-canvas"]`.
- **[2/2]** `AssertionError: expected [ { …(13) } ] to deeply equal [ ObjectContaining{…} ]` at
  `…product.e2e.test.tsx:262:54`.

**Expected vs received, verbatim (VERIFIED, `34717790889-103618023338.log:131-155`):**

```
- Expected
+ Received

@@ -1,11 +1,12 @@
  [
    {
      "descriptorId": "file-content-ebcd60efa9637dbccae0f0e4b3997936",
      "disposition": "painted",
      "itemId": "worktree-file-375bbee16afff4d9e59f782fbc432895",
-     "observedSha256": "00c066f84ada317d55614b9c379e4bd2e5923f994fca1837d952cbe806e4014e",
+     "observedSha256": "659fd932bf39e4343bf7b625d42816c843ae78b68611b0aec589c587f6ee7ee6",
+     "pierreItemId": "file:worktree-file-375bbee16afff4d9e59f782fbc432895",
      "position": "whole",
      "publicationId": "publication-3bc3dd64-9c49-446e-9a40-7aa79eaa4815",
      "requestId": "content-request-dcd5985c-0c07-4679-8f17-ac50bcfeba3d",
      "role": "file",
      "semanticItemId": "worktree-file-375bbee16afff4d9e59f782fbc432895",
```

**Read this diff correctly — one of the two `+` lines is noise. VERIFIED.** The assertion is
`expect(...).toEqual([expect.objectContaining({ … })])` (`…product.e2e.test.tsx:265-279`), and
`objectContaining` permits extra received keys. `pierreItemId` is therefore **not** a failure cause; it is
diff rendering of an unmatched extra property. The **only** real mismatch is `observedSha256`, whose
expected value is the literal `oracle.largeFileSha256` (`…product.e2e.test.tsx:271`).

**Retry contamination ruled out. VERIFIED.** The fixture is created **inside the test body** —
`…product.e2e.test.tsx:215-216`:

```ts
	test('paints complete final File bytes after deep scroll with descriptor, role, request, source, and disposition correlation', async () => {
		const fixture = await createBridgeViewerViteProductFixture();
```

and `createBridgeViewerViteProductFixture` `mkdtemp`s a fresh worktree per call
(`tests/e2e/bridge-viewer-vite-product-fixture.ts:119`). So attempt 2 did **not** inherit attempt 1's
`mutateLargeFile()` side effect (`fixture.ts:351-360`); it started from a pristine large file and still
painted a different hash.

**Verdict:** both attempts say the same thing in two registers — *the painted File content is not the
expected File content*. Attempt 1 expresses it as a 120 s readiness wait that never became true (the
predicate includes `expectedSha256`); attempt 2 expresses it as a hash mismatch on the initial
correlation. This is a genuine content-identity/completeness defect of exactly the kind this test exists
to catch. It is **not** a timing budget, and raising either number would delete the signal.

**UNVERIFIED:** what the `659fd932…` bytes actually are (partial materialisation, a stale descriptor, or
a normalisation difference between the oracle's file hash and the app-declared `observedSha256`). Note
`finalMarkerPainted` was already asserted `true` at `:259` before the mismatch at `:262`, so the final
marker *was* painted — an incomplete-middle or wrong-generation paint fits better than "nothing rendered".
This is adjacent to the known ContentIdentity fault line and deserves a ticket rather than a CI tweak.

---

## 4. Family C — `Bridge product bootstrap failed with status 409`

**Occurrence (VERIFIED):** `34610944088-103300992708.log:28-67`, 2026-09-11, branch `sidebar-new-changes`,
step `Test BridgeWeb Swift integration`.
`× opens typed File data and drains every verifier-owned metadata stream 2757ms`;
`FAIL scripts/verify-bridge-viewer-worktree-dev-server/worktree-data.integration.test.ts > Bridge viewer typed product File worktree data > opens typed File data and drains every verifier-owned metadata stream`;
`Error: Bridge product bootstrap failed with status 409.`; `Test Files 1 failed | 4 passed (5)`;
`Duration 7.48s`.

Stack (VERIFIED, same block):

```
❯ BridgeVerifierProductFileSession.#installServerAuthority scripts/verify-bridge-viewer-worktree-dev-server/product-file-session.ts:447:10
❯ BridgeVerifierProductFileSession.open                    scripts/verify-bridge-viewer-worktree-dev-server/product-file-session.ts:111:3
❯ Module.fetchWorktreeSurface                              scripts/verify-bridge-viewer-worktree-dev-server/worktree-data.ts:47:24
❯                                                          scripts/verify-bridge-viewer-worktree-dev-server/worktree-data.integration.test.ts:186:26
```

### Does this test open a second bootstrap while the first is live? **Yes. VERIFIED.**

`scripts/verify-bridge-viewer-worktree-dev-server/worktree-data.integration.test.ts:185-192`:

```ts
185			const surface = await worktreeData.fetchWorktreeSurface();
186			const secondSurface = await worktreeData.fetchWorktreeSurface();
187			const descriptor = await worktreeData.fetchFetchableWorktreeFileDescriptorForPath({ … });
190			const content = await worktreeData.fetchWorktreeFileContent(descriptor);
192			await worktreeData.closeAllWorktreeFileSurfaces();
```

The failing frame is **line 186 — the second bootstrap** — and the first surface is not closed until
line 192. The test's assertions (`:199-201`) require `observedMetadataStreamCloseCount === 2` and
`openWorktreeFileSurfaceCount() === 0`, so two simultaneously-open File surfaces are the *intent*.

Every bootstrap the verifier sends is unconditionally `reason: 'initial'` —
`scripts/verify-bridge-viewer-worktree-dev-server/product-file-session.ts:437-447`:

```ts
	async #installServerAuthority(): Promise<void> {
		const response = await fetch(this.#endpoint(BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE), {
			body: JSON.stringify({
				navigationIntent: { commandId: 'verifier-file-context', commandKind: 'activateContext', surface: 'file' },
				reason: 'initial',
			} satisfies BridgeProductDevBootstrapRequest),
			…
		});
		if (response.status !== 200 || response.headers.get('content-type') !== …) {
			throw new Error(`Bridge product bootstrap failed with status ${response.status}.`);
		}
```

### The host side matches the brief's stated mechanism. **VERIFIED.**

`Sources/AgentStudio/Features/Bridge/Runtime/Development/BridgeDevelopmentProductHost.swift:848-870`:

```swift
        case .initial:
            if let installation = await productSessionOwner.activeInstallation {
                guard let retirementBarriers = await installation.session
                        .metadataRetirementBarriersForReload()
                else { throw BridgeDevelopmentProductHostError.sessionAlreadyOpen }   // :858
                for retirementBarrier in retirementBarriers {
                    guard await retirementBarrier.wait() else {
                        throw BridgeDevelopmentProductHostError.sessionAlreadyOpen     // :862
                    }
                    try Task.checkCancellation()
                }
                guard await installation.session.metadataRetirementBarriersForReload()?.isEmpty == true
                else { throw BridgeDevelopmentProductHostError.sessionAlreadyOpen }   // :870
            }
```

Three separate paths to `sessionAlreadyOpen` → 409, all of them decided by whether the *previous*
session's metadata producer has reached a retirement barrier at the moment the second `initial` arrives.
Stream end reaching the host is asynchronous, so the outcome is a race: usually the first session's
producer has already published its barrier set and the second `initial` is admitted; occasionally it has
not, and the second `initial` is refused.

### What BridgeWeb does on 409. **VERIFIED — terminal, as the brief stated.**

`BridgeWeb/src/app/bridge-app-dev-product-session-host.ts:282-285`:

```ts
	if (response.status === 409) {
		await response.body?.cancel();
		throw new BridgeDevelopmentSessionInUseError('This dev server is open elsewhere.');
	}
```

No retry, no distinction between "another browser tab owns this dev server" and "the previous session in
*this* process has not finished retiring yet". The verifier (`product-file-session.ts:447`) is even
blunter: it collapses every non-200 into one untyped `Error` string, which is why the CI record carries no
host-side reason.

**Root cause:** a contract mismatch, not a flake. The verifier asserts that two File surfaces may be open
at once, while `reason: .initial` is defined by the host as "no other session is open, or the open one has
already reached retirement". The integration test is racing a barrier the protocol gives it no way to wait
on. **UNVERIFIED:** whether the intended second-surface bootstrap reason is `.workerReplacement`
(`…ProductHost.swift:872-880`) or whether the host should admit a concurrent File surface outright — that
is an ownership decision.

---

## 5. Family D — the two "unclassified" logs

**They are not failures. VERIFIED, with the mechanism.**

- `34651876564-103435665063.log` and `34796189300-103829643194.log` are complete `BridgeWeb Swift backend`
  transcripts in which **every** vitest lane passed: integration `5 passed (5)` / `25 passed (25)`; E2E
  stress `1 passed (1)`; E2E ordinary `15 passed (15)` / `26 passed (26)`. No `FAIL`, no `##[error]`, no
  non-zero exit, no cancellation; the only warning is the Node 20 deprecation notice.
- Both parent runs are `conclusion: success` in `flake-inventory/01-runs-list.json`
  (`34651876564`, branch `feat/zmx-update`, 2026-09-11; `34796189300`, branch
  `fix/panes-sidebar-recent-activity`, 2026-09-14).
- The inventory's own scripts explain the contradiction. `02-fetch-failed-jobs.sh:27-29` lists exactly
  these two runs under `RUNS_WITH_ATTEMPTS` with the comment `# attempt 2, success (check earlier
  attempts)`, and `:43-48` fetches **attempt 1**'s failing job IDs. Then `03-fetch-logs.sh:36` downloads
  the log with `gh run view "$run_id" --job "$job_id"` — **without `--attempt`** — so `gh` resolved the
  log against the latest attempt (2, green). Corroborated by the log timestamps: run `34651876564` was
  created at `2026-09-11T21:58Z` but its transcript runs `22:52 → 23:11`.

**Action:** re-fetch with `--attempt 1` if the attempt-1 failures are still wanted. Until then these two
rows should be removed from the flake inventory; they currently inflate the BridgeWeb failure count by two.

---

## 6. Family E — cross-cutting budgets and non-event waits

### 6.1 Every retry / timeout / budget governing these lanes

| `file:line` | Value | Governs |
|---|---|---|
| `.github/workflows/ci.yml:98-100` | job `bridge-web-validation`, `runs-on: macos-26` | check + unit + browser-integration + build |
| `.github/workflows/ci.yml:126-135` | sequential shell steps | the "load-dependent" separation (§2.1) |
| `.github/workflows/ci.yml:137,252,255` | job `bridge-web-swift-backend` | `test:integration:node:prepared`, `test:e2e:prepared` |
| *(no `timeout-minutes` on any BridgeWeb job)* | GitHub default 360 min | job wall clock. Only `release.yml:19` (45) and `daily-beta.yml:20` (5) set one anywhere in the repo |
| `BridgeWeb/vitest.config.ts` | *no* `testTimeout` / `retry` / worker overrides | unit lane runs on vitest defaults |
| `BridgeWeb/vitest.browser.config.ts:41` | `maxWorkers: '50%'` | concurrent browser test files on one runner |
| `BridgeWeb/vitest.browser.config.ts:16` | `headless: true` | Playwright provider |
| `BridgeWeb/vitest.browser.config.ts:15-17` | `playwright({ launchOptions: { channel: 'chrome' } })` | real Chrome channel |
| `BridgeWeb/vitest.browser.config.ts:21-23`, `:99-101` | `api.port` 63325 / 63326 | fixed ports, integration vs benchmark project |
| `BridgeWeb/vitest.browser.config.ts:24-27` | viewport 1728×972 | both browser projects |
| `BridgeWeb/vitest.browser.config.ts:68` | `testTimeout: 60_000` | **the 60 s in A1** |
| `BridgeWeb/vitest.browser.config.ts` | *no* `retry`, `hookTimeout`, `expect.poll` | defaults apply |
| `vitest@4.1.10/dist/chunks/test.DNmyFkvJ.js:3714` | `interval = 50`, `timeout = 1e3` | **the 1 000 ms in A2** — every `expect.element`/`expect.poll` in the browser suite |
| `BridgeWeb/vitest.integration.config.ts:20` | `fileParallelism: false` | shared Swift product-session authority |
| `BridgeWeb/vitest.integration.config.ts` | *no* `testTimeout` | integration lane on vitest default |
| `BridgeWeb/vitest.e2e.config.ts:6` | `fileParallelism: false` | one dev server |
| `BridgeWeb/vitest.e2e.config.ts:13` | `testTimeout: 180_000` | **the 180 s in B1** |
| `BridgeWeb/vitest.e2e.config.ts:14` | `hookTimeout: 60_000` | E2E hooks |
| `BridgeWeb/vitest.e2e.config.ts:17` | `retry: 1` | **the `(retry x1)` in B1 and B2**; comment at `:15-16` calls it "tolerating the known intermittent" |
| `tests/e2e/bridge-viewer-vite-annotation-save-journey.ts:48` | 120 000 | `annotationSaveJourneyTimeoutMilliseconds` — **the 120 s in B1** |
| `tests/e2e/bridge-viewer-vite-annotation-save-journey.ts:49` | 30 000 | `annotationProjectionResponseTimeoutMilliseconds` |
| `tests/e2e/bridge-viewer-vite-annotation-projection-test-support.ts:4` | 30 000 | the orphaned poll in B1 |
| `tests/e2e/bridge-viewer-vite-product.e2e.test.tsx:35` | 120 000 | `productJourneyTimeoutMilliseconds` — **the 120 s in B2 attempt 1** |
| `scripts/verify-bridge-viewer-worktree-dev-server/worktree-data.integration.test.ts:24` | 60 000 | `worktreeDataDeadlockGuardMilliseconds` — the C test's own cap |
| `scripts/dev-server/bridge-development-server-process.ts:10,11,12` | 120 000 / 10 000 / 50 | Swift backend startup, shutdown, readiness poll |
| `tests/e2e/bridge-viewer-vite-product-fixture.ts:20,21` | 30 000 / 10 000 | Vite readiness, shutdown |
| `tests/e2e/bridge-viewer-vite-annotation-backpressure-journey.ts:61-67` | 600 000 / 540 000 / 120 000 / 119 000 / 30 000 / 30 000 / 5 000 | stress lane (already diagnosed separately) |
| `src/app/bridge-app-dev-product-session-host.ts:36` | 250 | dev health probe interval |

A further ~30 module-level `*TimeoutMilliseconds` constants exist across `tests/`, `scripts/` and
`src/core/comm-worker/`; the ones above are the only ones on the failing paths. Playwright has **no**
`playwright.config.*` in BridgeWeb — `chromium.launch` is duplicated across 20 files, with two
inconsistent shapes (`{ channel: 'chrome', headless: true }` in E2E journeys vs `{ headless: true }` in
`scripts/verify-bridge-viewer-dev-server.ts:54`, `scripts/capture-bridge-viewer-dev-visual-proof.ts:88`
and `scripts/verify-bridge-viewer-worktree-dev-server/runner.ts:133,180,219`, which silently use
Playwright's bundled Chromium instead of the pinned channel) and two viewports (1728×980 vs 1728×972
with `deviceScaleFactor: 2`).

### 6.2 Top 20 files by polling / fixed-time wait count

| # | File (under `BridgeWeb/`) | Total | Breakdown |
|---|---|---|---|
| 1 | `src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx` | 29 | `expect.poll` ×29 |
| 2 | `tests/e2e/bridge-viewer-vite-annotation-save-journey.ts` | 17 | `waitFor(` ×10, `waitForFunction` ×3, `waitForResponse` ×2, `waitForRequest` ×1, `rAF` ×1 |
| 3 | `tests/e2e/bridge-viewer-vite-annotation-restart-journey.ts` | 15 | `waitFor(` ×10, `waitForFunction` ×4, `waitForResponse` ×1 |
| 4 | `scripts/verify-bridge-viewer-dev-server/page-harness.ts` | 14 | `waitForFunction` ×13, `rAF` ×1 |
| 5= | `src/review-viewer/test-support/bridge-viewer-browser.integration-large.browser.test.tsx` | 11 | `expect.poll` ×11 |
| 5= | `scripts/verify-bridge-viewer-worktree-dev-server/review-tree-click.ts` | 11 | `waitForFunction` ×6, `rAF` ×5 |
| 5= | `scripts/capture-bridge-viewer-dev-visual-proof.ts` | 11 | `waitForFunction` ×8, **`page.waitForTimeout` ×3** |
| 8= | `src/core/comm-worker/bridge-main-review-publication-recovery.unit.test.ts` | 10 | `waitFor(` ×5, `vi.waitFor` ×5 |
| 8= | `src/core/comm-worker/bridge-comm-worker-duplex-backpressure.integration.test.ts` | 10 | `waitFor(` ×10 |
| 10 | `tests/e2e/bridge-viewer-vite-annotation-output-capture.ts` | 9 | `waitFor(` ×7, `waitForResponse` ×2 |
| 11= | `tests/e2e/bridge-viewer-vite-worker-recovery.e2e.test.ts` | 8 | `waitFor(` ×3, `waitForResponse` ×5 |
| 11= | `tests/e2e/bridge-viewer-vite-annotation-edit-reopen.e2e.test.ts` | 8 | `waitFor(` ×6, `waitForFunction` ×1, `waitForResponse` ×1 |
| 11= | `tests/e2e/bridge-viewer-vite-annotation-backpressure-journey.ts` | 8 | `waitFor(` ×6, `waitForFunction` ×1, `setTimeout(` ×1 |
| 11= | `src/file-viewer/bridge-file-viewer-query-lifecycle.browser.test.tsx` | 8 | `expect.poll` ×6, `ResizeObserver` ×2 |
| 11= | `src/components/ui/style-system.browser.test.tsx` | 8 | `.finished` ×5, `rAF` ×2, `MutationObserver` ×1 |
| 11= | `src/app/bridge-app-dev-product-session-host.unit.test.ts` | 8 | `waitFor(` ×4, `vi.waitFor` ×4 |
| 11= | `scripts/verify-bridge-viewer-worktree-dev-server/complete-journey-collector.ts` | 8 | `waitForFunction` ×6, `rAF` ×2 |
| 18= | `tests/e2e/bridge-viewer-vite-product.e2e.test.tsx` | 7 | `waitForFunction` ×7 |
| 18= | `tests/e2e/bridge-viewer-vite-git-status-filters.e2e.test.ts` | 7 | `waitFor(` ×4, `waitForFunction` ×3 |
| 18= | `src/review-viewer/test-support/bridge-viewer-browser.integration-scroll.browser.test.tsx` | 7 | `expect.poll` ×7 |

`waitFor(` counts vitest `waitFor`/`expect.element` and Playwright locator `.waitFor(...)` together —
they share the literal. `node_modules` excluded throughout.

### 6.3 Unbounded waits — no timeout, no iteration cap

This is the highest-value part of the inventory: each of these hangs to the *outer* runner timeout with
no diagnostic, which is precisely the A1 signature.

| `file:line` | Shape |
|---|---|
| **`src/worktree-annotations/worktree-annotation-share-browser-test-support.ts:71`** | `await Promise.all(shelf.getAnimations().map(a => a.finished))` — **the A1 path**; uncaught *and* unbounded |
| **`src/worktree-annotations/worktree-annotation-thread.browser.test-support.tsx:173-178`** | `while (panel.isConnected && panel.hasAttribute('data-starting-style')) { await act(rAF) }` — unbounded retry loop; every sibling `settleBrowserCondition` in the same package uses `remainingFrames = 60` |
| `src/app/bridge-viewer-ui-journey.browser.test.tsx:332` | `Promise.all(el.getAnimations({subtree:true}).map(a => a.finished))` |
| `src/app/bridge-review-header-panels.browser.test.tsx:509` | same, on the drawer |
| `src/app/bridge-app-review-render-snapshot-controller.browser.test.tsx:513-515` | same, on canvas + tree |
| `src/app/bridge-viewer-view-settings-menu.browser.test.tsx:388-390` | same, on the menu |
| `src/components/ui/component-language.browser.test.tsx:101` | same |
| `src/components/ui/style-system.browser.test.tsx:213-216, 258-259, 276-277, 286-287, 412` | same, five sites |
| `src/worktree-annotations/worktree-annotation-recovery-and-history.browser.test.tsx:280-282` | same (its first step *is* bounded; this second await is not) |
| `src/worktree-annotations/worktree-annotation-admission.browser.test.tsx:86-88` | same, on the popover |
| `src/worktree-annotations/worktree-annotation-thread.browser.test-support.tsx:181-186` | `try/catch` around `.finished` — swallows *rejection*, does not bound a never-settling animation |
| `src/worktree-annotations/worktree-annotation-share-mode.browser.test.tsx:307-313` | same try/catch shape |
| `src/app/bridge-app-file-viewer-mode-reopen.browser.test.tsx:309-315` | same try/catch shape |
| `src/worktree-annotations/worktree-annotation-ui-journey.browser.test-support.tsx:187-190` | `.finished.catch(() => {})` — masks rejection only |

**Bounded by contrast (do not "fix" these):** `bridge-review-header-panels.browser.test.tsx:518-531`,
`bridge-review-comparison-control.browser.test-support.tsx:38-43`,
`worktree-annotation-share-browser-test-support.ts:74-79` and
`worktree-annotation-thread-motion.browser.test.tsx:64` all call `animation.finish()` **before** awaiting
`.finished`, so the awaited promise settles on the same microtask. That is the correct pattern already
present in this repo.

---

## 7. Family F — smallest correct fix per family

Rules honoured throughout: **no raised retry counts, no loosened assertions, no bigger budgets as the
fix.** Nothing below was implemented.

### F-A1 — `worktree-annotation-share-browser-test-support.ts:69-72`

Replace the unbounded animation await with the join that already exists ten files away. Concretely, make
`waitForShareShelfOpeningMotion` mirror `settleThreadMotion`
(`worktree-annotation-thread.browser.test-support.tsx:168-209`): force or bound the animations, catch the
cancel-rejection, and join base-ui's later `flushSync` via the `MutationObserver` rather than assuming
visual completion is state completion. Better still, **delete one of the two helpers** — they solve the
same problem, one correctly.

*Proof strength:* unchanged or increased. The test still proves the shelf opened; it gains the ability to
say *which* step failed instead of dying at the 60 s wall with no frame. This is not a budget change.

### F-A2 — `worktree-annotation-share-surface.browser.test.tsx:249-250`

`performBrowserAction(() => markViewed())` joins one animation frame; the assertion then leans on the
undeclared 1 000 ms `expect.poll` default. Join the actual condition instead: wait on the surface's
viewed-command receipt (the same `settleMostRecentViewed` the test already drives at `:252`) before
asserting the region, so the assertion runs against a settled projection rather than a guessed frame.

Separately, and repo-wide: set an explicit `expect: { poll: { timeout, interval } }` in
`vitest.browser.config.ts`. **Not to raise it** — to stop 89 test files from silently depending on a
library default that nobody chose and that the workflow comment doesn't know about. Making it explicit is
the precondition for reasoning about it at all.

*Proof strength:* unchanged. The assertion is the same; only the thing it waits on becomes real.

### F-A3 — `tests/vitest-browser-setup.ts:45-58` and the base-ui boundary

Two independent moves, both at the owning boundary:

1. **Attribution.** The guard drains `browserFailureMessages` in `afterEach` (`:53`) and resets in
   `beforeEach` (`:40`), so a late async update is blamed on whichever test was current. Capture the
   message *with* a stack at the point `console.error` fires (`:62-68`) and include it in the thrown
   error. Cost: nothing. Benefit: the next occurrence names the base-ui call path instead of just
   `CollapsiblePanel`.
2. **The actual leak.** The panel's deferred `flushSync` needs to be joined by whatever closes the
   interaction, the way `settleThreadMotion` already joins the opening one. The gap is on the *closing*
   and re-armed paths (`useCollapsiblePanel.js:238-265`, `useAnimationsFinished.js:53-64` with
   `treatAbortedAsFinished = false`). The screenshot at `…thread.browser.test.tsx:592` is the widest
   unguarded window and is the place to look first.

**Do not** add the act warning to `allowedConsoleErrorSubstrings` (`:30-32`). That allowlist already
contains one base-ui `flushSync` symptom; adding a second would convert this guard from a real proof gate
into decoration.

### F-B1 — `tests/e2e/bridge-viewer-vite-annotation-save-journey.ts:218-230`

This is a product/ordering question, not a test-harness one: **why does the File surface not emit a
committed `source.refresh` after `root.create`?** That belongs in a ticket with the run record attached,
not in CI configuration.

Two harness-level corrections that cost no proof and would have made this run self-explaining:

- The orphaned `expect.poll` at `…annotation-projection-test-support.ts:187` (reached via
  `…save-journey.ts:222-230`) rejects into the runner after the test has already failed, and Vitest warns
  it "might cause false positive tests". Tie those derived waiters to the same cancellation as their
  antecedent so a failed `sourceRefreshCommitted` abandons rather than orphans them.
- `waitForCommittedAnnotationCommand` (`:721-726`) currently reports only Playwright's generic
  `page.waitForResponse: Timeout 120000ms exceeded`. Since the journey already collects a browser
  transport transcript (visible as `browser=[...]` in the record), attach the observed
  `/__bridge-product/command` responses to *this* rejection so the record says which commands did arrive.

### F-B2 — `tests/e2e/bridge-viewer-vite-product.e2e.test.tsx:262-279`

**Change nothing in the test.** Both attempts agree that the painted correlation's `observedSha256`
disagrees with the fixture's file hash, on a freshly-created fixture. File it as a content-identity
defect. The one harness improvement worth making is in
`waitForSelectedFileContentReady` (`:522-535`): when its predicate times out, report the **observed**
correlations alongside the expected `sha256`/`lineCount`, so attempt 1 produces the same diagnostic
attempt 2 produced by accident. That converts a 120 s silent timeout into the assertion it actually is.

Note also that `retry: 1` (`vitest.e2e.config.ts:17`) is doing real harm here rather than real good: it
doubles a 993 s lane and produces two differently-shaped records for one defect. It is not in scope to
change, but it should be revisited once B1 and B2 are closed.

### F-C — `scripts/verify-bridge-viewer-worktree-dev-server/product-file-session.ts:437-447`

Two questions to settle with the owner before any code moves; this one is **not** unilaterally fixable:

1. Is a second concurrently-open File surface a supported product state? If yes, the second bootstrap
   should not use `reason: 'initial'` — `.workerReplacement`
   (`BridgeDevelopmentProductHost.swift:872-880`) exists for exactly this and does not consult the
   retirement barriers. If no, `worktree-data.integration.test.ts:185-192` is asserting an unsupported
   shape and the test is wrong.
2. Either way, `#installServerAuthority:445-448` should classify the 409 rather than collapse every
   non-200 into one string. The host distinguishes three barrier outcomes
   (`…ProductHost.swift:858, 862, 870`); none of that reaches the CI record today. Same for
   `bridge-app-dev-product-session-host.ts:282-285`, where `'This dev server is open elsewhere.'` is
   actively misleading when the conflicting session is in the *same* process.

*Proof strength:* unchanged. The test keeps asserting two metadata streams close and zero surfaces remain.

### F-D — `flake-inventory/03-fetch-logs.sh:36`

Add `--attempt "$attempt"` to the `gh run view` call. It already carries `$attempt` through
`JOBS_TO_FETCH` (`:20`) and then discards it. Two of the 30 inventoried logs are currently the wrong
attempt.

### F-E — the one structural change worth considering

`vitest.browser.config.ts:41` `maxWorkers: '50%'` is the untouched half of the `ci.yml:128-130` mitigation.
Every A-family failure is a wait that is either unbounded or budgeted at 1 000 ms, running concurrently
with N-1 other Chrome pages on one runner. Reducing browser-lane concurrency is *not* a fix for any of
A1/A2/A3 — each has a real defect underneath — but it is the honest way to stop load from being the
trigger while those defects are fixed, and unlike a raised timeout it does not weaken any assertion. It
costs wall-clock on a job that has no `timeout-minutes` at all.

---

## 8. Verified / unverified ledger

**VERIFIED:** the `ci.yml:126-135` comment text, its origin commit `f1bfedc28` and what that commit
restructured; `maxWorkers: '50%'` at `vitest.browser.config.ts:41`; `testTimeout: 60_000` at `:68`;
vitest 4.1.10's `expect.poll` defaults 50 ms / 1 000 ms at `test.DNmyFkvJ.js:3714` and the absence of any
BridgeWeb override; Playwright 1.61.0's default anti-backgrounding switches at `coreBundle.js:34433-34459`;
the A1/A2/A3 failure messages, durations, file/line sites and throw sites; the unbounded await at
`worktree-annotation-share-browser-test-support.ts:71` and the bounded sibling at
`worktree-annotation-thread.browser.test-support.tsx:180-208`; the region's owner at
`worktree-annotation-share-mode.tsx:86-89`; the act-environment pin and guard at
`tests/vitest-browser-setup.ts:19-28, 45-58`; base-ui's `flushSync` scheduling at
`useAnimationsFinished.js:37-53` and `useCollapsiblePanel.js:220-265, 385`; B1's failing waiter at
`…save-journey.ts:218-221, 721-726` and the two unhandled rejections; B2's verbatim diff, the
`objectContaining` reading of `pierreItemId`, and the per-test fixture creation at
`…product.e2e.test.tsx:215-216` + `…product-fixture.ts:119`; C's double bootstrap at
`worktree-data.integration.test.ts:185-192`, the unconditional `reason:'initial'` at
`product-file-session.ts:437-447`, the host's three 409 paths at `…ProductHost.swift:848-870`, and the
client's terminal 409 handling at `bridge-app-dev-product-session-host.ts:282-285`; D's full mechanism from
`02-fetch-failed-jobs.sh:27-29,43-48` and `03-fetch-logs.sh:36`; the literal-`^[` encoding of the logs.

**UNVERIFIED:** which await hung in A1; whether the A2 drawer closed or merely lagged, and which of the
two candidate dismissal paths applies; which specific base-ui deferred update escaped `act` in A3, and
whether the warning even belongs to the test it was attributed to; whether B1's `source.refresh` is never
emitted or emitted in a form the predicate rejects; what the `659fd932…` bytes in B2 are; whether C's
second surface should bootstrap as `.workerReplacement` or be admitted concurrently; the macos-26 runner's
core count.
