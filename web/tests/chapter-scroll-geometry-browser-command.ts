import { defineBrowserCommand } from "@vitest/browser-playwright";

export interface ChapterScrollGeometrySample {
  readonly chapterId: string;
  readonly width: number;
  readonly scrollY: number;
  readonly gaps: readonly number[];
  readonly branchEdgeError: number;
  readonly branchWithinTarget: boolean;
  readonly glassTransform: string;
  readonly glassLiftValue: number;
  readonly groupLiftValue: number;
  readonly minimumTextClearance: number;
}

interface ChapterScrollRequest {
  readonly pageUrl: string;
  readonly width: number;
  readonly height: number;
}

function readChapterScrollGeometry({
  chapterId,
  width,
}: {
  readonly chapterId: string;
  readonly width: number;
}): ChapterScrollGeometrySample {
  const chapter = document.getElementById(chapterId);
  const title = chapter?.querySelector("[data-rail-anchor]");
  const pill = chapter?.querySelector("[data-rail-step-pill-target]");
  const glass = chapter?.querySelector("[data-rail-surface-target]");
  const caption = chapter?.querySelector(".chapter-caption");
  const artwork = document.querySelector<SVGSVGElement>("[data-full-page-topology]");
  const route = artwork?.querySelector<SVGGElement>(
    `[data-route-kind="attach"][data-route-anchor="${chapterId}"]`,
  );
  const path = route?.querySelector<SVGPathElement>('[data-topology-path-role="core"]');
  if (
    title === null ||
    glass === null ||
    caption === null ||
    path === null ||
    chapter === null ||
    title === undefined ||
    glass === undefined ||
    caption === undefined ||
    path === undefined
  ) {
    throw new Error(`Chapter ${chapterId} has no measurable geometry`);
  }
  const matrix = path.getScreenCTM();
  if (matrix === null) throw new Error(`Chapter ${chapterId} has no route transform`);
  const end = path.getPointAtLength(path.getTotalLength()).matrixTransform(matrix);
  const titleBox = title.getBoundingClientRect();
  const glassBox = glass.getBoundingClientRect();
  const captionBox = caption.getBoundingClientRect();
  const pillBox = pill?.getBoundingClientRect();
  const desktop = width >= 1024;
  const targetIsPill = desktop && pillBox !== undefined;
  const targetIsTop = !desktop;
  const textRects = [
    title,
    ...chapter.querySelectorAll("[data-chapter-step-label], .chapter-caption__copy"),
  ]
    .filter(
      (element) =>
        getComputedStyle(element).visibility !== "hidden" &&
        getComputedStyle(element).display !== "none",
    )
    .map((element) => element.getBoundingClientRect());
  const pathLength = path.getTotalLength();
  const minimumTextClearance = Math.min(
    ...Array.from({ length: 101 }, (_, index) => {
      const point = path.getPointAtLength((pathLength * index) / 100).matrixTransform(matrix);
      return Math.min(
        ...textRects.map((rect) => {
          const dx = Math.max(rect.left - point.x, 0, point.x - rect.right);
          const dy = Math.max(rect.top - point.y, 0, point.y - rect.bottom);
          return Math.hypot(dx, dy);
        }),
      );
    }),
  );
  return {
    chapterId,
    width,
    scrollY: window.scrollY,
    gaps: targetIsPill
      ? [
          pillBox.top - titleBox.bottom,
          glassBox.top - pillBox.bottom,
          captionBox.top - glassBox.bottom,
        ]
      : pillBox === undefined
        ? [glassBox.top - titleBox.bottom, captionBox.top - glassBox.bottom]
        : [
            glassBox.top - titleBox.bottom,
            pillBox.top - glassBox.bottom,
            captionBox.top - pillBox.bottom,
          ],
    branchEdgeError: targetIsPill
      ? Math.max(
          Math.abs(end.x - pillBox.left),
          Math.abs(end.y - (pillBox.top + pillBox.bottom) / 2),
        )
      : targetIsTop
        ? Math.abs(end.y - glassBox.top)
        : Math.abs(end.x - glassBox.left),
    branchWithinTarget:
      targetIsPill || targetIsTop ? true : end.y >= glassBox.top && end.y <= glassBox.bottom,
    glassTransform: getComputedStyle(glass).transform,
    glassLiftValue: Number.parseFloat(
      getComputedStyle(glass).getPropertyValue("--scroll-material-lift"),
    ),
    groupLiftValue: Number.parseFloat(
      getComputedStyle(
        chapter.querySelector("[data-scroll-material-lift-target]") ?? chapter,
      ).getPropertyValue("--scroll-material-lift"),
    ),
    minimumTextClearance,
  };
}

