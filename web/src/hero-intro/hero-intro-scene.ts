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
      border: "5px solid #89b4fa",
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
      borderWidth: 1,
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

  if (codexTypedInput !== null && codexPlaceholder !== null && options.width >= 1024) {
    const codexPrompt = "map the worktrees";
    const codexTyping = { fraction: 0 };
    timeline.set(codexPlaceholder, { opacity: 0 }, 3.65);
    timeline.to(
      codexTyping,
      {
        fraction: 1,
        duration: 0.61,
        ease: "none",
        onUpdate: () => {
          codexTypedInput.textContent = codexPrompt.slice(
            0,
            Math.floor(codexTyping.fraction * codexPrompt.length),
          );
        },
      },
      3.65,
    );
    timeline.set(codexTypedInput, { textContent: "" }, 4.28);
    timeline.set(codexPlaceholder, { opacity: 1 }, 4.28);
    if (codexCurrentRows !== null)
      timeline.to(codexCurrentRows, { opacity: 0, duration: 0.18, ease: "power2.out" }, 4.28);
    revealRow(visibleCodexRows[0], 4.28);
    revealRow(codexWorking, 4.3);
    revealRow(worktreeCommand, 5.2);
  }

  const spinnerGlyphs = ["✢", "✳", "✶", "✻", "✽"] as const;
  const spinnerState = { fraction: 0 };
  timeline.addLabel("beat:spinner", 3.85);
  timeline.fromTo(spinner, { opacity: 0 }, { opacity: 1, duration: 0.01 }, 3.85);
  timeline.to(
    spinnerState,
    {
      fraction: 1,
      duration: 1.7,
      ease: "none",
      onUpdate: () => {
        const glyphIndex = Math.min(
          spinnerGlyphs.length - 1,
          Math.floor(spinnerState.fraction * spinnerGlyphs.length),
        );
        spinner.textContent = `${spinnerGlyphs[glyphIndex]} Brewing… (esc to interrupt)`;
      },
    },
    3.85,
  );
  progressRows.forEach((row, index) => revealRow(row, 4.05 + index * 0.3));

  timeline.addLabel("beat:install-decode", 4.45);
  timeline.fromTo(
    install,
    { opacity: 0 },
    { opacity: 1, duration: 0.25, ease: "power1.out" },
    4.45,
  );
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
    4.6,
  );

  timeline.addLabel("beat:ready", 5.6);
  timeline.to(spinner, { opacity: 0, duration: 0.1 }, 5.55);
  revealRow(ready, 5.6);
  timeline.fromTo(
    readyArrow,
    { opacity: 1 },
    { opacity: 0.35, duration: 0.2, repeat: 1, yoyo: true, ease: "sine.inOut" },
    5.78,
  );

  if (options.width < 1024) {
    revealRow(
      visibleClaudeRows.find((row) => row.textContent?.includes("map the worktrees")),
      5.7,
    );
    revealRow(worktreeCommand, 5.78);
  }
  worktreeRows.forEach((row, index) => revealRow(row, 5.82 + index * 0.45));
  const railTiming =
    rail === null
      ? { finalHopStart: 7.3, end: 7.4 }
      : addHeroRailStaircase({ timeline, artwork: rail });
  revealRow(worktreeResult, railTiming.end + 0.1);
  if (codexWorking !== null && options.width >= 1024)
    timeline.to(
      codexWorking,
      { opacity: 0, duration: 0.15, ease: "power2.out" },
      railTiming.end + 0.1,
    );
  timeline.fromTo(
    [payoffFirst, payoffSecond],
    { y: 8, opacity: 0 },
    { y: 0, opacity: 1, duration: 0.6, ease: "expo.out" },
    railTiming.finalHopStart,
  );
}
