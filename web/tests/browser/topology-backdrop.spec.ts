import { expect, test, type Page } from "@playwright/test";

async function waitForTopologyRender(page: Page): Promise<void> {
  await page.evaluate(
    () =>
      new Promise<void>((resolve) => {
        window.requestAnimationFrame(() => window.requestAnimationFrame(() => resolve()));
      }),
  );
}

test("mounts the responsive full-page topology from the hero icon anchor", async ({ page }) => {
  await page.setViewportSize({ width: 1810, height: 1066 });
  await page.goto("/");
  await waitForTopologyRender(page);

  const backdrop = page.locator("[data-site-topology-backdrop]");
  const artwork = page.locator("[data-full-page-topology]");
  await expect(backdrop).toBeVisible();

  const geometry = await artwork.evaluate((svg) => {
    if (!(svg instanceof SVGSVGElement)) {
      throw new Error("Homepage topology artwork is not an SVG");
    }
    const anchor = document.querySelector("[data-topology-mainline-anchor]");
    const mainline = svg.querySelector<SVGPathElement>(
      '[data-mainline][data-topology-path-role="core"]',
    );
    const startNode = svg.querySelector<SVGGraphicsElement>('[data-topology-node-progress="0"]');
    if (!(anchor instanceof HTMLElement) || mainline === null || startNode === null) {
      throw new Error("Homepage topology anchor geometry is incomplete");
    }

    const artworkBounds = svg.getBoundingClientRect();
    const anchorBounds = anchor.getBoundingClientRect();
    const frameBounds = document.querySelector(".site-frame")?.getBoundingClientRect();
    if (frameBounds === undefined) {
      throw new Error("Homepage frame geometry is missing");
    }
    const anchorRight = anchorBounds.right - artworkBounds.left;
    const frameRight = frameBounds.right - artworkBounds.left;
    const startPoint = mainline.getPointAtLength(0);
    const startMatrix = startNode.transform.baseVal.consolidate()?.matrix;
    const nodeAspectRatios = [...svg.querySelectorAll<SVGGraphicsElement>("[data-node]")].flatMap(
      (node) => {
        const bounds = node.getBoundingClientRect();
        return bounds.width > 0 && bounds.height > 0 ? [bounds.width / bounds.height] : [];
      },
    );
    const routes = [
      ...svg.querySelectorAll<SVGPathElement>('[data-route][data-topology-path-role="core"]'),
    ];
    const nodeRows = [...svg.querySelectorAll<SVGGraphicsElement>("[data-node]")].reduce(
      (rows, node) => {
        const row = node.dataset["row"];
        if (row !== undefined) {
          rows.set(row, (rows.get(row) ?? 0) + 1);
        }
        return rows;
      },
      new Map<string, number>(),
    );
    const visibleRoutes = routes.filter(
      (route) =>
        route.parentElement !== null && getComputedStyle(route.parentElement).display !== "none",
    );
    const mergingRoutes = routes.filter((route) => route.dataset["mergeRow"] !== undefined);
    const teleportRowDeltas = visibleRoutes.flatMap((route) => {
      const pathData = route.getAttribute("d") ?? "";
      return [
        ...pathData.matchAll(
          /M (-?\d+(?:\.\d+)?) (-?\d+(?:\.\d+)?) M (-?\d+(?:\.\d+)?) (-?\d+(?:\.\d+)?)/g,
        ),
      ]
        .filter((match) => Math.abs(Number(match[1]) - Number(match[3])) > frameBounds.width / 2)
        .map((match) => Math.abs(Number(match[2]) - Number(match[4])));
    });

    return {
      anchorCenterY: anchorBounds.top + anchorBounds.height / 2 - artworkBounds.top,
      clientWidth: document.documentElement.clientWidth,
      columnCount: Number(svg.dataset["columnCount"]),
      documentHeight: document.documentElement.scrollHeight,
      expectedMainlineX: Math.max(
        anchorRight + ((artworkBounds.width - anchorRight) * 2) / 3,
        frameRight + (artworkBounds.width - frameRight) / 2,
      ),
      maximumNodeAspectRatio: Math.max(...nodeAspectRatios),
      maximumNodesPerRow: Math.max(...nodeRows.values()),
      minimumNodeAspectRatio: Math.min(...nodeAspectRatios),
      minimumMergeRowSpan: Math.min(
        ...mergingRoutes.map(
          (route) => Number(route.dataset["mergeRow"]) - Number(route.dataset["mergeApproachRow"]),
        ),
      ),
      openRouteCount: routes.filter((route) => route.dataset["openEndRow"] !== undefined).length,
      portalActive: svg.hasAttribute("data-topology-portal-active"),
      rowCount: Number(svg.dataset["rowCount"]),
      scrollWidth: document.documentElement.scrollWidth,
      startNode: { x: startMatrix?.e, y: startMatrix?.f },
      startPoint: { x: startPoint.x, y: startPoint.y },
      svgHeight: artworkBounds.height,
      svgWidth: artworkBounds.width,
      teleportCount: teleportRowDeltas.length,
      maximumTeleportRowDelta: Math.max(...teleportRowDeltas),
      totalRouteCount: routes.length,
      visibleRouteCount: visibleRoutes.length,
      viewBoxHeight: svg.viewBox.baseVal.height,
      viewBoxWidth: svg.viewBox.baseVal.width,
    };
  });

  expect(geometry.scrollWidth).toBe(geometry.clientWidth);
  expect(geometry.svgHeight).toBeGreaterThanOrEqual(geometry.documentHeight - 20);
  expect(geometry.viewBoxWidth).toBeCloseTo(geometry.svgWidth, 0);
  expect(geometry.viewBoxHeight).toBeCloseTo(geometry.svgHeight, 0);
  expect(geometry.columnCount).toBeGreaterThan(1);
  expect(geometry.rowCount).toBeGreaterThan(1);
  expect(geometry.startPoint.x).toBeCloseTo(geometry.expectedMainlineX, 3);
  expect(geometry.startPoint.y).toBeCloseTo(geometry.anchorCenterY, 3);
  expect(geometry.startNode.x).toBeCloseTo(geometry.startPoint.x, 3);
  expect(geometry.startNode.y).toBeCloseTo(geometry.startPoint.y, 3);
  expect(geometry.minimumNodeAspectRatio).toBeGreaterThanOrEqual(0.99);
  expect(geometry.maximumNodeAspectRatio).toBeLessThanOrEqual(1.01);
  expect(geometry.maximumNodesPerRow).toBe(1);
  expect(geometry.openRouteCount).toBe(3);
  expect(geometry.minimumMergeRowSpan).toBeGreaterThanOrEqual(2);
  expect(geometry.portalActive).toBe(true);
  expect(geometry.visibleRouteCount).toBeGreaterThan(0);
  expect(geometry.visibleRouteCount).toBeLessThan(geometry.totalRouteCount);
  expect(geometry.teleportCount).toBeGreaterThan(0);
  expect(geometry.maximumTeleportRowDelta).toBe(0);

  await page.setViewportSize({ width: 3007, height: 1066 });
  await waitForTopologyRender(page);
  expect(
    await artwork.evaluate(
      (svg) =>
        [...svg.querySelectorAll("[data-topology-route-group]")].filter(
          (route) => getComputedStyle(route).display !== "none",
        ).length,
    ),
  ).toBe(9);
  await page.setViewportSize({ width: 1810, height: 1066 });
  await waitForTopologyRender(page);

  const initialState = await artwork.evaluate((svg) => {
    const startNode = svg.querySelector('[data-topology-node-progress="0"]');
    const mainline = svg.querySelector<SVGPathElement>(
      '[data-mainline][data-topology-path-role="core"]',
    );
    return {
      atStart: svg.hasAttribute("data-topology-at-start"),
      mainlineVisibility: mainline === null ? null : getComputedStyle(mainline).visibility,
      startAnimation: startNode === null ? null : getComputedStyle(startNode).animationName,
    };
  });
  expect(initialState).toEqual({
    atStart: true,
    mainlineVisibility: "hidden",
    startAnimation: "topology-start-node-breathe",
  });

  await page.evaluate(() => {
    const maximumScroll = document.documentElement.scrollHeight - window.innerHeight;
    window.scrollTo({ top: maximumScroll * 0.5, behavior: "instant" });
  });
  await waitForTopologyRender(page);

  const middleState = await artwork.evaluate((svg) => {
    const mainline = svg.querySelector<SVGPathElement>(
      '[data-mainline][data-topology-path-role="core"]',
    );
    if (mainline === null) {
      throw new Error("Homepage topology mainline is missing");
    }
    return {
      mainlineProgress:
        Number.parseFloat(mainline.style.strokeDasharray) / mainline.getTotalLength(),
      visibleLeadingBands: [
        ...svg.querySelectorAll('[data-topology-path-role="leading-band"]'),
      ].filter((path) => getComputedStyle(path).visibility !== "hidden").length,
    };
  });
  expect(middleState.mainlineProgress).toBeCloseTo(0.5, 2);
  expect(middleState.visibleLeadingBands).toBeGreaterThan(0);

  await page.evaluate(() =>
    window.scrollTo({ top: document.documentElement.scrollHeight, behavior: "instant" }),
  );
  await waitForTopologyRender(page);

  const finalState = await artwork.evaluate((svg) => {
    const finalNode = svg.querySelector('.node-terminal-group[data-topology-node-progress="1"]');
    const terminalHalo = finalNode?.querySelector(".node-terminal-halo");
    const topologyNodes = [...svg.querySelectorAll("[data-topology-node-progress]")];
    const progressOneNodes = topologyNodes.filter(
      (node) => node.getAttribute("data-topology-node-progress") === "1",
    );
    return {
      atEnd: svg.hasAttribute("data-topology-at-end"),
      finalNodeOpacity: finalNode === null ? null : getComputedStyle(finalNode).opacity,
      haloAnimation:
        terminalHalo === null || terminalHalo === undefined
          ? null
          : getComputedStyle(terminalHalo).animationName,
      totalNodes: topologyNodes.length,
      progressOneNodeCount: progressOneNodes.length,
      visibleLeadingBands: [
        ...svg.querySelectorAll('[data-topology-path-role="leading-band"]'),
      ].filter((path) => getComputedStyle(path).visibility !== "hidden").length,
      visibleNodes: topologyNodes.filter((node) => Number(getComputedStyle(node).opacity) > 0)
        .length,
    };
  });
  expect(finalState.atEnd).toBe(true);
  expect(finalState.finalNodeOpacity).toBe("1");
  expect(finalState.haloAnimation).toBe("topology-terminal-node-halo");
  expect(finalState.visibleLeadingBands).toBe(0);
  expect(finalState.visibleNodes).toBe(finalState.totalNodes);
  expect(finalState.progressOneNodeCount).toBe(1);
});

