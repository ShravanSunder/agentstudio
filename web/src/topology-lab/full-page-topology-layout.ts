// Measures the chapter DOM contract hooks, composes the topology, and writes it
// into the artwork: the mainline, one group per route (clearance + core path),
// and one node per row. Rendering is keyed so unchanged frames rewrite nothing.
//
// Relative imports keep this module loadable by Vitest, which has no "@/" alias.
import {
  railAnchorAttribute,
  railMediaTargetAttribute,
  railSurfaceTargetAttribute,
} from "../chapters/chapter-dom-contract";
import {
  composeFullPageTopology,
  type TopologyAnchorMeasurement,
  type TopologyComposition,
  type TopologyRect,
  type TopologyRoute,
  type TopologyRowDot,
} from "./full-page-topology-composition";

const svgNamespace = "http://www.w3.org/2000/svg";
// Node sizes from the retired artwork: commit nodes r=4, terminal nodes r=7.
const commitNodeRadius = 4;
const terminalNodeRadius = 7;

/** `<g data-topology-chapter-node="<anchorId>">`: the mainline dot level with each chapter anchor. */
export const topologyChapterNodeAttribute = "data-topology-chapter-node";
/** The primary-blue node where a port meets its target edge. */
export const topologyPortNodeAttribute = "data-topology-port-node";
/** `"left" | "top"` on a chapter node: the target edge its branch enters (which target lights). */
export const topologyChapterTargetEdgeAttribute = "data-topology-target-edge";

function createSvgElement<TTagName extends keyof SVGElementTagNameMap>(
  ownerDocument: Document,
  tagName: TTagName,
): SVGElementTagNameMap[TTagName] {
  return ownerDocument.createElementNS(svgNamespace, tagName);
}

function setAttributeIfChanged(element: Element, name: string, value: string): void {
  if (element.getAttribute(name) !== value) {
    element.setAttribute(name, value);
  }
}

/**
 * The first rendered element per non-empty id wins, so a duplicated id cannot
 * draw two branches and a `display: none` responsive variant cannot claim one.
 */
function elementsById(ownerDocument: Document, attribute: string): Map<string, HTMLElement> {
  const elements = new Map<string, HTMLElement>();
  for (const element of ownerDocument.querySelectorAll<HTMLElement>(`[${attribute}]`)) {
    const id = element.getAttribute(attribute)?.trim() ?? "";
    if (id !== "" && !elements.has(id) && element.getClientRects().length > 0) {
      elements.set(id, element);
    }
  }
  return elements;
}

/**
 * The anchor's copy block: the outermost rendered ancestor of the anchor that
 * does not contain the media target and ends above it (the chapter header or
 * the hero copy column). Boxless `display: contents` wrappers are skipped, and
 * the anchor itself is the fallback.
 */
function findCopyBlock(anchor: HTMLElement, media: HTMLElement): Element {
  const mediaTop = media.getBoundingClientRect().top;
  let copyBlock: Element = anchor;
  for (
    let ancestor = anchor.parentElement;
    ancestor !== null && !ancestor.contains(media);
    ancestor = ancestor.parentElement
  ) {
    if (
      ancestor.getClientRects().length > 0 &&
      ancestor.getBoundingClientRect().bottom <= mediaTop + 0.5
    ) {
      copyBlock = ancestor;
    }
  }
  return copyBlock;
}

function measureAnchors(artwork: SVGSVGElement): readonly TopologyAnchorMeasurement[] {
  const ownerDocument = artwork.ownerDocument;
  const origin = artwork.getBoundingClientRect();
  const measure = (element: Element): TopologyRect => {
    const bounds = element.getBoundingClientRect();
    return {
      left: bounds.left - origin.left,
      top: bounds.top - origin.top,
      width: bounds.width,
      height: bounds.height,
    };
  };
  const surfaces = elementsById(ownerDocument, railSurfaceTargetAttribute);
  const medias = elementsById(ownerDocument, railMediaTargetAttribute);
  return [...elementsById(ownerDocument, railAnchorAttribute)].map(([id, anchor]) => {
    const surface = surfaces.get(id);
    const media = medias.get(id);
    return {
      id,
      rect: measure(anchor),
      surface: surface === undefined ? undefined : measure(surface),
      media: media === undefined ? undefined : measure(media),
      copyBlock: media === undefined ? undefined : measure(findCopyBlock(anchor, media)),
    };
  });
}

function progressForY(composition: TopologyComposition, y: number): number {
  const startY = composition.rowYs[0] ?? 0;
  const endY = composition.rowYs.at(-1) ?? startY;
  return endY <= startY ? 1 : Math.min(Math.max((y - startY) / (endY - startY), 0), 1);
}

