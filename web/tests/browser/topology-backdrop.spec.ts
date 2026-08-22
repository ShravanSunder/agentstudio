import { expect, test, type Page } from "@playwright/test";

async function waitForTopologyRender(page: Page): Promise<void> {
  await page.evaluate(
    () =>
      new Promise<void>((resolve) => {
        window.requestAnimationFrame(() => window.requestAnimationFrame(() => resolve()));
      }),
  );
}

async function inspectVisibleTopology(page: Page): Promise<{
  readonly bridgeSurfaceIndexes: readonly number[];
  readonly columnCount: number;
  readonly duplicateNodeRowCount: number;
  readonly mainlineX: number;
  readonly maximumReverseYStep: number;
  readonly resolvedLanes: readonly number[];
  readonly rowCount: number;
  readonly topologyVariant: string | undefined;
  readonly worktreesMovingLeftCount: number;
  readonly visibleWorktreeCount: number;
  readonly visibleNodeCount: number;
  readonly worktreeCount: number;
}> {
  return page.locator("[data-full-page-topology]").evaluate((svg) => {
    if (!(svg instanceof SVGSVGElement)) {
      throw new Error("Homepage topology artwork is not an SVG");
    }
    const artworkBounds = svg.getBoundingClientRect();
    const mainline = svg.querySelector<SVGPathElement>(
      '[data-mainline][data-topology-path-role="core"]',
    );
    if (mainline === null) {
      throw new Error("Homepage topology mainline is missing");
    }
    const visibleRoutes = [
      ...svg.querySelectorAll<SVGGElement>("[data-topology-route-group]"),
    ].filter((group) => getComputedStyle(group).display !== "none");
    const routeYSteps = visibleRoutes.flatMap((group) => {
      const route = group.querySelector<SVGPathElement>(
        '[data-route][data-topology-path-role="core"]',
      );
      if (route === null) {
        return [];
      }
      const routeLength = route.getTotalLength();
      const points = Array.from({ length: 101 }, (_, index) =>
        route.getPointAtLength((routeLength * index) / 100),
      );
      return points.flatMap((point, index) => {
        const previousPoint = points[index - 1];
        return previousPoint === undefined ? [] : [previousPoint.y - point.y];
      });
    });
    const visibleNodes = [...svg.querySelectorAll<SVGGraphicsElement>("[data-node]")].filter(
      (node) => {
        const routeGroup = node.closest<SVGGElement>("[data-topology-route-group]");
        return (
          getComputedStyle(node).display !== "none" &&
          (routeGroup === null || getComputedStyle(routeGroup).display !== "none")
        );
      },
    );
    const resolvedRows = visibleNodes.map((node) => node.dataset["resolvedRow"]);
    const bridgeNodes = visibleNodes.filter((node) =>
      node.hasAttribute("data-topology-glass-bridge"),
    );
    const glassSurfaces = [
      ...document.querySelectorAll<HTMLElement>("[data-scroll-material-surface]"),
    ].map((surface) => surface.getBoundingClientRect());
    const bridgeSurfaceIndexes = bridgeNodes
      .map((node) => {
        const bounds = node.getBoundingClientRect();
        const centerY = bounds.top + bounds.height / 2;
        return glassSurfaces.findIndex(
          (surface) => centerY >= surface.top && centerY <= surface.bottom,
        );
      })
      .toSorted((left, right) => left - right);
    return {
      bridgeSurfaceIndexes,
      columnCount: Number(svg.dataset["columnCount"]),
      duplicateNodeRowCount: resolvedRows.length - new Set(resolvedRows).size,
      mainlineX: mainline.getPointAtLength(0).x - artworkBounds.left,
      maximumReverseYStep: Math.max(...routeYSteps),
      resolvedLanes: visibleRoutes.map((group) => Number(group.dataset["resolvedLane"])),
      rowCount: Number(svg.dataset["rowCount"]),
      topologyVariant: svg.dataset["topologyVariant"],
      worktreesMovingLeftCount: visibleRoutes.filter((group) => {
        return Number(group.dataset["resolvedTargetX"]) < Number(group.dataset["resolvedSourceX"]);
      }).length,
      visibleWorktreeCount: visibleRoutes.length,
      visibleNodeCount: visibleNodes.length,
      worktreeCount: Number(svg.dataset["worktreeCount"]),
    };
  });
}

