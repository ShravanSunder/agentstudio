import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import {
  railBendHorizontalControlRatio,
  railBendHorizontalLiftRatio,
  railBendVerticalControlRatio,
} from "../src/chapter-rail/chapter-rail-bend-path";
import { phoneRailRowUnit, railRowUnit } from "../src/chapter-rail/chapter-rail-grid";
import {
  chapterRailPhoneBreakpointWidth,
  layoutChapterRail,
  railNodeStateAt,
  railTargetCornerInset,
  selectCurrentRailNodeIndex,
  type ChapterRailLayout,
  type ChapterRailLayoutProps,
  type RailPoint,
  type RailRect,
} from "../src/chapter-rail/chapter-rail-layout";

type DrawnRailLayout = Extract<ChapterRailLayout, { readonly kind: "drawn" }>;

function rect(left: number, top: number, width: number, height: number): RailRect {
  return { left, top, width, height };
}

function drawn(layout: ChapterRailLayout): DrawnRailLayout {
  if (layout.kind !== "drawn") {
    throw new Error("Expected a drawn rail");
  }
  return layout;
}

interface ChapterFixture {
  readonly id: string;
  readonly anchor: RailRect;
  readonly surface: RailRect;
  readonly media: RailRect;
  readonly copy: RailRect;
}

interface RailPageFixture {
  readonly name: string;
  readonly props: ChapterRailLayoutProps;
  readonly textRects: readonly RailRect[];
  readonly rowUnit: number;
  readonly columnCount: number;
  readonly heroAccents: readonly string[];
}

function railPageFixture(props: {
  readonly name: string;
  readonly viewportWidth: number;
  readonly pageHeight: number;
  readonly chapters: readonly ChapterFixture[];
  readonly rowUnit: number;
  readonly columnCount: number;
  readonly heroAccents: readonly string[];
}): RailPageFixture {
  return {
    name: props.name,
    props: {
      viewportWidth: props.viewportWidth,
      pageHeight: props.pageHeight,
      anchors: props.chapters.map((chapter) => ({ id: chapter.id, rect: chapter.anchor })),
      surfaceTargets: new Map(props.chapters.map((chapter) => [chapter.id, chapter.surface])),
      mediaTargets: new Map(props.chapters.map((chapter) => [chapter.id, chapter.media])),
      copyBlocks: new Map(props.chapters.map((chapter) => [chapter.id, chapter.copy])),
    },
    textRects: props.chapters.flatMap((chapter) => [chapter.anchor, chapter.copy]),
    rowUnit: props.rowUnit,
    columnCount: props.columnCount,
    heroAccents: props.heroAccents,
  };
}

const chapterIds = ["many-agents", "context-with-task", "find-and-focus", "review", "come-back"];

// Measured from the built home page (anchor tops, content lefts, page height).
const wideFixture = railPageFixture({
  name: "wide 1920",
  viewportWidth: 1920,
  pageHeight: 5602,
  rowUnit: railRowUnit,
  columnCount: 3,
  heroAccents: ["peach", "cyan"],
  chapters: [
    {
      id: "hero",
      anchor: rect(433, 113, 500, 12),
      surface: rect(383, 541, 1234, 780),
      media: rect(383, 541, 1234, 780),
      copy: rect(433, 113, 1000, 380),
    },
    ...[1451, 2181, 2911, 3572, 4241].map((anchorTop, index) => ({
      id: chapterIds[index] ?? "chapter",
      anchor: rect(437, anchorTop, 90, 12),
      surface: rect(383, anchorTop - 54, 1154, 620),
      media: rect(819, anchorTop - 40, 700, 440),
      copy: rect(437, anchorTop, 340, 120),
    })),
  ],
});

const laptopFixture = railPageFixture({
  name: "laptop 1280",
  viewportWidth: 1280,
  pageHeight: 4869,
  rowUnit: railRowUnit,
  columnCount: 2,
  heroAccents: ["peach"],
  chapters: [
    {
      id: "hero",
      anchor: rect(149, 98, 400, 12),
      surface: rect(116, 455, 1106, 690),
      media: rect(116, 455, 1106, 690),
      copy: rect(149, 98, 1000, 320),
    },
    ...[1258, 1853, 2449, 3034, 3620].map((anchorTop, index) => ({
      id: chapterIds[index] ?? "chapter",
      anchor: rect(160, anchorTop, 90, 12),
      surface: rect(116, anchorTop - 44, 1106, 520),
      media: rect(507, anchorTop - 36, 700, 440),
      copy: rect(160, anchorTop, 300, 110),
    })),
  ],
});

