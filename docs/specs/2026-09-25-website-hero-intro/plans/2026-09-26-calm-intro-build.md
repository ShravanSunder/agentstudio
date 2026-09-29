# Plan: the calm intro (slice 11), after slice 10

Author: the orchestrator. **Owner-approved 2026-09-26** ("looks good, let's try it"). It replaces the slice-9 beat timing. The source review is `/private/tmp/agentstudio-verify/MEDIA-REVIEW.md` (the media lead's per-beat table, cut list and proof checks). **Follow its §3 tables exactly**, except for the owner overrides below.

## Owner overrides and additions to MEDIA-REVIEW §3
1. **The brew box has a digital "decode" entrance, with no slide.** At 4.45 the box frame fades in (0.25s, `power1.out`, opacity only; transform stays `none`). Then both command lines **decode** left to right over 0.7s (4.60–5.30): each character cycles through 2–3 mono glyphs from a fixed set (for example `▓▒░█<>/\\#$`) and settles on its real character. The settle front sweeps left to right, line 2 starts 0.12s after line 1, and the `COPY` label fades in when both have settled.
   - It's deterministic: the glyph choice is a hash of (char index, quantized timeline time), and never `Math.random` (the scene contract applies; see the media rule `hacker-flip-3d` / decode).
   - The command text is always the real text in the DOM (the decode is a visual overlay or `aria-hidden` layer), so copy, selection and screen readers are unaffected.
   - Reduced motion or skip shows the real text instantly.
2. **The payoff lands at the end as one line** ("Stay oriented. Miss nothing.", 6.20, `expo.out`), per MEDIA-REVIEW (a). The owner agreed.
3. **Refresh always plays the intro:** set `history.scrollRestoration = "manual"` on the home page and scroll to the top before the playback host starts, unless the URL has a `#hash` (an anchor link keeps its position and settles the intro). **Only user input skips the intro** (`wheel`, `touchstart`, `keydown`, pointerdown on the page); remove `scroll` from the skip triggers so browser scroll restoration can't settle it.
4. **The rail draw origin (corrected by the orchestrator 2026-09-26):** keep the existing rail geometry exactly (the hero branch still targets the first app frame). The staircase **starts at the hero's mainline node** (the ring level with the eyebrow, a real anchor) and steps DOWN the mainline in reading order; lanes fork at their own dots; **the last hop is the existing hero branch into the first app frame**. Don't add a branch to the terminal window. (The 'start from the window edge' idea was an orchestrator/media assumption that doesn't fit the approved geometry, so it's dropped; the owner-approved outcome, the staircase landing with the payoff, is unchanged.) On phone: the same order, and the branch into the glass comes last.
5. **The tree draws as a STAIRCASE, dot to dot** (owner-approved): the rail reveal proceeds segment by segment in reading order, starting from the window-edge branch. Each hop is 0.12s (`power2.inOut`); when the line reaches a dot, the dot pops in (scale 0.6 → 1, `back.out(2)`, 0.14s, overlapping the next hop). Forks start AT their own dot and then draw alongside the mainline in parallel. The last hop lands on the branch into the first image, together with the payoff landing. The total stays ≈1.0s (compress the hop duration if there are more dots; never exceed 1.1s). Reduced motion or skip shows the complete tree instantly. Test: seek mid-draw, where exactly the dots above the draw front are revealed and none below; forks begin at their dot's time; the total draw duration ≤ 1.1s.
6. Keep the existing contracts: zero layout shift (pre-sized rows), skip, resize and reduced motion give the final state, the card-fan angles and the step offsets from slice 7b, and the phone finale in the Claude pane.

## Tests (TDD; seek the host timeline; no time waits)
Update the slice-9 beat tests to the new timeline:
- no eyebrow typing;
- headline lines at 0.25 / 0.37;
- icon Δx ≥ 0 for every positional tween in Act 2 (no right-edge entrance, no dock travel);
- **no new tween starts in the pause windows 2.4–2.6 and 5.0–5.6** (inspect the timeline children);
- the focal-event count is ≤ 9;
- the stagger groups are ≤ 0.5s;
- the brew box transform is `none` throughout and its real text is present at every t, with the decode layer settled by 5.30;
- the payoff is hidden before 6.20 and complete by 6.80;
- the rail draw starts at the window edge;
- refresh with a restored scroll offset plays the intro from the top; a `#hash` URL settles.

## Proof
A **60 fps** capture (CDP screencast at 60 fps or a frame-stepped seek render). Contact sheets at 0.3, 0.9, 1.5, 2.2, 2.5, 3.2, 4.3, 4.9, 5.2, 5.8, 6.5 and 7.0s at 1600 and 390, plus `intro-1600.mp4` / `intro-390.mp4` at 60 fps. Gates: 3 consecutive green `check` runs + `build`. Update RESULT.md 'Slice 11', append 'slice11 done' to STATUS.md, and don't push.

## 11b. A more pronounced staircase (owner 2026-09-26: "the staircase can be more staircased or staggered")
Today's 0.12s eased hops read as nearly one continuous draw. Make each step read as a distinct commit:
- per hop: **draw 0.10s (`power2.out`)**, then **hold 0.09s at the dot** while the dot pops (scale 0.4 → 1.15 → 1, `back.out(2.4)`, 0.18s, starting as the line arrives);
- the next hop starts only after the hold, so there's a visible beat at every dot;
- **forks** start their own hop 0.06s *after* the mainline has popped their fork dot (so a branch visibly splits off rather than drawing simultaneously);
- total draw cap **1.6s**: if there are more dots, shrink the hold before the draw, never below a 0.05s hold;
- the payoff "Stay oriented. Miss nothing." still lands with the final hop (shift its start to the last hop's start), and the final state and skip/reduced-motion behaviour are unchanged.
Test: seek at the middle of a hold, where exactly one dot is mid-pop and the line front sits at that dot; fork hops start after their dot pops; total ≤ 1.6s; a zero-shift check across the new finale window.

## 11c. The icon's real angles, and the tilt only after all cards have appeared (owner 2026-09-26)
Owner: "when the tilt happens to the cards, it's after the last card appears; lastly, I thought we were going to do more angles like the actual icon?"
- **The final stack pose = the actual app-icon composition** (from `web/src/assets/brand/app-icon.svg`): rear peach plane **−12°**, second peach plane **+7°** (the discordant angles), and the **blue front plane at 0°** with `>_`, using the icon's relative offsets, scaled to the stack size. It replaces slice 7/7b's uniform −3°/−6°/−9° fan and step offsets (hard cutover of `--hero-stack-step`). So the blue front doesn't read as an accident parallel to the window, the whole icon group sits **offset up-left** of the window corner: the blue plane's top-left corner shows at least 10px desktop / 5px phone outside the window, and the peach planes peek further at their icon angles. Keep the overall peek within 52px desktop / 20px phone.
- **Choreography order (Act 2):** 0.90 the icon's three planes **appear flat and aligned** (0°, stacked, growing in place, `back.out(1.4)`); **only after the last plane has appeared** (≈1.35) the planes **tilt into the icon angles** (0.35s, `power3.out`); then the 4th plane deals off and grows into the window as now. No plane rotates before all three are visible.
- The bookend finale (slice 12) must land on this same icon pose (it already shows the real icon asset at the end; make its transitional fan use these angles too).
- Tests: the settled stack angles are −12° / +7° / 0° (computed transforms); the blue corner is visible outside the window by ≥10px / 5px; no rotation tween starts before the third plane's appear tween ends (inspect the timeline); the resize/skip final state is identical.
- Proof: settled frames at 1600 and 390 next to the app icon (`web/src/assets/brand/app-icon.svg` rendered), plus intro frames at 1.0, 1.4 and 1.8s.
Do it after 11b, before 10k.

## 11d. Show the work happening: brew progress, and a typed Codex prompt (owner 2026-09-26)
Owner: "`⎿ ✓ Ready. Copy it below ↓` while animating the brew should not be ready; it should show an intermediate state, and can be a bit slower. Same for the worktree step: show something happening after the prompts are typed. `map the worktrees` has no prompt typed in Codex."
- **Claude's Bash, a working state:** after `● Bash(brew tap … && brew install --cask agent-studio)`, show brew-like progress rows in the tool result **one at a time** (pre-sized slots; opacity only):
  - `⎿ ==> Tapping shravansunder/agentstudio`
  - `   ==> Downloading agent-studio`
  - `   ==> Installing Cask agent-studio`
  with the real Claude spinner (`✶ Brewing… (esc to interrupt)`, cycling ✢✳✶✻✽) visible while they run.
  - **The install box decodes in DURING this working phase** (it's "the command you'll run"), and **"✓ Ready. Copy it below ↓" appears only after the box has finished decoding**, replacing the spinner row.
  - Stretch Act 3 by about 0.8s to breathe (keep the pause windows; move later beats accordingly).
  - Phone uses a shorter set (1–2 progress rows) so nothing wraps.
- **Codex, a typed prompt, then work:** in Act 4, **type `map the worktrees` into Codex's `›` input band** at a readable speed (≈38ms/char, matching Claude's prompt). On "enter", it moves up into the transcript as a user band, then a Codex working indicator runs (`• Working (2s • esc to interrupt)`, or Codex's real spinner style; check `refs/codex-real-startup.png` / the herdr reference for its working line). `└ git worktree list` appears, then the worktree rows **stream in one by one** (for example three short rows `~/agent-studio  main`, `~/agent-studio.drawer  drawer-improvements`, `~/agent-studio.review  review-comments`), then `└ 3 worktrees · 5 branches`. **The staircase tree draw starts as the rows stream** and lands with the payoff.
  - Phone: the same in the Claude pane (no pane switch).
- **No layout shift:** every new row is pre-sized in the settled markup; the zero-shift test covers the extended timeline. The settled/final state (skip, resize, reduced motion) shows the finished transcripts ("✓ Ready…", the worktree rows, the result) and the full tree.
- Tests: no "✓ Ready" row visible before the install decode ends; the progress rows appear in order during the working phase; Codex's input shows partial prompt text mid-typing; the rows stream before the result; the tree draw starts after the first streamed row; zero shift across the new windows.
Do it after 11c, before 10k.

### 11d revision (owner, supersedes 11d's sequencing; overrides MEDIA-REVIEW's "one live pane at a time")
Owner: "both can be typed immediately after each other. 1. then it shows brew in an intermediate state; brew done and check in terminal. 2. while we have loading. 3. stairs, then some other state. 4. Codex also done."
Sequence (desktop; phone: the Claude pane only, with the Codex beats skipped and the tree still drawing in step 3):
| step | Claude pane | Codex pane | page |
|---|---|---|---|
| T | types `set up Agent Studio for me` (≈38ms/char), sends | **immediately after Claude's send**, types `map the worktrees` into its `›` input, sends | — |
| 1 | `● Bash(brew …)` → progress rows one by one with the spinner (the intermediate state) | a working indicator (loading) | **the install box decodes in** during this |
| 1-end | the spinner row is replaced by **`⎿ ✓ Ready. Copy it below ↓`** (brew done, check in the terminal) | still loading | — |
| 2 | (done, static) | loading continues: `• Ran └ git worktree list` | — |
| 3 | — | **the worktree rows stream in** ("some other state") | **the staircase tree draws** (11b timing) while the rows stream |
| 4 | — | **`└ 3 worktrees · 5 branches`**; Codex done | the payoff "Stay oriented. Miss nothing." lands with the last hop; then stillness |
Keep the pause before step T (after the window forms) and a stillness after step 4. The Act-3 breath window moves to between 1-end and 3 only if it fits; otherwise, drop that breath (the owner's overlapping flow wins). The tests from 11d still apply (no Ready before the decode ends, typed partial text in both inputs, rows before the result, zero shift), plus: Codex's typing starts within 0.15s after Claude's send.