interface ExpectedTopologyVariant {
  readonly expectedBridgeSurfaceIndexes: readonly number[];
  readonly expectedColumns: number;
  readonly expectedLanes: readonly number[];
  readonly expectedVariant: string;
  readonly expectedWorktrees: number;
  readonly width: number;
}

async function expectTopologyVariant(page: Page, expected: ExpectedTopologyVariant): Promise<void> {
  await page.setViewportSize({ height: 1066, width: expected.width });
  await waitForTopologyRender(page);
  const state = await inspectVisibleTopology(page);
  expect(state.columnCount).toBe(expected.expectedColumns);
  expect(state.topologyVariant).toBe(expected.expectedVariant);
  expect(state.visibleWorktreeCount).toBe(expected.expectedWorktrees);
  expect(state.worktreeCount).toBe(expected.expectedWorktrees);
  expect(state.resolvedLanes).toEqual(expected.expectedLanes);
  expect(state.duplicateNodeRowCount).toBe(0);
  expect(state.visibleNodeCount).toBe(state.rowCount);
  expect(state.worktreesMovingLeftCount).toBe(expected.expectedWorktrees);
  expect(state.bridgeSurfaceIndexes).toEqual(expected.expectedBridgeSurfaceIndexes);
  expect(state.mainlineX).toBeCloseTo(expected.width - 144, 3);
  expect(state.maximumReverseYStep).toBeLessThanOrEqual(0.01);
}

test("hides the complete topology until both gutters fit two usable columns", async ({ page }) => {
  await page.setViewportSize({ height: 1066, width: 1810 });
  await page.goto("/");
  await waitForTopologyRender(page);

  const artwork = page.locator("[data-full-page-topology]");
  await expect(artwork).toBeHidden();
  await expect(artwork).toHaveAttribute(
    "data-topology-hidden-reason",
    "insufficient-gutter-capacity",
  );
});

test("selects the authored 1, 3, and 5-worktree variants from gutter capacity", async ({
  page,
}) => {
  await page.goto("/");
  await expectTopologyVariant(page, {
    expectedBridgeSurfaceIndexes: [],
    expectedColumns: 2,
    expectedLanes: [1],
    expectedVariant: "compact",
    expectedWorktrees: 1,
    width: 2200,
  });
  await expectTopologyVariant(page, {
    expectedBridgeSurfaceIndexes: [1, 3],
    expectedColumns: 3,
    expectedLanes: [1, 2, 3],
    expectedVariant: "standard",
    expectedWorktrees: 3,
    width: 2300,
  });
  await expectTopologyVariant(page, {
    expectedBridgeSurfaceIndexes: [1, 2, 3],
    expectedColumns: 4,
    expectedLanes: [1, 2, 3, 4, 2],
    expectedVariant: "expanded",
    expectedWorktrees: 5,
    width: 2400,
  });
});

