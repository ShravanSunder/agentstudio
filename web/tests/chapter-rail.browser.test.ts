import { afterEach, describe, expect, it, vi } from "vitest";
import { page } from "vitest/browser";

import {
  chapterRailBranchAttribute,
  chapterRailLayoutAttribute,
  chapterRailNodeAttribute,
  chapterRailStateAttribute,
  chapterRailTargetEdgeAttribute,
  initializeChapterRail,
} from "../src/chapter-rail/chapter-rail-controller";
import { railCurrentAttribute } from "../src/chapters/chapter-dom-contract";

interface ChapterRailFixture {
  readonly host: HTMLElement;
  readonly rail: HTMLElement;
  readonly artwork: SVGSVGElement;
  readonly dispose: () => void;
}

const activeFixtures: ChapterRailFixture[] = [];

// The same rail markup that ChapterRail.astro renders, plus a hero and two
// chapters laid out the way lane B places anchors and targets.
const railMarkup = `
  <div data-chapter-rail style="position:absolute;inset:0;pointer-events:none">
    <svg data-chapter-rail-artwork style="display:block;width:100%;height:100%"></svg>
  </div>
`;

const pageMarkup = `
  <section style="padding:160px 0 0 96px">
    <p data-rail-anchor="hero" style="margin:0;height:16px">Hero eyebrow</p>
    <div data-rail-surface-target="hero" data-rail-media-target="hero"
      style="margin-top:220px;width:min(640px,70vw);height:360px"></div>
  </section>
  <section data-rail-surface-target="many-agents"
    style="margin:900px 0 0 72px;width:min(720px,80vw);padding:40px 24px 40px 48px">
    <p data-rail-anchor="many-agents" style="margin:0;height:16px">Chapter 1</p>
    <div data-rail-media-target="many-agents" style="margin:120px 0 0 -40px;height:240px"></div>
  </section>
  <section data-rail-surface-target="context-with-task"
    style="margin:1400px 0 2400px 72px;width:min(720px,80vw);padding:40px 24px 40px 48px">
    <p data-rail-anchor="context-with-task" style="margin:0;height:16px">Chapter 2</p>
    <div data-rail-media-target="context-with-task" style="margin:120px 0 0 -40px;height:240px"></div>
  </section>
`;

function mountChapterRailFixture(contentMarkup: string): ChapterRailFixture {
  const host = document.createElement("div");
  host.style.position = "relative";
  host.innerHTML = `${railMarkup}${contentMarkup}`;
  document.body.append(host);
  const rail = host.querySelector<HTMLElement>("[data-chapter-rail]");
  const artwork = host.querySelector<SVGSVGElement>("[data-chapter-rail-artwork]");
  if (rail === null || artwork === null) {
    throw new Error("Chapter rail fixture is incomplete");
  }
  const fixture = { host, rail, artwork, dispose: initializeChapterRail(rail) };
  activeFixtures.push(fixture);
  return fixture;
}

function requiredElement(selector: string): HTMLElement {
  const element = document.querySelector<HTMLElement>(selector);
  if (element === null) {
    throw new Error(`Chapter rail fixture is missing ${selector}`);
  }
  return element;
}

function railNodes(artwork: SVGSVGElement): readonly SVGGElement[] {
  return [...artwork.querySelectorAll<SVGGElement>(`[${chapterRailNodeAttribute}]`)];
}

function railNode(artwork: SVGSVGElement, anchorId: string): SVGGElement {
  const node = artwork.querySelector<SVGGElement>(`[${chapterRailNodeAttribute}="${anchorId}"]`);
  if (node === null) {
    throw new Error(`Rail has no node for ${anchorId}`);
  }
  return node;
}

function railBranch(artwork: SVGSVGElement, anchorId: string): SVGPathElement {
  const branch = artwork.querySelector<SVGPathElement>(
    `[${chapterRailBranchAttribute}="${anchorId}"]`,
  );
  if (branch === null) {
    throw new Error(`Rail has no branch for ${anchorId}`);
  }
  return branch;
}

/** A node's center and a branch's end, in viewport coordinates. */
function nodeCenter(node: SVGGElement): DOMPoint {
  const bounds = node.getBoundingClientRect();
  return new DOMPoint(bounds.left + bounds.width / 2, bounds.top + bounds.height / 2);
}

function branchEnd(artwork: SVGSVGElement, branch: SVGPathElement): DOMPoint {
  const end = branch.getPointAtLength(branch.getTotalLength());
  const artworkBounds = artwork.getBoundingClientRect();
  return new DOMPoint(artworkBounds.left + end.x, artworkBounds.top + end.y);
}

function verticalCenter(element: Element): number {
  const bounds = element.getBoundingClientRect();
  return bounds.top + bounds.height / 2;
}

afterEach(() => {
  for (const fixture of activeFixtures.splice(0)) {
    fixture.dispose();
    fixture.host.remove();
  }
  window.scrollTo(0, 0);
});

