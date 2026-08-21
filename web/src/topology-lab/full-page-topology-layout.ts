const columnUnit = 96;
const edgePadding = 96;
const forkCurveBias = 0.9;
const forkDepartureDrift = 0.08;
const leftPadding = 64;
const mainlineRatio = 0.915;
const rowUnit = 96;

interface FullPageTopologyGrid {
  readonly columnCount: number;
  readonly finalRow: number;
  readonly mainlineX: number;
  readonly rowCount: number;
  readonly topPadding: number;
}

interface FullPageTopologyPortal {
  readonly glassSurfaces: readonly FullPageTopologyGlassSurface[];
  readonly leftOuter: number;
  readonly rightOuter: number;
}

interface FullPageTopologyGlassSurface {
  readonly bottom: number;
  readonly left: number;
  readonly rails: readonly [number, number];
  readonly right: number;
  readonly top: number;
}

export function measureFullPageTopologyGrid(
  width: number,
  height: number,
  requestedMainlineX: number = width * mainlineRatio,
  requestedTopPadding: number = edgePadding,
  availableHorizontalDistance?: number,
  requestedRightPadding: number = leftPadding,
): FullPageTopologyGrid | undefined {
  if (width <= 0 || height <= edgePadding + rowUnit) {
    return undefined;
  }

  const mainlineX = Math.min(
    width - requestedRightPadding,
    Math.max(leftPadding, requestedMainlineX),
  );
  const topPadding = Math.min(
    height - edgePadding - rowUnit,
    Math.max(edgePadding, requestedTopPadding),
  );
  const horizontalDistance = availableHorizontalDistance ?? mainlineX - leftPadding;
  const columnCount = Math.max(1, Math.floor(Math.max(horizontalDistance, 0) / columnUnit) + 1);
  const rowCount = Math.max(2, Math.floor((height - topPadding - edgePadding) / rowUnit) + 1);
  return {
    columnCount,
    finalRow: rowCount - 1,
    mainlineX,
    rowCount,
    topPadding,
  };
}

interface FullPageTopologyAnchor {
  readonly mainlineX: number;
  readonly topPadding: number;
}

function resolveTopologyAnchor(artwork: SVGSVGElement, width: number): FullPageTopologyAnchor {
  const anchorSelector = artwork.dataset["mainlineAnchorSelector"];
  if (anchorSelector === undefined || anchorSelector === "") {
    return { mainlineX: width * mainlineRatio, topPadding: edgePadding };
  }

  const anchor = document.querySelector<HTMLElement>(anchorSelector);
  if (anchor === null) {
    return { mainlineX: width * mainlineRatio, topPadding: edgePadding };
  }

  const artworkBounds = artwork.getBoundingClientRect();
  const anchorBounds = anchor.getBoundingClientRect();
  const anchorRight = anchorBounds.right - artworkBounds.left;
  return {
    mainlineX: anchorRight + ((width - anchorRight) * 2) / 3,
    topPadding: anchorBounds.top + anchorBounds.height / 2 - artworkBounds.top,
  };
}

function resolveTopologyPortal(artwork: SVGSVGElement): FullPageTopologyPortal | undefined {
  const frameSelector = artwork.dataset["portalFrameSelector"];
  const surfaceSelector = artwork.dataset["portalSurfaceSelector"];
  if (
    frameSelector === undefined ||
    frameSelector === "" ||
    surfaceSelector === undefined ||
    surfaceSelector === ""
  ) {
    return undefined;
  }

  const frame = document.querySelector<HTMLElement>(frameSelector);
  if (frame === null) {
    return undefined;
  }

  const artworkBounds = artwork.getBoundingClientRect();
  const frameBounds = frame.getBoundingClientRect();
  const leftOuter = frameBounds.left - artworkBounds.left;
  const rightOuter = frameBounds.right - artworkBounds.left;
  const glassSurfaces = [
    ...document.querySelectorAll<HTMLElement>(surfaceSelector),
  ].map((surface): FullPageTopologyGlassSurface => {
    const bounds = surface.getBoundingClientRect();
    const transform = getComputedStyle(surface).transform;
    const transformY = transform === "none" ? 0 : new DOMMatrixReadOnly(transform).m42;
    const top = bounds.top - transformY - artworkBounds.top;
    const bottom = top + bounds.height;
    return {
      bottom,
      left: bounds.left - artworkBounds.left,
      rails: [top + bounds.height * 0.3, top + bounds.height * 0.7],
      right: bounds.right - artworkBounds.left,
      top,
    };
  });
  return { glassSurfaces, leftOuter, rightOuter };
}

