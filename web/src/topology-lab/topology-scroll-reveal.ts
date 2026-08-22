import { layoutWorktreeTopology } from "./topology-layout";

type LayoutTopologyArtwork = (artwork: SVGSVGElement) => boolean;

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(value, minimum), maximum);
}

export function initializeTopologyScrollReveal(
  artwork: SVGSVGElement,
  layoutArtwork: LayoutTopologyArtwork = layoutWorktreeTopology,
): () => void {
  const revealPaths = [...artwork.querySelectorAll<SVGPathElement>("[data-topology-path-start]")];
  const revealNodes = [
    ...artwork.querySelectorAll<SVGGraphicsElement>("[data-topology-node-progress]"),
  ];
  const verticalRevealSolid = artwork.querySelector<SVGRectElement>("[data-topology-reveal-solid]");
  const verticalRevealFade = artwork.querySelector<SVGRectElement>("[data-topology-reveal-fade]");
  const lifecycle = new AbortController();
  const reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  let lastLayoutHeight = 0;
  let lastLayoutWidth = 0;
  let layoutNeedsUpdate = true;
  let pendingAnimationFrame: number | undefined;

  const renderReveal = (): void => {
    pendingAnimationFrame = undefined;
    if (layoutNeedsUpdate) {
      if (!layoutArtwork(artwork)) {
        return;
      }
      lastLayoutWidth = artwork.clientWidth;
      lastLayoutHeight = artwork.clientHeight;
      layoutNeedsUpdate = false;
    }

    const maximumScroll = Math.max(document.documentElement.scrollHeight - window.innerHeight, 1);
    const scrollProgress = clamp(window.scrollY / maximumScroll, 0, 1);
    const revealProgress = reducedMotionQuery.matches ? 1 : scrollProgress;
    const leadingBuffer = revealProgress === 0 ? 0 : Math.min(0.06, revealProgress * 0.8);
    const atStart = !reducedMotionQuery.matches && window.scrollY <= 0;
    artwork.dataset["topologyScrollProgress"] = String(scrollProgress);

    artwork.toggleAttribute("data-topology-at-start", atStart);
    artwork.toggleAttribute(
      "data-topology-at-end",
      !reducedMotionQuery.matches && scrollProgress >= 0.9999,
    );

    if (verticalRevealSolid !== null && verticalRevealFade !== null) {
      const topologyStartY = Number(artwork.dataset["topologyStartY"]);
      const topologyEndY = Number(artwork.dataset["topologyEndY"]);
      if (!Number.isFinite(topologyStartY) || !Number.isFinite(topologyEndY)) {
        return;
      }
      if (atStart) {
        verticalRevealSolid.setAttribute("height", String(artwork.clientHeight));
        verticalRevealFade.setAttribute("y", String(topologyStartY));
        verticalRevealFade.setAttribute("height", "0");
        artwork.dataset["topologyRevealEdgeY"] = String(topologyStartY);
        for (const path of revealPaths) {
          path.style.visibility = "hidden";
          path.style.strokeDasharray = "0 1";
          path.style.strokeDashoffset = "0";
        }
        for (const node of revealNodes) {
          node.style.opacity = node.dataset["topologyNodeProgress"] === "0" ? "1" : "0";
        }
        return;
      }
      const revealY = topologyStartY + (topologyEndY - topologyStartY) * revealProgress;
      const fadeHeight =
        revealProgress >= 1
          ? 0
          : Math.min(288, Math.max(96, (topologyEndY - topologyStartY) * 0.06));
      verticalRevealSolid.setAttribute(
        "height",
        String(revealProgress >= 1 ? artwork.clientHeight : revealY),
      );
      verticalRevealFade.setAttribute("y", String(revealY));
      verticalRevealFade.setAttribute("height", String(fadeHeight));
      artwork.dataset["topologyRevealEdgeY"] = String(revealY);

      for (const path of revealPaths) {
        const leadingBand = path.dataset["topologyPathRole"] === "leading-band";
        path.style.visibility = leadingBand ? "hidden" : "visible";
        path.style.strokeDasharray = leadingBand ? "0 1" : "none";
        path.style.strokeDashoffset = "0";
      }
      for (const node of revealNodes) {
        node.style.opacity = "1";
      }
      return;
    }

    for (const path of revealPaths) {
      const totalLength = path.getTotalLength();
      const start = Number(path.dataset["topologyPathStart"]);
      const end = Number(path.dataset["topologyPathEnd"]);
      const duration = Math.max(end - start, 0.001);
      const localProgressAt = (progress: number): number =>
        clamp((progress - start) / duration, 0, 1);
      const role = path.dataset["topologyPathRole"];

      if (role === "leading-band") {
        if (leadingBuffer <= 0 || revealProgress >= 1 || (start > 0 && revealProgress <= start)) {
          path.style.visibility = "hidden";
          continue;
        }

        const bandStart = Number(path.dataset["topologyLeadStart"]);
        const bandEnd = Number(path.dataset["topologyLeadEnd"]);
        const localBandStart = localProgressAt(revealProgress + leadingBuffer * bandStart);
        const localBandEnd = localProgressAt(revealProgress + leadingBuffer * bandEnd);
        const bandLength = Math.max(localBandEnd - localBandStart, 0);
        path.style.visibility = bandLength > 0.0001 ? "visible" : "hidden";
        path.style.strokeDasharray = `${bandLength * totalLength} ${totalLength}`;
        path.style.strokeDashoffset = String(-localBandStart * totalLength);
        continue;
      }

      const pathRevealProgress =
        role === "clearance" && revealProgress > start
          ? revealProgress + leadingBuffer
          : revealProgress;
      const localProgress = localProgressAt(pathRevealProgress);
      path.style.visibility = localProgress > 0.0001 ? "visible" : "hidden";
      path.style.strokeDasharray = `${localProgress * totalLength} ${totalLength}`;
      path.style.strokeDashoffset = "0";
    }

    for (const node of revealNodes) {
      const nodeProgress = Number(node.dataset["topologyNodeProgress"]);
      node.style.opacity = nodeProgress === 0 || revealProgress >= nodeProgress ? "1" : "0";
    }
  };

  const scheduleRender = (): void => {
    if (pendingAnimationFrame !== undefined) {
      return;
    }
    pendingAnimationFrame = window.requestAnimationFrame(renderReveal);
  };

  const forceLayoutUpdate = (): void => {
    layoutNeedsUpdate = true;
    scheduleRender();
  };

  const scheduleMeaningfulLayoutUpdate = (entries: readonly ResizeObserverEntry[]): void => {
    const entry = entries[0];
    if (entry === undefined) {
      return;
    }
    const widthChanged = Math.abs(entry.contentRect.width - lastLayoutWidth) > 0.5;
    const heightChanged = Math.abs(entry.contentRect.height - lastLayoutHeight) > 8;
    if (widthChanged || heightChanged) {
      forceLayoutUpdate();
    }
  };

  const artworkResizeObserver = new ResizeObserver(scheduleMeaningfulLayoutUpdate);
  artworkResizeObserver.observe(artwork);
  window.addEventListener("scroll", scheduleRender, { passive: true, signal: lifecycle.signal });
  window.addEventListener("resize", forceLayoutUpdate, { signal: lifecycle.signal });
  reducedMotionQuery.addEventListener("change", scheduleRender, { signal: lifecycle.signal });
  scheduleRender();

  return (): void => {
    lifecycle.abort();
    artworkResizeObserver.disconnect();
    if (pendingAnimationFrame !== undefined) {
      window.cancelAnimationFrame(pendingAnimationFrame);
    }
  };
}