test("hides the topology below the xl breakpoint", async ({ page }) => {
  await page.setViewportSize({ width: 1279, height: 900 });
  await page.goto("/");

  await expect(page.locator("[data-site-topology-backdrop]")).toBeHidden();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth === document.documentElement.clientWidth,
    ),
  ).toBe(true);
});

test("renders the complete grid without animation for reduced motion", async ({ page }) => {
  await page.setViewportSize({ width: 1810, height: 1066 });
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await waitForTopologyRender(page);

  const state = await page.locator("[data-full-page-topology]").evaluate((svg) => {
    const startNode = svg.querySelector('[data-topology-node-progress="0"]');
    const finalNode = svg.querySelector('.node-terminal-group[data-topology-node-progress="1"]');
    const terminalHalo = finalNode?.querySelector(".node-terminal-halo");
    const topologyNodes = [...svg.querySelectorAll("[data-topology-node-progress]")];
    return {
      haloAnimation:
        terminalHalo === null || terminalHalo === undefined
          ? null
          : getComputedStyle(terminalHalo).animationName,
      startAnimation: startNode === null ? null : getComputedStyle(startNode).animationName,
      totalNodes: topologyNodes.length,
      visibleNodes: topologyNodes.filter((node) => Number(getComputedStyle(node).opacity) > 0)
        .length,
    };
  });

  expect(state.haloAnimation).toBe("none");
  expect(state.startAnimation).toBe("none");
  expect(state.visibleNodes).toBe(state.totalNodes);
});