function setPortalMask(artwork: SVGSVGElement, portal: FullPageTopologyPortal | undefined): void {
  if (portal === undefined) {
    artwork.style.maskImage = "";
    artwork.style.maskPosition = "";
    artwork.style.maskRepeat = "";
    artwork.style.maskSize = "";
    artwork.removeAttribute("data-topology-portal-active");
    return;
  }

  const maskImages = [
    `linear-gradient(to right, #000 0, #000 ${portal.leftOuter}px, transparent ${portal.leftOuter}px, transparent ${portal.rightOuter}px, #000 ${portal.rightOuter}px, #000 100%)`,
    ...portal.glassSurfaces.map(() => "linear-gradient(#000, #000)"),
  ];
  const maskPositions = [
    "0 0",
    ...portal.glassSurfaces.map((surface) => `${surface.left}px ${surface.top}px`),
  ];
  const maskSizes = [
    "100% 100%",
    ...portal.glassSurfaces.map(
      (surface) => `${surface.right - surface.left}px ${surface.bottom - surface.top}px`,
    ),
  ];
  artwork.style.maskImage = maskImages.join(", ");
  artwork.style.maskPosition = maskPositions.join(", ");
  artwork.style.maskRepeat = "no-repeat";
  artwork.style.maskSize = maskSizes.join(", ");
  artwork.setAttribute("data-topology-portal-active", "");
}

function crossesPortal(
  startX: number,
  endX: number,
  portal: FullPageTopologyPortal | undefined,
): "left-to-right" | "right-to-left" | undefined {
  if (portal === undefined) {
    return undefined;
  }
  if (startX >= portal.rightOuter && endX <= portal.leftOuter) {
    return "right-to-left";
  }
  if (startX <= portal.leftOuter && endX >= portal.rightOuter) {
    return "left-to-right";
  }
  return undefined;
}

function forkSegments(
  sourceX: number,
  laneX: number,
  forkY: number,
  arrivalY: number,
  portal: FullPageTopologyPortal | undefined,
): readonly string[] {
  const crossing = crossesPortal(sourceX, laneX, portal);
  const curveStartX =
    crossing === "right-to-left" && portal !== undefined
      ? portal.leftOuter
      : crossing === "left-to-right" && portal !== undefined
        ? portal.rightOuter
        : sourceX;
  const firstControlX = curveStartX + (laneX - curveStartX) * forkCurveBias;
  const firstControlY = forkY + (arrivalY - forkY) * forkDepartureDrift;
  const secondControlY = forkY + (arrivalY - forkY) * (1 - forkCurveBias);
  const curve = `C ${firstControlX} ${firstControlY} ${laneX} ${secondControlY} ${laneX} ${arrivalY}`;
  if (crossing === undefined || portal === undefined) {
    return [`M ${sourceX} ${forkY}`, curve];
  }
  const exitX = crossing === "right-to-left" ? portal.rightOuter : portal.leftOuter;
  return [
    `M ${sourceX} ${forkY} L ${exitX} ${forkY}`,
    `M ${exitX} ${forkY}`,
    `M ${curveStartX} ${forkY}`,
    `M ${curveStartX} ${forkY}`,
    curve,
  ];
}

function mergeSegments(
  laneX: number,
  sourceX: number,
  approachY: number,
  mergeY: number,
  portal: FullPageTopologyPortal | undefined,
): readonly string[] {
  const crossing = crossesPortal(laneX, sourceX, portal);
  const curveEndX =
    crossing === "left-to-right" && portal !== undefined
      ? portal.leftOuter
      : crossing === "right-to-left" && portal !== undefined
        ? portal.rightOuter
        : sourceX;
  const firstControlY = approachY + (mergeY - approachY) * forkCurveBias;
  const secondControlX = laneX + (curveEndX - laneX) * (1 - forkCurveBias);
  const secondControlY = approachY + (mergeY - approachY) * (1 - forkDepartureDrift);
  const curve = `C ${laneX} ${firstControlY} ${secondControlX} ${secondControlY} ${curveEndX} ${mergeY}`;
  if (crossing === undefined || portal === undefined) {
    return [`L ${laneX} ${approachY}`, curve];
  }
  const entryX = crossing === "left-to-right" ? portal.rightOuter : portal.leftOuter;
  return [
    `L ${laneX} ${approachY}`,
    curve,
    `M ${curveEndX} ${mergeY}`,
    `M ${entryX} ${mergeY}`,
    `M ${entryX} ${mergeY} L ${sourceX} ${mergeY}`,
  ];
}

function routeNumber(path: SVGPathElement, key: string): number | undefined {
  const value = path.dataset[key];
  if (value === undefined || value === "") {
    return undefined;
  }
  return Number(value);
}

