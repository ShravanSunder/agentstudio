import { defineBrowserCommand } from "@vitest/browser-playwright";

interface FooterLinkBounds {
  readonly centerX: number;
  readonly right: number;
  readonly top: number;
}

interface FooterLayoutState {
  readonly footerCenterX: number;
  readonly footerRight: number;
  readonly horizontalOverflow: number;
  readonly links: readonly FooterLinkBounds[];
}

export interface SiteFooterResponsiveLayoutResult {
  readonly desktop: FooterLayoutState;
  readonly narrow: FooterLayoutState;
}

export interface FooterEndRoomObservation {
  readonly width: number;
  readonly bottomPadding: number;
  readonly blankBelowCredits: number;
  readonly finaleState: string | undefined;
  readonly endReached: boolean;
}

export const verifyFooterEndRoom = defineBrowserCommand(
  async (
    { context },
    pageUrl: string,
    widths: readonly number[],
  ): Promise<FooterEndRoomObservation[]> => {
    const results: FooterEndRoomObservation[] = [];
    for (const width of widths) {
      const page = await context.newPage();
      try {
        await page.setViewportSize({
          width,
          height: width === 390 ? 844 : width === 1280 ? 800 : 1080,
        });
        await page.goto(pageUrl, { waitUntil: "domcontentloaded" });
        await page.evaluate(() => window.dispatchEvent(new WheelEvent("wheel")));
        await page.locator('[data-hero-intro-state="settled"]').waitFor();
        await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
        await page.locator("[data-topology-end-reached]").waitFor();
        results.push(
          await page.evaluate(() => {
            const credits = document.querySelector<HTMLElement>(
              'footer nav[aria-label="Product credits and links"]',
            );
            const footer = credits?.closest<HTMLElement>("footer");
            const finale = document.querySelector<HTMLElement>("[data-finale-root]");
            if (credits === null || footer === null || footer === undefined || finale === null)
              throw new Error("Footer end-room proof markup is missing");
            return {
              width: innerWidth,
              bottomPadding: Number.parseFloat(getComputedStyle(footer).paddingBottom),
              blankBelowCredits:
                document.documentElement.scrollHeight -
                (credits.getBoundingClientRect().bottom + scrollY),
              finaleState: finale.dataset["finaleState"],
              endReached: document.querySelector("[data-topology-end-reached]") !== null,
            };
          }),
        );
      } finally {
        await page.close();
      }
    }
    return results;
  },
);

export const verifySiteFooterResponsiveLayout = defineBrowserCommand(
  async ({ context }, pageUrl: string): Promise<SiteFooterResponsiveLayoutResult> => {
    const applicationPage = await context.newPage();
    try {
      const readFooterLayout = async (width: number): Promise<FooterLayoutState> => {
        await applicationPage.setViewportSize({ height: 900, width });
        const response = await applicationPage.goto(pageUrl, { waitUntil: "domcontentloaded" });
        if (response === null || !response.ok()) {
          throw new Error(
            `Footer browser-test page failed to load: ${applicationPage.url()} (${String(response?.status())})`,
          );
        }
        await applicationPage.waitForSelector(
          'footer nav[aria-label="Product credits and links"]',
          { state: "visible" },
        );
        return await applicationPage.evaluate((): FooterLayoutState => {
          // Scene recreations render pane footers too; the site footer owns the credits nav.
          const creditsNav = document.querySelector<HTMLElement>(
            'footer nav[aria-label="Product credits and links"]',
          );
          const footer = creditsNav?.closest<HTMLElement>("footer") ?? null;
          const links = creditsNav?.querySelectorAll<HTMLAnchorElement>("a");
          if (footer === null || links === undefined || links.length !== 2) {
            throw new Error("Rendered page is missing the two product-credit footer links");
          }
          const footerBounds = footer.getBoundingClientRect();
          return {
            footerCenterX: footerBounds.x + footerBounds.width / 2,
            footerRight: footerBounds.right,
            horizontalOverflow:
              document.documentElement.scrollWidth - document.documentElement.clientWidth,
            links: Array.from(links, (link): FooterLinkBounds => {
              const linkBounds = link.getBoundingClientRect();
              return {
                centerX: linkBounds.x + linkBounds.width / 2,
                right: linkBounds.right,
                top: linkBounds.top,
              };
            }),
          };
        });
      };

      return {
        desktop: await readFooterLayout(1_440),
        narrow: await readFooterLayout(767),
      };
    } finally {
      await applicationPage.close();
    }
  },
);
