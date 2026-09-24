import { defineBrowserCommand } from "@vitest/browser-playwright";

interface PageRect {
  readonly left: number;
  readonly top: number;
  readonly right: number;
  readonly bottom: number;
}

/** Where the rail ends on the served home page at one viewport width, in page coordinates. */
export interface TopologyEndObservation {
  readonly width: number;
  readonly endNodeY: number;
  readonly installCenterY: number;
  readonly ctaTop: number;
  /** The lowest point of any rail path or node. */
  readonly lowestRailY: number;
  /** Rail path samples and nodes that fall inside a call-to-action or footer element's box. */
  readonly pointsOverEndContent: number;
}

function observeEnd(width: number): TopologyEndObservation {
  const artwork = document.querySelector<SVGSVGElement>("[data-full-page-topology]");
  const section = document.querySelector("[data-rail-end-section]");
  const install = document.querySelector("[data-rail-end]");
  const endNode = document.querySelector('[data-node-kind="end"] circle');
  if (artwork === null || section === null || install === null || endNode === null) {
    throw new Error("The home page is missing its rail end hooks");
  }
  const origin = artwork.getBoundingClientRect();
  const toPage = (bounds: DOMRect): PageRect => ({
    left: bounds.left + window.scrollX,
    top: bounds.top + window.scrollY,
    right: bounds.right + window.scrollX,
    bottom: bounds.bottom + window.scrollY,
  });
  const artworkTop = origin.top + window.scrollY;
  const artworkLeft = origin.left + window.scrollX;
  const points: { readonly x: number; readonly y: number }[] = [];
  for (const path of artwork.querySelectorAll<SVGPathElement>("path[d]")) {
    const total = path.getTotalLength();
    for (let step = 0; step <= 200; step += 1) {
      const point = path.getPointAtLength((total * step) / 200);
      points.push({ x: artworkLeft + point.x, y: artworkTop + point.y });
    }
  }
  for (const circle of artwork.querySelectorAll<SVGCircleElement>("circle")) {
    points.push({
      x: artworkLeft + circle.cx.baseVal.value,
      y: artworkTop + circle.cy.baseVal.value,
    });
  }
  const endContent = [
    ...section.querySelectorAll(":scope > *"),
    ...document.querySelectorAll("footer, footer *"),
  ]
    .filter((element) => element.getClientRects().length > 0)
    .map((element) => toPage(element.getBoundingClientRect()));
  const installBox = toPage(install.getBoundingClientRect());
  return {
    width,
    endNodeY: artworkTop + Number(endNode.getAttribute("cy")),
    installCenterY: (installBox.top + installBox.bottom) / 2,
    ctaTop: toPage(section.getBoundingClientRect()).top,
    lowestRailY: Math.max(...points.map((point) => point.y)),
    pointsOverEndContent: points.filter((point) =>
      endContent.some(
        (box) =>
          point.x >= box.left &&
          point.x <= box.right &&
          point.y >= box.top &&
          point.y <= box.bottom,
      ),
    ).length,
  };
}

/** Loads the served home page at each width and reads where the rail ends. */
export const verifyTopologyEnd = defineBrowserCommand(
  async (
    { context },
    pageUrl: string,
    widths: readonly number[],
  ): Promise<TopologyEndObservation[]> => {
    const applicationPage = await context.newPage();
    const observations: TopologyEndObservation[] = [];
    try {
      /* eslint-disable no-await-in-loop -- one page owns the viewport; each width must settle before the next. */
      for (const width of widths) {
        await applicationPage.setViewportSize({ width, height: 900 });
        await applicationPage.goto(pageUrl, { waitUntil: "networkidle" });
        await applicationPage.waitForSelector('[data-full-page-topology] [data-node-kind="end"]', {
          state: "attached",
        });
        observations.push(await applicationPage.evaluate(observeEnd, width));
      }
      /* eslint-enable no-await-in-loop */
      return observations;
    } finally {
      await applicationPage.close();
    }
  },
);