const phoneFixture = railPageFixture({
  name: "phone 390",
  viewportWidth: 390,
  pageHeight: 4698,
  rowUnit: phoneRailRowUnit,
  columnCount: 2,
  heroAccents: ["peach"],
  chapters: [
    {
      id: "hero",
      anchor: rect(40, 91, 300, 12),
      surface: rect(40, 560, 332, 420),
      media: rect(40, 560, 332, 420),
      copy: rect(40, 91, 332, 430),
    },
    ...[1027, 1602, 2205, 2734, 3421].map((anchorTop, index) => ({
      id: chapterIds[index] ?? "chapter",
      anchor: rect(40, anchorTop, 90, 12),
      surface: rect(40, anchorTop - 40, 332, 560),
      media: rect(40, anchorTop + 100, 332, 220),
      copy: rect(40, anchorTop, 332, 76),
    })),
  ],
});

interface PathCommand {
  readonly command: string;
  readonly from: RailPoint;
  readonly points: readonly RailPoint[];
}

function pathCommands(pathData: string): readonly PathCommand[] {
  const tokens = pathData.trim().split(/[\s,]+/u);
  const commands: PathCommand[] = [];
  let current: RailPoint = { x: Number.NaN, y: Number.NaN };
  let index = 0;
  while (index < tokens.length) {
    const command = tokens[index] ?? "";
    const coordinateCount = command === "C" ? 6 : 2;
    const values = tokens.slice(index + 1, index + 1 + coordinateCount).map(Number);
    const points = Array.from({ length: coordinateCount / 2 }, (_, pointIndex) => ({
      x: values[pointIndex * 2] ?? Number.NaN,
      y: values[pointIndex * 2 + 1] ?? Number.NaN,
    }));
    commands.push({ command, from: current, points });
    current = points.at(-1) ?? current;
    index += 1 + coordinateCount;
  }
  return commands;
}

function endPoint(pathData: string): RailPoint | undefined {
  return pathCommands(pathData).at(-1)?.points.at(-1);
}

function near(first: number, second: number): boolean {
  return Math.abs(first - second) <= 0.02;
}

function nearPoint(first: RailPoint | undefined, second: RailPoint): boolean {
  return first !== undefined && near(first.x, second.x) && near(first.y, second.y);
}

/** True when a cubic is the rail's tight bend, in either direction. */
function isTightBend(command: PathCommand): boolean {
  const [firstControl, secondControl, end] = command.points;
  const start = command.from;
  if (firstControl === undefined || secondControl === undefined || end === undefined) {
    return false;
  }
  // Horizontal into vertical (the retired localForkPath).
  const forkCorner = { x: end.x, y: start.y };
  const forkMatches =
    nearPoint(firstControl, {
      x: start.x + (forkCorner.x - start.x) * railBendHorizontalControlRatio,
      y: forkCorner.y + (end.y - forkCorner.y) * railBendHorizontalLiftRatio,
    }) &&
    nearPoint(secondControl, {
      x: forkCorner.x,
      y: forkCorner.y + (end.y - forkCorner.y) * railBendVerticalControlRatio,
    });
  // Vertical into horizontal (the retired localMergePath).
  const mergeCorner = { x: start.x, y: end.y };
  const mergeMatches =
    nearPoint(firstControl, {
      x: mergeCorner.x,
      y: mergeCorner.y + (start.y - mergeCorner.y) * railBendVerticalControlRatio,
    }) &&
    nearPoint(secondControl, {
      x: end.x + (mergeCorner.x - end.x) * railBendHorizontalControlRatio,
      y: mergeCorner.y + (start.y - mergeCorner.y) * railBendHorizontalLiftRatio,
    });
  return forkMatches || mergeMatches;
}

/** Points along a command every 1% of the way: a straight run or a cubic bend. */
function commandSamplePoints(command: PathCommand): readonly RailPoint[] {
  const [firstControl, secondControl, end] =
    command.command === "C"
      ? command.points
      : [command.from, command.points[0] ?? command.from, command.points[0] ?? command.from];
  if (firstControl === undefined || secondControl === undefined || end === undefined) {
    return [];
  }
  return Array.from({ length: 101 }, (_, step) => {
    const t = step / 100;
    const u = 1 - t;
    const weigh = (start: number, first: number, second: number, last: number): number =>
      u * u * u * start + 3 * u * u * t * first + 3 * u * t * t * second + t * t * t * last;
    return {
      x: weigh(command.from.x, firstControl.x, secondControl.x, end.x),
      y: weigh(command.from.y, firstControl.y, secondControl.y, end.y),
    };
  });
}

