// One owner for the left chapter rail: measures rail anchors and their
// targets, draws the lane, dots and branches, and marks the current chapter.
// It reads page positions and never sets page layout.
//
// Relative imports keep this module loadable by Vitest, which has no "@/" alias.
import {
  railAnchorAttribute,
  railCurrentAttribute,
  railMediaTargetAttribute,
  railSurfaceTargetAttribute,
} from "../chapters/chapter-dom-contract";
import {
  layoutChapterRail,
  railNodeStateAt,
  railReadingLineRatio,
  selectCurrentRailNodeIndex,
  type ChapterRailLayout,
  type ChapterRailNodeLayout,
  type RailAnchorMeasurement,
  type RailRect,
} from "./chapter-rail-layout";

/** The rail's container. Its SVG stays empty (invisible) until at least one rail anchor exists. */
export const chapterRailAttribute = "data-chapter-rail";
/** The full-page SVG inside the container. */
export const chapterRailArtworkAttribute = "data-chapter-rail-artwork";
/** `"empty" | "drawn"` on the container once measured. */
export const chapterRailLayoutAttribute = "data-chapter-rail-layout";
/** The vertical lane path. */
export const chapterRailLaneAttribute = "data-chapter-rail-lane";
/** `<g data-chapter-rail-node="<anchorId>">`: one dot per rail anchor. */
export const chapterRailNodeAttribute = "data-chapter-rail-node";
/** `<path data-chapter-rail-branch="<anchorId>">`: one branch per dot that has a target. */
export const chapterRailBranchAttribute = "data-chapter-rail-branch";
/** `"left" | "top"` on a branch: the target edge it lands on. */
export const chapterRailTargetEdgeAttribute = "data-chapter-rail-target-edge";
/** `"passed" | "current" | "upcoming"` on every dot and branch. */
export const chapterRailStateAttribute = "data-chapter-rail-state";

const svgNamespace = "http://www.w3.org/2000/svg";
const nodeRingRadius = 6;
const nodeCoreRadius = 2.75;

interface RenderedRailNode {
  readonly anchorId: string;
  readonly group: SVGGElement;
  readonly ring: SVGCircleElement;
  readonly core: SVGCircleElement;
  readonly branch: SVGPathElement;
}

interface RailTargetElements {
  readonly surface: HTMLElement | undefined;
  readonly media: HTMLElement | undefined;
}

interface RailMeasurement {
  readonly anchors: readonly RailAnchorMeasurement[];
  readonly targets: ReadonlyMap<string, RailTargetElements>;
  readonly surfaceRects: ReadonlyMap<string, RailRect>;
  readonly mediaRects: ReadonlyMap<string, RailRect>;
}

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

function measureRailPage(ownerDocument: Document, artwork: SVGSVGElement): RailMeasurement {
  const origin = artwork.getBoundingClientRect();
  const measure = (element: Element): RailRect => {
    const bounds = element.getBoundingClientRect();
    return {
      left: bounds.left - origin.left,
      top: bounds.top - origin.top,
      width: bounds.width,
      height: bounds.height,
    };
  };
  const anchorElements = elementsById(ownerDocument, railAnchorAttribute);
  const surfaceElements = elementsById(ownerDocument, railSurfaceTargetAttribute);
  const mediaElements = elementsById(ownerDocument, railMediaTargetAttribute);
  const anchors = [...anchorElements].map(([id, element]) => ({ id, rect: measure(element) }));
  const targets = new Map<string, RailTargetElements>();
  const surfaceRects = new Map<string, RailRect>();
  const mediaRects = new Map<string, RailRect>();
  for (const { id } of anchors) {
    const surface = surfaceElements.get(id);
    const media = mediaElements.get(id);
    targets.set(id, { surface, media });
    if (surface !== undefined) {
      surfaceRects.set(id, measure(surface));
    }
    if (media !== undefined) {
      mediaRects.set(id, measure(media));
    }
  }
  return { anchors, targets, surfaceRects, mediaRects };
}

function createRenderedRailNode(ownerDocument: Document, anchorId: string): RenderedRailNode {
  const group = createSvgElement(ownerDocument, "g");
  group.setAttribute(chapterRailNodeAttribute, anchorId);
  const ring = createSvgElement(ownerDocument, "circle");
  ring.setAttribute("class", "chapter-rail-node-ring");
  ring.setAttribute("r", String(nodeRingRadius));
  const core = createSvgElement(ownerDocument, "circle");
  core.setAttribute("class", "chapter-rail-node-core");
  core.setAttribute("r", String(nodeCoreRadius));
  group.append(ring, core);
  const branch = createSvgElement(ownerDocument, "path");
  branch.setAttribute(chapterRailBranchAttribute, anchorId);
  return { anchorId, group, ring, core, branch };
}

function applyRenderedNodeGeometry(rendered: RenderedRailNode, node: ChapterRailNodeLayout): void {
  for (const circle of [rendered.ring, rendered.core]) {
    setAttributeIfChanged(circle, "cx", String(node.x));
    setAttributeIfChanged(circle, "cy", String(node.y));
  }
  if (node.branch === undefined) {
    return;
  }
  setAttributeIfChanged(rendered.branch, "d", node.branch.pathData);
  setAttributeIfChanged(rendered.branch, chapterRailTargetEdgeAttribute, node.branch.targetEdge);
}

