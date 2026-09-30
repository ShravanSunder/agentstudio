# Plan: site follow-ups after #375 (slice 14)

Author: the orchestrator. Branch `website/site-followups` from main `67d9c2541` (it includes #375 at `2ca7610ce`).

These are owner asks from 2026-09-28, reviewing the live site. Each is quoted, then turned into binding outcomes. Design or plan questions come back to the orchestrator with evidence. This slice excludes the hero cause→effect storyboard (#59/#62/#63, awaiting owner approval) and the lane alignment (#54, meaning still open).

## 14a. One blue and one join into every step line (#53, #53b)
Owner: "the colour blue we use should be the same from where the branch starts"; "the attachment and colour are issues, it's not consistent in every image glass".
- The attach branch from its lane into each chapter's step line is **the same solid `--color-primary` (#89b4fa) at full strength as the step line's passed segment**, from its fork to the line start, with no 46% muted curve that then turns into a bright line.
  - The unpassed step-line track stays primary at 46%.
  - The rail's scroll vibrancy (colour, then grey, then gone) still applies to the attach branch the way it applies to every rail path.
- **Every chapter's join has identical geometry:** the same fork-to-line vertical drop, the same bend radius (existing `localForkPath` cubic), and the same horizontal lead-in length before the line start, measured at 390, 1280 and 1920.
  - If today's layout gives chapters different drops or lead-ins, fix it at the layout owner (the attach geometry and step-line target), not with per-chapter offsets.
- Test: for all three step-line chapters, the attach path's computed stroke equals the step line's passed-segment colour, and the join metrics (drop, lead-in length, bend control points relative to the fork) are equal across chapters (±1px) at the three widths.

## 14b. The commit node sits at the fork (#57)
Owner: "the title-related dot should be here with the branch to the pill."
- The node on the chapter's lane belongs **where the chapter branch leaves the lane**, at the branch's origin, level with the chapter title row.
- Move that chapter's lane node from the step-line height to the fork point. The branch starts from the node, and there is still exactly one node per row (keep the one-dot-per-row and node-vocabulary guards green; update the fixtures they assert only as this move requires).
- Test: each step-line chapter's lane node centre coincides with its attach path's start point (±1px), and its y is within the chapter title's line box.

## 14c. The finale aligns with the images and gutter, with room above it (#55)
Owner: "I meant this to be aligned to our images and gutter, not like this. Not enough space on top to separate it; it looks sloppy."
- The finale block (the icon+title row, the split pill, and the macOS note) shares **the chapter glass/image left edge**, the same x as the chapter surfaces above it, at every width. It no longer sits at `--finale-left-inset` near the rail.
- The rail's final branch still ends at the pill's left edge, so the branch becomes longer. It keeps one bend (the existing no-sharp-corners guard).
- **Top separation:** the finale starts at least `clamp(120px, 12vw, 200px)` below the last chapter's caption, so it reads as its own closing section, not a trailing caption.
- Test: the finale row, pill and note left edges equal the last chapter glass's left edge (±1px) at 390, 1280 and 1920; the gap between the last caption's bottom and the finale row's top is ≥ the clamp value; the rail node touches the pill (±1px).

## 14d. The split pill: one clean outline and a tangent node (#56)
Owner: "the animation and node all look sloppy." The orchestrator's measured faults:
1. The trace is a rounded rectangle with 11px quadratic corners on a stadium pill (`finale-bookend-playback.ts:53`).
2. There are two outlines: the glass border plus the trace, 2px inside it.
3. The glass top highlight streaks over the blue fill.
4. The end node is centred on the pill edge.
5. The fill is inset from the outline, leaving a crescent gap.

Required:
- **One outline:** the border-trace path is the pill's exact stadium outline: arcs of radius height/2, drawn on the border's centre line. The pill's own glass border is suppressed while the trace is present, so there's one visible edge before, during and after the trace.
- The trace animation keeps its beat (a clockwise run from the node, 0.6s). Its settled state is that single outline.
- **The fills are clipped** to the same stadium (the pill clips its children with its radius), so the Star half's blue meets the outline with no gap at the round end, and the Copy half's right end is round.
- **No glass highlight over the blue half.**
- **Node tangent:** the rail's end node sits **outside** the pill, with its outer ring's right edge touching the pill's left edge (±1px) and the rail line entering the node's centre. No halo disc overlaps the pill.
- Tests:
  - the trace path's end arcs match the pill's rect: the start/end cap radius equals height/2 (±0.5px);
  - exactly one visible outline (the pill border colour is transparent while the trace exists);
  - the Star fill's leftmost painted pixel column is within 1px of the outline;
  - the node's rightmost extent equals the pill's left edge (±1px);
  - a 3× capture shows no crescent or double edge.

## 14e. A cleaner hop fold (#58)
The owner's still at about 0–120ms showed a half-folded ghost label and a branch stub.
- In the commit hop, the outgoing label **fades to ≤ 0.3 opacity within the first 60ms** and is gone by 100ms, shrinking only while fading.
- The outgoing drop-turn branch retracts fully to the dot by 120ms (no visible stub after 120ms).
- The total hop stays ≤ 250ms, and the incoming timing (120–250ms) is unchanged.
- Test: sampling the hop's animations at 30, 60, 100 and 130ms, the outgoing label opacity is ≤ 0.3 at 60ms and 0 at 100ms, and the outgoing branch's visible dash length is 0 at 130ms.

## 14f. What's on screen takes over (#61), an owner REQUIREMENT
Owner: "Every chapter taking over is fine but I really want what's on screen to take over. That's the requirement."
Today each chapter scene plays only at ≥60% of its own stage visible (`stagePlaybackProgressForBounds`), which leaves a dead zone where the reader sees the next title and step line but nothing moves.
- **Exactly one active chapter.** It's the chapter whose step line has crossed the reading line (45% of the viewport height from the top), and that has the lowest such step line: the chapter the reader has most recently scrolled into.
- The active chapter's scene plays. Every other chapter pauses (its step line shows the existing auto-hold state, not the manual ❚❚).
- When a chapter **becomes** active, its scene starts **from step 1**; it does not resume mid-story.
- **Hysteresis:** the active chapter changes only when another step line crosses the reading line. Scrolling back up hands activity back to the previous chapter only when its step line re-crosses.
- **Keep:**
  - manual pause (a step click, or the stage toggle) holds that chapter until the reader scrolls away, the existing rule;
  - reduced motion (no playback);
  - the proof beat/replay loop within the active chapter;
  - the ring countdown and the commit hop.
- Own this in one place, a small chapter-activity coordinator the scroll controller consults, rather than per-surface thresholds scattered across the chapters. Non-chapter videos keep their existing rule.
- Tests (browser, no polling: drive with scroll plus the existing ready events):
  - scrolling so chapter 2's step line crosses 45% vh makes chapter 2 play from step 1 and chapter 1 hold;
  - at the old dead-zone position (the next title visible, its stage < 60% visible), the new chapter is playing;
  - scrolling back up past chapter 2's line reactivates chapter 1;
  - at most one chapter is ever in the playing state.

## Gates and proof
- TDD, red first, for each part.
- Focused tests, then 3 consecutive green full `pnpm --dir web run check` runs plus `build`; check `uptime` and wait while the 1-minute load is > 40.
- Proof, as CDP captures under `tmp/proof/`:
  - the join crops for all three chapters at 1600;
  - the fork node crops;
  - the finale at 390, 1280 and 1920, plus a 3× pill crop (settled and mid-trace);
  - hop frames at 0/30/60/100/130/250ms;
  - two scroll positions proving the on-screen takeover (the dead-zone position with the new chapter playing).
- One commit per part (14a–14f); don't push. Write STATUS.md lines 'slice14<x> done' / 'blocked: <exact>' and RESULT.md with commands, counts, exit codes and proof paths.