export function layoutFullPageTopology(artwork: SVGSVGElement): boolean {
  const width = artwork.clientWidth;
  const height = artwork.clientHeight;
  const designFinalRow = Number(artwork.dataset["designFinalRow"]);
  const anchor = resolveTopologyAnchor(artwork, width);
  const portal = resolveTopologyPortal(artwork);
  const rightGutterWidth = portal === undefined ? leftPadding : width - portal.rightOuter;
  const portalRightPadding =
    portal === undefined ? leftPadding : Math.min(leftPadding, Math.max(8, rightGutterWidth / 2));
  const portalMainlineX =
    portal === undefined
      ? anchor.mainlineX
      : Math.max(anchor.mainlineX, portal.rightOuter + rightGutterWidth / 2);
  const portalHorizontalDistance =
    portal === undefined
      ? undefined
      : Math.max(portalMainlineX - portal.rightOuter, 0) +
        Math.max(portal.leftOuter - leftPadding, 0);
  const grid = measureFullPageTopologyGrid(
    width,
    height,
    portalMainlineX,
    anchor.topPadding,
    portalHorizontalDistance,
    portalRightPadding,
  );
  if (grid === undefined || !Number.isFinite(designFinalRow) || designFinalRow <= 0) {
    return false;
  }

  const xForLane = (lane: number): number => {
    const logicalDistance = Math.min(lane, grid.columnCount - 1) * columnUnit;
    if (portal === undefined) {
      return grid.mainlineX - logicalDistance;
    }
    const rightGutterDistance = Math.max(grid.mainlineX - portal.rightOuter, 0);
    return logicalDistance <= rightGutterDistance
      ? grid.mainlineX - logicalDistance
      : portal.leftOuter - (logicalDistance - rightGutterDistance);
  };
  const resolvedRow = (designRow: number): number =>
    Math.round((designRow / designFinalRow) * grid.finalRow);
  const yForRow = (designRow: number): number => grid.topPadding + resolvedRow(designRow) * rowUnit;
  artwork.dataset["columnCount"] = String(grid.columnCount);
  artwork.dataset["rowCount"] = String(grid.rowCount);
  artwork.dataset["finalRow"] = String(grid.finalRow);
  setPortalMask(artwork, portal);

  for (const routeGroup of artwork.querySelectorAll<SVGGElement>("[data-topology-route-group]")) {
    const lane = Number(routeGroup.dataset["routeLane"]);
    const sourceLane = Number(routeGroup.dataset["routeSourceLane"]);
    routeGroup.style.display =
      lane < grid.columnCount && sourceLane < grid.columnCount ? "" : "none";
  }
  for (const routeNode of artwork.querySelectorAll<SVGGraphicsElement>(
    "[data-topology-route-node]",
  )) {
    const lane = Number(routeNode.dataset["routeLane"]);
    const sourceLane = Number(routeNode.dataset["routeSourceLane"]);
    routeNode.style.display =
      lane < grid.columnCount && sourceLane < grid.columnCount ? "" : "none";
  }

  artwork.setAttribute("viewBox", `0 0 ${width} ${height}`);

  for (const mainline of artwork.querySelectorAll<SVGPathElement>("[data-mainline]")) {
    mainline.setAttribute(
      "d",
      `M ${xForLane(0)} ${yForRow(0)} L ${xForLane(0)} ${yForRow(designFinalRow)}`,
    );
  }

  for (const path of artwork.querySelectorAll<SVGPathElement>("[data-route]")) {
    const sourceLane = routeNumber(path, "sourceLane") ?? 0;
    const lane = routeNumber(path, "lane") ?? 0;
    const forkRow = routeNumber(path, "forkRow") ?? 0;
    const arrivalRow = routeNumber(path, "arrivalRow") ?? forkRow;
    const mergeApproachRow = routeNumber(path, "mergeApproachRow");
    const mergeRow = routeNumber(path, "mergeRow");
    const openEndRow = routeNumber(path, "openEndRow");
    const sourceX = xForLane(sourceLane);
    const laneX = xForLane(lane);
    const forkY = yForRow(forkRow);
    const arrivalY = yForRow(arrivalRow);
    const segments = [...forkSegments(sourceX, laneX, forkY, arrivalY, portal)];

    if (mergeApproachRow !== undefined && mergeRow !== undefined) {
      const approachY = yForRow(mergeApproachRow);
      const mergeY = yForRow(mergeRow);
      segments.push(...mergeSegments(laneX, sourceX, approachY, mergeY, portal));
    } else {
      segments.push(`L ${laneX} ${yForRow(openEndRow ?? designFinalRow)}`);
    }
    path.setAttribute("d", segments.join(" "));
  }

  for (const node of artwork.querySelectorAll<SVGGraphicsElement>("[data-node]")) {
    const lane = Number(node.dataset["lane"]);
    const row = Number(node.dataset["row"]);
    const x = xForLane(lane);
    const y = yForRow(row);
    if (node instanceof SVGCircleElement) {
      node.setAttribute("cx", String(x));
      node.setAttribute("cy", String(y));
    } else {
      node.setAttribute("transform", `translate(${x} ${y})`);
    }
  }
  return true;
}

export function initializeFullPageTopologyLayout(artwork: SVGSVGElement): () => void {
  let lastHeight = 0;
  let lastWidth = 0;
  let pendingFrame: number | undefined;

  const render = (): void => {
    pendingFrame = undefined;
    if (layoutFullPageTopology(artwork)) {
      lastWidth = artwork.clientWidth;
      lastHeight = artwork.clientHeight;
    }
  };
  const schedule = (entries?: readonly ResizeObserverEntry[]): void => {
    const entry = entries?.[0];
    if (
      entry !== undefined &&
      Math.abs(entry.contentRect.width - lastWidth) <= 0.5 &&
      Math.abs(entry.contentRect.height - lastHeight) <= 8
    ) {
      return;
    }
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
