const baseCanvasWidth = 540;
const baseCanvasHeight = 2384;

function scaledDatasetValue(
  element: SVGPathElement,
  key:
    | "topologySegmentEndX"
    | "topologySegmentEndY"
    | "topologySegmentStartX"
    | "topologySegmentStartY",
  scale: number,
): number {
  return Number(element.dataset[key]) * scale;
}

export function layoutWorktreeTopology(artwork: SVGSVGElement): boolean {
  const width = artwork.clientWidth;
  const height = artwork.clientHeight;
  if (width <= 0 || height <= 0) {
    return false;
  }

  const horizontalScale = width / baseCanvasWidth;
  const verticalScale = height / baseCanvasHeight;
  const rowHeight = 84 * verticalScale;
  const firstRowY = 100 * verticalScale;
  const finalRowY = 2284 * verticalScale;
  const mainlineX = 240 * horizontalScale;

  artwork.setAttribute("viewBox", `0 0 ${width} ${height}`);
  artwork.dataset["topologyProgressStartY"] = String(firstRowY);
  artwork.dataset["topologyProgressEndY"] = String(finalRowY);

  for (const path of artwork.querySelectorAll<SVGPathElement>(".topology-primary path")) {
    path.setAttribute("d", `M ${mainlineX} ${firstRowY} L ${mainlineX} ${finalRowY}`);
  }

  for (const path of artwork.querySelectorAll<SVGPathElement>("[data-topology-segment-kind]")) {
    const kind = path.dataset["topologySegmentKind"];
    const startX = scaledDatasetValue(path, "topologySegmentStartX", horizontalScale);
    const startY = scaledDatasetValue(path, "topologySegmentStartY", verticalScale);
    const endX = scaledDatasetValue(path, "topologySegmentEndX", horizontalScale);
    const endY = scaledDatasetValue(path, "topologySegmentEndY", verticalScale);
    const middleX = startX + (endX - startX) / 2;

    if (kind === "fork") {
      path.setAttribute(
        "d",
        `M ${startX} ${startY} C ${middleX} ${startY} ${endX} ${endY - rowHeight / 2} ${endX} ${endY}`,
      );
    } else if (kind === "merge") {
      path.setAttribute(
        "d",
        `M ${startX} ${startY} C ${startX} ${startY + rowHeight / 2} ${middleX} ${endY} ${endX} ${endY}`,
      );
    } else {
      path.setAttribute("d", `M ${startX} ${startY} L ${endX} ${endY}`);
    }
  }

  for (const node of artwork.querySelectorAll<SVGGraphicsElement>("[data-topology-node-row]")) {
    const lane = Number(node.dataset["topologyNodeLane"]);
    const row = Number(node.dataset["topologyNodeRow"]);
    const x = (240 + lane * 60) * horizontalScale;
    const y = (100 + row * 84) * verticalScale;
    node.setAttribute("transform", `translate(${x} ${y})`);
  }

  return true;
}
