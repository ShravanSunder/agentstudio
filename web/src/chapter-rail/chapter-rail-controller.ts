// One owner for the left chapter rail: measures rail anchors and their
// targets, draws the grid's main lane, row dots and branches, and marks the
// current chapter. It reads page positions and never sets page layout.
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
  type ChapterRailBranchLayout,
  type ChapterRailLayout,
  type ChapterRailRowDot,
  type RailAnchorMeasurement,
  type RailNodeState,
  type RailRect,
} from "./chapter-rail-layout";

/** The rail's container. Its SVG stays empty (invisible) until at least one rail anchor exists. */
export const chapterRailAttribute = "data-chapter-rail";
/** The full-page SVG inside the container. */
export const chapterRailArtworkAttribute = "data-chapter-rail-artwork";
/** `"empty" | "drawn"` on the container once measured. */
export const chapterRailLayoutAttribute = "data-chapter-rail-layout";
/** The main (chapter progress) lane path. */
export const chapterRailLaneAttribute = "data-chapter-rail-lane";
/** `<g data-chapter-rail-row="<rowIndex>">`: the one dot on each grid row. */
export const chapterRailRowAttribute = "data-chapter-rail-row";
/** `<g data-chapter-rail-node="<anchorId>">`: set on the row dot of each rail anchor. */
export const chapterRailNodeAttribute = "data-chapter-rail-node";
/** `<path data-chapter-rail-branch="<anchorId>">`: each branch from an anchor into its glass. */
export const chapterRailBranchAttribute = "data-chapter-rail-branch";
/** `"main" | "peach" | "cyan"` on every row dot and branch: the lane that owns it. */
export const chapterRailAccentAttribute = "data-chapter-rail-accent";
/** `"left" | "top"` on a branch: the target edge it lands on. */
export const chapterRailTargetEdgeAttribute = "data-chapter-rail-target-edge";
/** `"passed" | "current" | "upcoming"` on every row dot and branch. */
export const chapterRailStateAttribute = "data-chapter-rail-state";

const svgNamespace = "http://www.w3.org/2000/svg";
// Node sizes from the retired topology artwork: commit nodes r=4, terminal
// nodes (with their halo) r=7.
const commitNodeRadius = 4;
const terminalNodeRadius = 7;

interface RenderedRowDot {
  readonly signature: string;
  readonly group: SVGGElement;
  readonly circles: readonly SVGCircleElement[];
}

interface RenderedBranch {
  readonly signature: string;
  readonly path: SVGPathElement;
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
  readonly copyBlockRects: ReadonlyMap<string, RailRect>;
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
  const copyBlockRects = new Map<string, RailRect>();
  for (const { id } of anchors) {
    const surface = surfaceElements.get(id);
    const media = mediaElements.get(id);
    targets.set(id, { surface, media });
    if (surface !== undefined) {
      surfaceRects.set(id, measure(surface));
    }
    const anchor = anchorElements.get(id);
    if (media !== undefined) {
      mediaRects.set(id, measure(media));
      if (anchor !== undefined) {
        copyBlockRects.set(id, measure(findCopyBlock(anchor, media)));
      }
    }
  }
  return { anchors, targets, surfaceRects, mediaRects, copyBlockRects };
}

function rowDotSignature(row: ChapterRailRowDot): string {
  return `${row.accent}:${row.anchorId ?? ""}`;
}

function createRowDot(ownerDocument: Document, row: ChapterRailRowDot): RenderedRowDot {
  const group = createSvgElement(ownerDocument, "g");
  group.setAttribute(chapterRailRowAttribute, String(row.rowIndex));
  group.setAttribute(chapterRailAccentAttribute, row.accent);
  const commit = createSvgElement(ownerDocument, "circle");
  commit.setAttribute("class", "chapter-rail-commit");
  commit.setAttribute("r", String(commitNodeRadius));
  const circles = [commit];
  if (row.anchorId !== undefined) {
    group.setAttribute(chapterRailNodeAttribute, row.anchorId);
    const halo = createSvgElement(ownerDocument, "circle");
    halo.setAttribute("class", "chapter-rail-terminal-halo");
    halo.setAttribute("r", String(terminalNodeRadius));
    const terminal = createSvgElement(ownerDocument, "circle");
    terminal.setAttribute("class", "chapter-rail-terminal");
    terminal.setAttribute("r", String(terminalNodeRadius));
    circles.push(halo, terminal);
  }
  group.append(...circles);
  return { signature: rowDotSignature(row), group, circles };
}

function branchSignature(branch: ChapterRailBranchLayout): string {
  return `${branch.anchorId}:${branch.accent}`;
}

