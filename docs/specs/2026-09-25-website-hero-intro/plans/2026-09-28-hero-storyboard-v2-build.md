# Plan: hero storyboard v2, the agents hand off (slice 15)

Author: the orchestrator. Branch `website/hero-storyboard-v2` from main `67d9c2541`.

**Owner approval (2026-09-28):** "overall good" on the storyboard v2 live mock, after these directions:
- no drawn lines ("like a laser show");
- the motion lives in the panes, which stay lively; outside the panes it's calm;
- Claude brews first, then pings Codex, which starts the worktree part;
- the cues are bursts of tokens, muted ("less colour vibrant");
- there's a cue from Codex to the start of the tree;
- panes scroll like a real terminal, with no overlap;
- #59: Codex runs in `~/agent-studio`.

**The reference implementation of every motion** (timing, easing, routes, token sets, the scroll rule) is `tmp/proof/storyboard-v2-reference-mock.html`. It's deterministic in `t` (add `?t=<seconds>` to freeze a frame). Port its behaviour into the real hero, and don't copy its markup. The real hero keeps its components, the GSAP paused-timeline scene contract (`hero-intro-scene.ts` + `hero-intro-playback.ts`), zero page-layout shift, skip/resize/reduced-motion settle, and refresh-replays.

## 15a. Keep the opening beats; rebuild the terminal story (desktop ≥ 1024)
Keep beats 1–3 as they are today: the statement (0.15), the icon (0.9), and the window forming (1.72–2.4). Replace everything after the window forms with this storyboard. Times are seconds on the hero timeline. Keep beat labels so tests and media bundles can seek them.
| t | Claude pane | Codex pane | Outside the panes |
|---|---|---|---|
| 2.6–3.6 | types `set up Agent Studio for me` in the input (the existing typing speed) and sends; the pane lifts (border inset 1.5px primary at 55%, background primary at 5%) | quiet | — |
| 3.7 | `● I'll install it with Homebrew.` | | |
| 3.95–6.95 | **working, lively:** `● Bash(brew tap … && brew install …)` with the `●` blinking at 2.5 Hz; the spinner row cycles `✢✳✶✻✽` at 8 Hz with the shimmer sweeping "Brewing…" and live `(Ns · ↑ X.Xk tokens · esc to interrupt)`; `==> Tapping` (✓ at +0.6); `==> Downloading` with the Homebrew `#` bar filling to 100% over 1.3s (then ✓); `==> Installing Cask` (✓); the `●` turns green | quiet | — |
| 7.0 | `⎿ ✓ Ready. Copy it below ↓` replaces the spinner row | | **burst 1** (7.05, 0.34s): tokens from right of `↓` → down through the empty space → the install box |
| 7.3–8.0 | | | the install box lights up and decodes (the existing decode), then COPY |
| 7.6 | | | **burst 2** (0.34s): from right of Claude's Ready row → to Codex's input band |
| 7.85–8.6 | the pane lift settles | wakes: the input band glows once; types `map the worktrees`; sends; the pane lifts | |
| 8.65–11.25 | resting | **working, lively:** `• Working (Ns • esc to interrupt)` with the shimmer, then `• Running └ git worktree list`, the rows printing one by one (each with a 0.45s highlight sweep), then `└ 3 worktrees · 5 branches`, and `Running` → `Ran` | |
| 11.3 | | the pane lift settles | **burst 3** (0.34s): from right of Codex's result → up Codex's outer edge → left through the gap between the headline and the window → the rail |
| 11.6+ | | | the existing staircase tree draw starts from burst 3's arrival (the 11b hold+pop timing, capped at 1.6s); "Stay oriented. Miss nothing." lands with the last hop; stillness |

**Also:**
- The whole terminal story is sequential; never run two bursts at once.
- If the total from 0 to stillness exceeds 13.5s, shorten typing to 30ms/char and Codex "Working" to 0.8s (and nothing else), then report the total.

