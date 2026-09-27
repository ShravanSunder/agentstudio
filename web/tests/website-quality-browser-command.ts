import { defineBrowserCommand } from "@vitest/browser-playwright";

interface WebsiteLayoutObservation {
  readonly width: number;
  readonly chapterCount: number;
  readonly clippedHeadings: readonly string[];
  readonly horizontalOverflow: number;
  readonly introHorizontalOverflow: number;
}

export const verifyWebsiteQualityLayout = defineBrowserCommand(
  async ({ context }, pageUrl: string): Promise<readonly WebsiteLayoutObservation[]> => {
    const applicationPage = await context.newPage();
    const observations: WebsiteLayoutObservation[] = [];
    try {
      await applicationPage.addInitScript((): void => {
        (window as Window & { websiteIntroReady?: Promise<void> }).websiteIntroReady = new Promise(
          (resolve) => {
            document.addEventListener("hero-intro-playback-ready", (event) => {
              if (!(event instanceof CustomEvent)) return;
              const control = event.detail as { pause(): void; seek(seconds: number): void };
              control.pause();
              (window as Window & { websiteIntroControl?: typeof control }).websiteIntroControl =
                control;
              resolve();
            });
          },
        );
      });
      await applicationPage.emulateMedia({ reducedMotion: "reduce" });
      /* eslint-disable no-await-in-loop -- One page owns the viewport; each width must settle before it is read. */
      for (const width of [320, 360, 375, 390, 900, 1144, 1280, 1440, 1600, 1920]) {
        await applicationPage.setViewportSize({ width, height: width <= 375 ? 667 : 1000 });
        await applicationPage.goto(pageUrl, { waitUntil: "networkidle" });
        const settledObservation = await applicationPage.evaluate(
          (): Omit<WebsiteLayoutObservation, "introHorizontalOverflow"> => {
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
          },
        );
        let introHorizontalOverflow = 0;
        if (width <= 375) {
          await applicationPage.emulateMedia({ reducedMotion: "no-preference" });
          await applicationPage.reload({ waitUntil: "load" });
          await applicationPage.evaluate(
            async (): Promise<void> =>
              await (window as Window & { websiteIntroReady?: Promise<void> }).websiteIntroReady,
          );
          introHorizontalOverflow = await applicationPage.evaluate((): number => {
            const introControl = (
              window as Window & { websiteIntroControl?: { seek(seconds: number): void } }
            ).websiteIntroControl;
            if (introControl === undefined) throw new Error("Intro playback control missing");
            introControl.seek(5.8);
            return document.documentElement.scrollWidth - document.documentElement.clientWidth;
          });
          await applicationPage.emulateMedia({ reducedMotion: "reduce" });
        }
        observations.push({ ...settledObservation, introHorizontalOverflow });
      }
      /* eslint-enable no-await-in-loop */
      return observations;
    } finally {
      await applicationPage.close();
    }
  },
);

export type { WebsiteLayoutObservation };
