import { defineBrowserCommand } from "@vitest/browser-playwright";

export interface ChapterActivitySample {
  readonly chapterId: string;
  readonly playingChapters: readonly string[];
  readonly selectedStep: string | undefined;
  readonly stageVisibleFraction: number;
  readonly sceneState: string | undefined;
}

export const verifyChapterActivity = defineBrowserCommand(
  async (
    { context },
    pageUrl: string,
    width: number,
    height: number,
  ): Promise<ChapterActivitySample[]> => {
    const page = await context.newPage();
    const samples: ChapterActivitySample[] = [];
    try {
      await page.setViewportSize({ width, height });
      await page.goto(pageUrl, { waitUntil: "domcontentloaded" });
      await page.evaluate(async () => await document.fonts.ready);
      for (const [index, chapterId] of [
        "many-agents",
        "context-with-task",
        "many-agents",
        "review",
        "come-back",
      ].entries()) {
        samples.push(
          await page.evaluate(async (id): Promise<ChapterActivitySample> => {
            const chapter = document.querySelector<HTMLElement>(`[data-chapter="${id}"]`);
            const title = chapter?.querySelector<HTMLElement>(".chapter-title");
            const stage = chapter?.querySelector<HTMLElement>("[data-scroll-playback-stage]");
            const scene = chapter?.querySelector<HTMLElement>("[data-scene-root]");
            if (
              chapter === null ||
              title === null ||
              title === undefined ||
              stage === null ||
              stage === undefined ||
              scene === null ||
              scene === undefined
            )
              throw new Error(`Chapter activity markup missing for ${id}`);
            await new Promise<void>((resolve) => {
              const onChange = (event: Event): void => {
                if (!(event instanceof CustomEvent) || event.detail?.chapterId !== id) return;
                document.removeEventListener("chapter-activity-changed", onChange);
                resolve();
              };
              document.addEventListener("chapter-activity-changed", onChange);
              window.scrollTo({
                top: scrollY + title.getBoundingClientRect().top - innerHeight * 0.45 + 1,
                behavior: "instant",
              });
              window.dispatchEvent(new Event("scroll"));
            });
            const bounds = stage.getBoundingClientRect();
            const visibleHeight = Math.max(
              0,
              Math.min(bounds.bottom, innerHeight) - Math.max(bounds.top, 0),
            );
            return {
              chapterId: id,
              playingChapters: [
                ...document.querySelectorAll<HTMLElement>(
                  '[data-chapter] [data-scene-root][data-scene-playback-state="playing"]',
                ),
              ].map(
                (root) => root.closest<HTMLElement>("[data-chapter]")?.dataset["chapter"] ?? "",
              ),
              selectedStep: chapter.querySelector<HTMLElement>(
                '[data-chapter-step][aria-selected="true"]',
              )?.dataset["chapterStep"],
              stageVisibleFraction: visibleHeight / Math.min(bounds.height, innerHeight),
              sceneState: scene.dataset["scenePlaybackState"],
            };
          }, chapterId),
        );
        if (index === 0) {
          await page.evaluate(() =>
            document
              .querySelector<HTMLButtonElement>('#many-agents [data-chapter-step="navigation"]')
              ?.click(),
          );
        }
      }
      return samples;
    } finally {
      await page.close();
    }
  },
);
