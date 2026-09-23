import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import {
  chapterRailPhoneBreakpointWidth,
  layoutChapterRail,
  railTargetCornerInset,
  railNodeStateAt,
  selectCurrentRailNodeIndex,
  type ChapterRailLayoutProps,
  type RailRect,
} from "../src/chapter-rail/chapter-rail-layout";

function rect(left: number, top: number, width: number, height: number): RailRect {
  return { left, top, width, height };
}

function wideChapterPage(): ChapterRailLayoutProps {
  return {
    viewportWidth: 1280,
    pageHeight: 3000,
    anchors: [
      { id: "hero", rect: rect(300, 150, 400, 16) },
      { id: "many-agents", rect: rect(160, 1100, 200, 16) },
    ],
    surfaceTargets: new Map([
      ["hero", rect(240, 520, 960, 600)],
      ["many-agents", rect(120, 1060, 1040, 640)],
    ]),
    mediaTargets: new Map([
      ["hero", rect(240, 520, 960, 600)],
      ["many-agents", rect(520, 1300, 600, 380)],
    ]),
    copyBlocks: new Map(),
  };
}

interface PathSegmentBounds {
  readonly command: string;
  readonly left: number;
  readonly right: number;
  readonly top: number;
  readonly bottom: number;
}

/** Each drawn segment's bounding box. A quarter-circle elbow lies within its endpoints' box. */
function pathSegmentBounds(pathData: string): readonly PathSegmentBounds[] {
  const tokens = pathData.trim().split(/[\s,]+/u);
  const segments: PathSegmentBounds[] = [];
  let current = { x: 0, y: 0 };
  let index = 0;
  while (index < tokens.length) {
    const command = tokens[index] ?? "";
    const argumentCount = command === "A" ? 7 : 2;
    const values = tokens.slice(index + 1, index + 1 + argumentCount).map(Number);
    const next = { x: values.at(-2) ?? Number.NaN, y: values.at(-1) ?? Number.NaN };
    if (command !== "M") {
      segments.push({
        command,
        left: Math.min(current.x, next.x),
        right: Math.max(current.x, next.x),
        top: Math.min(current.y, next.y),
        bottom: Math.max(current.y, next.y),
      });
    }
    current = next;
    index += 1 + argumentCount;
  }
  return segments;
}

function intersects(segment: PathSegmentBounds, area: RailRect): boolean {
  return (
    segment.right > area.left &&
    segment.left < area.left + area.width &&
    segment.bottom > area.top &&
    segment.top < area.top + area.height
  );
}

function endPoint(pathData: string): { readonly x: number; readonly y: number } {
  const coordinates = pathData
    .trim()
    .split(/[\s,]+/u)
    .slice(-2)
    .map(Number);
  const [x, y] = coordinates;
  if (x === undefined || y === undefined) {
    throw new Error(`Path has no end point: ${pathData}`);
  }
  return { x, y };
}