test("reveals the authored topology by scroll progress and ends on the mainline halo", async ({
  page,
}) => {
  await page.setViewportSize({ height: 1066, width: 2400 });
  await page.goto("/");
  await waitForTopologyRender(page);

  const artwork = page.locator("[data-full-page-topology]");
  await page.evaluate(() => {
    const maximumScroll = document.documentElement.scrollHeight - window.innerHeight;
    window.scrollTo({ behavior: "instant", top: maximumScroll * 0.5 });
  });
  await waitForTopologyRender(page);
  const middleReveal = await artwork.evaluate((svg) => {
    const revealPaths = [...svg.querySelectorAll<SVGPathElement>("[data-topology-path-start]")];
    const revealLayer = svg.querySelector<SVGGElement>("[data-topology-reveal-layer]");
    const revealSolid = svg.querySelector<SVGRectElement>("[data-topology-reveal-solid]");
    const revealFade = svg.querySelector<SVGRectElement>("[data-topology-reveal-fade]");
    if (revealLayer === null || revealSolid === null || revealFade === null) {
      throw new Error("Topology vertical reveal mask is incomplete");
    }
    const topologyStartY = Number(svg.dataset["topologyStartY"]);
    const topologyEndY = Number(svg.dataset["topologyEndY"]);
    return {
      fadeHeight: Number(revealFade.getAttribute("height")),
      fadeY: Number(revealFade.getAttribute("y")),
      maskReference: revealLayer.getAttribute("mask"),
      pathDashArrays: revealPaths.map((path) => path.style.strokeDasharray),
      expectedRevealEdgeY: topologyStartY + (topologyEndY - topologyStartY) * 0.5,
      leadingBandCount: [
        ...svg.querySelectorAll<SVGPathElement>('[data-topology-path-role="leading-band"]'),
      ].filter((path) => getComputedStyle(path).visibility !== "hidden").length,
      revealEdgeY: Number(svg.dataset["topologyRevealEdgeY"]),
      solidHeight: Number(revealSolid.getAttribute("height")),
    };
  });
  expect(middleReveal.leadingBandCount).toBe(0);
  expect(middleReveal.maskReference).toBe("url(#topology-vertical-reveal-mask)");
  expect(new Set(middleReveal.pathDashArrays)).toEqual(new Set(["none"]));
  expect(Math.abs(middleReveal.revealEdgeY - middleReveal.expectedRevealEdgeY)).toBeLessThan(1);
  expect(middleReveal.solidHeight).toBeCloseTo(middleReveal.revealEdgeY, 4);
  expect(middleReveal.fadeY).toBeCloseTo(middleReveal.revealEdgeY, 4);
  expect(middleReveal.fadeHeight).toBeGreaterThan(0);

  await page.evaluate(() =>
    window.scrollTo({ behavior: "instant", top: document.documentElement.scrollHeight }),
  );
  await waitForTopologyRender(page);
  const finalState = await artwork.evaluate((svg) => {
    const finalNode = svg.querySelector('[data-mainline-node="end"]');
    const finalHalo = finalNode?.querySelector(".node-terminal-halo");
    const startNode = svg.querySelector('[data-mainline-node="start"]');
    const startHalo = startNode?.querySelector(".node-terminal-halo");
    return {
      atEnd: svg.hasAttribute("data-topology-at-end"),
      finalHaloAnimation:
        finalHalo === null || finalHalo === undefined
          ? null
          : getComputedStyle(finalHalo).animationName,
      startHaloAnimation:
        startHalo === null || startHalo === undefined
          ? null
          : getComputedStyle(startHalo).animationName,
    };
  });
  expect(finalState).toEqual({
    atEnd: true,
    finalHaloAnimation: "topology-terminal-node-halo",
    startHaloAnimation: "none",
  });

  await page.evaluate(() => window.scrollTo({ behavior: "instant", top: 0 }));
  await waitForTopologyRender(page);
  const reversedState = await artwork.evaluate((svg) => {
    const revealSolid = svg.querySelector<SVGRectElement>("[data-topology-reveal-solid]");
    const startHalo = svg
      .querySelector('[data-mainline-node="start"]')
      ?.querySelector(".node-terminal-halo");
    const finalHalo = svg
      .querySelector('[data-mainline-node="end"]')
      ?.querySelector(".node-terminal-halo");
    return {
      atStart: svg.hasAttribute("data-topology-at-start"),
      finalHaloAnimation:
        finalHalo === null || finalHalo === undefined
          ? null
          : getComputedStyle(finalHalo).animationName,
      revealEdgeY: Number(svg.dataset["topologyRevealEdgeY"]),
      solidHeight: revealSolid === null ? null : Number(revealSolid.getAttribute("height")),
      startHaloAnimation:
        startHalo === null || startHalo === undefined
          ? null
          : getComputedStyle(startHalo).animationName,
      topologyStartY: Number(svg.dataset["topologyStartY"]),
    };
  });
  expect(reversedState.atStart).toBe(true);
  expect(reversedState.revealEdgeY).toBeCloseTo(reversedState.topologyStartY, 4);
  expect(reversedState.solidHeight).toBeCloseTo(reversedState.topologyStartY, 4);
  expect(reversedState.startHaloAnimation).toBe("topology-terminal-node-halo");
  expect(reversedState.finalHaloAnimation).toBe("none");
});

