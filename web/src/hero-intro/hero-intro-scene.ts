import type { SceneBuildOptions, SceneTimeline } from "../motion-scenes/scene-contract";
import {
  heroIconCursorAttribute,
  heroIconFrontAttribute,
  heroIconRearAttribute,
  heroIconStackAttribute,
  heroIntroContentAttribute,
  heroIntroCopyAttribute,
  heroIntroEyebrowSettledAttribute,
  heroIntroFinaleRowAttribute,
  heroIntroHeadlineFirstAttribute,
  heroIntroHeadlineSecondAttribute,
  heroIntroPayoffFirstAttribute,
  heroIntroPayoffSecondAttribute,
  heroIntroFourthPlaneAttribute,
  heroIntroGlowAttribute,
  heroIntroInstallAttribute,
  heroIntroSpinnerAttribute,
  heroIntroReadyAttribute,
  heroIntroReadyArrowAttribute,
  heroIntroTypedInputAttribute,
  heroTerminalWindowAttribute,
} from "./hero-intro-dom-contract";
import { addHeroRailStaircase } from "./hero-intro-rail-draw";
import { addHeroTokenBursts } from "./hero-intro-token-bursts";

function requiredTarget(root: HTMLElement, attribute: string): HTMLElement {
  const target = root.querySelector<HTMLElement>(`[${attribute}]`);
  if (target === null) {
    throw new Error(`Hero intro is missing ${attribute}`);
  }
  return target;
}

export function collectHeroIntroTargets(root: HTMLElement): HTMLElement[] {
  return [
    requiredTarget(root, heroIntroCopyAttribute),
    requiredTarget(root, heroIntroEyebrowSettledAttribute),
    requiredTarget(root, heroIntroHeadlineFirstAttribute),
    requiredTarget(root, heroIntroHeadlineSecondAttribute),
    requiredTarget(root, heroIntroPayoffFirstAttribute),
    requiredTarget(root, heroIntroPayoffSecondAttribute),
    requiredTarget(root, heroIconStackAttribute),
    requiredTarget(root, heroIconFrontAttribute),
    ...root.querySelectorAll<HTMLElement>(`[${heroIconRearAttribute}]`),
    requiredTarget(root, heroIconCursorAttribute),
    requiredTarget(root, heroTerminalWindowAttribute),
    requiredTarget(root, heroIntroContentAttribute),
    requiredTarget(root, heroIntroInstallAttribute),
    ...root.querySelectorAll<HTMLElement>("[data-install-decode-line], [data-install-copy]"),
    requiredTarget(root, heroIntroReadyArrowAttribute),
    requiredTarget(root, heroIntroGlowAttribute),
    requiredTarget(root, heroIntroTypedInputAttribute),
    ...root.querySelectorAll<HTMLElement>(
      "[data-hero-codex-placeholder], [data-hero-codex-typed-input]",
    ),
    requiredTarget(root, heroIntroSpinnerAttribute),
    ...root.querySelectorAll<HTMLElement>(".hero-codex-footer"),
    ...root.querySelectorAll<HTMLElement>(".hero-transcript-row"),
    ...root.querySelectorAll<HTMLElement>("[data-hero-bash-dot], [data-hero-brew-bar]"),
    ...root.querySelectorAll<HTMLElement>("[data-hero-brew-check], [data-hero-codex-working-meta]"),
    ...root.querySelectorAll<HTMLElement>("[data-hero-pane-lift], [data-hero-codex-verb]"),
    ...root.querySelectorAll<HTMLElement>(".hero-codex-current-rows, .hero-claude-current-rows"),
  ];
}

function createFourthPlane(root: HTMLElement): HTMLElement {
  const fourthPlane = document.createElement("div");
  fourthPlane.setAttribute(heroIntroFourthPlaneAttribute, "");
  fourthPlane.setAttribute("aria-hidden", "true");
  fourthPlane.style.position = "absolute";
  fourthPlane.style.zIndex = "3";
  fourthPlane.style.pointerEvents = "none";
  fourthPlane.style.boxSizing = "border-box";
  fourthPlane.style.background = "#282c34";
  root.append(fourthPlane);
  return fourthPlane;
}