function createBranch(ownerDocument: Document, branch: ChapterRailBranchLayout): RenderedBranch {
  const path = createSvgElement(ownerDocument, "path");
  path.setAttribute(chapterRailBranchAttribute, branch.anchorId);
  path.setAttribute(chapterRailAccentAttribute, branch.accent);
  return { signature: branchSignature(branch), path };
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
  const dotLayer = createSvgElement(ownerDocument, "g");
  artwork.replaceChildren(lane, branchLayer, dotLayer);

  const lifecycle = new AbortController();
  let renderedDots: readonly RenderedRowDot[] = [];
  let renderedBranches: readonly RenderedBranch[] = [];
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
      renderedDots = [];
      renderedBranches = [];
      branchLayer.replaceChildren();
      dotLayer.replaceChildren();
      lane.removeAttribute("d");
      return;
    }
    setAttributeIfChanged(lane, "d", layout.lanePath);

    const dotsChanged =
      renderedDots.length !== layout.rows.length ||
      layout.rows.some((row, index) => renderedDots[index]?.signature !== rowDotSignature(row));
    if (dotsChanged) {
      renderedDots = layout.rows.map((row) => createRowDot(ownerDocument, row));
      dotLayer.replaceChildren(...renderedDots.map((dot) => dot.group));
    }
    for (const [index, dot] of renderedDots.entries()) {
      const row = layout.rows[index];
      if (row === undefined) {
        continue;
      }
      for (const circle of dot.circles) {
        setAttributeIfChanged(circle, "cx", String(row.x));
        setAttributeIfChanged(circle, "cy", String(row.y));
      }
    }

    const branchesChanged =
      renderedBranches.length !== layout.branches.length ||
      layout.branches.some(
        (branch, index) => renderedBranches[index]?.signature !== branchSignature(branch),
      );
    if (branchesChanged) {
      renderedBranches = layout.branches.map((branch) => createBranch(ownerDocument, branch));
      branchLayer.replaceChildren(...renderedBranches.map((branch) => branch.path));
    }
    for (const [index, rendered] of renderedBranches.entries()) {
      const branch = layout.branches[index];
      if (branch !== undefined) {
        setAttributeIfChanged(rendered.path, "d", branch.pathData);
        setAttributeIfChanged(rendered.path, chapterRailTargetEdgeAttribute, branch.targetEdge);
      }
    }
  };

  const renderCurrentChapter = (): void => {
    if (currentLayout.kind === "empty") {
      lightTarget(undefined);
      return;
    }
    const layout = currentLayout;
    const readingLineY =
      ownerWindow.innerHeight * railReadingLineRatio - artwork.getBoundingClientRect().top;
    const currentAnchorIndex = selectCurrentRailNodeIndex(
      layout.anchorNodes.map((node) => node.y),
      readingLineY,
    );
    const currentRowIndex =
      currentAnchorIndex === undefined
        ? undefined
        : layout.anchorNodes[currentAnchorIndex]?.rowIndex;
    const anchorIndexById = new Map(
      layout.anchorNodes.map((node, index) => [node.anchorId, index] as const),
    );
    for (const [index, dot] of renderedDots.entries()) {
      const row = layout.rows[index];
      if (row === undefined) {
        continue;
      }
      const anchorIndex =
        row.anchorId === undefined ? undefined : anchorIndexById.get(row.anchorId);
      const state: RailNodeState =
        anchorIndex !== undefined
          ? railNodeStateAt(anchorIndex, currentAnchorIndex)
          : currentRowIndex !== undefined && row.rowIndex < currentRowIndex
            ? "passed"
            : "upcoming";
      setAttributeIfChanged(dot.group, chapterRailStateAttribute, state);
    }
    for (const [index, rendered] of renderedBranches.entries()) {
      const anchorIndex = anchorIndexById.get(layout.branches[index]?.anchorId ?? "");
      setAttributeIfChanged(
        rendered.path,
        chapterRailStateAttribute,
        railNodeStateAt(anchorIndex ?? Number.POSITIVE_INFINITY, currentAnchorIndex),
      );
    }
    const currentAnchor =
      currentAnchorIndex === undefined ? undefined : layout.anchorNodes[currentAnchorIndex];
    const currentBranch = layout.branches.find(
      (branch) => branch.anchorId === currentAnchor?.anchorId,
    );
    const currentTargets =
      currentAnchor === undefined ? undefined : targetsById.get(currentAnchor.anchorId);
    const joinedTarget =
      currentBranch?.targetEdge === "top" ? currentTargets?.media : currentTargets?.surface;
    lightTarget(currentBranch === undefined ? undefined : joinedTarget);
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
        copyBlocks: measurement.copyBlockRects,
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
