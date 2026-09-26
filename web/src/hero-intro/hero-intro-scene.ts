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
  const fanPlanes = [iconFront, rearTwo, rearOne] as const;
  const stackStep =
    Number.parseFloat(getComputedStyle(root).getPropertyValue("--hero-stack-step")) || 3;
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
  const claudeCurrentRows = root.querySelector<HTMLElement>(".hero-claude-current-rows");
  const finalePane = options.width < 1024 ? "claude" : "codex";
  const finaleRows = [
    ...root.querySelectorAll<HTMLElement>(
      `.hero-terminal-pane--${finalePane} [${heroIntroFinaleRowAttribute}]`,
    ),
  ];
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
  timeline.fromTo(
    [payoffFirst, payoffSecond],
    { y: 8, opacity: 0 },
    { y: 0, opacity: 1, duration: 0.6, ease: "expo.out" },
    6.2,
  );

  if (codexCurrentRows !== null) timeline.set(codexCurrentRows, { opacity: 1 }, 0);
  if (claudeCurrentRows !== null && options.width < 1024)
    timeline.set(claudeCurrentRows, { opacity: 1 }, 0);
  if (finaleRows.length > 0) timeline.set(finaleRows, { opacity: 0 }, 0);
  timeline.set(ready, { opacity: 0 }, 0);
  timeline.set(spinner, { opacity: 0 }, 0);
  timeline.set(typedInput, { textContent: "" }, 0);
  timeline.set(decodeLines, { opacity: 0 }, 0);
  if (copyButton !== null) timeline.set(copyButton, { opacity: 0 }, 0);

  timeline.addLabel("beat:icon", 0.9);
  timeline.fromTo(
    iconStack,
    { scale: 0.86, opacity: 0 },
    { scale: 1, opacity: 1, duration: 0.45, ease: "back.out(1.4)" },
    0.9,
  );
  timeline.set(fanPlanes, { rotation: 0 }, 0);
  fanPlanes.forEach((plane, index) => {
    timeline.to(
      plane,
      { rotation: -stackStep * (index + 1), duration: 0.35, ease: "power3.out" },
      1.2,
    );
  });
  timeline.set(iconCursor, { opacity: 0 }, 0);
  timeline.addLabel("beat:window", 1.45);
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
      duration: 0.2,
      ease: "power2.out",
    },
    1.45,
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
      duration: 0.55,
      ease: "power3.inOut",
    },
    1.65,
  );
  timeline.fromTo(windowNode, { opacity: 0 }, { opacity: 1, duration: 0.2, ease: "sine.out" }, 2.2);
  timeline.to(fourthPlane, { opacity: 0, duration: 0.2, ease: "sine.out" }, 2.2);
  timeline.fromTo(
    windowContent,
    { opacity: 0 },
    { opacity: 1, duration: 0.2, ease: "sine.out" },
    2.2,
  );
  timeline.set(iconStack, { zIndex: 1 }, 2.2);
  timeline.fromTo(glow, { opacity: 0 }, { opacity: 1, duration: 2.8, ease: "sine.inOut" }, 2.2);

  timeline.addLabel("beat:prompt", 2.6);
  const inputText = "set up Agent Studio for me";
  const typing = { fraction: 0 };
  timeline.to(
    typing,
    {
      fraction: 1,
      duration: 1,
      ease: "none",
      onUpdate: () => {
        typedInput.textContent = inputText.slice(0, Math.floor(typing.fraction * inputText.length));
      },
    },
    2.6,
  );
  timeline.set(typedInput, { textContent: "" }, 3.7);
  const spinnerGlyphs = ["✢", "✳", "✶", "✻", "✽"] as const;
  const spinnerState = { fraction: 0 };
  timeline.addLabel("beat:spinner", 3.7);
  timeline.fromTo(spinner, { opacity: 0 }, { opacity: 1, duration: 0.01 }, 3.7);
  timeline.to(
    spinnerState,
    {
      fraction: 1,
      duration: 0.5,
      ease: "none",
      onUpdate: () => {
        const glyphIndex = Math.min(
          spinnerGlyphs.length - 1,
          Math.floor(spinnerState.fraction * spinnerGlyphs.length),
        );
        spinner.textContent = `${spinnerGlyphs[glyphIndex]} Brewing… (esc to interrupt)`;
      },
    },
    3.7,
  );
  timeline.to(spinner, { opacity: 0, duration: 0.01 }, 4.2);

  timeline.addLabel("beat:ready-and-install", 4.2);
  timeline.fromTo(
    ready,
    { opacity: 0, x: -4 },
    { opacity: 1, x: 0, duration: 0.2, ease: "power2.out" },
    4.2,
  );
  timeline.fromTo(
    readyArrow,
    { opacity: 1 },
    { opacity: 0.35, duration: 0.2, repeat: 1, yoyo: true, ease: "sine.inOut" },
    4.35,
  );
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

  timeline.addLabel("beat:resolve", 5.6);
  const currentFinaleRows = options.width < 1024 ? claudeCurrentRows : codexCurrentRows;
  if (currentFinaleRows !== null)
    timeline.to(currentFinaleRows, { opacity: 0, duration: 0.25, ease: "power2.out" }, 5.6);
  if (finaleRows[0] !== undefined)
    timeline.fromTo(
      finaleRows[0],
      { opacity: 0 },
      { opacity: 1, duration: 0.25, ease: "power2.out" },
      5.6,
    );
  if (options.width < 1024) {
    const preservedBashRow = finaleRows.find((row) => row.textContent?.includes("Bash("));
    if (preservedBashRow !== undefined) timeline.set(preservedBashRow, { opacity: 1 }, 5.6);
  }

  if (rail !== null) {
    addHeroRailStaircase({ timeline, artwork: rail });
  }
}
