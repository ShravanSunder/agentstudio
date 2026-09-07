import { defineBrowserCommand } from "@vitest/browser-playwright";

interface WebsiteLayoutObservation {
  readonly width: number;
  readonly story: string;
  readonly clippedHeadline: boolean;
  readonly imageCenterOffset: number;
  readonly horizontalOverflow: number;
}

export const verifyWebsiteQualityLayout = defineBrowserCommand(
  async ({ context }, pageUrl: string): Promise<readonly WebsiteLayoutObservation[]> => {
    const applicationPage = await context.newPage();
    const observations: WebsiteLayoutObservation[] = [];
    try {
      await applicationPage.emulateMedia({ reducedMotion: "reduce" });
      /* eslint-disable no-await-in-loop -- One page owns viewport and selection; each state must settle before the next action. */
      for (const width of [320, 390, 900, 1144, 1280, 1440, 1600]) {
        await applicationPage.setViewportSize({ width, height: 1000 });
        await applicationPage.goto(pageUrl, { waitUntil: "networkidle" });
        await applicationPage.waitForSelector('[data-product-plate][data-enhanced="true"]');
        const selectors = applicationPage.locator("[data-product-plate-selector]");
        for (let index = 0; index < (await selectors.count()); index += 1) {
          if (width < 1024 && index > 0) {
            await applicationPage.locator("[data-product-plate-next]").click();
          } else if (width >= 1024) {
            await selectors.nth(index).click();
          }
          await applicationPage.waitForFunction((): boolean => {
            const image = document.querySelector<HTMLImageElement>(
              "[data-product-plate-panel]:not([hidden]) img",
            );
            return image !== null && image.complete && image.naturalWidth > 0;
          });
          observations.push(
            await applicationPage.evaluate((): WebsiteLayoutObservation => {
              const headline = document.querySelector<HTMLElement>("#hero-title");
              const column = document.querySelector<HTMLElement>(".product-plate__image-column");
              const panel = document.querySelector<HTMLElement>(
                "[data-product-plate-panel]:not([hidden])",
              );
              const image = panel?.querySelector<HTMLImageElement>("img");
              if (
                headline === null ||
                column === null ||
                panel === null ||
                image === undefined ||
                image === null
              ) {
                throw new Error("Website quality inspection is missing headline or selected media");
              }
              const headlineBounds = headline.getBoundingClientRect();
              const range = document.createRange();
              range.selectNodeContents(headline);
              const clippedHeadline = Array.from(range.getClientRects()).some(
                (bounds): boolean =>
                  bounds.left < headlineBounds.left - 1 || bounds.right > headlineBounds.right + 1,
              );
              const columnBounds = column.getBoundingClientRect();
              const imageBounds = image.getBoundingClientRect();
              return {
                width: window.innerWidth,
                story: panel.dataset["productPlatePanel"] ?? "unknown",
                clippedHeadline,
                imageCenterOffset: Math.abs(
                  (imageBounds.top + imageBounds.bottom - columnBounds.top - columnBounds.bottom) /
                    2,
                ),
                horizontalOverflow:
                  document.documentElement.scrollWidth - document.documentElement.clientWidth,
              };
            }),
          );
        }
      }
      /* eslint-enable no-await-in-loop */
      return observations;
    } finally {
      await applicationPage.close();
    }
  },
);

export type { WebsiteLayoutObservation };
