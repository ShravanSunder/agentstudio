import { createHash } from "node:crypto";

import { defineBrowserCommand } from "@vitest/browser-playwright";

export interface ChapterAutoplayObservation {
  readonly width: number;
  readonly stageVisibleFraction: number;
  readonly selectedStep: string;
  readonly sceneState: string | undefined;
}

export interface ChapterClickObservation {
  readonly stepId: string;
  readonly selectedStepId: string;
  readonly sceneState: string | undefined;
  readonly stageImageHash: string;
}

export const verifyChapterSceneClicks = defineBrowserCommand(
  async (
    { context },
    pageUrl: string,
    width: number,
    height: number,
  ): Promise<ChapterClickObservation[]> => {
    const applicationPage = await context.newPage();
    const samples: ChapterClickObservation[] = [];
    try {
      await applicationPage.route(/\.(mp4|webm)(\?|$)/u, async (route) => {
        await route.abort();
      });
      await applicationPage.setViewportSize({ width, height });
      await applicationPage.goto(pageUrl, { waitUntil: "domcontentloaded" });
      await applicationPage.evaluate(async () => {
        await document.fonts.ready;
      });
      await applicationPage.evaluate(() => {
        const chapter = document.getElementById("many-agents");
        if (chapter === null) throw new Error("Many-agents chapter is missing");
        window.scrollTo({
          top: window.scrollY + chapter.getBoundingClientRect().top - 96,
          behavior: "instant",
        });
      });
      await applicationPage.waitForSelector(
        '#many-agents [data-scene-root][data-scene-playback-state="playing"]',
      );
      for (const stepId of ["parallel-agents", "watch-folders", "navigation"]) {
        await applicationPage.click(`#many-agents [data-chapter-step="${stepId}"]`);
        const geometry = await applicationPage.evaluate(() => {
          const stage = document.querySelector("#many-agents [data-scroll-playback-stage]");
          const scene = document.querySelector<HTMLElement>("#many-agents [data-scene-root]");
          const selected = document.querySelector<HTMLElement>(
            '#many-agents [data-chapter-step][aria-selected="true"]',
          );
          if (stage === null || scene === null || selected === null)
            throw new Error("Chapter click state is missing");
          const bounds = stage.getBoundingClientRect();
          const x = Math.max(0, bounds.left);
          const y = Math.max(0, bounds.top);
          return {
            x,
            y,
            width: Math.min(bounds.right, innerWidth) - x,
            height: Math.min(bounds.bottom, innerHeight) - y,
            sceneState: scene.dataset["scenePlaybackState"],
            selectedStepId: selected.dataset["chapterStep"] ?? "",
          };
        });
        const image = await applicationPage.screenshot({
          clip: { x: geometry.x, y: geometry.y, width: geometry.width, height: geometry.height },
        });
        samples.push({
          stepId,
          selectedStepId: geometry.selectedStepId,
          sceneState: geometry.sceneState,
          stageImageHash: createHash("sha256").update(image).digest("hex"),
        });
        if (stepId === "parallel-agents") {
          await applicationPage.evaluate(() => window.scrollBy({ top: 1, behavior: "instant" }));
          await applicationPage.waitForFunction(() => {
            const artwork = document.querySelector<SVGSVGElement>("[data-full-page-topology]");
            const progress = Number(artwork?.dataset["topologyScrollProgress"]);
            const maxScroll = Math.max(document.documentElement.scrollHeight - innerHeight, 1);
            return Number.isFinite(progress) && Math.abs(progress - scrollY / maxScroll) < 0.0001;
          });
          const stillFirst = await applicationPage.evaluate(() => ({
            selected: document
              .querySelector('#many-agents [data-chapter-step][aria-selected="true"]')
              ?.getAttribute("data-chapter-step"),
            state: document.querySelector<HTMLElement>("#many-agents [data-scene-root]")?.dataset[
              "scenePlaybackState"
            ],
          }));
          if (stillFirst.selected !== "parallel-agents" || stillFirst.state !== "paused") {
            throw new Error(
              `Manual first step was reclaimed by autoplay: ${JSON.stringify(stillFirst)}`,
            );
          }
        }
      }
      return samples;
    } finally {
      await applicationPage.close();
    }
  },
);

export const verifyChapterAutoplayAtNaturalFraming = defineBrowserCommand(
  async (
    { context },
    pageUrl: string,
    width: number,
    height: number,
  ): Promise<ChapterAutoplayObservation> => {
    const applicationPage = await context.newPage();
    try {
      await applicationPage.route(/\.(mp4|webm)(\?|$)/u, async (route) => {
        await route.abort();
      });
      await applicationPage.setViewportSize({ width, height });
      await applicationPage.goto(pageUrl, { waitUntil: "domcontentloaded" });
      await applicationPage.evaluate(async () => {
        await document.fonts.ready;
      });
      await applicationPage.evaluate(() => {
        const chapter = document.getElementById("many-agents");
        if (chapter === null) throw new Error("Many-agents chapter is missing");
        window.scrollTo({
          top: window.scrollY + chapter.getBoundingClientRect().top - 96,
          behavior: "instant",
        });
      });
      await applicationPage.waitForSelector(
        '#many-agents [data-scene-root][data-scene-playback-state="playing"]',
      );
      await applicationPage.waitForFunction(
        () =>
          document
            .querySelector('#many-agents [data-chapter-step][aria-selected="true"]')
            ?.getAttribute("data-chapter-step") !== "parallel-agents",
      );
      return await applicationPage.evaluate((width): ChapterAutoplayObservation => {
        const stage = document.querySelector("#many-agents [data-scroll-playback-stage]");
        const scene = document.querySelector<HTMLElement>("#many-agents [data-scene-root]");
        const selected = document.querySelector<HTMLElement>(
          '#many-agents [data-chapter-step][aria-selected="true"]',
        );
        if (stage === null || scene === null || selected === null)
          throw new Error("Chapter autoplay is incomplete");
        const bounds = stage.getBoundingClientRect();
        const visible = Math.max(
          0,
          Math.min(bounds.bottom, window.innerHeight) - Math.max(bounds.top, 0),
        );
        return {
          width,
          stageVisibleFraction: visible / Math.min(bounds.height, window.innerHeight),
          selectedStep: selected.dataset["chapterStep"] ?? "",
          sceneState: scene.dataset["scenePlaybackState"],
        };
      }, width);
    } finally {
      await applicationPage.close();
    }
  },
);