/** Adds the single seek-safe intro to a paused timeline owned by playback. */
export function buildHeroIntroScene(
  root: HTMLElement,
  timeline: SceneTimeline,
  options: SceneBuildOptions,
): void {
  const eyebrowSettled = requiredTarget(root, heroIntroEyebrowSettledAttribute);
  const headlineFirst = requiredTarget(root, heroIntroHeadlineFirstAttribute);
  const headlineSecond = requiredTarget(root, heroIntroHeadlineSecondAttribute);
  const payoffFirst = requiredTarget(root, heroIntroPayoffFirstAttribute);
  const payoffSecond = requiredTarget(root, heroIntroPayoffSecondAttribute);
  const iconStack = requiredTarget(root, heroIconStackAttribute);
  const sceneContainer = iconStack.parentElement;
  if (sceneContainer === null) {
    throw new Error("Hero intro stack has no positioning container");
  }
  const iconFront = requiredTarget(root, heroIconFrontAttribute);
  const iconRears = root.querySelectorAll<HTMLElement>(`[${heroIconRearAttribute}]`);
  const rearOne = iconRears[0];
  const rearTwo = iconRears[1];
  if (rearOne === undefined || rearTwo === undefined) {
    throw new Error("Hero intro needs both rear icon planes");
  }
  const iconCursor = requiredTarget(root, heroIconCursorAttribute);
  const windowNode = requiredTarget(root, heroTerminalWindowAttribute);
  const windowContent = requiredTarget(root, heroIntroContentAttribute);
  const install = requiredTarget(root, heroIntroInstallAttribute);
  const glow = requiredTarget(root, heroIntroGlowAttribute);
  const typedInput = requiredTarget(root, heroIntroTypedInputAttribute);
  const spinner = requiredTarget(root, heroIntroSpinnerAttribute);
  const ready = requiredTarget(root, heroIntroReadyAttribute);
  const readyArrow = requiredTarget(root, heroIntroReadyArrowAttribute);
  const codexCurrentRows = root.querySelector<HTMLElement>(".hero-codex-current-rows");
  const finalePane = options.width < 1024 ? "claude" : "codex";
  const finaleRows = [...root.querySelectorAll<HTMLElement>(`[${heroIntroFinaleRowAttribute}]`)];
  const claudeRows = [
    ...root.querySelectorAll<HTMLElement>(
      `.hero-terminal-pane--claude [${heroIntroFinaleRowAttribute}]`,
    ),
  ];
  const codexRows = [
    ...root.querySelectorAll<HTMLElement>(
      `.hero-terminal-pane--codex [${heroIntroFinaleRowAttribute}]`,
    ),
  ];
  const visibleRows = (rows: readonly HTMLElement[]): HTMLElement[] =>
    rows.filter((row) => getComputedStyle(row).display !== "none");
  const visibleClaudeRows = visibleRows(claudeRows);
  const visibleCodexRows = visibleRows(codexRows);
  const progressRows = visibleRows([
    ...root.querySelectorAll<HTMLElement>("[data-hero-progress-row]"),
  ]);
  const brewBar = root.querySelector<HTMLElement>("[data-hero-brew-bar]");
  const bashDots = [...root.querySelectorAll<HTMLElement>("[data-hero-bash-dot]")];
  const brewChecks = [...root.querySelectorAll<HTMLElement>("[data-hero-brew-check]")];
  const codexWorkingMeta = root.querySelector<HTMLElement>("[data-hero-codex-working-meta]");
  const claudeLift = root.querySelector<HTMLElement>('[data-hero-pane-lift="claude"]');
  const codexLift = root.querySelector<HTMLElement>('[data-hero-pane-lift="codex"]');
  const codexRunning = root.querySelector<HTMLElement>("[data-hero-codex-running]");
  const codexVerb = root.querySelector<HTMLElement>("[data-hero-codex-verb]");
  const worktreeRows = visibleRows([
    ...root.querySelectorAll<HTMLElement>(
      `.hero-terminal-pane--${finalePane} [data-hero-worktree-row]`,
    ),
  ]);
  const worktreeResult = root.querySelector<HTMLElement>(
    `.hero-terminal-pane--${finalePane} [data-hero-worktree-result]`,
  );
  const worktreeCommand = root.querySelector<HTMLElement>(
    `.hero-terminal-pane--${finalePane} [data-hero-worktree-command]`,
  );
  const codexTypedInput = root.querySelector<HTMLElement>("[data-hero-codex-typed-input]");
  const codexPlaceholder = root.querySelector<HTMLElement>("[data-hero-codex-placeholder]");
  const codexWorking = root.querySelector<HTMLElement>("[data-hero-codex-working]");
  const rail = root.ownerDocument.querySelector<SVGSVGElement>("[data-full-page-topology]");

  // All layout measurements are taken before the timeline moves any surface.
  const sceneRect = sceneContainer.getBoundingClientRect();
  const frontRect = iconFront.getBoundingClientRect();
  const windowRect = windowNode.getBoundingClientRect();
  const startWidth = options.width < 620 ? 170 : 260;
  const startHeight = options.width < 620 ? 108 : 165;
  const fourthPlane = createFourthPlane(sceneContainer);
  const fourthDestinationLeft = windowRect.left - sceneRect.left;
  const fourthDestinationTop = windowRect.top - sceneRect.top;
  const fourthLeft = Math.min(
    frontRect.left - sceneRect.left,
    fourthDestinationLeft - (options.width < 620 ? 24 : 48),
  );
  const fourthTop = frontRect.top - sceneRect.top;
  const fourthDealX = fourthLeft + (fourthDestinationLeft - fourthLeft) * 0.35;
  const glassRadius = getComputedStyle(windowNode).borderTopLeftRadius;
  const decodeLines = [...install.querySelectorAll<HTMLElement>("[data-install-decode-line]")];
  const decodeText = decodeLines.map((line) => line.parentElement?.textContent ?? "");
  const copyButton = install.querySelector<HTMLElement>("[data-install-copy]");
  const eyebrowStyle = getComputedStyle(eyebrowSettled);
  const eyebrowBaseSpacing = Number.parseFloat(eyebrowStyle.letterSpacing) || 0;
  const eyebrowStartSpacing = eyebrowBaseSpacing + Number.parseFloat(eyebrowStyle.fontSize) * 0.08;

  timeline.addLabel("beat:statement", 0.15);
  timeline.fromTo(
    eyebrowSettled,
    { opacity: 0, letterSpacing: `${eyebrowStartSpacing}px` },
    { opacity: 1, letterSpacing: `${eyebrowBaseSpacing}px`, duration: 0.3, ease: "power1.out" },
    0.15,
  );
  timeline.fromTo(
    headlineFirst,
    { y: 18, opacity: 0 },
    { y: 0, opacity: 1, duration: 0.55, ease: "expo.out" },
    0.25,
  );
  timeline.fromTo(
    headlineSecond,
    { y: 18, opacity: 0 },
    { y: 0, opacity: 1, duration: 0.55, ease: "expo.out" },
    0.37,
  );

  if (codexCurrentRows !== null) timeline.set(codexCurrentRows, { opacity: 1 }, 0);
  if (finaleRows.length > 0) timeline.set(finaleRows, { opacity: 0 }, 0);
  timeline.set(ready, { opacity: 0 }, 0);
  timeline.set(spinner, { opacity: 0 }, 0);
  timeline.set(brewChecks, { opacity: 0 }, 0);
  timeline.set(typedInput, { textContent: "" }, 0);
  if (codexTypedInput !== null) timeline.set(codexTypedInput, { textContent: "" }, 0);
  timeline.set(decodeLines, { opacity: 0 }, 0);
  if (copyButton !== null) timeline.set(copyButton, { opacity: 0 }, 0);

  timeline.addLabel("beat:icon", 0.9);
  timeline.set(iconStack, { opacity: 1 }, 0);
  for (const [plane, start] of [
    [rearOne, 0.9],
    [rearTwo, 1.06],
    [iconFront, 1.22],
  ] as const) {
    timeline.fromTo(
      plane,
      { opacity: 0, scale: 0.86, rotation: 0 },
      { opacity: 1, scale: 1, duration: 0.13, ease: "back.out(1.4)" },
      start,
    );
  }
  timeline.to(rearOne, { rotation: -12, duration: 0.35, ease: "power3.out" }, 1.36);
  timeline.to(rearTwo, { rotation: 7, duration: 0.35, ease: "power3.out" }, 1.36);
  timeline.set(iconCursor, { opacity: 0 }, 0);
  timeline.addLabel("beat:window", 1.72);
  timeline.fromTo(
    fourthPlane,
    {
      left: fourthLeft,
      top: fourthTop,
      width: startWidth,
      height: startHeight,
      border: "1px solid #89b4fa",
      borderRadius: getComputedStyle(iconFront).borderTopLeftRadius,
      opacity: 0,
    },
    {
      left: fourthDealX,
      top: fourthTop - 10,
      width: startWidth,
      height: startHeight,
      opacity: 1,
      duration: 0.18,
      ease: "power2.out",
    },
    1.72,
  );
  timeline.to(
    fourthPlane,
    {
      left: fourthDestinationLeft,
      top: fourthDestinationTop,
      width: windowRect.width,
      height: windowRect.height,
      borderColor: "rgb(137 180 250 / 38%)",
      borderRadius: glassRadius,
      duration: 0.44,
      ease: "power3.inOut",
    },
    1.9,
  );
  timeline.fromTo(
    windowNode,
    { opacity: 0 },
    { opacity: 1, duration: 0.18, ease: "sine.out" },
    2.34,
  );
  timeline.to(fourthPlane, { opacity: 0, duration: 0.18, ease: "sine.out" }, 2.34);
  timeline.fromTo(
    windowContent,
    { opacity: 0 },
    { opacity: 1, duration: 0.18, ease: "sine.out" },
    2.34,
  );
  timeline.set(iconStack, { zIndex: 1 }, 2.34);
  timeline.fromTo(glow, { opacity: 0 }, { opacity: 1, duration: 2.66, ease: "sine.inOut" }, 2.34);

  const revealRow = (row: HTMLElement | null | undefined, start: number): void => {
    if (row !== null && row !== undefined)
      timeline.fromTo(
        row,
        { opacity: 0 },
        { opacity: 1, duration: 0.15, ease: "power2.out" },
        start,
      );
  };

  timeline.addLabel("beat:prompt", 2.6);
  const claudePrompt = "set up Agent Studio for me";
  const claudeTyping = { fraction: 0 };
  timeline.to(
    claudeTyping,
    {
      fraction: 1,
      duration: 1,
      ease: "none",
      onUpdate: () => {
        typedInput.textContent = claudePrompt.slice(
          0,
          Math.floor(claudeTyping.fraction * claudePrompt.length),
        );
      },
    },
    2.6,
  );
  timeline.set(typedInput, { textContent: "" }, 3.62);
  revealRow(
    visibleClaudeRows.find((row) => row.textContent?.includes("set up Agent Studio")),
    3.62,
  );
  revealRow(
    visibleClaudeRows.find((row) => row.textContent?.includes("I'll install")),
    3.72,
  );
  revealRow(
    visibleClaudeRows.find((row) => row.textContent?.includes("Bash(")),
    3.83,
  );
  const activePaneStyle = {
    boxShadow: "inset 0 0 0 1.5px rgb(137 180 250 / 55%)",
    backgroundColor: "rgb(137 180 250 / 5%)",
  };
  if (claudeLift !== null) {
    timeline.set(claudeLift, activePaneStyle, 3.62);
    timeline.set(claudeLift, { boxShadow: "none", backgroundColor: "transparent" }, 7.85);
  }
  if (codexLift !== null && options.width >= 1024) {
    timeline.set(codexLift, activePaneStyle, 7.85);
    timeline.set(codexLift, { boxShadow: "none", backgroundColor: "transparent" }, 11.3);
  }

  timeline.addLabel("beat:codex-prompt", 7.85);
  if (codexTypedInput !== null && codexPlaceholder !== null && options.width >= 1024) {
    const codexPrompt = "map the worktrees";
    const codexTyping = { fraction: 0 };
    timeline.set(codexPlaceholder, { opacity: 0 }, 7.85);
    timeline.to(
      codexTyping,
      {
        fraction: 1,
        duration: 0.51,
        ease: "none",
        onUpdate: () => {
          codexTypedInput.textContent = codexPrompt.slice(
            0,
            Math.floor(codexTyping.fraction * codexPrompt.length),
          );
        },
      },
      7.85,
    );
    timeline.set(codexTypedInput, { textContent: "" }, 8.6);
    timeline.set(codexPlaceholder, { opacity: 1 }, 8.6);
    if (codexCurrentRows !== null)
      timeline.to(codexCurrentRows, { opacity: 0, duration: 0.18, ease: "power2.out" }, 8.6);
    revealRow(visibleCodexRows[0], 8.6);
    revealRow(codexWorking, 8.65);
    revealRow(worktreeCommand, 9.5);
  }

  const spinnerGlyphs = ["✢", "✳", "✶", "✻", "✽"] as const;
  const spinnerState = { fraction: 0 };
  timeline.addLabel("beat:claude-brew", 3.95);
  timeline.addLabel("beat:spinner", 3.95);
  timeline.fromTo(spinner, { opacity: 0 }, { opacity: 1, duration: 0.01 }, 3.95);
  timeline.to(
    spinnerState,
    {
      fraction: 1,
      duration: 3,
      ease: "none",
      onUpdate: () => {
        const elapsed = spinnerState.fraction * 3;
        const glyphIndex = Math.floor((3.95 + elapsed) * 8) % spinnerGlyphs.length;
        spinner.textContent = `${spinnerGlyphs[glyphIndex]} Brewing… (${Math.floor(elapsed + 1)}s · ↑ ${(0.3 + elapsed * 0.35).toFixed(1)}k tokens · esc to interrupt)`;
        for (const dot of bashDots) {
          dot.style.color =
            elapsed >= 2.4
              ? "#a6e3a1"
              : Math.floor(elapsed * 2.5) % 2 === 0
                ? "#f3f3f4"
                : "#9ba1ad";
        }
        spinner.style.backgroundPosition = `${100 - ((elapsed * 60) % 100)}% 0`;
      },
    },
    3.95,
  );
  progressRows.forEach((row, index) => revealRow(row, [4.35, 5.05, 6.2][index] ?? 6.2));
  brewChecks.forEach((check, index) => revealRow(check, [4.95, 6.35, 6.8, 6.8][index] ?? 6.8));
  if (brewBar !== null) {
    const barState = { fraction: 0 };
    timeline.to(
      barState,
      {
        fraction: 1,
        duration: 1.3,
        ease: "none",
        onUpdate: () => {
          const filled = Math.round(barState.fraction * 16);
          brewBar.textContent = `${"#".repeat(filled)}${" ".repeat(16 - filled)} ${(barState.fraction * 100).toFixed(1)}%`;
        },
      },
      5.05,
    );
  }

  timeline.addLabel("beat:install-decode", 7.3);
  timeline.fromTo(install, { opacity: 0 }, { opacity: 1, duration: 0.25, ease: "power1.out" }, 7.3);
  const decodeState = { fraction: 0 };
  const glyphs = "▓▒░█<>/\\#$";
  timeline.to(
    decodeState,
    {
      fraction: 1,
      duration: 0.82,
      ease: "none",
      onUpdate: () => {
        const elapsed = decodeState.fraction * 0.82;
        decodeLines.forEach((line, lineIndex) => {
          const text = decodeText[lineIndex] ?? "";
          const localDuration = lineIndex === 0 ? 0.7 : 0.58;
          const progress = Math.max(0, Math.min(1, (elapsed - lineIndex * 0.12) / localDuration));
          const settledCharacters = Math.floor(progress * text.length);
          const timeSlice = Math.floor(elapsed * 30);
          line.textContent = text
            .split("")
            .map((character, characterIndex) => {
              if (characterIndex < settledCharacters || character === " ") return character;
              return glyphs[(characterIndex * 17 + timeSlice * 7 + lineIndex * 11) % glyphs.length];
            })
            .join("");
          line.style.opacity = progress >= 1 ? "0" : "1";
        });
        if (copyButton !== null) {
          copyButton.style.opacity = String(Math.max(0, Math.min(1, (elapsed - 0.7) / 0.12)));
        }
      },
    },
    7.3,
  );

  timeline.addLabel("beat:ready", 7.0);
  timeline.to(spinner, { opacity: 0, duration: 0.05 }, 6.95);
  revealRow(ready, 7.0);
  timeline.fromTo(
    readyArrow,
    { opacity: 1 },
    { opacity: 0.35, duration: 0.2, repeat: 1, yoyo: true, ease: "sine.inOut" },
    7.12,
  );

  if (options.width < 1024) {
    revealRow(
      visibleClaudeRows.find((row) => row.textContent?.includes("map the worktrees")),
      8.0,
    );
    revealRow(worktreeCommand, 9.2);
  }
  if (codexWorkingMeta !== null) {
    const workingState = { seconds: 0 };
    timeline.to(
      workingState,
      {
        seconds: 0.85,
        duration: 0.85,
        ease: "none",
        onUpdate: () => {
          codexWorkingMeta.textContent = ` (${Math.floor(workingState.seconds + 1)}s • esc to interrupt)`;
        },
      },
      8.65,
    );
  }
  worktreeRows.forEach((row, index) => {
    revealRow(row, 9.85 + index * 0.4);
    timeline.fromTo(
      row,
      { "--hero-row-flash": 1 },
      { "--hero-row-flash": 0, duration: 0.45, ease: "power1.out" },
      9.85 + index * 0.4,
    );
  });
  revealRow(codexRunning, 9.5);
  if (codexVerb !== null) {
    timeline.set(codexVerb, { textContent: "Running" }, 9.5);
    timeline.set(codexVerb, { textContent: "Ran" }, 11.25);
  }
  if (codexWorking !== null && options.width >= 1024)
    timeline.to(codexWorking, { opacity: 0, duration: 0.15, ease: "power2.out" }, 9.5);
  timeline.addLabel("beat:codex-result", 11.25);
  revealRow(worktreeResult, 11.25);
  timeline.addLabel("beat:rail-handoff", 11.6);
  const railTiming =
    rail === null
      ? { finalHopStart: 13.1, end: 13.2 }
      : addHeroRailStaircase({ timeline, artwork: rail, start: 11.6 });
  if (codexWorking !== null && options.width >= 1024)
    timeline.to(codexWorking, { opacity: 0, duration: 0.15, ease: "power2.out" }, 11.25);
  timeline.fromTo(
    [payoffFirst, payoffSecond],
    { y: 8, opacity: 0 },
    { y: 0, opacity: 1, duration: 0.3, ease: "expo.out" },
    railTiming.finalHopStart,
  );
  addHeroTokenBursts({ root, timeline, width: options.width });
}
