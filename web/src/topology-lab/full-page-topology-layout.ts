import {
  assignWorktreeColumns,
  closestTopologySurfaceRow,
  measureFullPageTopologyGrid,
  resolveTopologyGlassBand,
  topologyRowUnit as rowUnit,
  type FullPageTopologyGrid,
  type TopologyGlassBand,
  type TopologyGlassSurfaceBounds,
  type WorktreeLifecycle,
} from "./full-page-topology-model";

interface FullPageTopologyPortal {
  readonly frameLeft: number;
  readonly frameRight: number;
  readonly glassSurfaces: readonly TopologyGlassSurfaceBounds[];
}

interface RouteDataset extends WorktreeLifecycle {
  readonly endGlassIndex?: number;
  readonly forkGlassIndex?: number;
  readonly minimumColumns: number;
}

interface ResolvedRouteGeometry {
  readonly endRow: number;
  readonly forkRow: number;
  readonly pathData: string;
  readonly sourceX: number;
  readonly targetX: number;
}

function requiredDatasetNumber(element: HTMLElement | SVGElement, key: string): number {
  const value = element.dataset[key];
  const numberValue = Number(value);
  if (value === undefined || value === "" || !Number.isFinite(numberValue)) {
    throw new Error(`Invalid topology data attribute: ${key}`);
  }
  return numberValue;
}

function readRouteDataset(group: SVGGElement): RouteDataset {
  const endKind = group.dataset["endKind"];
  const id = group.dataset["routeId"];
  if ((endKind !== "merge" && endKind !== "open") || !id) {
    throw new Error("Invalid authored worktree route");
  }
  return {
    endKind,
    endSlot: requiredDatasetNumber(group, "endSlot"),
    forkSlot: requiredDatasetNumber(group, "forkSlot"),
    id,
    minimumColumns: requiredDatasetNumber(group, "minimumColumns"),
    ...(group.dataset["endGlassIndex"] === undefined
      ? {}
      : { endGlassIndex: requiredDatasetNumber(group, "endGlassIndex") }),
    ...(group.dataset["forkGlassIndex"] === undefined
      ? {}
      : { forkGlassIndex: requiredDatasetNumber(group, "forkGlassIndex") }),
  };
}

function rowForSlot(slot: number, band: TopologyGlassBand): number {
  const bandRowCount = band.lastCrossRow - band.firstCrossRow;
  return band.firstCrossRow + Math.round((slot / band.slotCount) * bandRowCount);
}

