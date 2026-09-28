import { defineBrowserCommand } from "@vitest/browser-playwright";

export interface StepLineJoinObservation {
  readonly width: number;
  readonly joins: readonly {
    readonly anchorId: string;
    readonly stroke: string;
    readonly passedStroke: string;
    readonly drop: number;
    readonly leadIn: number;
    readonly controlOffsets: readonly number[];
    readonly sourceY: number;
    readonly titleTop: number;
    readonly titleBottom: number;
    readonly nodeDistance: number;
    readonly nodeCountAtFork: number;
    readonly visibleInterveningNodeCount: number;
  }[];
}

export const verifyStepLineJoins = defineBrowserCommand(
  async (
    { context },
    pageUrl: string,
    widths: readonly number[],
  ): Promise<StepLineJoinObservation[]> => {
    const page = await context.newPage();
    const observations: StepLineJoinObservation[] = [];
    try {
      for (const width of widths) {
        await page.setViewportSize({
          width,
          height: width === 390 ? 844 : width === 1280 ? 800 : 1080,
        });
        await page.goto(pageUrl, { waitUntil: "domcontentloaded" });
        await page
          .locator('[data-route-kind="attach"][data-route-anchor]')
          .first()
          .waitFor({ state: "attached" });
        observations.push(
          await page.evaluate(() => {
            const groups = [
              ...document.querySelectorAll<SVGGElement>(
                '[data-route-kind="attach"][data-route-anchor]',
              ),
            ].filter(
              (group) =>
                document.querySelector(
                  `[data-rail-step-line-target="${group.dataset["routeAnchor"] ?? ""}"]`,
                ) !== null,
            );
            return {
              width: innerWidth,
              joins: groups.map((group) => {
                const anchorId = group.dataset["routeAnchor"] ?? "";
                const path = group.querySelector<SVGPathElement>(
                  '[data-topology-path-role="core"]',
                );
                const line = document.querySelector<HTMLElement>(
                  `[data-chapter-steps-root="${anchorId}"]`,
                );
                const passed = line?.querySelector<HTMLElement>(".chapter-step-progress-fill");
                const title = line?.querySelector<HTMLElement>(".chapter-title");
                if (
                  path === null ||
                  passed === null ||
                  passed === undefined ||
                  title === null ||
                  title === undefined
                )
                  throw new Error(`Step join ${anchorId} is missing`);
                const numbers = [
                  ...(path.getAttribute("d") ?? "").matchAll(/-?\d+(?:\.\d+)?/gu),
                ].map((match) => Number(match[0]));
                const [
                  sourceX = 0,
                  sourceY = 0,
                  cp1X = 0,
                  cp1Y = 0,
                  cp2X = 0,
                  cp2Y = 0,
                  endX = 0,
                  endY = 0,
                ] = numbers;
                const artwork = group.closest<SVGSVGElement>("[data-full-page-topology]");
                const distances = [
                  ...(artwork?.querySelectorAll<SVGGElement>("[data-node]") ?? []),
                ].map((node) => {
                  const circle = node.querySelector<SVGCircleElement>("circle");
                  return circle === null
                    ? Number.POSITIVE_INFINITY
                    : Math.hypot(
                        Number(circle.getAttribute("cx")) - sourceX,
                        Number(circle.getAttribute("cy")) - sourceY,
                      );
                });
                const visibleInterveningNodeCount = [
                  ...(artwork?.querySelectorAll<SVGGElement>("[data-node]") ?? []),
                ].filter((node) => {
                  const circle = node.querySelector<SVGCircleElement>("circle");
                  if (circle === null || getComputedStyle(node).display === "none") return false;
                  const x = Number(circle.getAttribute("cx"));
                  const y = Number(circle.getAttribute("cy"));
                  return Math.abs(x - sourceX) <= 0.5 && y > sourceY + 0.5 && y <= endY + 0.5;
                }).length;
                return {
                  anchorId,
                  stroke: getComputedStyle(path).stroke,
                  passedStroke: getComputedStyle(passed).backgroundColor,
                  drop: endY - sourceY,
                  leadIn: endX - sourceX,
                  controlOffsets: [cp1X - sourceX, cp1Y - sourceY, cp2X - sourceX, cp2Y - sourceY],
                  sourceY,
                  titleTop: title.getBoundingClientRect().top + scrollY,
                  titleBottom: title.getBoundingClientRect().bottom + scrollY,
                  nodeDistance: Math.min(...distances),
                  nodeCountAtFork: distances.filter((distance) => distance <= 1).length,
                  visibleInterveningNodeCount,
                };
              }),
            };
          }),
        );
      }
      return observations;
    } finally {
      await page.close();
    }
  },
);
