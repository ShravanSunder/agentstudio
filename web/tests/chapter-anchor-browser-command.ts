import { defineBrowserCommand } from "@vitest/browser-playwright";

export interface ChapterAnchorLandingViewport {
  readonly height: number;
  readonly width: number;
}

export interface ChapterAnchorLandingObservation {
  readonly chapterHeadingTop: number;
  readonly chapterTitleBottom: number;
  readonly headerBottom: number;
  readonly scrollY: number;
  readonly viewport: ChapterAnchorLandingViewport;
  readonly viewportHeight: number;
}

interface ChapterAnchorLandingRequest {
  readonly chapterId: string;
  readonly pageUrl: string;
  readonly viewports: readonly ChapterAnchorLandingViewport[];
}

/**
 * Opens the page at `#<chapterId>` in a fresh page per viewport and reports
 * where the chapter heading lands relative to the sticky header. Reduced
 * motion makes the fragment jump and the header's floating transition settle
 * at once, so the settled geometry is read without timing the animations.
 */
export const verifyChapterAnchorLanding = defineBrowserCommand(
  async (
    { context },
    request: ChapterAnchorLandingRequest,
  ): Promise<readonly ChapterAnchorLandingObservation[]> => {
    const observations: ChapterAnchorLandingObservation[] = [];
    /* eslint-disable no-await-in-loop -- Each viewport needs its own fresh navigation to the fragment. */
    for (const viewport of request.viewports) {
      const applicationPage = await context.newPage();
      try {
        await applicationPage.emulateMedia({ reducedMotion: "reduce" });
        await applicationPage.setViewportSize(viewport);
        const pageUrl = new URL(request.pageUrl);
        pageUrl.hash = request.chapterId;
        const response = await applicationPage.goto(pageUrl.href, { waitUntil: "networkidle" });
        if (response === null || !response.ok()) {
          throw new Error(`Chapter anchor page failed to load: ${pageUrl.href}`);
        }
        await applicationPage.waitForSelector('[data-site-header][data-visual-state="floating"]');
        observations.push({
          ...(await applicationPage.evaluate(
            (chapterId: string): Omit<ChapterAnchorLandingObservation, "viewport"> => {
              const header = document.querySelector<HTMLElement>("[data-site-header]");
              const chapter = document.getElementById(chapterId);
              const heading = chapter?.querySelector<HTMLElement>("[data-rail-anchor]") ?? null;
              const title = chapter?.querySelector<HTMLElement>("h2") ?? null;
              if (header === null || heading === null || title === null) {
                throw new Error(`Page is missing the header or chapter "${chapterId}"`);
              }
              return {
                chapterHeadingTop: heading.getBoundingClientRect().top,
                chapterTitleBottom: title.getBoundingClientRect().bottom,
                headerBottom: header.getBoundingClientRect().bottom,
                scrollY: window.scrollY,
                viewportHeight: window.innerHeight,
              };
            },
            request.chapterId,
          )),
          viewport,
        });
      } finally {
        await applicationPage.close();
      }
    }
    /* eslint-enable no-await-in-loop */
    return observations;
  },
);
