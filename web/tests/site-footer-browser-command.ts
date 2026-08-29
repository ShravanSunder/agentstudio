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

export const verifySiteFooterResponsiveLayout = defineBrowserCommand(
  async ({ context }, pageUrl: string): Promise<SiteFooterResponsiveLayoutResult> => {
    const applicationPage = await context.newPage();
    try {
      const readFooterLayout = async (width: number): Promise<FooterLayoutState> => {
        await applicationPage.setViewportSize({ height: 900, width });
        const response = await applicationPage.goto(pageUrl, { waitUntil: "networkidle" });
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
          const footer = document.querySelector<HTMLElement>("footer");
          const links = footer?.querySelectorAll<HTMLAnchorElement>("nav a");
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
