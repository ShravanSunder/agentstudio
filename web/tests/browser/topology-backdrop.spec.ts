import { expect, test, type Page } from "@playwright/test";

async function waitForTopologyRender(page: Page): Promise<void> {
  await page.evaluate(
    () =>
      new Promise<void>((resolve) => {
        window.requestAnimationFrame(() => window.requestAnimationFrame(() => resolve()));
      }),
  );
}

test("mounts one responsive topology grid in the wide left gutter", async ({ page }) => {
  await page.setViewportSize({ width: 1810, height: 1066 });
  await page.goto("/");
  await waitForTopologyRender(page);

  const backdrop = page.locator("[data-site-topology-backdrop]");
  const artwork = page.locator("[data-topology-artwork]");
  await expect(backdrop).toBeVisible();

  const geometry = await artwork.evaluate((svg) => {
    const frame = document.querySelector(".site-frame");
    const backdropElement = document.querySelector("[data-site-topology-backdrop]");
    if (
      !(svg instanceof SVGSVGElement) ||
      !(frame instanceof HTMLElement) ||
      !(backdropElement instanceof HTMLElement)
    ) {
      throw new Error("Topology shell geometry is incomplete");
    }
    const svgBounds = svg.getBoundingClientRect();
    const frameBounds = frame.getBoundingClientRect();
    const backdropBounds = backdropElement.getBoundingClientRect();
    const nodeAspectRatios = [...svg.querySelectorAll("[data-topology-node-progress]")].map(
      (node) => {
        const bounds = node.getBoundingClientRect();
        return bounds.width / bounds.height;
      },
    );
    return {
      boundaryDelta: Math.abs(backdropBounds.right - frameBounds.left),
      clientWidth: document.documentElement.clientWidth,
      documentHeight: document.documentElement.scrollHeight,
      maximumNodeAspectRatio: Math.max(...nodeAspectRatios),
      minimumNodeAspectRatio: Math.min(...nodeAspectRatios),
      scrollWidth: document.documentElement.scrollWidth,
      svgHeight: svgBounds.height,
      svgWidth: svgBounds.width,
      viewBoxHeight: svg.viewBox.baseVal.height,
      viewBoxWidth: svg.viewBox.baseVal.width,
    };
  });

  expect(geometry.boundaryDelta).toBeLessThanOrEqual(1);
  expect(geometry.scrollWidth).toBe(geometry.clientWidth);
  expect(geometry.svgHeight).toBeGreaterThanOrEqual(geometry.documentHeight - 20);
  expect(geometry.minimumNodeAspectRatio).toBeGreaterThanOrEqual(0.99);
  expect(geometry.maximumNodeAspectRatio).toBeLessThanOrEqual(1.01);
  expect(geometry.viewBoxWidth).toBeCloseTo(geometry.svgWidth, 0);
  expect(geometry.viewBoxHeight).toBeCloseTo(geometry.svgHeight, 0);

  await page.evaluate(() => {
    const maximumScroll = document.documentElement.scrollHeight - window.innerHeight;
    window.scrollTo({ top: Math.ceil((maximumScroll * 2) / 26) + 1, behavior: "instant" });
  });
  await waitForTopologyRender(page);

  const firstFork = await artwork.evaluate((svg) => {
    const mainline = svg.querySelector<SVGPathElement>(
      '.topology-primary [data-topology-path-role="core"]',
    );
    const forkPath = svg.querySelector<SVGPathElement>(
      '.worktree-a [data-topology-segment-kind="fork"][data-topology-path-role="core"]',
    );
    const forkNode = svg.querySelector<SVGGElement>('[data-topology-node-row="2"]');
    if (mainline === null || forkPath === null || forkNode === null) {
      throw new Error("Topology first-fork geometry is incomplete");
    }
    const forkOrigin = forkPath.getPointAtLength(0);
    const nodeMatrix = forkNode.transform.baseVal.consolidate()?.matrix;
    const prefixLength = Number.parseFloat(mainline.style.strokeDasharray);
    return {
      forkOrigin: { x: forkOrigin.x, y: forkOrigin.y },
      mainlineProgress: prefixLength / mainline.getTotalLength(),
      node: { x: nodeMatrix?.e, y: nodeMatrix?.f, opacity: getComputedStyle(forkNode).opacity },
      visibleNodes: [...svg.querySelectorAll("[data-topology-node-progress]")].filter(
        (node) => Number(getComputedStyle(node).opacity) > 0,
      ).length,
    };
  });

  expect(firstFork.mainlineProgress).toBeCloseTo(2 / 26, 3);
  expect(firstFork.node.opacity).toBe("1");
  expect(firstFork.forkOrigin.x).toBeCloseTo(firstFork.node.x ?? Number.NaN, 3);
  expect(firstFork.forkOrigin.y).toBeCloseTo(firstFork.node.y ?? Number.NaN, 3);
  expect(firstFork.visibleNodes).toBe(3);

  await page.evaluate(() =>
    window.scrollTo({ top: document.documentElement.scrollHeight, behavior: "instant" }),
  );
  await waitForTopologyRender(page);

  const finalState = await artwork.evaluate((svg) => {
    const terminalHalo = svg.querySelector(".node-terminal-halo");
    if (terminalHalo === null) {
      throw new Error("Topology terminal halo is missing");
    }
    return {
      atEnd: svg.hasAttribute("data-topology-at-end"),
      haloAnimation: getComputedStyle(terminalHalo).animationName,
      visibleBands: [...svg.querySelectorAll('[data-topology-path-role="leading-band"]')].filter(
        (path) => getComputedStyle(path).visibility !== "hidden",
      ).length,
      visibleNodes: [...svg.querySelectorAll("[data-topology-node-progress]")].filter(
        (node) => Number(getComputedStyle(node).opacity) > 0,
      ).length,
    };
  });

  expect(finalState).toEqual({
    atEnd: true,
    haloAnimation: "topology-terminal-node-halo",
    visibleBands: 0,
    visibleNodes: 27,
  });

  await page.evaluate(() => window.scrollTo({ top: 0, behavior: "instant" }));
  await waitForTopologyRender(page);
  await expect(artwork.locator('[data-topology-node-progress="1"]')).toHaveCSS("opacity", "0");
});

test("hides the topology below its minimum gutter width", async ({ page }) => {
  await page.setViewportSize({ width: 1791, height: 1000 });
  await page.goto("/");

  await expect(page.locator("[data-site-topology-backdrop]")).toBeHidden();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth === document.documentElement.clientWidth,
    ),
  ).toBe(true);
});

test("renders a complete static grid with reduced motion", async ({ page }) => {
  await page.setViewportSize({ width: 1810, height: 1066 });
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await waitForTopologyRender(page);

  const artwork = page.locator("[data-topology-artwork]");
  const state = await artwork.evaluate((svg) => {
    const terminalHalo = svg.querySelector(".node-terminal-halo");
    const startNode = svg.querySelector('[data-topology-node-progress="0"]');
    if (terminalHalo === null || startNode === null) {
      throw new Error("Topology endpoint markup is incomplete");
    }
    return {
      haloAnimation: getComputedStyle(terminalHalo).animationName,
      startAnimation: getComputedStyle(startNode).animationName,
      visibleNodes: [...svg.querySelectorAll("[data-topology-node-progress]")].filter(
        (node) => Number(getComputedStyle(node).opacity) > 0,
      ).length,
    };
  });

  expect(state).toEqual({ haloAnimation: "none", startAnimation: "none", visibleNodes: 27 });
});