function strictlyInside(point: RailPoint, area: RailRect): boolean {
  return (
    point.x > area.left &&
    point.x < area.left + area.width &&
    point.y > area.top &&
    point.y < area.top + area.height
  );
}

describe("layoutChapterRail grid", () => {
  for (const fixture of [wideFixture, laptopFixture, phoneFixture]) {
    describe(fixture.name, () => {
      const layout = drawn(layoutChapterRail(fixture.props));

      it("gives every row exactly one dot, on one of the lanes", () => {
        // Assert
        expect(layout.columnXs).toHaveLength(fixture.columnCount);
        expect(layout.rows.map((row) => row.rowIndex)).toEqual(
          layout.rows.map((_, rowIndex) => rowIndex),
        );
        expect(new Set(layout.rows.map((row) => row.y)).size).toBe(layout.rows.length);
        for (const row of layout.rows) {
          expect(layout.columnXs).toContain(row.x);
        }
      });

      it("puts every anchor on its own main-lane row, level with the anchor", () => {
        // Assert
        for (const anchor of fixture.props.anchors) {
          const anchorRow = layout.rows.find((row) => row.anchorId === anchor.id);
          expect(anchorRow?.y).toBeCloseTo(anchor.rect.top + anchor.rect.height / 2, 1);
          expect(anchorRow?.x).toBe(layout.railX);
        }
      });

      it("keeps the row pitch within a quarter of the base unit", () => {
        // Assert
        const pitches = layout.rows
          .slice(1)
          .map((row, index) => row.y - (layout.rows[index]?.y ?? 0));
        expect(pitches.length).toBeGreaterThan(20);
        for (const pitch of pitches) {
          expect(pitch).toBeGreaterThanOrEqual(fixture.rowUnit * 0.75);
          expect(pitch).toBeLessThanOrEqual(fixture.rowUnit * 1.25);
        }
      });

      it("builds every branch from straight runs joined by the retired tight bend", () => {
        // Assert
        expect(layout.branches.length).toBeGreaterThan(0);
        for (const branch of layout.branches) {
          const commands = pathCommands(branch.pathData);
          expect(commands[0]?.command).toBe("M");
          for (const command of commands.slice(1)) {
            expect(["L", "C"]).toContain(command.command);
            if (command.command === "L") {
              const end = command.points[0];
              expect(
                near(end?.x ?? Number.NaN, command.from.x) ||
                  near(end?.y ?? Number.NaN, command.from.y),
              ).toBe(true);
            } else {
              expect(isTightBend(command)).toBe(true);
            }
          }
          expect(nearPoint(endPoint(branch.pathData), branch.end)).toBe(true);
        }
      });

      it("never routes a branch across the eyebrow, title or copy", () => {
        // Assert
        for (const branch of layout.branches) {
          const crossings = pathCommands(branch.pathData)
            .slice(1)
            .flatMap(commandSamplePoints)
            .filter((point) =>
              fixture.textRects.some((textRect) => strictlyInside(point, textRect)),
            );
          expect(crossings).toEqual([]);
        }
      });

      it("forks the hero's worktree lanes into the app frame in their own colors", () => {
        // Assert
        const heroBranches = layout.branches.filter((branch) => branch.anchorId === "hero");
        expect(heroBranches.map((branch) => branch.accent)).toEqual(fixture.heroAccents);
        const worktreeDotAccents = new Set(
          layout.rows.filter((row) => row.accent !== "main").map((row) => row.accent),
        );
        expect([...worktreeDotAccents].toSorted()).toEqual([...fixture.heroAccents].toSorted());
        for (const row of layout.rows.filter((dot) => dot.accent !== "main")) {
          expect(row.x).not.toBe(layout.railX);
        }
      });
    });
  }

  it("enters the hero frame's left edge on wide screens, one lane per worktree column", () => {
    // Act
    const layout = drawn(layoutChapterRail(wideFixture.props));

    // Assert
    const frame = wideFixture.props.surfaceTargets.get("hero");
    const heroBranches = layout.branches.filter((branch) => branch.anchorId === "hero");
    expect(layout.columnXs).toEqual([95.5, 191.5, 287.5]);
    for (const branch of heroBranches) {
      expect(branch.targetEdge).toBe("left");
      expect(branch.end.x).toBe(frame?.left);
      expect(branch.end.y).toBeGreaterThan((frame?.top ?? 0) + railTargetCornerInset);
    }
    // Chapters beside their glass get one straight run from the dot.
    const chapterBranch = layout.branches.find((branch) => branch.anchorId === "many-agents");
    expect(pathCommands(chapterBranch?.pathData ?? "").map((command) => command.command)).toEqual([
      "M",
      "L",
    ]);
  });

  it("drops phone branches into the media's top edge, turning below the copy", () => {
    // Act
    const layout = drawn(layoutChapterRail(phoneFixture.props));

    // Assert
    for (const branch of layout.branches) {
      const media = phoneFixture.props.mediaTargets.get(branch.anchorId);
      const copy = phoneFixture.props.copyBlocks.get(branch.anchorId);
      expect(branch.targetEdge).toBe("top");
      expect(branch.end).toEqual({ x: (media?.left ?? 0) + railTargetCornerInset, y: media?.top });
      const crossingYs = pathCommands(branch.pathData)
        .filter((command) => command.command === "C")
        .map((command) => command.points.at(-1)?.y ?? Number.NaN);
      const crossingY = crossingYs[1];
      expect(crossingY).toBeGreaterThan((copy?.top ?? 0) + (copy?.height ?? 0));
      expect(crossingY).toBeLessThan(media?.top ?? 0);
    }
  });
});

