import { gsap } from "gsap";
import { afterEach, beforeAll, describe, expect, inject, it } from "vitest";

import { chapterCatalog } from "../src/chapters/chapter-catalog";
import { sceneRootAttribute } from "../src/chapters/chapter-dom-contract";
import {
  isSceneId,
  sceneIds,
  type SceneId,
  type SceneTimeline,
} from "../src/motion-scenes/scene-contract";
import { resolveSceneModule } from "../src/motion-scenes/scene-registry";
import { kitPhoneAttribute } from "../src/recreation-kit/recreation-kit-dom";

declare module "vitest" {
  export interface ProvidedContext {
    siteHeaderBrowserTestUrl: string;
  }
}

// The only route that renders every scene until page integration. When the lab
// route is removed, point this at the page that mounts the chapter scenes.
const sceneMarkupPagePath = "lab/scenes/";

const desktopStage = { width: 1100, height: 688 } as const;
const phoneStage = { width: 358, height: 224 } as const;

interface SceneMarkupSource {
  readonly styles: readonly HTMLStyleElement[];
  readonly rootsBySceneId: ReadonlyMap<SceneId, HTMLElement>;
}

let sceneMarkupSource: SceneMarkupSource;
const mountedStages: HTMLElement[] = [];

async function loadSceneMarkupSource(): Promise<SceneMarkupSource> {
  const pageUrl = new URL(sceneMarkupPagePath, inject("siteHeaderBrowserTestUrl"));
  // Chrome refuses this page's fetch to the 127.0.0.1 spelling of the loopback
  // server; the test page's own host name reaches the same server.
  pageUrl.hostname = location.hostname;
  const response = await fetch(pageUrl);
  if (!response.ok) {
    throw new Error(`Scene markup page answered ${String(response.status)}`);
  }
  const page = new DOMParser().parseFromString(await response.text(), "text/html");
  const rootsBySceneId = new Map<SceneId, HTMLElement>();
  for (const root of page.querySelectorAll<HTMLElement>(`[${sceneRootAttribute}]`)) {
    const sceneId = root.getAttribute(sceneRootAttribute) ?? "";
    if (isSceneId(sceneId)) {
      rootsBySceneId.set(sceneId, root);
    }
  }
  return { styles: Array.from(page.querySelectorAll("head style")), rootsBySceneId };
}

function mountScene(
  sceneId: SceneId,
  stage: { readonly width: number; readonly height: number },
): HTMLElement {
  const sourceRoot = sceneMarkupSource.rootsBySceneId.get(sceneId);
  if (sourceRoot === undefined) {
    throw new Error(`Scene markup page has no root for ${sceneId}`);
  }
  const stageElement = document.createElement("div");
  stageElement.style.width = `${String(stage.width)}px`;
  stageElement.style.height = `${String(stage.height)}px`;
  const root = document.importNode(sourceRoot, true);
  stageElement.append(root);
  document.body.append(stageElement);
  mountedStages.push(stageElement);
  return root;
}

function buildMountedScene(sceneId: SceneId, root: HTMLElement, seed: number): SceneTimeline {
  const sceneModule = resolveSceneModule(sceneId);
  if (sceneModule === undefined) {
    throw new Error(`No scene module registered for ${sceneId}`);
  }
  const timeline = gsap.timeline({ paused: true });
  sceneModule.buildScene(root, timeline, {
    width: root.clientWidth,
    height: root.clientHeight,
    seed,
  });
  return timeline;
}

function elementPath(root: HTMLElement, element: Element): string {
  if (element === root) {
    return "root";
  }
  return String(Array.from(root.querySelectorAll("*")).indexOf(element));
}

// GSAP links its own runtime objects into vars; only the scene's declared values count.
function declaredValue(key: string, value: unknown): unknown {
  if (key.startsWith("_") || key === "parent" || value instanceof gsap.core.Animation) {
    return undefined;
  }
  return value instanceof Element ? "element" : value;
}

/** Every tween as start, duration, target positions, and its declared values. */
function describeTweens(root: HTMLElement, timeline: SceneTimeline): readonly string[] {
  return timeline.getChildren(true, true, false).map((tween) => {
    const targets = tween
      .targets()
      .map((target: unknown) => (target instanceof Element ? elementPath(root, target) : "hold"));
    return JSON.stringify(
      [tween.startTime(), tween.duration(), targets, tween.vars],
      declaredValue,
    );
  });
}

function animatedElements(timeline: SceneTimeline): readonly HTMLElement[] {
  const elements = timeline
    .getChildren(true, true, false)
    .flatMap((tween) => tween.targets())
    .filter((target: unknown): target is HTMLElement => target instanceof HTMLElement);
  return Array.from(new Set(elements));
}

// Visually equivalent spellings: GSAP leaves an identity transform or a fully
// open inset where the markup has none.
function canonicalStyleValue(value: string): string {
  if (value === "matrix(1, 0, 0, 1, 0, 0)" || value === "inset(0%)") {
    return "none";
  }
  return value.trim();
}

