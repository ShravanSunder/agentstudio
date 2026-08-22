import {
  readTopologyRouteContract,
  type TopologyRouteContract,
  type TopologyRoutePlacement,
} from "./full-page-topology-contract";
import {
  assignTopologyRowOwners,
  assignWorktreeLanes,
  centeredTopologyColumnXs,
  maximumGutterColumnCount,
  measureFullPageTopologyGrid,
  resolveTopologyGlassBand,
  topologyVariantColumnCapacities,
  topologyRowUnit as rowUnit,
  type FullPageTopologyGrid,
  type FullPageTopologyVariant,
  type TopologyGlassSurfaceBounds,
  type WorktreeLifecycle,
} from "./full-page-topology-model";
import {
  resolveTopologyRouteGeometry,
  resolveTopologyRouteRows,
  topologyPathLengthFractionAtY,
  topologyPathPointAtY,
  type FullPageTopologyPortal,
  type ResolvedTopologyRoute,
} from "./full-page-topology-paths";

interface RouteLaneAssignment {
  readonly lane: number;
  readonly placement: TopologyRoutePlacement;
}

interface ResolvedRowWorktree {
  readonly accentClass: string;
  readonly endRow: number;
  readonly id: string;
  readonly path: SVGPathElement;
  readonly priority: number;
  readonly startRow: number;
}

function lifecycleForResolvedRoute(dataset: ResolvedTopologyRoute): WorktreeLifecycle {
  return {
    endRow: dataset.endRow,
    endKind: dataset.endKind,
    forkRow: dataset.forkRow,
    id: dataset.id,
  };
}

function resolveTopologyPortal(artwork: SVGSVGElement): FullPageTopologyPortal | undefined {
  const frameSelector = artwork.dataset["portalFrameSelector"];
  const surfaceSelector = artwork.dataset["portalSurfaceSelector"];
  if (!frameSelector || !surfaceSelector) {
    return undefined;
  }
  const frame = document.querySelector<HTMLElement>(frameSelector);
  if (frame === null) {
    return undefined;
  }

  const artworkBounds = artwork.getBoundingClientRect();
  const frameBounds = frame.getBoundingClientRect();
  const glassSurfaces = [...document.querySelectorAll<HTMLElement>(surfaceSelector)].map(
    (surface): TopologyGlassSurfaceBounds => {
      const bounds = surface.getBoundingClientRect();
      const transform = getComputedStyle(surface).transform;
      const transformY = transform === "none" ? 0 : new DOMMatrixReadOnly(transform).m42;
      const top = bounds.top - transformY - artworkBounds.top;
      return { bottom: top + bounds.height, top };
    },
  );
  return {
    frameLeft: frameBounds.left - artworkBounds.left,
    frameRight: frameBounds.right - artworkBounds.left,
    glassSurfaces,
  };
}

function resolveTopologyTopPadding(artwork: SVGSVGElement): number {
  const anchorSelector = artwork.dataset["mainlineAnchorSelector"];
  const anchor = anchorSelector ? document.querySelector<HTMLElement>(anchorSelector) : undefined;
  if (anchor === null || anchor === undefined) {
    return rowUnit;
  }
  const artworkBounds = artwork.getBoundingClientRect();
  const anchorBounds = anchor.getBoundingClientRect();
  return anchorBounds.top + anchorBounds.height / 2 - artworkBounds.top;
}

function setPortalMask(artwork: SVGSVGElement, portal: FullPageTopologyPortal): void {
  artwork.style.maskImage = [
    `linear-gradient(to right, #000 0, #000 ${portal.frameLeft}px, transparent ${portal.frameLeft}px, transparent ${portal.frameRight}px, #000 ${portal.frameRight}px, #000 100%)`,
    ...portal.glassSurfaces.map(() => "linear-gradient(#000, #000)"),
  ].join(", ");
  artwork.style.maskPosition = [
    "0 0",
    ...portal.glassSurfaces.map((surface) => `${portal.frameLeft}px ${surface.top}px`),
  ].join(", ");
  artwork.style.maskRepeat = "no-repeat";
  artwork.style.maskSize = [
    "100% 100%",
    ...portal.glassSurfaces.map(
      (surface) => `${portal.frameRight - portal.frameLeft}px ${surface.bottom - surface.top}px`,
    ),
  ].join(", ");
  artwork.setAttribute("data-topology-portal-active", "");
}