describe("layoutChapterRail", () => {
  it("draws nothing when the page has no rail anchors", () => {
    // Arrange
    const props = { ...wideChapterPage(), anchors: [] };

    // Act
    const layout = layoutChapterRail(props);

    // Assert
    expect(layout.kind).toBe("empty");
  });

  it("centers one node per anchor on that anchor, on one lane inside the left gutter", () => {
    // Arrange
    const props = wideChapterPage();

    // Act
    const layout = layoutChapterRail(props);

    // Assert
    if (layout.kind !== "drawn") {
      throw new Error("Expected a drawn rail");
    }
    expect(layout.nodes.map((node) => node.anchorId)).toEqual(["hero", "many-agents"]);
    expect(layout.nodes.map((node) => node.y)).toEqual([158, 1108]);
    expect(new Set(layout.nodes.map((node) => node.x))).toEqual(new Set([layout.railX]));
    expect(layout.railX).toBeGreaterThan(0);
    expect(layout.railX).toBeLessThan(120);
  });

  it("joins each wide branch to its surface target's left edge", () => {
    // Arrange
    const props = wideChapterPage();

    // Act
    const layout = layoutChapterRail(props);

    // Assert
    if (layout.kind !== "drawn") {
      throw new Error("Expected a drawn rail");
    }
    const [heroNode, chapterNode] = layout.nodes;
    // The chapter glass spans its eyebrow, so the branch runs straight across.
    expect(chapterNode?.branch?.targetEdge).toBe("left");
    expect(chapterNode?.branch?.end).toEqual({ x: 120, y: 1108 });
    expect(chapterNode?.branch?.pathData.match(/A/gu)).toBeNull();
    // The hero frame sits below its eyebrow, so the branch forks, runs parallel,
    // and turns into the frame's left edge.
    expect(heroNode?.branch?.targetEdge).toBe("left");
    expect(heroNode?.branch?.end.x).toBe(240);
    expect(heroNode?.branch?.end.y).toBeGreaterThan(520);
    expect(heroNode?.branch?.end.y).toBeLessThan(1120);
    expect(endPoint(heroNode?.branch?.pathData ?? "")).toEqual(heroNode?.branch?.end);
  });

  it("drops each phone branch into its media target's top edge in line with the chapter text", () => {
    // Arrange
    const props: ChapterRailLayoutProps = {
      viewportWidth: 390,
      pageHeight: 4000,
      anchors: [{ id: "many-agents", rect: rect(48, 900, 200, 16) }],
      surfaceTargets: new Map([["many-agents", rect(16, 880, 358, 900)]]),
      mediaTargets: new Map([["many-agents", rect(16, 1040, 358, 220)]]),
      copyBlocks: new Map([["many-agents", rect(48, 900, 320, 100)]]),
    };

    // Act
    const layout = layoutChapterRail(props);

    // Assert
    if (layout.kind !== "drawn") {
      throw new Error("Expected a drawn rail");
    }
    const branch = layout.nodes[0]?.branch;
    expect(branch?.targetEdge).toBe("top");
    expect(branch?.end).toEqual({ x: 48, y: 1040 });
    expect(endPoint(branch?.pathData ?? "")).toEqual(branch?.end);
  });

  it("routes each phone branch around the chapter copy, never through it", () => {
    // Arrange: the eyebrow and title sit beside the rail; the media stage
    // starts below the title, with a gap between them.
    const eyebrow = rect(40, 900, 90, 16);
    const copyBlock = rect(40, 900, 330, 72);
    const copyBottom = copyBlock.top + copyBlock.height;
    const media = rect(40, 996, 330, 220);
    const props: ChapterRailLayoutProps = {
      viewportWidth: 390,
      pageHeight: 4000,
      anchors: [{ id: "many-agents", rect: eyebrow }],
      surfaceTargets: new Map([["many-agents", rect(40, 900, 330, 600)]]),
      mediaTargets: new Map([["many-agents", media]]),
      copyBlocks: new Map([["many-agents", copyBlock]]),
    };

    // Act
    const layout = layoutChapterRail(props);

    // Assert
    if (layout.kind !== "drawn") {
      throw new Error("Expected a drawn rail");
    }
    const branch = layout.nodes[0]?.branch;
    expect(branch?.end).toEqual({ x: media.left + railTargetCornerInset, y: media.top });
    const segments = pathSegmentBounds(branch?.pathData ?? "");
    for (const segment of segments) {
      expect(intersects(segment, eyebrow)).toBe(false);
      expect(intersects(segment, copyBlock)).toBe(false);
    }
    // Fork down a parallel lane, turn right in the gap, then drop in: three elbows.
    expect(branch?.pathData.match(/A/gu)).toHaveLength(3);
    const crossingRun = segments.findLast(
      (segment) =>
        segment.command === "L" && segment.top === segment.bottom && segment.left < segment.right,
    );
    expect(crossingRun?.top).toBeGreaterThan(copyBottom);
    expect(crossingRun?.top).toBeLessThan(media.top);
    expect(crossingRun?.right).toBeGreaterThan(copyBlock.left);
  });

  it("joins a glass straight across whenever the dot clears its rounded corner", () => {
    // Arrange: the eyebrow sits just inside the glass's top corner radius.
    const glassTop = 1100;
    const props: ChapterRailLayoutProps = {
      ...wideChapterPage(),
      anchors: [{ id: "many-agents", rect: rect(160, glassTop + railTargetCornerInset, 200, 16) }],
      surfaceTargets: new Map([["many-agents", rect(120, glassTop, 1040, 640)]]),
    };

    // Act
    const layout = layoutChapterRail(props);

    // Assert
    if (layout.kind !== "drawn") {
      throw new Error("Expected a drawn rail");
    }
    const node = layout.nodes[0];
    expect(node?.branch?.end).toEqual({ x: 120, y: node?.y });
    expect(node?.branch?.pathData.match(/A/gu)).toBeNull();
  });

  it("keeps the phone drop clear of the media target's rounded corner", () => {
    // Arrange
    const mediaLeft = 40;
    const props: ChapterRailLayoutProps = {
      viewportWidth: 390,
      pageHeight: 4000,
      anchors: [{ id: "many-agents", rect: rect(44, 900, 200, 16) }],
      surfaceTargets: new Map([["many-agents", rect(mediaLeft, 880, 332, 900)]]),
      mediaTargets: new Map([["many-agents", rect(mediaLeft, 1040, 332, 220)]]),
      copyBlocks: new Map(),
    };

    // Act
    const layout = layoutChapterRail(props);

    // Assert
    if (layout.kind !== "drawn") {
      throw new Error("Expected a drawn rail");
    }
    expect(layout.nodes[0]?.branch?.end).toEqual({
      x: mediaLeft + railTargetCornerInset,
      y: 1040,
    });
  });

  it("switches from left-edge to top-edge branches at the site's phone breakpoint", () => {
    // Arrange
    const base = wideChapterPage();

    // Act
    const atBreakpoint = layoutChapterRail({
      ...base,
      viewportWidth: chapterRailPhoneBreakpointWidth,
    });
    const belowBreakpoint = layoutChapterRail({
      ...base,
      viewportWidth: chapterRailPhoneBreakpointWidth - 1,
    });

    // Assert
    if (atBreakpoint.kind !== "drawn" || belowBreakpoint.kind !== "drawn") {
      throw new Error("Expected drawn rails");
    }
    expect(atBreakpoint.nodes[1]?.branch?.targetEdge).toBe("left");
    expect(belowBreakpoint.nodes[1]?.branch?.targetEdge).toBe("top");
  });

  it("keeps a node without a matching target and gives it no branch", () => {
    // Arrange
    const props: ChapterRailLayoutProps = {
      ...wideChapterPage(),
      anchors: [{ id: "review", rect: rect(160, 2000, 200, 16) }],
    };

    // Act
    const layout = layoutChapterRail(props);

    // Assert
    if (layout.kind !== "drawn") {
      throw new Error("Expected a drawn rail");
    }
    expect(layout.nodes).toHaveLength(1);
    expect(layout.nodes[0]?.branch).toBeUndefined();
  });

  it("matches the phone breakpoint token that the page layout uses", () => {
    // Arrange
    const globalStylesheet = readFileSync(
      new URL("../src/styles/global.css", import.meta.url),
      "utf8",
    );

    // Act
    const phoneBreakpointRem = Number(
      /--breakpoint-phone:\s*([\d.]+)rem/u.exec(globalStylesheet)?.[1],
    );

    // Assert
    expect(phoneBreakpointRem * 16).toBe(chapterRailPhoneBreakpointWidth);
  });
});