export function initializeChapterRail(rail: HTMLElement): () => void {
  const ownerDocument = rail.ownerDocument;
  const ownerWindow = ownerDocument.defaultView;
  const artwork = rail.querySelector<SVGSVGElement>(`[${chapterRailArtworkAttribute}]`);
  if (artwork === null || ownerWindow === null) {
    throw new Error("Chapter rail is missing its artwork or window");
  }

  const lane = createSvgElement(ownerDocument, "path");
  lane.setAttribute(chapterRailLaneAttribute, "");
  const branchLayer = createSvgElement(ownerDocument, "g");
  const nodeLayer = createSvgElement(ownerDocument, "g");
  artwork.replaceChildren(lane, branchLayer, nodeLayer);

  const lifecycle = new AbortController();
  let renderedNodes: readonly RenderedRailNode[] = [];
  let currentLayout: ChapterRailLayout = { kind: "empty" };
  let targetsById: ReadonlyMap<string, RailTargetElements> = new Map();
  let litTarget: HTMLElement | undefined;
  let pendingAnimationFrame: number | undefined;

  const lightTarget = (nextTarget: HTMLElement | undefined): void => {
    if (litTarget === nextTarget) {
      return;
    }
    litTarget?.removeAttribute(railCurrentAttribute);
    nextTarget?.setAttribute(railCurrentAttribute, "");
    litTarget = nextTarget;
  };

  const renderLayout = (layout: ChapterRailLayout): void => {
    currentLayout = layout;
    setAttributeIfChanged(rail, chapterRailLayoutAttribute, layout.kind);
    if (layout.kind === "empty") {
      renderedNodes = [];
      branchLayer.replaceChildren();
      nodeLayer.replaceChildren();
      lane.removeAttribute("d");
      return;
    }
    const anchorIdsChanged =
      renderedNodes.length !== layout.nodes.length ||
      renderedNodes.some((rendered, index) => rendered.anchorId !== layout.nodes[index]?.anchorId);
    if (anchorIdsChanged) {
      renderedNodes = layout.nodes.map((node) =>
        createRenderedRailNode(ownerDocument, node.anchorId),
      );
      nodeLayer.replaceChildren(...renderedNodes.map((rendered) => rendered.group));
    }
    setAttributeIfChanged(lane, "d", layout.lanePath);
    const branchesWithTargets: SVGPathElement[] = [];
    for (const [index, rendered] of renderedNodes.entries()) {
      const node = layout.nodes[index];
      if (node === undefined) {
        continue;
      }
      applyRenderedNodeGeometry(rendered, node);
      if (node.branch !== undefined) {
        branchesWithTargets.push(rendered.branch);
      }
    }
    const branchSetChanged =
      branchLayer.childElementCount !== branchesWithTargets.length ||
      branchesWithTargets.some((branch, index) => branchLayer.children[index] !== branch);
    if (branchSetChanged) {
      branchLayer.replaceChildren(...branchesWithTargets);
    }
  };

  const renderCurrentChapter = (): void => {
    if (currentLayout.kind === "empty") {
      lightTarget(undefined);
      return;
    }
    const readingLineY =
      ownerWindow.innerHeight * railReadingLineRatio - artwork.getBoundingClientRect().top;
    const currentIndex = selectCurrentRailNodeIndex(
      currentLayout.nodes.map((node) => node.y),
      readingLineY,
    );
    for (const [index, rendered] of renderedNodes.entries()) {
      const state = railNodeStateAt(index, currentIndex);
      setAttributeIfChanged(rendered.group, chapterRailStateAttribute, state);
      setAttributeIfChanged(rendered.branch, chapterRailStateAttribute, state);
    }
    const currentNode = currentIndex === undefined ? undefined : currentLayout.nodes[currentIndex];
    const currentTargets =
      currentNode === undefined ? undefined : targetsById.get(currentNode.anchorId);
    const joinedTarget =
      currentNode?.branch?.targetEdge === "top" ? currentTargets?.media : currentTargets?.surface;
    lightTarget(currentNode?.branch === undefined ? undefined : joinedTarget);
  };

  // Glass surfaces lift with a scroll-driven transform, so anchors and targets
  // move without resizing. Every frame re-measures; transforms leave layout
  // clean, so the reads are cheap, and unchanged attributes are not rewritten.
  const renderFrame = (): void => {
    pendingAnimationFrame = undefined;
    const measurement = measureRailPage(ownerDocument, artwork);
    targetsById = measurement.targets;
    renderLayout(
      layoutChapterRail({
        viewportWidth: ownerWindow.innerWidth,
        pageHeight: artwork.getBoundingClientRect().height,
        anchors: measurement.anchors,
        surfaceTargets: measurement.surfaceRects,
        mediaTargets: measurement.mediaRects,
      }),
    );
    renderCurrentChapter();
  };

  const scheduleRender = (): void => {
    if (pendingAnimationFrame !== undefined || lifecycle.signal.aborted) {
      return;
    }
    pendingAnimationFrame = ownerWindow.requestAnimationFrame(renderFrame);
  };

  const pageResizeObserver = new ResizeObserver(scheduleRender);
  pageResizeObserver.observe(ownerDocument.body);
  pageResizeObserver.observe(artwork);
  ownerWindow.addEventListener("scroll", scheduleRender, {
    passive: true,
    signal: lifecycle.signal,
  });
  ownerWindow.addEventListener("resize", scheduleRender, { signal: lifecycle.signal });
  ownerWindow.addEventListener("load", scheduleRender, { signal: lifecycle.signal });
  void ownerDocument.fonts.ready.then(scheduleRender);
  scheduleRender();

  return (): void => {
    lifecycle.abort();
    pageResizeObserver.disconnect();
    if (pendingAnimationFrame !== undefined) {
      ownerWindow.cancelAnimationFrame(pendingAnimationFrame);
      pendingAnimationFrame = undefined;
    }
    lightTarget(undefined);
  };
}