function branchEdgeFor(layout: DrawnRailLayout, anchorId: string): string | undefined {
  return layout.branches.find((branch) => branch.anchorId === anchorId)?.targetEdge;
}

describe("layoutChapterRail edges", () => {
  function wideTwoAnchorPage(): ChapterRailLayoutProps {
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

  it("draws nothing when the page has no rail anchors", () => {
    // Arrange
    const props = { ...wideTwoAnchorPage(), anchors: [] };

    // Act / Assert
    expect(layoutChapterRail(props).kind).toBe("empty");
  });

  it("joins a glass straight across whenever the dot clears its rounded corner", () => {
    // Arrange: the eyebrow sits just inside the glass's top corner radius.
    const glassTop = 1100;
    const props: ChapterRailLayoutProps = {
      ...wideTwoAnchorPage(),
      anchors: [{ id: "many-agents", rect: rect(160, glassTop + railTargetCornerInset, 200, 16) }],
      surfaceTargets: new Map([["many-agents", rect(120, glassTop, 1040, 640)]]),
    };

    // Act
    const layout = drawn(layoutChapterRail(props));

    // Assert
    const branch = layout.branches[0];
    expect(branch?.end).toEqual({ x: 120, y: layout.anchorNodes[0]?.y });
    expect(pathCommands(branch?.pathData ?? "")).toHaveLength(2);
  });

  it("drops a phone branch in line with the chapter text", () => {
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
    const layout = drawn(layoutChapterRail(props));

    // Assert
    expect(layout.branches[0]?.end).toEqual({ x: 48, y: 1040 });
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
    const layout = drawn(layoutChapterRail(props));

    // Assert
    expect(layout.branches[0]?.end).toEqual({ x: mediaLeft + railTargetCornerInset, y: 1040 });
  });

  it("switches from left-edge to top-edge branches at the site's phone breakpoint", () => {
    // Arrange
    const base = wideTwoAnchorPage();

    // Act
    const atBreakpoint = drawn(
      layoutChapterRail({ ...base, viewportWidth: chapterRailPhoneBreakpointWidth }),
    );
    const belowBreakpoint = drawn(
      layoutChapterRail({ ...base, viewportWidth: chapterRailPhoneBreakpointWidth - 1 }),
    );

    // Assert
    expect(branchEdgeFor(atBreakpoint, "many-agents")).toBe("left");
    expect(branchEdgeFor(belowBreakpoint, "many-agents")).toBe("top");
  });

  it("keeps a dot for an anchor without a matching target and gives it no branch", () => {
    // Arrange
    const props: ChapterRailLayoutProps = {
      ...wideTwoAnchorPage(),
      anchors: [{ id: "review", rect: rect(160, 2000, 200, 16) }],
    };

    // Act
    const layout = drawn(layoutChapterRail(props));

    // Assert
    expect(layout.anchorNodes.map((node) => node.anchorId)).toEqual(["review"]);
    expect(layout.branches).toHaveLength(0);
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
