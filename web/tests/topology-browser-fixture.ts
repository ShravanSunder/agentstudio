// A browser fixture for the page topology: the artwork markup that
// FullPageTopologyArtwork.astro renders, over a page laid out with the chapter
// DOM contract hooks (hero plus chapters), each placed absolutely so the
// geometry is known.

export interface TopologyFixtureLayout {
  readonly contentLeft: number;
  readonly anchorTops: readonly number[];
  readonly height: number;
  readonly phone: boolean;
}

export interface TopologyFixture {
  readonly host: HTMLElement;
  readonly artwork: SVGSVGElement;
}

const artworkMarkup = `
  <div style="position:absolute;inset:0;pointer-events:none">
    <svg data-full-page-topology style="display:block;width:100%;height:100%">
      <defs>
        <linearGradient id="topology-vertical-reveal-gradient" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="white" stop-opacity="1" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </linearGradient>
        <mask id="topology-vertical-reveal-mask" maskUnits="userSpaceOnUse">
          <rect data-topology-reveal-solid x="0" y="0" width="1000" height="0" fill="white" />
          <rect data-topology-reveal-fade x="0" y="0" width="1000" height="0" fill="url(#topology-vertical-reveal-gradient)" />
        </mask>
      </defs>
      <g data-topology-reveal-layer mask="url(#topology-vertical-reveal-mask)">
        <path data-mainline data-topology-path-role="core" data-topology-path-start="0" data-topology-path-end="1" />
        <g data-topology-routes></g>
        <g data-topology-row-nodes></g>
      </g>
    </svg>
  </div>
`;

function box(left: number, top: number, width: number, height: number): string {
  return `position:absolute;left:${left}px;top:${top}px;width:${width}px;height:${height}px;margin:0`;
}

// Chapter titles wrap onto two lines, so the first line's centre differs from
// the element's centre, as on the real page.
const titleStyle = "font-size:28px;line-height:1.2";
const titleWords = "a title long enough to wrap";

function chapterMarkup(id: string, layout: TopologyFixtureLayout, anchorTop: number): string {
  const { contentLeft, phone } = layout;
  const width = `calc(100% - ${contentLeft + 24}px)`;
  if (phone) {
    return `
      <h2 data-rail-anchor="${id}" style="position:absolute;left:${contentLeft}px;top:${anchorTop}px;width:220px;margin:0;${titleStyle}">${id} ${titleWords}</h2>
      <section data-rail-surface-target="${id}" style="position:absolute;left:${contentLeft}px;top:${anchorTop - 40}px;width:${width};height:560px"></section>
      <div data-rail-media-target="${id}" style="position:absolute;left:${contentLeft}px;top:${anchorTop + 100}px;width:${width};height:220px"></div>
    `;
  }
  return `
    <section data-rail-surface-target="${id}" style="position:absolute;left:${contentLeft}px;top:${anchorTop - 54}px;width:${width};height:620px">
      <header style="position:absolute;left:54px;top:54px;width:300px;height:110px">
        <h2 data-rail-anchor="${id}" style="margin:0;${titleStyle}">${id} ${titleWords}</h2>
      </header>
      <div data-rail-media-target="${id}" style="position:absolute;left:40%;top:14px;width:55%;height:440px"></div>
    </section>
  `;
}

export function mountTopologyFixture(layout: TopologyFixtureLayout): TopologyFixture {
  const host = document.createElement("div");
  host.style.cssText = `position:relative;width:100%;height:${layout.height}px`;
  const [heroTop = 110, ...chapterTops] = layout.anchorTops;
  const heroFrameTop = heroTop + 430;
  host.innerHTML = `
    ${artworkMarkup}
    <div style="${box(layout.contentLeft, heroTop, 700, 380)}">
      <p data-rail-anchor="hero" style="margin:0">Hero eyebrow</p>
    </div>
    <div data-rail-surface-target="hero" data-rail-media-target="hero"
      style="position:absolute;left:${layout.contentLeft}px;top:${heroFrameTop}px;width:calc(100% - ${layout.contentLeft + 24}px);height:400px"></div>
    ${chapterTops.map((anchorTop, index) => chapterMarkup(`chapter-${index + 1}`, layout, anchorTop)).join("")}
  `;
  document.body.append(host);
  const artwork = host.querySelector<SVGSVGElement>("[data-full-page-topology]");
  if (artwork === null) {
    throw new Error("Topology fixture is missing its artwork");
  }
  return { host, artwork };
}
