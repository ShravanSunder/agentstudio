import {
  assignTopologyRowOwners,
  assignWorktreeLanes,
  centeredTopologyColumnXs,
  closestTopologySurfaceRow,
  measureFullPageTopologyGrid,
  resolveTopologyGlassBand,
  topologyRowUnit as rowUnit,
  type FullPageTopologyGrid,
  type FullPageTopologyVariant,
  type TopologyGlassBand,
  type TopologyGlassSurfaceBounds,
  type WorktreeLifecycle,
} from "./full-page-topology-model";

interface FullPageTopologyPortal {
  readonly frameLeft: number;
  readonly frameRight: number;
  readonly glassSurfaces: readonly TopologyGlassSurfaceBounds[];
}

type RoutePlacement = "cross-glass-left" | "local-right";

interface RouteDatasetBase extends WorktreeLifecycle {
  readonly variants: readonly FullPageTopologyVariant[];
}

type OptionalRoutePageEndAnchor =
  | { readonly endPageOffset?: never; readonly endPageRow?: never }
  | { readonly endPageOffset: number; readonly endPageRow?: never }
  | { readonly endPageOffset?: never; readonly endPageRow: number };

type LocalRightRouteDataset = RouteDatasetBase &
  OptionalRoutePageEndAnchor & {
    readonly endGlassIndex?: never;
    readonly forkGlassIndex?: never;
    readonly forkPageRow?: number;
    readonly placement: "local-right";
  };

type CrossGlassLeftRouteDataset =
  | (RouteDatasetBase & {
      readonly endGlassIndex: number;
      readonly endKind: "merge";
      readonly endPageOffset?: never;
      readonly endPageRow?: never;
      readonly forkGlassIndex: number;
      readonly forkPageRow?: never;
      readonly placement: "cross-glass-left";
    })
  | (RouteDatasetBase &
      OptionalRoutePageEndAnchor & {
        readonly endGlassIndex?: never;
        readonly endKind: "open";
        readonly forkGlassIndex: number;
        readonly forkPageRow?: never;
        readonly placement: "cross-glass-left";
      });

type RouteDataset = CrossGlassLeftRouteDataset | LocalRightRouteDataset;

type ResolvedRouteDataset = RouteDataset & {
  readonly endRow: number;
  readonly forkRow: number;
};

interface ResolvedRouteGeometry {
  readonly endRow: number;
  readonly forkRow: number;
  readonly pathData: string;
  readonly sourceX: number;
  readonly targetX: number;
}

interface RouteLaneAssignment {
  readonly lane: number;
  readonly placement: RoutePlacement;
}

interface ResolvedRowWorktree {
  readonly accentClass: string;
  readonly endRow: number;
  readonly id: string;
  readonly lane: number;
  readonly path: SVGPathElement;
  readonly startRow: number;
}

function lifecycleForResolvedRoute(dataset: ResolvedRouteDataset): WorktreeLifecycle {
  return {
    endKind: dataset.endKind,
    endSlot: dataset.endRow,
    forkSlot: dataset.forkRow,
    id: dataset.id,
  };
}

function requiredDatasetNumber(element: HTMLElement | SVGElement, key: string): number {
  const value = element.dataset[key];
  const numberValue = Number(value);
  if (value === undefined || value === "" || !Number.isFinite(numberValue)) {
    throw new Error(`Invalid topology data attribute: ${key}`);
  }
  return numberValue;
}

function optionalDatasetNumber(element: HTMLElement | SVGElement, key: string): number | undefined {
  return element.dataset[key] === undefined ? undefined : requiredDatasetNumber(element, key);
}

function isTopologyVariant(value: string): value is FullPageTopologyVariant {
  return value === "compact" || value === "standard" || value === "expanded";
}

function readRouteDataset(group: SVGGElement): RouteDataset {
  const endKind = group.dataset["endKind"];
  const id = group.dataset["routeId"];
  const placement = group.dataset["routePlacement"];
  const variantValues = (group.dataset["topologyVariants"] ?? "").split(" ").filter(Boolean);
  if (
    (endKind !== "merge" && endKind !== "open") ||
    !id ||
    (placement !== "local-right" && placement !== "cross-glass-left") ||
    variantValues.length === 0 ||
    !variantValues.every(isTopologyVariant)
  ) {
    throw new Error("Invalid authored worktree route");
  }
  const variants = variantValues.filter(isTopologyVariant);
  const base = {
    endSlot: requiredDatasetNumber(group, "endSlot"),
    forkSlot: requiredDatasetNumber(group, "forkSlot"),
    id,
    variants,
  };
  const endGlassIndex = optionalDatasetNumber(group, "endGlassIndex");
  const endPageOffset = optionalDatasetNumber(group, "endPageOffset");
  const endPageRow = optionalDatasetNumber(group, "endPageRow");
  const forkGlassIndex = optionalDatasetNumber(group, "forkGlassIndex");
  const forkPageRow = optionalDatasetNumber(group, "forkPageRow");
  if (endPageOffset !== undefined && endPageRow !== undefined) {
    throw new Error("Invalid authored topology placement");
  }
  const pageEndAnchor =
    endPageOffset === undefined
      ? endPageRow === undefined
        ? {}
        : { endPageRow }
      : { endPageOffset };
  if (placement === "local-right") {
    if (forkGlassIndex !== undefined || endGlassIndex !== undefined) {
      throw new Error("Invalid authored topology placement");
    }
    return {
      ...base,
      ...pageEndAnchor,
      endKind,
      ...(forkPageRow === undefined ? {} : { forkPageRow }),
      placement,
    };
  }
  if (forkGlassIndex === undefined || forkPageRow !== undefined) {
    throw new Error("Invalid authored topology placement");
  }
  if (endKind === "merge") {
    if (endGlassIndex === undefined || endPageOffset !== undefined || endPageRow !== undefined) {
      throw new Error("Invalid authored topology placement");
    }
    return {
      ...base,
      endGlassIndex,
      endKind,
      forkGlassIndex,
      placement,
    };
  }
  if (endGlassIndex !== undefined) {
    throw new Error("Invalid authored topology placement");
  }
  return {
    ...base,
    ...pageEndAnchor,
    endKind,
    forkGlassIndex,
    placement,
  };
}