const snapshotProperties = [
  "opacity",
  "visibility",
  "transform",
  "clip-path",
  "grid-template-rows",
  "flex-grow",
  "translate",
  "--scene-zoom",
  "--scene-files-reveal",
  "--scene-drawer-scroll",
] as const;

function snapshotVisibleState(elements: readonly HTMLElement[]): readonly string[] {
  return elements.map((element) => {
    const computedStyle = getComputedStyle(element);
    return snapshotProperties
      .map(
        (property) =>
          `${property}=${canonicalStyleValue(computedStyle.getPropertyValue(property))}`,
      )
      .join(" ");
  });
}

function countRenderedPanes(root: HTMLElement): number {
  return Array.from(root.querySelectorAll<HTMLElement>(".kit-pane")).filter((pane) => {
    const bounds = pane.getBoundingClientRect();
    return bounds.width > 1 && getComputedStyle(pane).opacity !== "0";
  }).length;
}

describe("motion scenes on their real markup", () => {
  beforeAll(async () => {
    sceneMarkupSource = await loadSceneMarkupSource();
    for (const style of sceneMarkupSource.styles) {
      document.head.append(document.importNode(style, true));
    }
  });

  afterEach(() => {
    for (const stage of mountedStages.splice(0)) {
      stage.remove();
    }
  });

  for (const sceneId of sceneIds) {
    describe(sceneId, () => {
      it("labels its timeline with the chapter's steps and lasts 8 to 14 seconds", () => {
        // Arrange
        const chapter = chapterCatalog.find(
          (candidate) => candidate.stage.kind === "scene" && candidate.stage.sceneId === sceneId,
        );
        const root = mountScene(sceneId, desktopStage);

        // Act
        const timeline = buildMountedScene(sceneId, root, 1);
        const labelsInTimeOrder = Object.entries(timeline.labels)
          .toSorted(([, firstTime], [, secondTime]) => firstTime - secondTime)
          .map(([labelName]) => labelName);

        // Assert
        expect(labelsInTimeOrder).toEqual(
          resolveSceneModule(sceneId)?.steps.map((step) => step.timelineLabel),
        );
        expect(resolveSceneModule(sceneId)?.steps.map((step) => step.stepId)).toEqual(
          chapter?.steps.map((step) => step.id),
        );
        expect(timeline.duration()).toBeGreaterThanOrEqual(8);
        expect(timeline.duration()).toBeLessThanOrEqual(14);
      });

      it("builds the same tween list for the same seed", () => {
        // Arrange
        const firstRoot = mountScene(sceneId, desktopStage);
        const secondRoot = mountScene(sceneId, desktopStage);

        // Act
        const firstTweens = describeTweens(firstRoot, buildMountedScene(sceneId, firstRoot, 7));
        const secondTweens = describeTweens(secondRoot, buildMountedScene(sceneId, secondRoot, 7));

        // Assert
        expect(firstTweens.length).toBeGreaterThan(5);
        expect(secondTweens).toEqual(firstTweens);
      });

      it("ends on its settled markup and returns there after out-of-order seeks", () => {
        // Arrange
        const root = mountScene(sceneId, desktopStage);
        const settledMarkupRoot = mountScene(sceneId, desktopStage);
        const timeline = buildMountedScene(sceneId, root, 1);
        const targets = animatedElements(timeline);
        const settledTargets = targets.map((target) => {
          const path = elementPath(root, target);
          return path === "root"
            ? settledMarkupRoot
            : (settledMarkupRoot.querySelectorAll<HTMLElement>("*")[Number(path)] ??
                settledMarkupRoot);
        });
        const settledMarkupState = snapshotVisibleState(settledTargets);

        // Act
        const startState = snapshotVisibleState(targets);
        timeline.progress(1);
        const endState = snapshotVisibleState(targets);
        timeline.progress(0.4);
        timeline.progress(0);
        timeline.progress(1);
        const replayedEndState = snapshotVisibleState(targets);

        // Assert
        expect(startState).not.toEqual(settledMarkupState);
        expect(endState).toEqual(settledMarkupState);
        expect(replayedEndState).toEqual(settledMarkupState);
      });

      it("shows fewer panes in the phone crop than on desktop", () => {
        // Arrange
        const desktopRoot = mountScene(sceneId, desktopStage);
        const phoneRoot = mountScene(sceneId, phoneStage);

        // Act
        const phoneHiddenElements = Array.from(
          phoneRoot.querySelectorAll<HTMLElement>(`[${kitPhoneAttribute}="hidden"]`),
        );

        // Assert
        expect(phoneHiddenElements.length).toBeGreaterThan(0);
        expect(
          phoneHiddenElements.every((element) => element.getBoundingClientRect().width === 0),
        ).toBe(true);
        expect(countRenderedPanes(phoneRoot)).toBeLessThanOrEqual(countRenderedPanes(desktopRoot));
        expect(countRenderedPanes(phoneRoot)).toBeGreaterThan(0);
      });
    });
  }
});