function slotForRow(row: number, band: TopologyGlassBand): number {
  const bandRowCount = band.lastCrossRow - band.firstCrossRow;
  return Math.round(((row - band.firstCrossRow) / bandRowCount) * band.slotCount);
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

function resolveRouteGlassSlots(
  dataset: RouteDataset,
  portal: FullPageTopologyPortal,
  grid: FullPageTopologyGrid,
  band: TopologyGlassBand,
): RouteDataset | undefined {
  const forkRow =
    dataset.forkGlassIndex === undefined
      ? undefined
      : rowForGlassIndex(dataset.forkGlassIndex, portal, grid, band);
  const endRow =
    dataset.endGlassIndex === undefined
      ? undefined
      : rowForGlassIndex(dataset.endGlassIndex, portal, grid, band);
  if (
    (dataset.forkGlassIndex !== undefined && forkRow === undefined) ||
    (dataset.endGlassIndex !== undefined && endRow === undefined)
  ) {
    return undefined;
  }
  return {
    ...dataset,
    endSlot: endRow === undefined ? dataset.endSlot : slotForRow(endRow, band),
    forkSlot: forkRow === undefined ? dataset.forkSlot : slotForRow(forkRow, band),
  };
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
  dataset: RouteDataset,
  lane: number,
  grid: FullPageTopologyGrid,
  band: TopologyGlassBand,
  portal: FullPageTopologyPortal,
): ResolvedRouteGeometry {
  const sourceX = grid.rightLaneXs[0];
  const targetX =
    lane <= 2 ? grid.rightLaneXs[lane] : grid.leftLaneXs[grid.leftLaneXs.length - (lane - 2)];
  if (sourceX === undefined || targetX === undefined) {
    throw new Error("Missing authored topology lane");
  }
  const forkRow = rowForSlot(dataset.forkSlot, band);
  const endRow = rowForSlot(dataset.endSlot, band);
  const arrivalRow = Math.min(forkRow + 1, endRow);
  const yForRow = (row: number): number => grid.topPadding + row * rowUnit;
  const segments = [
    ...(dataset.forkGlassIndex === undefined
      ? localForkPath(sourceX, targetX, yForRow(forkRow), yForRow(arrivalRow))
      : crossFrameForkPath(sourceX, targetX, yForRow(forkRow), yForRow(arrivalRow), portal)),
  ];
  if (dataset.endKind === "merge") {
    const approachRow = Math.max(endRow - 1, arrivalRow);
    segments.push(
      ...(dataset.endGlassIndex === undefined
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

function buildMainlinePath(grid: FullPageTopologyGrid): string {
  const rightX = grid.rightLaneXs[0];
  if (rightX === undefined) {
    throw new Error("Missing mainline topology lane");
  }
  const yForRow = (row: number): number => grid.topPadding + row * rowUnit;
  return `M ${rightX} ${yForRow(0)} L ${rightX} ${yForRow(grid.finalRow)}`;
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
  const visibleRouteCandidates = routeGroups
    .map((group) => ({ dataset: readRouteDataset(group), group }))
    .filter(({ dataset }) => dataset.minimumColumns <= grid.usableColumnCount);
  const visibleRoutes = visibleRouteCandidates.flatMap(({ dataset, group }) => {
    const resolvedDataset = resolveRouteGlassSlots(dataset, portal, grid, band);
    return resolvedDataset === undefined ? [] : [{ dataset: resolvedDataset, group }];
  });
  if (visibleRoutes.length !== visibleRouteCandidates.length) {
    return hideTopology(artwork, "invalid-route-glass-anchor");
  }
  const assignments = assignWorktreeColumns(
    visibleRoutes.map(({ dataset }) => dataset),
    Math.min(6, grid.usableColumnCount * 2),
  );
  if (assignments === undefined) {
    return hideTopology(artwork, "invalid-worktree-occupancy");
  }
  const laneByRouteId = new Map(assignments.map(({ id, lane }) => [id, lane]));
  const datasetByRouteId = new Map(visibleRoutes.map(({ dataset }) => [dataset.id, dataset]));

  artwork.style.visibility = "visible";
  delete artwork.dataset["topologyHiddenReason"];
  artwork.dataset["columnCount"] = String(grid.usableColumnCount);
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

  const mainlineData = buildMainlinePath(grid);
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
    const x = grid.rightLaneXs[0];
    if (x === undefined || !reserveNodeRow(row)) {
      return hideTopology(artwork, "duplicate-node-row");
    }
    const y = yForRow(row);
    setNodePosition(node, x, y);
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
    const lane = laneByRouteId.get(routeId);
    group.style.display = lane === undefined ? "none" : "";
    if (lane === undefined || dataset === undefined) {
      continue;
    }
    group.dataset["resolvedLane"] = String(lane);
    const geometry = resolveRouteGeometry(dataset, lane, grid, band, portal);
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

  const remainingRows = Array.from({ length: grid.rowCount }, (_, row) => row).filter(
    (row) => !occupiedNodeRows.has(row),
  );
  const fillNodes = [...artwork.querySelectorAll<SVGCircleElement>("[data-mainline-fill-index]")];
  if (remainingRows.length > fillNodes.length) {
    return hideTopology(artwork, "insufficient-mainline-fill-nodes");
  }
  for (const [fillIndex, fillNode] of fillNodes.entries()) {
    const row = remainingRows[fillIndex];
    fillNode.style.display = row === undefined ? "none" : "";
    if (row === undefined) {
      continue;
    }
    const y = yForRow(row);
    const point = pathPointAtY(mainlineCore, y);
    setNodePosition(fillNode, point.x, y);
    fillNode.dataset["resolvedRow"] = String(row);
    fillNode.dataset["topologyNodeProgress"] = String(pathLengthFractionAtY(mainlineCore, y));
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