function rowForSlot(slot: number, band: TopologyGlassBand): number {
  const bandRowCount = band.lastCrossRow - band.firstCrossRow;
  return band.firstCrossRow + Math.round((slot / band.slotCount) * bandRowCount);
}

function rowForGlassIndex(
  glassIndex: number,
  portal: FullPageTopologyPortal,
  grid: FullPageTopologyGrid,
  band: TopologyGlassBand,
): number | undefined {
  if (glassIndex === 0) {
    return band.firstCrossRow;
  }
  if (glassIndex === portal.glassSurfaces.length - 1) {
    return band.lastCrossRow;
  }
  const surface = portal.glassSurfaces[glassIndex];
  return surface === undefined ? undefined : closestTopologySurfaceRow(surface, grid, 0.5);
}

function resolveRouteRows(
  dataset: RouteDataset,
  portal: FullPageTopologyPortal,
  grid: FullPageTopologyGrid,
  band: TopologyGlassBand,
): ResolvedRouteDataset | undefined {
  const forkRow =
    dataset.forkPageRow ??
    (dataset.forkGlassIndex === undefined
      ? rowForSlot(dataset.forkSlot, band)
      : rowForGlassIndex(dataset.forkGlassIndex, portal, grid, band));
  const endRow =
    dataset.endPageRow ??
    (dataset.endPageOffset === undefined ? undefined : grid.finalRow - dataset.endPageOffset) ??
    (dataset.endGlassIndex === undefined
      ? rowForSlot(dataset.endSlot, band)
      : rowForGlassIndex(dataset.endGlassIndex, portal, grid, band));
  if (
    forkRow === undefined ||
    endRow === undefined ||
    forkRow < 1 ||
    forkRow >= grid.finalRow ||
    endRow < 1 ||
    endRow >= grid.finalRow ||
    endRow <= forkRow
  ) {
    return undefined;
  }
  return { ...dataset, endRow, forkRow };
}

function localForkPath(
  sourceX: number,
  targetX: number,
  forkY: number,
  arrivalY: number,
): readonly string[] {
  return [
    `M ${sourceX} ${forkY}`,
    `C ${sourceX + (targetX - sourceX) * 0.9} ${forkY + (arrivalY - forkY) * 0.08} ${targetX} ${forkY + (arrivalY - forkY) * 0.1} ${targetX} ${arrivalY}`,
  ];
}

function localMergePath(
  sourceX: number,
  targetX: number,
  approachY: number,
  mergeY: number,
): readonly string[] {
  return [
    `L ${targetX} ${approachY}`,
    `C ${targetX} ${approachY + (mergeY - approachY) * 0.9} ${targetX + (sourceX - targetX) * 0.1} ${approachY + (mergeY - approachY) * 0.92} ${sourceX} ${mergeY}`,
  ];
}

function crossFrameForkPath(
  sourceX: number,
  targetX: number,
  forkY: number,
  arrivalY: number,
  portal: FullPageTopologyPortal,
): readonly string[] {
  return [
    `M ${sourceX} ${forkY}`,
    `L ${portal.frameLeft} ${forkY}`,
    `C ${portal.frameLeft + (targetX - portal.frameLeft) * 0.9} ${forkY + (arrivalY - forkY) * 0.08} ${targetX} ${forkY + (arrivalY - forkY) * 0.1} ${targetX} ${arrivalY}`,
  ];
}

function crossFrameMergePath(
  sourceX: number,
  targetX: number,
  approachY: number,
  mergeY: number,
  portal: FullPageTopologyPortal,
): readonly string[] {
  return [
    `L ${targetX} ${approachY}`,
    `C ${targetX} ${approachY + (mergeY - approachY) * 0.9} ${targetX + (portal.frameLeft - targetX) * 0.1} ${approachY + (mergeY - approachY) * 0.92} ${portal.frameLeft} ${mergeY}`,
    `L ${sourceX} ${mergeY}`,
  ];
}

