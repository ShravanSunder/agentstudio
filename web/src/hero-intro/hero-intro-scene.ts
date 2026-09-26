import type { SceneBuildOptions, SceneTimeline } from "../motion-scenes/scene-contract";
import {
  heroIconCursorAttribute,
  heroIconFrontAttribute,
  heroIconRearAttribute,
  heroIconStackAttribute,
  heroIntroContentAttribute,
  heroIntroCopyAttribute,
  heroIntroFourthPlaneAttribute,
  heroIntroGlowAttribute,
  heroIntroInstallAttribute,
  heroIntroSpinnerAttribute,
  heroIntroReadyAttribute,
  heroIntroTypedInputAttribute,
  heroTerminalWindowAttribute,
} from "./hero-intro-dom-contract";

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
    requiredTarget(root, heroIconStackAttribute),
    requiredTarget(root, heroIconFrontAttribute),
    ...root.querySelectorAll<HTMLElement>(`[${heroIconRearAttribute}]`),
    requiredTarget(root, heroIconCursorAttribute),
    requiredTarget(root, heroTerminalWindowAttribute),
    requiredTarget(root, heroIntroContentAttribute),
    requiredTarget(root, heroIntroInstallAttribute),
    requiredTarget(root, heroIntroGlowAttribute),
    requiredTarget(root, heroIntroTypedInputAttribute),
    requiredTarget(root, heroIntroSpinnerAttribute),
    ...root.querySelectorAll<HTMLElement>(".hero-codex-footer"),
    ...root.querySelectorAll<HTMLElement>(".hero-transcript-row"),
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

function storyboardPower3InOut(progress: number): number {
  return progress < 0.5 ? 4 * progress ** 3 : 1 - (-2 * progress + 2) ** 3 / 2;
}

