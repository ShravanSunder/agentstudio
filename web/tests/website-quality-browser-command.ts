import { defineBrowserCommand } from "@vitest/browser-playwright";

interface WebsiteLayoutObservation {
  readonly width: number;
  readonly chapterCount: number;
  readonly clippedHeadings: readonly string[];
  readonly horizontalOverflow: number;
}

export const verifyWebsiteQualityLayout = defineBrowserCommand(
  async ({ context }, pageUrl: string): Promise<readonly WebsiteLayoutObservation[]> => {
    const applicationPage = await context.newPage();
    const observations: WebsiteLayoutObservation[] = [];
    try {
      await applicationPage.emulateMedia({ reducedMotion: "reduce" });
      /* eslint-disable no-await-in-loop -- One page owns the viewport; each width must settle before it is read. */
      for (const width of [320, 390, 900, 1144, 1280, 1440, 1600, 1920]) {
        await applicationPage.setViewportSize({ width, height: 1000 });
        await applicationPage.goto(pageUrl, { waitUntil: "networkidle" });
        observations.push(
          await applicationPage.evaluate((): WebsiteLayoutObservation => {
            const headings = [
              ...document.querySelectorAll<HTMLElement>("#hero-title, [data-chapter] h2"),
            ];
            // A heading is clipped when any line box of its text leaves the heading's box.
            const clippedHeadings = headings
              .filter((heading): boolean => {
                const headingBounds = heading.getBoundingClientRect();
                const range = document.createRange();
                range.selectNodeContents(heading);
                return Array.from(range.getClientRects()).some(
                  (bounds): boolean =>
                    bounds.left < headingBounds.left - 1 || bounds.right > headingBounds.right + 1,
                );
              })
              .map((heading): string => heading.id);
            return {
              width: window.innerWidth,
              chapterCount: document.querySelectorAll("[data-chapter]").length,
              clippedHeadings,
              horizontalOverflow:
                document.documentElement.scrollWidth - document.documentElement.clientWidth,
            };
          }),
        );
      }
      /* eslint-enable no-await-in-loop */
      return observations;
    } finally {
      await applicationPage.close();
    }
  },
);

export type { WebsiteLayoutObservation };