test("keeps the topology hidden below xl and static for reduced motion", async ({ page }) => {
  await page.setViewportSize({ height: 900, width: 1279 });
  await page.goto("/");
  await expect(page.locator("[data-site-topology-backdrop]")).toBeHidden();

  await page.setViewportSize({ height: 1066, width: 2400 });
  await page.emulateMedia({ reducedMotion: "reduce" });
  await waitForTopologyRender(page);
  const state = await page.locator("[data-full-page-topology]").evaluate((svg) => {
    const nodes = [
      ...svg.querySelectorAll<SVGGraphicsElement>("[data-topology-node-progress]"),
    ].filter((node) => {
      const group = node.closest<SVGGElement>("[data-topology-route-group]");
      return group === null || getComputedStyle(group).display !== "none";
    });
    return {
      totalNodes: nodes.length,
      visibleNodes: nodes.filter((node) => Number(getComputedStyle(node).opacity) > 0).length,
    };
  });
  expect(state.visibleNodes).toBe(state.totalNodes);
});

test("proves main-based allocation and row occupancy on the uncluttered topology lab", async ({
  page,
}) => {
  await page.setViewportSize({ height: 1066, width: 2800 });
  await page.goto("/topology-full-page-lab");
  await page.evaluate(() =>
    window.scrollTo({ behavior: "instant", top: document.documentElement.scrollHeight }),
  );
  await waitForTopologyRender(page);

  const state = await page.locator("[data-full-page-topology]").evaluate((svg) => {
    const svgBounds = svg.getBoundingClientRect();
    const frameBounds = document
      .querySelector<HTMLElement>("[data-topology-lab-frame]")
      ?.getBoundingClientRect();
    if (frameBounds === undefined) {
      throw new Error("Topology lab frame is missing");
    }
    const frameLeft = frameBounds.left - svgBounds.left;
    const frameRight = frameBounds.right - svgBounds.left;
    const glassBands = [
      ...document.querySelectorAll<HTMLElement>("[data-topology-lab-surface]"),
    ].map((surface) => {
      const bounds = surface.getBoundingClientRect();
      return { bottom: bounds.bottom - svgBounds.top, top: bounds.top - svgBounds.top };
    });
    const visibleGroups = [
      ...svg.querySelectorAll<SVGGElement>("[data-topology-route-group]"),
    ].filter((group) => getComputedStyle(group).display !== "none");
    const visibleNodes = [...svg.querySelectorAll<SVGGraphicsElement>("[data-node]")].filter(
      (node) => {
        const group = node.closest<SVGGElement>("[data-topology-route-group]");
        return (
          getComputedStyle(node).display !== "none" &&
          Number(getComputedStyle(node).opacity) > 0 &&
          (group === null || getComputedStyle(group).display !== "none")
        );
      },
    );
    const routeFacts = visibleGroups.map((group) => {
      const fork = group.querySelector<SVGCircleElement>('[data-node-position="fork"]');
      const end = group.querySelector<SVGCircleElement>('[data-node-position="end"]');
      const route = group.querySelector<SVGPathElement>(
        '[data-route][data-topology-path-role="core"]',
      );
      if (fork === null || end === null || route === null) {
        throw new Error("Topology lab route nodes are incomplete");
      }
      const routeLength = route.getTotalLength();
      const routePoints = Array.from({ length: 401 }, (_, pointIndex) =>
        route.getPointAtLength((routeLength * pointIndex) / 400),
      );
      const startPoint = routePoints[0];
      const endPoint = routePoints.at(-1);
      if (startPoint === undefined || endPoint === undefined) {
        throw new Error("Topology lab route geometry is empty");
      }
      return {
        endDelta: Math.hypot(
          endPoint.x - Number(end.getAttribute("cx")),
          endPoint.y - Number(end.getAttribute("cy")),
        ),
        endKind: group.dataset["endKind"],
        endX: Number(end.getAttribute("cx")),
        forkX: Number(fork.getAttribute("cx")),
        lane: Number(group.dataset["resolvedLane"]),
        minimumX: Math.min(...routePoints.map((point) => point.x)),
        startDelta: Math.hypot(
          startPoint.x - Number(fork.getAttribute("cx")),
          startPoint.y - Number(fork.getAttribute("cy")),
        ),
        targetX: Number(group.dataset["resolvedTargetX"]),
        unauthorizedFramePointCount: routePoints.filter(
          (point) =>
            point.x > frameLeft &&
            point.x < frameRight &&
            !glassBands.some((band) => point.y >= band.top && point.y <= band.bottom),
        ).length,
      };
    });
    const mainline = svg.querySelector<SVGPathElement>(
      '[data-mainline][data-topology-path-role="core"]',
    );
    if (mainline === null) {
      throw new Error("Topology lab mainline is missing");
    }
    const mainlineXAtY = (targetY: number): number => {
      const totalLength = mainline.getTotalLength();
      let lowerLength = 0;
      let upperLength = totalLength;
      for (let iteration = 0; iteration < 24; iteration += 1) {
        const middleLength = lowerLength + (upperLength - lowerLength) / 2;
        if (mainline.getPointAtLength(middleLength).y <= targetY) {
          lowerLength = middleLength;
        } else {
          upperLength = middleLength;
        }
      }
      return mainline.getPointAtLength(lowerLength).x;
    };
    const resolvedRows = visibleNodes.map((node) => Number(node.dataset["resolvedRow"]));
    const fillerOwnerIds = [...svg.querySelectorAll<SVGCircleElement>("[data-mainline-fill-index]")]
      .filter((node) => getComputedStyle(node).display !== "none")
      .map((node) => node.dataset["nodeOwner"]);
    const ownerPaths = new Map<string, SVGPathElement>([["main", mainline]]);
    const ownerColors = new Map<string, string>();
    const ownerSpans = new Map<string, { endRow: number; startRow: number }>();
    const mainStartNode = svg.querySelector<SVGGraphicsElement>('[data-mainline-node="start"]');
    if (mainStartNode === null) {
      throw new Error("Topology lab mainline color owner is missing");
    }
    ownerColors.set("main", getComputedStyle(mainStartNode).color);
    for (const group of visibleGroups) {
      const routeId = group.dataset["routeId"];
      const routePath = group.querySelector<SVGPathElement>(
        '[data-route][data-topology-path-role="core"]',
      );
      if (routeId === undefined || routePath === null) {
        throw new Error("Topology lab filler owner route is missing");
      }
      const forkNode = group.querySelector<SVGGraphicsElement>('[data-node-position="fork"]');
      const endNode = group.querySelector<SVGGraphicsElement>('[data-node-position="end"]');
      if (forkNode === null || endNode === null) {
        throw new Error("Topology lab filler owner span is missing");
      }
      ownerPaths.set(routeId, routePath);
      ownerColors.set(routeId, getComputedStyle(group).color);
      ownerSpans.set(routeId, {
        endRow: Number(endNode.dataset["resolvedRow"]),
        startRow: Number(forkNode.dataset["resolvedRow"]),
      });
    }
    const visibleFillers = [
      ...svg.querySelectorAll<SVGCircleElement>("[data-mainline-fill-index]"),
    ].filter((node) => getComputedStyle(node).display !== "none");
    const fillerOwnerPathDistances = visibleFillers.map((node) => {
      const ownerId = node.dataset["nodeOwner"];
      const ownerPath = ownerId === undefined ? undefined : ownerPaths.get(ownerId);
      if (ownerPath === undefined) {
        throw new Error("Topology lab filler node has no rendered owner path");
      }
      const targetY = Number(node.getAttribute("cy"));
      const totalLength = ownerPath.getTotalLength();
      let lowerLength = 0;
      let upperLength = totalLength;
      for (let iteration = 0; iteration < 24; iteration += 1) {
        const middleLength = lowerLength + (upperLength - lowerLength) / 2;
        if (ownerPath.getPointAtLength(middleLength).y <= targetY) {
          lowerLength = middleLength;
        } else {
          upperLength = middleLength;
        }
      }
      const ownerPoint = ownerPath.getPointAtLength(lowerLength);
      return Math.hypot(ownerPoint.x - Number(node.getAttribute("cx")), ownerPoint.y - targetY);
    });
    const fillerColorMismatchCount = visibleFillers.filter((node) => {
      const ownerId = node.dataset["nodeOwner"];
      return ownerId === undefined || getComputedStyle(node).color !== ownerColors.get(ownerId);
    }).length;
    const inactiveWorktreeOwnerCount = visibleFillers.filter((node) => {
      const ownerId = node.dataset["nodeOwner"];
      if (ownerId === undefined || ownerId === "main") {
        return false;
      }
      const span = ownerSpans.get(ownerId);
      const row = Number(node.dataset["resolvedRow"]);
      return span === undefined || row <= span.startRow || row >= span.endRow;
    }).length;
    return {
      duplicateRowCount: resolvedRows.length - new Set(resolvedRows).size,
      fillerColorMismatchCount,
      fillerOwnerIds,
      inactiveWorktreeOwnerCount,
      maximumForkMainlineDelta: Math.max(
        ...visibleGroups.map((group) => {
          const fork = group.querySelector<SVGCircleElement>('[data-node-position="fork"]');
          if (fork === null) {
            throw new Error("Topology lab fork is missing");
          }
          return Math.abs(
            Number(fork.getAttribute("cx")) - mainlineXAtY(Number(fork.getAttribute("cy"))),
          );
        }),
      ),
      maximumLocalLaneSpacingError: Math.max(
        ...routeFacts
          .filter((route) => route.lane <= 2)
          .map((route) => Math.abs(route.forkX - route.targetX - route.lane * 96)),
      ),
      maximumMainlineXDrift: Math.max(
        ...Array.from({ length: 101 }, (_, index) =>
          Math.abs(
            mainline.getPointAtLength((mainline.getTotalLength() * index) / 100).x -
              mainline.getPointAtLength(0).x,
          ),
        ),
      ),
      maximumFillerOwnerPathDistance: Math.max(...fillerOwnerPathDistances),
      nonMainFillerOffMainlineCount: visibleFillers.filter(
        (node) =>
          node.dataset["nodeOwner"] !== "main" &&
          Math.abs(Number(node.getAttribute("cx")) - mainline.getPointAtLength(0).x) > 0.01,
      ).length,
      mainlineForkX: routeFacts[0]?.forkX,
      rowCount: Number(svg.dataset["rowCount"]),
      routeFacts,
      visibleNodeCount: visibleNodes.length,
      worktreeCount: Number(svg.dataset["worktreeCount"]),
    };
  });

  expect(await page.locator("main").innerText()).toBe("");
  expect(state.worktreeCount).toBe(5);
  expect(state.visibleNodeCount).toBe(state.rowCount);
  expect(state.duplicateRowCount).toBe(0);
  expect(new Set(state.fillerOwnerIds)).toEqual(
    new Set(["main", "worktree-a", "worktree-b", "worktree-c", "worktree-d", "worktree-e"]),
  );
  expect(state.fillerOwnerIds.filter((ownerId) => ownerId === "main").length).toBeLessThan(
    state.fillerOwnerIds.length,
  );
  expect(state.fillerColorMismatchCount).toBe(0);
  expect(state.inactiveWorktreeOwnerCount).toBe(0);
  expect(state.routeFacts.map((route) => route.lane)).toEqual([1, 2, 3, 4, 2]);
  expect(new Set(state.routeFacts.map((route) => route.forkX)).size).toBe(1);
  expect(state.mainlineForkX).toBe(2800 - 144);
  expect(state.maximumForkMainlineDelta).toBeLessThanOrEqual(0.01);
  expect(state.maximumLocalLaneSpacingError).toBeLessThanOrEqual(0.01);
  expect(state.maximumMainlineXDrift).toBeLessThanOrEqual(0.01);
  expect(state.maximumFillerOwnerPathDistance).toBeLessThanOrEqual(0.01);
  expect(state.nonMainFillerOffMainlineCount).toBeGreaterThan(0);
  expect(state.routeFacts.every((route) => route.startDelta <= 0.01)).toBe(true);
  expect(state.routeFacts.every((route) => route.endDelta <= 0.01)).toBe(true);
  expect(state.routeFacts.every((route) => Math.abs(route.minimumX - route.targetX) <= 0.01)).toBe(
    true,
  );
  expect(state.routeFacts.every((route) => route.unauthorizedFramePointCount === 0)).toBe(true);
  expect(state.routeFacts.map((route) => route.targetX)).toEqual([
    2800 - 240,
    2800 - 336,
    144 + (6 - 1) * 96,
    144 + (6 - 2) * 96,
    2800 - 336,
  ]);
  expect(state.routeFacts.every((route) => route.targetX < route.forkX)).toBe(true);
  expect(
    state.routeFacts
      .filter((route) => route.endKind === "open")
      .every((route) => route.endX === route.targetX),
  ).toBe(true);
  expect(
    state.routeFacts
      .filter((route) => route.endKind === "merge")
      .every((route) => route.endX === route.forkX),
  ).toBe(true);
  expect(state.routeFacts.filter((route) => route.endKind === "open")).toHaveLength(3);
  expect(state.routeFacts.filter((route) => route.endKind === "merge")).toHaveLength(2);
});