function createRouteGroup(ownerDocument: Document, route: TopologyRoute): SVGGElement {
  const group = createSvgElement(ownerDocument, "g");
  group.setAttribute("class", `topology-route accent-${route.accent}`);
  group.setAttribute("data-topology-route-group", "");
  group.setAttribute("data-route-id", route.id);
  group.setAttribute("data-route-kind", route.kind);
  group.setAttribute("data-end-kind", "merge");
  group.setAttribute("data-route-column", String(route.column));
  group.setAttribute("data-route-parent-column", String(route.parentColumn));
  if (route.anchorId !== undefined) {
    group.setAttribute("data-route-anchor", route.anchorId);
  }
  for (const role of ["clearance", "core"] as const) {
    const path = createSvgElement(ownerDocument, "path");
    path.setAttribute(
      "class",
      `${role === "clearance" ? "topology-clearance" : "topology-line"} topology-reveal-path`,
    );
    path.setAttribute("data-route", "");
    path.setAttribute("data-topology-path-role", role);
    group.append(path);
  }
  if (route.portNode !== undefined) {
    const port = createSvgElement(ownerDocument, "circle");
    port.setAttribute("class", "node-port");
    port.setAttribute(topologyPortNodeAttribute, "");
    port.setAttribute("r", String(commitNodeRadius));
    group.append(port);
  }
  return group;
}

function rowDotSignature(dot: TopologyRowDot): string {
  return `${dot.kind}:${dot.accent}:${dot.ownerId}:${dot.anchorId ?? ""}`;
}

function createRowNode(ownerDocument: Document, dot: TopologyRowDot): SVGGElement {
  const group = createSvgElement(ownerDocument, "g");
  const terminal = dot.kind === "chapter" || dot.kind === "end";
  group.setAttribute("class", `${terminal ? "node-terminal-group " : ""}accent-${dot.accent}`);
  group.setAttribute("data-node", "");
  group.setAttribute("data-node-kind", dot.kind);
  if (dot.anchorId !== undefined) {
    group.setAttribute(topologyChapterNodeAttribute, dot.anchorId);
  }
  const commit = createSvgElement(ownerDocument, "circle");
  commit.setAttribute("class", "node-commit");
  commit.setAttribute("r", String(commitNodeRadius));
  group.append(commit);
  if (terminal) {
    const halo = createSvgElement(ownerDocument, "circle");
    halo.setAttribute("class", "node-terminal-halo");
    halo.setAttribute("r", String(terminalNodeRadius));
    const disc = createSvgElement(ownerDocument, "circle");
    disc.setAttribute("class", "node-terminal");
    disc.setAttribute("r", String(terminalNodeRadius));
    group.append(halo, disc);
  }
  return group;
}

function hideTopology(artwork: SVGSVGElement, reason: string): boolean {
  artwork.style.visibility = "hidden";
  artwork.dataset["topologyHiddenReason"] = reason;
  return true;
}