/** Adds the single seek-safe intro to a paused timeline owned by playback. */
export function buildHeroIntroScene(
  root: HTMLElement,
  timeline: SceneTimeline,
  options: SceneBuildOptions,
): void {
  const copy = requiredTarget(root, heroIntroCopyAttribute);
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
    Number.parseFloat(getComputedStyle(root).getPropertyValue("--hero-stack-step")) || 7;
  const iconCursor = requiredTarget(root, heroIconCursorAttribute);
  const windowNode = requiredTarget(root, heroTerminalWindowAttribute);
  const windowContent = requiredTarget(root, heroIntroContentAttribute);
  const install = requiredTarget(root, heroIntroInstallAttribute);
  const glow = requiredTarget(root, heroIntroGlowAttribute);
  const typedInput = requiredTarget(root, heroIntroTypedInputAttribute);
  const spinner = requiredTarget(root, heroIntroSpinnerAttribute);
  const ready = requiredTarget(root, heroIntroReadyAttribute);
  const codexFooter = root.querySelector<HTMLElement>(".hero-codex-footer");

  // Read the three layout rects once. Every following value is derived from them.
  const sceneRect = sceneContainer.getBoundingClientRect();
  const frontRect = iconFront.getBoundingClientRect();
  const windowRect = windowNode.getBoundingClientRect();
  const frontCenterX = frontRect.left + frontRect.width / 2;
  const frontCenterY = frontRect.top + frontRect.height / 2;
  const windowCenterX = windowRect.left + windowRect.width / 2;
  const windowCenterY = windowRect.top + windowRect.height / 2;
  const startWidth = options.width < 620 ? 170 : 260;
  const startHeight = options.width < 620 ? 108 : 165;
  const stackScale = startWidth / frontRect.width;
  const stackStartX = windowCenterX - frontCenterX;
  const stackStartY = windowCenterY - frontCenterY;
  const fourthPlane = createFourthPlane(sceneContainer);
  const fourthLeft = frontRect.left - sceneRect.left;
  const fourthTop = frontRect.top - sceneRect.top;
  const fourthDestinationLeft = windowRect.left - sceneRect.left;
  const fourthDestinationTop = windowRect.top - sceneRect.top;
  const fourthDeal = options.width < 620 ? 24 : 48;
  // The fanned front's bounding box starts farther left than its painted
  // origin; these offsets keep the dealt plane behind the visible icon.
  const fourthStartAdjustmentX = options.width < 620 ? 0 : -60;
  const fourthDealAdjustmentX = options.width < 620 ? 12 : 6;
  const fourthDealAdjustmentY = options.width < 620 ? 3 : 9;
  const dockAtDeal = (2.55 - 2.4) / (2.75 - 2.4);
  const dockProgressAtDeal = storyboardPower3InOut(dockAtDeal);
  const fourthStartLeft =
    fourthLeft + stackStartX * (1 - dockProgressAtDeal) + fourthStartAdjustmentX;
  const fourthStartTop = fourthTop + stackStartY * (1 - dockProgressAtDeal);
  const frontEntranceX = options.width - windowRect.left + startWidth;
  const glassRadius = getComputedStyle(windowNode).borderTopLeftRadius;

  timeline.fromTo(copy, { y: 20, opacity: 0 }, { y: 0, opacity: 1, duration: 0.6 }, 0);
  timeline.set(iconStack, { zIndex: 4 }, 0);
  timeline.fromTo(
    iconStack,
    { x: stackStartX, y: stackStartY, scale: stackScale },
    { x: stackStartX, y: stackStartY, scale: stackScale, duration: 0.01 },
    0,
  );
  timeline.set(fanPlanes, { rotation: 0 }, 0);
  timeline.fromTo(
    iconFront,
    { x: frontEntranceX, opacity: 0 },
    { x: 0, opacity: 1, duration: 0.5, ease: "power3.out" },
    0.8,
  );
  timeline.fromTo(rearTwo, { x: 24, opacity: 0 }, { x: 0, opacity: 1, duration: 0.22 }, 1.35);
  timeline.fromTo(rearOne, { x: 18, opacity: 0 }, { x: 0, opacity: 1, duration: 0.22 }, 1.58);
  timeline.fromTo(iconCursor, { opacity: 0 }, { opacity: 1, duration: 0.12 }, 2.2);
  timeline.set(iconCursor, { opacity: 0 }, 2.75);
  timeline.set(iconCursor, { opacity: 1 }, 3.05);
  timeline.to(
    iconStack,
    { x: 0, y: 0, scale: 1, duration: 0.35, ease: storyboardPower3InOut },
    2.4,
  );
  fanPlanes.forEach((plane, index) => {
    const planeStep = index + 1;
    timeline.to(
      plane,
      { rotation: -6 * planeStep, duration: 0.35, ease: storyboardPower3InOut },
      2.4,
    );
    timeline.to(
      plane,
      { rotation: -stackStep * planeStep, duration: 0.3, ease: "back.out(1.6)" },
      2.75,
    );
  });
  timeline.set(iconStack, { zIndex: 1 }, 3.05);

  timeline.fromTo(
    fourthPlane,
    {
      left: fourthStartLeft,
      top: fourthStartTop,
      width: startWidth,
      height: startHeight,
      border: "5px solid #89b4fa",
      borderRadius: getComputedStyle(iconFront).borderTopLeftRadius,
      opacity: 0,
    },
    {
      left: fourthLeft + fourthDeal + fourthDealAdjustmentX,
      top: fourthTop + fourthDealAdjustmentY,
      width: startWidth,
      height: startHeight,
      opacity: 1,
      duration: 0.4,
      ease: "power3.out",
    },
    2.55,
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
      duration: 0.45,
      ease: storyboardPower3InOut,
    },
    2.95,
  );
  timeline.fromTo(windowNode, { opacity: 0 }, { opacity: 1, duration: 0.01 }, 3.4);
  timeline.to(fourthPlane, { opacity: 0, duration: 0.01 }, 3.4);
  timeline.fromTo(windowContent, { opacity: 0 }, { opacity: 1, duration: 0.14 }, 3.4);

  const currentRows = root.querySelectorAll<HTMLElement>(
    ".hero-transcript-row--user-band, .hero-transcript-row--assistant-text, .hero-transcript-row--tool-call, .hero-transcript-row--tool-result:not([data-hero-intro-ready]), .hero-transcript-row--codex-action, .hero-transcript-row--codex-detail, .hero-transcript-row--codex-prose",
  );
  currentRows.forEach((row, index) => {
    timeline.fromTo(row, { opacity: 0 }, { opacity: 1, duration: 0.08 }, 3.65 + index * 0.055);
  });

  const inputText = "set up Agent Studio for me";
  const typing = { fraction: 0 };
  timeline.to(
    typing,
    {
      fraction: 1,
      duration: inputText.length * 0.018,
      ease: "none",
      onUpdate: () => {
        typedInput.textContent = inputText.slice(0, Math.floor(typing.fraction * inputText.length));
      },
    },
    3.45,
  );
  timeline.set(typedInput, { textContent: "" }, 4.03);
  const spinnerGlyphs = ["✢", "✳", "✶", "✻", "✽"] as const;
  const spinnerState = { fraction: 0 };
  timeline.fromTo(spinner, { opacity: 0 }, { opacity: 1, duration: 0.01 }, 4.1);
  timeline.to(
    spinnerState,
    {
      fraction: 1,
      duration: 0.4,
      ease: "none",
      onUpdate: () => {
        const glyphIndex = Math.min(4, Math.floor(spinnerState.fraction * spinnerGlyphs.length));
        spinner.textContent = `${spinnerGlyphs[glyphIndex]} Brewing… (esc to interrupt)`;
      },
    },
    4.1,
  );
  timeline.to(spinner, { opacity: 0, duration: 0.01 }, 4.5);
  timeline.fromTo(ready, { opacity: 0 }, { opacity: 1, duration: 0.08 }, 4.5);
  if (codexFooter !== null) {
    timeline.fromTo(codexFooter, { opacity: 0 }, { opacity: 1, duration: 0.16 }, 4.0);
  }
  timeline.fromTo(install, { y: 14, opacity: 0 }, { y: 0, opacity: 1, duration: 0.3 }, 4.5);
  timeline.fromTo(glow, { opacity: 0 }, { opacity: 1, duration: 0.8 }, 4.8);
}