function resolveRouteGeometry(
  dataset: ResolvedRouteDataset,
  sourceX: number,
  targetX: number,
  grid: FullPageTopologyGrid,
  portal: FullPageTopologyPortal,
): ResolvedRouteGeometry {
  const { endRow, forkRow } = dataset;
  const arrivalRow = Math.min(forkRow + 1, endRow);
  const yForRow = (row: number): number => grid.topPadding + row * rowUnit;
  const segments = [
    ...(dataset.placement === "local-right"
      ? localForkPath(sourceX, targetX, yForRow(forkRow), yForRow(arrivalRow))
      : crossFrameForkPath(sourceX, targetX, yForRow(forkRow), yForRow(arrivalRow), portal)),
  ];
  if (dataset.endKind === "merge") {
    const approachRow = Math.max(endRow - 1, arrivalRow);
    segments.push(
      ...(dataset.placement === "local-right"
        ? localMergePath(sourceX, targetX, yForRow(approachRow), yForRow(endRow))
        : crossFrameMergePath(sourceX, targetX, yForRow(approachRow), yForRow(endRow), portal)),
    );
  } else {
    segments.push(`L ${targetX} ${yForRow(endRow)}`);
  }
  return { endRow, forkRow, pathData: segments.join(" "), sourceX, targetX };
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

function pathLengthFractionAtY(path: SVGPathElement, targetY: number): number {
  const totalLength = path.getTotalLength();
  let lowerLength = 0;
  let upperLength = totalLength;
  for (let iteration = 0; iteration < 24; iteration += 1) {
    const middleLength = lowerLength + (upperLength - lowerLength) / 2;
    if (path.getPointAtLength(middleLength).y <= targetY) {
      lowerLength = middleLength;
    } else {
      upperLength = middleLength;
    }
  }
  return totalLength <= 0 ? 0 : lowerLength / totalLength;
}

function pathPointAtY(path: SVGPathElement, targetY: number): DOMPoint {
  const totalLength = path.getTotalLength();
  return path.getPointAtLength(totalLength * pathLengthFractionAtY(path, targetY));
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
  let authoredRoutes: readonly { readonly dataset: RouteDataset; readonly group: SVGGElement }[];
  try {
    authoredRoutes = routeGroups.map((group) => ({ dataset: readRouteDataset(group), group }));
  } catch {
    return hideTopology(artwork, "invalid-authored-route");
  }
  if (new Set(authoredRoutes.map(({ dataset }) => dataset.id)).size !== authoredRoutes.length) {
    return hideTopology(artwork, "invalid-authored-route");
  }
  const variantCapacities = {
    compact: 2,
    expanded: 4,
    standard: 3,
  } satisfies Record<FullPageTopologyVariant, number>;
  const variantLayouts = new Map<
    FullPageTopologyVariant,
    {
      readonly leftAssignments: readonly { readonly id: string; readonly lane: number }[];
      readonly rightAssignments: readonly { readonly id: string; readonly lane: number }[];
      readonly visibleRoutes: readonly {
        readonly dataset: ResolvedRouteDataset;
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
      const resolvedDataset = resolveRouteRows(dataset, portal, grid, band);
      return resolvedDataset === undefined ? [] : [{ dataset: resolvedDataset, group }];
    });
    if (variantRoutes.length !== variantRouteCandidates.length) {
      return hideTopology(artwork, "invalid-route-glass-anchor");
    }
    const variantCapacity = variantCapacities[variant];
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
    const geometry = resolveRouteGeometry(dataset, mainlineX, targetX, grid, portal);
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
    const routeAccent = group.dataset["routeAccent"];
    if (routeAccent !== "cyan" && routeAccent !== "peach") {
      return hideTopology(artwork, "missing-route-accent");
    }
    resolvedRowWorktrees.push({
      accentClass: `accent-${routeAccent}`,
      endRow: geometry.endRow,
      id: dataset.id,
      lane: placement === "local-right" ? lane + 1 : lane + 5,
      path: corePath,
      startRow: geometry.forkRow,
    });

    for (const node of group.querySelectorAll<SVGGraphicsElement>("[data-node]")) {
      const position = node.dataset["nodePosition"];
      const row =
        position === "fork"
          ? geometry.forkRow
          : position === "end"
            ? geometry.endRow
            : rowForSlot(requiredDatasetNumber(node, "nodeSlot"), band);
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
      const routeFraction = pathLengthFractionAtY(corePath, y);
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
    const point = pathPointAtY(ownerPath, y);
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

export function initializeFullPageTopologyLayout(artwork: SVGSVGElement): () => void {
  let pendingFrame: number | undefined;
  const render = (): void => {
    pendingFrame = undefined;
    layoutFullPageTopology(artwork);
  };
  const schedule = (): void => {
    if (pendingFrame === undefined) {
      pendingFrame = window.requestAnimationFrame(render);
    }
  };
  const observer = new ResizeObserver(schedule);
  observer.observe(artwork);
  schedule();
  return (): void => {
    observer.disconnect();
    if (pendingFrame !== undefined) {
      window.cancelAnimationFrame(pendingFrame);
    }
  };
}