## 15b. Token bursts (the only cues outside the panes)
- **Style:** monospace tokens at 11–13px, weight 500, in the muted palette `#9aafcf #bfa597 #a5b8a3 #b3a8c4 #9db6c2 #c2b9a0`, with peak opacity 0.72.
- **Token sets:**
  - burst 1: `brew { } ✦ tap ⟨/⟩ # cask ▍ → ✦ 01`;
  - burst 2: `map ✦ λ { } git ⟨/⟩ ▍ ✦ tree → 01`;
  - burst 3: `wt main ✦ { } drawer ▍ → review ·`.
- **Movement:** the tokens travel along a **route polyline through clear space** (the reference's `pointAlong`), staggered, with a small perpendicular offset. They **emerge only after leaving the source text and dissolve before the target text** (visible for p ∈ (0.22, 0.84)).
- **Never over text:** tokens must never paint over transcript or input text. Derive the routes from live element rects (text-end positions), not constants.
- **No lines** are drawn anywhere.
- Reduced motion or skip: no bursts; the final state.

## 15c. Terminal scrolling in the panes (#63)
- Each pane's transcript is a region above its pinned input and footer, with **≥ 20px clear space** between the last visible row and the pinned block.
- The transcript fills from the top. Once full, it stays scrolled to the newest row, so new rows push older rows up and off the top.
- Rows never overlap the input or footer at any time.
- The page layout never shifts (the window size is fixed; only the transcript scrolls inside it).
- The last visible row at the end is the result: `✓ Ready…` for Claude, `3 worktrees · 5 branches` for Codex.

## 15d. The Codex pane runs in `~/agent-studio` (#59)
- The header reads `directory: ~/agent-studio`, and the footer branch is `main`.
- The worktree rows stay `~/agent-studio main`, `~/agent-studio.drawer drawer-improvements`, `~/agent-studio.review review-comments`, and `3 worktrees · 5 branches`.
- Remove every `tool-portal` / `fix/lease-client` reference from the hero transcripts.

## 15e. Phone (< 1024, Codex hidden)
- Claude does both tasks in its pane. After `✓ Ready` and burst 1, the Claude input types `map the worktrees`, Claude works (the same spinner and shimmer), and the rows print in Claude's pane. Burst 3 goes from the result to the rail.
- There's no burst 2 on phone.
- The same scroll rule applies, the tall-phone fill (10g3/43) holds, and the first app image stays below the fold during the intro.

## Tests (TDD, red first; seek the host timeline; no polling or time waits)
- Beat order and labels:
  - `Ready` appears before burst 1;
  - burst 2 starts after burst 1 ends;
  - Codex's typing starts only after burst 2 ends;
  - burst 3 starts at `Ran`;
  - the staircase starts after burst 3 arrives;
  - the payoff lands with the last hop.
- In-pane motion at seek points:
  - the spinner glyph changes between two seeks 0.13s apart;
  - the brew bar's percentage increases;
  - the `●` is green only after the bar reaches 100%;
  - `Running` becomes `Ran` at the result.
- Bursts:
  - at sampled seek times during each burst, no visible token's box intersects any transcript row's or input's text box (a Range rect test);
  - no `<line>`/`<path>` connector elements are drawn outside the rail.
- Scroll: at every sampled time, the last visible row's bottom is ≥ 20px above the pinned block's top in each pane, and the page's layout is unchanged (the existing zero-shift test extended to the new window).
- #59: no `tool-portal` text anywhere in the hero.
- Phone: no burst 2, both tasks in the Claude pane, and burst 3 → the rail.
- Reduced motion, skip and resize: the final state (both results, the box decoded, the tree drawn, the payoff), with no bursts and no timeline.

## Proof
- CDP frames at 1600 and 390 at: the Claude working state (5.5), each burst's midpoint, the Codex working state (9.5), rows printing (10.5), burst 3's midpoint, and the settled frame.
- A 60fps capture of 2.4 → stillness at 1600, as `hero-v2-1600.mp4`.
- Gates: 3 green full `pnpm --dir web run check` runs plus `build` (load < 40).
- Commits per part (15a–15e); don't push. Write `tmp/proof/STATUS.md` and `RESULT.md`.