function buildMainlinePath(grid: FullPageTopologyGrid, mainlineX: number): string {
  const yForRow = (row: number): number => grid.topPadding + row * rowUnit;
  return `M ${mainlineX} ${yForRow(0)} L ${mainlineX} ${yForRow(grid.finalRow)}`;
}

function setNodePosition(node: SVGGraphicsElement, x: number, y: number): void {
  if (node instanceof SVGCircleElement) {
    node.setAttribute("cx", String(x));
    node.setAttribute("cy", String(y));
  } else {
    node.setAttribute("transform", `translate(${x} ${y})`);
  }
}

function hideTopology(artwork: SVGSVGElement, reason: string): boolean {
  artwork.style.visibility = "hidden";
  artwork.dataset["topologyHiddenReason"] = reason;
  artwork.removeAttribute("data-topology-variant");
  return true;
}

export function layoutFullPageTopology(artwork: SVGSVGElement): boolean {
  const portal = resolveTopologyPortal(artwork);
  if (portal === undefined) {
    return hideTopology(artwork, "missing-portal");
  }
  const grid = measureFullPageTopologyGrid({
    frameLeft: portal.frameLeft,
    frameRight: portal.frameRight,
    height: artwork.clientHeight,
    requestedTopPadding: resolveTopologyTopPadding(artwork),
    width: artwork.clientWidth,
  });
  if (grid === undefined) {
    return hideTopology(artwork, "insufficient-gutter-capacity");
  }
  const band = resolveTopologyGlassBand({ glassSurfaces: portal.glassSurfaces, grid });
  if (band === undefined) {
    return hideTopology(artwork, "invalid-glass-band");
  }

  const routeGroups = [...artwork.querySelectorAll<SVGGElement>("[data-topology-route-group]")];
  let authoredRoutes: readonly {
    readonly dataset: TopologyRouteContract;
    readonly group: SVGGElement;
  }[];
  try {
    authoredRoutes = routeGroups.map((group) => ({
      dataset: readTopologyRouteContract(group),
      group,
    }));
  } catch {
    return hideTopology(artwork, "invalid-authored-route");
  }
  if (new Set(authoredRoutes.map(({ dataset }) => dataset.id)).size !== authoredRoutes.length) {
    return hideTopology(artwork, "invalid-authored-route");
  }
  const variantLayouts = new Map<
    FullPageTopologyVariant,
    {
      readonly leftAssignments: readonly { readonly id: string; readonly lane: number }[];
      readonly rightAssignments: readonly { readonly id: string; readonly lane: number }[];
      readonly visibleRoutes: readonly {
        readonly dataset: ResolvedTopologyRoute;
        readonly group: SVGGElement;
      }[];
    }
  >();
  const stableAssignmentByRouteId = new Map<string, RouteLaneAssignment>();
  for (const variant of ["compact", "standard", "expanded"] as const) {
    const variantRouteCandidates = authoredRoutes.filter(({ dataset }) =>
      dataset.variants.includes(variant),
    );
    const variantRoutes = variantRouteCandidates.flatMap(({ dataset, group }) => {
      const resolvedDataset = resolveTopologyRouteRows(dataset, portal, grid, band);
      return resolvedDataset === undefined ? [] : [{ dataset: resolvedDataset, group }];
    });
    if (variantRoutes.length !== variantRouteCandidates.length) {
      return hideTopology(artwork, "invalid-route-glass-anchor");
    }
    const variantCapacity = topologyVariantColumnCapacities[variant];
    const rightVariantAssignments = assignWorktreeLanes(
      variantRoutes
        .filter(({ dataset }) => dataset.placement === "local-right")
        .map(({ dataset }) => lifecycleForResolvedRoute(dataset)),
      variantCapacity - 1,
    );
    const leftVariantAssignments = assignWorktreeLanes(
      variantRoutes
        .filter(({ dataset }) => dataset.placement === "cross-glass-left")
        .map(({ dataset }) => lifecycleForResolvedRoute(dataset)),
      variantCapacity,
    );
    if (rightVariantAssignments === undefined || leftVariantAssignments === undefined) {
      return hideTopology(artwork, "invalid-worktree-occupancy");
    }
    const variantAssignments: readonly [string, RouteLaneAssignment][] = [
      ...rightVariantAssignments.map(({ id, lane }): [string, RouteLaneAssignment] => [
        id,
        { lane, placement: "local-right" },
      ]),
      ...leftVariantAssignments.map(({ id, lane }): [string, RouteLaneAssignment] => [
        id,
        { lane, placement: "cross-glass-left" },
      ]),
    ];
    for (const [id, assignment] of variantAssignments) {
      const stableAssignment = stableAssignmentByRouteId.get(id);
      if (
        stableAssignment !== undefined &&
        (stableAssignment.lane !== assignment.lane ||
          stableAssignment.placement !== assignment.placement)
      ) {
        return hideTopology(artwork, "invalid-variant-identity");
      }
      stableAssignmentByRouteId.set(id, assignment);
    }
    variantLayouts.set(variant, {
      leftAssignments: leftVariantAssignments,
      rightAssignments: rightVariantAssignments,
      visibleRoutes: variantRoutes,
    });
  }
  const currentVariantLayout = variantLayouts.get(grid.variant);
  if (currentVariantLayout === undefined) {
    return hideTopology(artwork, "invalid-authored-route");
  }
  const { leftAssignments, rightAssignments, visibleRoutes } = currentVariantLayout;
  const usedRightColumnCount =
    1 +
    (rightAssignments.length === 0 ? 0 : Math.max(...rightAssignments.map(({ lane }) => lane)) + 1);
  const usedLeftColumnCount =
    leftAssignments.length === 0 ? 0 : Math.max(...leftAssignments.map(({ lane }) => lane)) + 1;
  const rightColumnXs = centeredTopologyColumnXs({
    columnCount: usedRightColumnCount,
    gutterEnd: artwork.clientWidth,
    gutterStart: portal.frameRight,
  });
  const leftColumnXs = centeredTopologyColumnXs({
    columnCount: usedLeftColumnCount,
    gutterEnd: portal.frameLeft,
    gutterStart: 0,
  });
  const mainlineX = rightColumnXs?.at(-1);
  if (rightColumnXs === undefined || leftColumnXs === undefined || mainlineX === undefined) {
    return hideTopology(artwork, "invalid-centered-columns");
  }
  const laneByRouteId = new Map<string, RouteLaneAssignment>([
    ...rightAssignments.map(({ id, lane }): [string, RouteLaneAssignment] => [
      id,
      { lane, placement: "local-right" },
    ]),
    ...leftAssignments.map(({ id, lane }): [string, RouteLaneAssignment] => [
      id,
      { lane, placement: "cross-glass-left" },
    ]),
  ]);
  const datasetByRouteId = new Map(visibleRoutes.map(({ dataset }) => [dataset.id, dataset]));

  artwork.style.visibility = "visible";
  delete artwork.dataset["topologyHiddenReason"];
  artwork.dataset["columnCount"] = String(grid.columnCapacity);
  artwork.dataset["leftColumnCount"] = String(usedLeftColumnCount);
  artwork.dataset["rightColumnCount"] = String(usedRightColumnCount);
  artwork.dataset["firstGlassRow"] = String(band.firstCrossRow);
  artwork.dataset["finalRow"] = String(grid.finalRow);
  artwork.dataset["lastGlassRow"] = String(band.lastCrossRow);
  artwork.dataset["rowCount"] = String(grid.rowCount);
  artwork.dataset["topologyStartY"] = String(grid.topPadding);
  artwork.dataset["topologyEndY"] = String(grid.topPadding + grid.finalRow * rowUnit);
  artwork.dataset["topologyVariant"] = grid.variant;
  artwork.dataset["worktreeCount"] = String(visibleRoutes.length);
  artwork.setAttribute("viewBox", `0 0 ${artwork.clientWidth} ${artwork.clientHeight}`);
  for (const revealRect of artwork.querySelectorAll<SVGRectElement>(
    "[data-topology-reveal-solid], [data-topology-reveal-fade]",
  )) {
    revealRect.setAttribute("width", String(artwork.clientWidth));
  }
  setPortalMask(artwork, portal);

  const mainlineData = buildMainlinePath(grid, mainlineX);
  for (const mainline of artwork.querySelectorAll<SVGPathElement>("[data-mainline]")) {
    mainline.setAttribute("d", mainlineData);
  }
  const mainlineCore = artwork.querySelector<SVGPathElement>(
    '[data-mainline][data-topology-path-role="core"]',
  );
  if (mainlineCore === null) {
    return hideTopology(artwork, "missing-mainline");
  }

  const yForRow = (row: number): number => grid.topPadding + row * rowUnit;
  const topologyEndY = yForRow(grid.finalRow);
  const progressForY = (y: number): number =>
    Math.min(Math.max((y - grid.topPadding) / (topologyEndY - grid.topPadding), 0), 1);
  const occupiedNodeRows = new Set<number>();
  const resolvedRowWorktrees: ResolvedRowWorktree[] = [];
  const reserveNodeRow = (row: number): boolean => {
    if (occupiedNodeRows.has(row)) {
      return false;
    }
    occupiedNodeRows.add(row);
    return true;
  };

  for (const node of artwork.querySelectorAll<SVGGraphicsElement>("[data-mainline-node]")) {
    const kind = node.dataset["mainlineNode"];
    const row = kind === "start" ? 0 : grid.finalRow;
    if (!reserveNodeRow(row)) {
      return hideTopology(artwork, "duplicate-node-row");
    }
    const y = yForRow(row);
    setNodePosition(node, mainlineX, y);
    node.dataset["nodeOwner"] = "main";
    node.dataset["resolvedRow"] = String(row);
    node.removeAttribute("data-topology-glass-bridge");
    node.dataset["topologyNodeProgress"] = kind === "start" ? "0" : "1";
  }

  for (const group of routeGroups) {
    const routeId = group.dataset["routeId"];
    const dataset = routeId === undefined ? undefined : datasetByRouteId.get(routeId);
    if (routeId === undefined) {
      return hideTopology(artwork, "missing-route-id");
    }
    const assignment = laneByRouteId.get(routeId);
    group.style.display = assignment === undefined ? "none" : "";
    if (assignment === undefined || dataset === undefined) {
      continue;
    }
    const { lane, placement } = assignment;
    const targetX =
      placement === "local-right"
        ? rightColumnXs[rightColumnXs.length - 2 - lane]
        : leftColumnXs[leftColumnXs.length - 1 - lane];
    if (targetX === undefined || placement !== dataset.placement) {
      return hideTopology(artwork, "invalid-route-placement");
    }
    group.dataset["resolvedLane"] = String(lane);
    group.dataset["resolvedPlacement"] = placement;
    group.dataset["resolvedSideSlot"] = String(lane);
    const geometry = resolveTopologyRouteGeometry(dataset, mainlineX, targetX, grid, portal);
    group.dataset["resolvedSourceX"] = String(geometry.sourceX);
    group.dataset["resolvedTargetX"] = String(geometry.targetX);
    const routeStart = progressForY(yForRow(geometry.forkRow));
    const routeEnd = progressForY(yForRow(geometry.endRow));
    for (const path of group.querySelectorAll<SVGPathElement>("[data-route]")) {
      path.setAttribute("d", geometry.pathData);
      path.dataset["topologyPathStart"] = String(routeStart);
      path.dataset["topologyPathEnd"] = String(routeEnd);
    }
    const corePath = group.querySelector<SVGPathElement>(
      '[data-route][data-topology-path-role="core"]',
    );
    if (corePath === null) {
      return hideTopology(artwork, "missing-core-route");
    }
    resolvedRowWorktrees.push({
      accentClass: `accent-${dataset.accent}`,
      endRow: geometry.endRow,
      id: dataset.id,
      priority: placement === "local-right" ? lane + 1 : maximumGutterColumnCount + lane + 1,
      path: corePath,
      startRow: geometry.forkRow,
    });

    for (const node of group.querySelectorAll<SVGGraphicsElement>("[data-node]")) {
      const position = node.dataset["nodePosition"];
      if (position !== "fork" && position !== "end") {
        return hideTopology(artwork, "invalid-route-node");
      }
      const row = position === "fork" ? geometry.forkRow : geometry.endRow;
      const x =
        position === "fork" || (position === "end" && dataset.endKind === "merge")
          ? geometry.sourceX
          : geometry.targetX;
      if (!reserveNodeRow(row)) {
        return hideTopology(artwork, "duplicate-node-row");
      }
      const y = yForRow(row);
      setNodePosition(node, x, y);
      node.dataset["nodeOwner"] =
        position === "fork" || (position === "end" && dataset.endKind === "merge")
          ? "main"
          : dataset.id;
      node.dataset["resolvedRow"] = String(row);
      node.toggleAttribute(
        "data-topology-glass-bridge",
        (position === "fork" && dataset.forkGlassIndex !== undefined) ||
          (position === "end" && dataset.endGlassIndex !== undefined),
      );
      const routeFraction = topologyPathLengthFractionAtY(corePath, y);
      const minimumVisibleFraction = Math.min(4 / Math.max(corePath.getTotalLength(), 1), 1);
      node.dataset["topologyNodeProgress"] = String(
        routeStart +
          (routeEnd - routeStart) * (position === "fork" ? minimumVisibleFraction : routeFraction),
      );
    }
  }

  const rowOwners = assignTopologyRowOwners({
    reservedRows: occupiedNodeRows,
    rowCount: grid.rowCount,
    worktrees: resolvedRowWorktrees,
  });
  const fillNodes = [...artwork.querySelectorAll<SVGCircleElement>("[data-mainline-fill-index]")];
  if (rowOwners.length > fillNodes.length) {
    return hideTopology(artwork, "insufficient-mainline-fill-nodes");
  }
  for (const [fillIndex, fillNode] of fillNodes.entries()) {
    const rowOwner = rowOwners[fillIndex];
    fillNode.style.display = rowOwner === undefined ? "none" : "";
    if (rowOwner === undefined) {
      continue;
    }
    const { ownerId, row } = rowOwner;
    const ownerWorktree = resolvedRowWorktrees.find((worktree) => worktree.id === ownerId);
    const ownerPath = ownerWorktree?.path ?? mainlineCore;
    const y = yForRow(row);
    const point = topologyPathPointAtY(ownerPath, y);
    setNodePosition(fillNode, point.x, y);
    fillNode.setAttribute("class", ownerWorktree?.accentClass ?? "accent-main");
    fillNode.dataset["nodeOwner"] = ownerId;
    fillNode.dataset["resolvedRow"] = String(row);
    fillNode.dataset["topologyNodeProgress"] = String(progressForY(y));
    occupiedNodeRows.add(row);
  }
  if (occupiedNodeRows.size !== grid.rowCount) {
    return hideTopology(artwork, "incomplete-node-rows");
  }
  return true;
}