describe("chapter rail", () => {
  it("draws nothing when the page has no rail anchors", async () => {
    // Arrange
    await page.viewport(1280, 800);

    // Act
    const fixture = mountChapterRailFixture(`<section style="height:2000px">No chapters</section>`);
    await vi.waitFor(() => {
      expect(fixture.rail.getAttribute(chapterRailLayoutAttribute)).toBe("empty");
    });

    // Assert
    expect(railNodes(fixture.artwork)).toHaveLength(0);
    expect(fixture.artwork.querySelector("path[d]")).toBeNull();
  });

  it("aligns one dot per anchor and joins each wide branch to its glass's left edge", async () => {
    // Arrange
    await page.viewport(1280, 800);

    // Act
    const fixture = mountChapterRailFixture(pageMarkup);
    await vi.waitFor(() => {
      expect(railNodes(fixture.artwork)).toHaveLength(3);
    });

    // Assert
    expect(fixture.rail.getAttribute(chapterRailLayoutAttribute)).toBe("drawn");
    const railXs = new Set<number>();
    for (const anchorId of ["hero", "many-agents", "context-with-task"]) {
      const anchor = requiredElement(`[data-rail-anchor="${anchorId}"]`);
      const surface = requiredElement(`[data-rail-surface-target="${anchorId}"]`);
      const center = nodeCenter(railNode(fixture.artwork, anchorId));
      const end = branchEnd(fixture.artwork, railBranch(fixture.artwork, anchorId));
      railXs.add(Math.round(center.x));
      expect(Math.abs(center.y - verticalCenter(anchor))).toBeLessThanOrEqual(1);
      expect(center.x).toBeLessThan(anchor.getBoundingClientRect().left);
      expect(Math.abs(end.x - surface.getBoundingClientRect().left)).toBeLessThanOrEqual(1);
      expect(end.y).toBeGreaterThanOrEqual(surface.getBoundingClientRect().top - 1);
      expect(end.y).toBeLessThanOrEqual(surface.getBoundingClientRect().bottom + 1);
    }
    expect(railXs.size).toBe(1);
    // A chapter glass spans its eyebrow, so the branch lands level with the dot.
    const chapterCenter = nodeCenter(railNode(fixture.artwork, "many-agents"));
    const chapterEnd = branchEnd(fixture.artwork, railBranch(fixture.artwork, "many-agents"));
    expect(Math.abs(chapterEnd.y - chapterCenter.y)).toBeLessThanOrEqual(1);
  });

  it("drops each phone branch into its media glass's top edge under the chapter text", async () => {
    // Arrange
    await page.viewport(390, 844);

    // Act
    const fixture = mountChapterRailFixture(pageMarkup);
    await vi.waitFor(() => {
      expect(railNodes(fixture.artwork)).toHaveLength(3);
      expect(
        railBranch(fixture.artwork, "many-agents").getAttribute(chapterRailTargetEdgeAttribute),
      ).toBe("top");
    });

    // Assert
    for (const anchorId of ["many-agents", "context-with-task"]) {
      const anchor = requiredElement(`[data-rail-anchor="${anchorId}"]`);
      const media = requiredElement(`[data-rail-media-target="${anchorId}"]`);
      const end = branchEnd(fixture.artwork, railBranch(fixture.artwork, anchorId));
      expect(Math.abs(end.y - media.getBoundingClientRect().top)).toBeLessThanOrEqual(1);
      expect(Math.abs(end.x - anchor.getBoundingClientRect().left)).toBeLessThanOrEqual(1);
    }
  });

  it("marks the chapter nearest above the reading line current and lights its glass", async () => {
    // Arrange
    await page.viewport(1280, 800);
    const fixture = mountChapterRailFixture(pageMarkup);
    await vi.waitFor(() => {
      expect(railNodes(fixture.artwork)).toHaveLength(3);
    });
    const secondChapterAnchor = requiredElement('[data-rail-anchor="many-agents"]');
    const readingLine = window.innerHeight * 0.4;

    // Act: bring the second anchor just above the 40% line; the third stays below it.
    window.scrollTo(0, window.scrollY + verticalCenter(secondChapterAnchor) - readingLine + 24);

    // Assert
    await vi.waitFor(() => {
      expect(railNode(fixture.artwork, "many-agents").getAttribute(chapterRailStateAttribute)).toBe(
        "current",
      );
    });
    expect(railNode(fixture.artwork, "hero").getAttribute(chapterRailStateAttribute)).toBe(
      "passed",
    );
    expect(
      railNode(fixture.artwork, "context-with-task").getAttribute(chapterRailStateAttribute),
    ).toBe("upcoming");
    expect(railBranch(fixture.artwork, "many-agents").getAttribute(chapterRailStateAttribute)).toBe(
      "current",
    );
    expect(
      [...document.querySelectorAll(`[${railCurrentAttribute}]`)].map((element) =>
        element.getAttribute("data-rail-surface-target"),
      ),
    ).toEqual(["many-agents"]);

    // Act: return to the top, where the hero anchor is current.
    window.scrollTo(0, 0);

    // Assert
    await vi.waitFor(() => {
      expect(railNode(fixture.artwork, "hero").getAttribute(chapterRailStateAttribute)).toBe(
        "current",
      );
    });
    expect(
      requiredElement('[data-rail-surface-target="hero"]').hasAttribute(railCurrentAttribute),
    ).toBe(true);
    expect(
      requiredElement('[data-rail-surface-target="many-agents"]').hasAttribute(
        railCurrentAttribute,
      ),
    ).toBe(false);
  });

  it("clears the lit glass when disposed", async () => {
    // Arrange
    await page.viewport(1280, 800);
    const fixture = mountChapterRailFixture(pageMarkup);
    await vi.waitFor(() => {
      expect(document.querySelectorAll(`[${railCurrentAttribute}]`)).toHaveLength(1);
    });

    // Act
    fixture.dispose();

    // Assert
    expect(document.querySelectorAll(`[${railCurrentAttribute}]`)).toHaveLength(0);
  });
});