describe("selectCurrentRailNodeIndex", () => {
  it("chooses the last node at or above the reading line", () => {
    // Arrange
    const nodeYs = [150, 1100, 2100];

    // Act / Assert
    expect(selectCurrentRailNodeIndex(nodeYs, 360)).toBe(0);
    expect(selectCurrentRailNodeIndex(nodeYs, 1100)).toBe(1);
    expect(selectCurrentRailNodeIndex(nodeYs, 2099)).toBe(1);
    expect(selectCurrentRailNodeIndex(nodeYs, 5000)).toBe(2);
  });

  it("has no current node before the first anchor reaches the reading line", () => {
    // Arrange / Act / Assert
    expect(selectCurrentRailNodeIndex([400, 1100], 360)).toBeUndefined();
    expect(selectCurrentRailNodeIndex([], 360)).toBeUndefined();
  });
});

describe("railNodeStateAt", () => {
  it("marks earlier nodes passed, the current node current, and later nodes upcoming", () => {
    // Arrange / Act / Assert
    expect([0, 1, 2].map((index) => railNodeStateAt(index, 1))).toEqual([
      "passed",
      "current",
      "upcoming",
    ]);
    expect([0, 1].map((index) => railNodeStateAt(index, undefined))).toEqual([
      "upcoming",
      "upcoming",
    ]);
  });
});
