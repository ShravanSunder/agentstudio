# Plan: intro beats with rhythmic text, and a Codex finale that draws the git tree (slice 9)

Author: the orchestrator. **Owner-approved 2026-09-26** ("looks good, let's try on the real site"), from storyboard v2 (`/private/tmp/agentstudio-intro-storyboard2/storyboard.png`, frames in `frames/`, the reference overlay `inject-beats.js`). Branch `website/hero-intro`.

## Beats (desktop ≥ 1024; phone differences below)
| t (s) | text | stage |
|---|---|---|
| 0.00–0.45 | the eyebrow **types** character by character (mono) with a block cursor; the cursor disappears at the end | empty |
| 0.45–0.75 | headline line 1 rises (+10px → 0, opacity 0 → 1) | empty |
| 0.65–0.95 | headline line 2 rises | empty |
| 0.80 → 3.40 | — | existing: the blue card slides in, the peach cards deal, the fan tilts, the 4th card deals and grows into the window |
| 3.40–3.70 | **"Stay oriented."** fades in (the first half of the payoff) | the window forms (existing) |
| 3.40 → 5.75 | — | existing: Claude types, Bash, `✓ Ready`, the arrow pulses, the brew box fades in (5.05–5.75); the glow is 5.4–6.2 |
| 6.10 | — | **Codex finale** (truthful: Codex acts on its own, no Claude handoff line): a user band `› map the worktrees` appears in the Codex transcript (in its reserved, pre-sized space; nothing moves) |
| 6.40 | — | `• Ran` / `└ git worktree list` |
| 6.80 | — | `└ 3 worktrees · 5 branches`; **the git tree starts drawing** from the page top: the mainline, then the lane forks, then the branch into the first image. The real rail draws in via its reveal (stroke-dash or clip), 6.80–7.80 |
| 7.80–8.10 | **"Miss nothing."** fades in (the payoff completes) | Codex `• Mapped. Scroll to explore ↓`; the tree is complete |

- **Rail visibility:** the rail (mainline, lanes, nodes, branches) is **hidden until 6.80** during a playing intro. It's revealed by the finale. On skip or resize (settle), reduced motion, or no JS, it shows fully at once. After the intro, today's scroll reveal, vibrancy band and glow behave as now.
- **No layout shift:** the finale rows are pre-rendered in the settled markup (the final transcript), so the Codex pane's height includes them. The scene only animates their opacity. The existing zero-shift test covers the whole timeline to 8.1s.
- **Phone (< 1024, Claude-only):** the finale runs in the **Claude** pane: a user band `› map the worktrees` → `● Bash(git worktree list)` → `⎿ 3 worktrees · 5 branches` → `● Mapped. Scroll to explore ↓`, with the same times and the same tree draw. Never switch panes.
- **Settled/final state = the finale state:** the Codex (desktop) and Claude (phone) transcripts end with the finale lines, "Stay oriented. Miss nothing." is complete, and the rail is fully drawn.
- **Truthfulness note (keep this code comment):** the finale shows agents working in the same workspace; the cross-pane handoff isn't shown because it isn't a shipped feature.

## Tests (TDD; no time waits; seek the host timeline)
- Seek-based browser tests at 1600 and 390:
  - the eyebrow's typed length grows with t (0.2 → partial, 0.45 → full, and no cursor after);
  - "Stay oriented." is hidden before 3.40 and visible after 3.70;
  - "Miss nothing." is hidden before 7.80 and visible at the end;
  - the rail is invisible before 6.80, partially drawn at 7.2, and fully drawn at the end;
  - the finale rows appear in the right pane per width.
- Zero shift: the app-frame top, the window height and the first chapter node stay constant across t ∈ {0, 3.5, 5.5, 6.5, 7.2, 8.1, settled}.
- Settle-by-skip and settle-by-resize mid-finale end in the full final state (the rail fully drawn and no inline styles).
- Reduced motion shows the final state immediately, with the rail visible.
- Follow the CI test-quality criteria (`agent-studio.ci-improvements/tmp/ci-speed/2026-09-26-good-test-criteria.md`): a shared server per file, no sleeps.

## Proof
Production-build CDP frames at the storyboard beats (B01–B11) at 1600, plus the starred ones at 390, paired against the storyboard frames with differences listed; intro videos at 1600 and 390. Gates: 3 consecutive green `check` runs + `build`. Commit, append 'slice9 done' to STATUS.md, and don't push.