/** Lays the topology out from the current page. Returns false when the artwork has no size yet. */
export function layoutFullPageTopology(artwork: SVGSVGElement): boolean {
  if (artwork.clientWidth <= 0 || artwork.clientHeight <= 0) {
    return false;
  }
  const ownerDocument = artwork.ownerDocument;
  const ownerWindow = ownerDocument.defaultView;
  const mainline = artwork.querySelector<SVGPathElement>("[data-mainline]");
  const routeLayer = artwork.querySelector<SVGGElement>("[data-topology-routes]");
  const nodeLayer = artwork.querySelector<SVGGElement>("[data-topology-row-nodes]");
  if (ownerWindow === null || mainline === null || routeLayer === null || nodeLayer === null) {
    return hideTopology(artwork, "incomplete-artwork");
  }
  const composition = composeFullPageTopology({
    viewportWidth: ownerWindow.innerWidth,
    height: artwork.clientHeight,
    anchors: measureAnchors(artwork),
  });
  if (composition === undefined) {
    routeLayer.replaceChildren();
    nodeLayer.replaceChildren();
    mainline.removeAttribute("d");
    return hideTopology(artwork, "no-rail-anchors");
  }

  artwork.style.visibility = "visible";
  delete artwork.dataset["topologyHiddenReason"];
  setAttributeIfChanged(artwork, "viewBox", `0 0 ${artwork.clientWidth} ${artwork.clientHeight}`);
  setAttributeIfChanged(artwork, "data-column-unit", String(composition.columnUnit));
  setAttributeIfChanged(artwork, "data-lane-count", String(composition.laneXs.length));
  setAttributeIfChanged(artwork, "data-mainline-x", String(composition.mainlineX));
  setAttributeIfChanged(artwork, "data-row-count", String(composition.rows.length));
  setAttributeIfChanged(artwork, "data-topology-start-y", String(composition.rowYs[0] ?? 0));
  setAttributeIfChanged(artwork, "data-topology-end-y", String(composition.rowYs.at(-1) ?? 0));
  for (const revealRect of artwork.querySelectorAll<SVGRectElement>(
    "[data-topology-reveal-solid], [data-topology-reveal-fade]",
  )) {
    setAttributeIfChanged(revealRect, "width", String(artwork.clientWidth));
  }

  setAttributeIfChanged(mainline, "d", composition.mainlinePath);
  setAttributeIfChanged(mainline, "data-topology-path-start", "0");
  setAttributeIfChanged(mainline, "data-topology-path-end", "1");

  const routeGroups = [...routeLayer.children].filter(
    (child): child is SVGGElement => child instanceof SVGGElement,
  );
  const routesChanged =
    routeGroups.length !== composition.routes.length ||
    composition.routes.some(
      (route, index) =>
        routeGroups[index]?.dataset["routeId"] !== route.id ||
        !routeGroups[index]?.classList.contains(`accent-${route.accent}`),
    );
  const renderedRouteGroups = routesChanged
    ? composition.routes.map((route) => createRouteGroup(ownerDocument, route))
    : routeGroups;
  if (routesChanged) {
    routeLayer.replaceChildren(...renderedRouteGroups);
  }
  for (const [index, route] of composition.routes.entries()) {
    const group = renderedRouteGroups[index];
    if (group === undefined) {
      continue;
    }
    for (const path of group.querySelectorAll<SVGPathElement>("[data-route]")) {
      setAttributeIfChanged(path, "d", route.pathData);
      setAttributeIfChanged(
        path,
        "data-topology-path-start",
        String(progressForY(composition, route.startY)),
      );
      setAttributeIfChanged(
        path,
        "data-topology-path-end",
        String(progressForY(composition, route.endY)),
      );
    }
    if (route.targetEdge !== undefined) {
      setAttributeIfChanged(group, "data-target-edge", route.targetEdge);
    }
    const port = group.querySelector(`[${topologyPortNodeAttribute}]`);
    if (port !== null && route.portNode !== undefined) {
      setAttributeIfChanged(port, "cx", String(route.portNode.x));
      setAttributeIfChanged(port, "cy", String(route.portNode.y));
    }
  }

  const rowNodes = [...nodeLayer.children].filter(
    (child): child is SVGGElement => child instanceof SVGGElement,
  );
  const nodesChanged =
    rowNodes.length !== composition.rows.length ||
    composition.rows.some(
      (dot, index) => rowNodes[index]?.dataset["nodeSignature"] !== rowDotSignature(dot),
    );
  const renderedRowNodes = nodesChanged
    ? composition.rows.map((dot) => {
        const node = createRowNode(ownerDocument, dot);
        node.dataset["nodeSignature"] = rowDotSignature(dot);
        return node;
      })
    : rowNodes;
  if (nodesChanged) {
    nodeLayer.replaceChildren(...renderedRowNodes);
  }
  const attachEdgeByAnchor = new Map(
    composition.routes.flatMap((route) =>
      route.anchorId === undefined || route.targetEdge === undefined
        ? []
        : [[route.anchorId, route.targetEdge] as const],
    ),
  );
  for (const [index, dot] of composition.rows.entries()) {
    const node = renderedRowNodes[index];
    if (node === undefined) {
      continue;
    }
    for (const circle of node.querySelectorAll("circle")) {
      setAttributeIfChanged(circle, "cx", String(dot.x));
      setAttributeIfChanged(circle, "cy", String(dot.y));
    }
    setAttributeIfChanged(node, "data-node-owner", dot.ownerId);
    setAttributeIfChanged(node, "data-resolved-row", String(dot.row));
    setAttributeIfChanged(
      node,
      "data-topology-node-progress",
      String(progressForY(composition, dot.y)),
    );
    if (dot.anchorId !== undefined) {
      const edge = attachEdgeByAnchor.get(dot.anchorId);
      if (edge === undefined) {
        node.removeAttribute(topologyChapterTargetEdgeAttribute);
      } else {
        setAttributeIfChanged(node, topologyChapterTargetEdgeAttribute, edge);
      }
    }
  }
  return true;
}