export const verifyChapterScrollGeometry = defineBrowserCommand(
  async ({ context }, request: ChapterScrollRequest): Promise<ChapterScrollGeometrySample[]> => {
    const applicationPage = await context.newPage();
    const observations: ChapterScrollGeometrySample[] = [];
    try {
      await applicationPage.setViewportSize({ width: request.width, height: request.height });
      await applicationPage.goto(request.pageUrl, { waitUntil: "networkidle" });
      await applicationPage.evaluate(async () => {
        await document.fonts.ready;
      });
      for (const chapterId of [
        "many-agents",
        "context-with-task",
        "find-and-focus",
        "review",
        "come-back",
      ]) {
        for (const viewportFraction of [0.8, 0.5, 0.2]) {
          await applicationPage.evaluate(
            ({ chapterId, viewportFraction }) => {
              const chapter = document.getElementById(chapterId);
              if (chapter === null) throw new Error(`Chapter ${chapterId} is missing`);
              const chapterTop = chapter.getBoundingClientRect().top + window.scrollY;
              window.scrollTo({
                top: chapterTop - window.innerHeight * viewportFraction,
                behavior: "instant",
              });
            },
            { chapterId, viewportFraction },
          );
          await applicationPage.waitForFunction(() => {
            const artwork = document.querySelector<SVGSVGElement>("[data-full-page-topology]");
            const progress = Number(artwork?.dataset["topologyScrollProgress"]);
            const maximumScroll = Math.max(
              document.documentElement.scrollHeight - window.innerHeight,
              1,
            );
            return (
              Number.isFinite(progress) &&
              Math.abs(progress - window.scrollY / maximumScroll) < 0.0001
            );
          });
          await applicationPage.waitForFunction(
            ({ chapterId, width }) => {
              const glass = document.querySelector(`[data-rail-surface-target="${chapterId}"]`);
              const pill = document.querySelector(`[data-rail-step-pill-target="${chapterId}"]`);
              const path = document.querySelector<SVGPathElement>(
                `[data-route-kind="attach"][data-route-anchor="${chapterId}"] [data-topology-path-role="core"]`,
              );
              const matrix = path?.getScreenCTM();
              if (glass === null || path === null || matrix === null || matrix === undefined)
                return false;
              const end = path.getPointAtLength(path.getTotalLength()).matrixTransform(matrix);
              const glassBox = glass.getBoundingClientRect();
              const pillBox = pill?.getBoundingClientRect();
              return width < 1024
                ? Math.abs(end.y - glassBox.top) <= 1
                : pillBox === undefined
                  ? Math.abs(end.x - glassBox.left) <= 1
                  : Math.abs(end.x - pillBox.left) <= 1 &&
                    Math.abs(end.y - (pillBox.top + pillBox.bottom) / 2) <= 1;
            },
            { chapterId, width: request.width },
          );
          observations.push(
            await applicationPage.evaluate(readChapterScrollGeometry, {
              chapterId,
              width: request.width,
            }),
          );
        }
      }
    } finally {
      await applicationPage.close();
    }
    return observations;
  },
);
