function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(value, minimum), maximum);
}

export function initializeTopologyScrollReveal(artwork: SVGSVGElement): () => void {
  const revealPaths = [...artwork.querySelectorAll<SVGPathElement>("[data-topology-path-start]")];
  const revealNodes = [
    ...artwork.querySelectorAll<SVGGraphicsElement>("[data-topology-node-progress]"),
  ];

  const lifecycle = new AbortController();
  const reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  let pendingAnimationFrame: number | undefined;

  const renderReveal = (): void => {
    pendingAnimationFrame = undefined;
    const documentHeight = document.documentElement.scrollHeight;
    const maximumScroll = Math.max(documentHeight - window.innerHeight, 1);
    const scrollProgress = clamp(window.scrollY / maximumScroll, 0, 1);
    const revealProgress = reducedMotionQuery.matches ? 1 : scrollProgress;
    const leadingBuffer = revealProgress === 0 ? 0 : Math.min(0.06, revealProgress * 0.8);
    artwork.toggleAttribute(
      "data-topology-at-start",
      !reducedMotionQuery.matches && scrollProgress <= 0.0001,
    );
    artwork.toggleAttribute(
      "data-topology-at-end",
      !reducedMotionQuery.matches && scrollProgress >= 0.9999,
    );

    for (const path of revealPaths) {
      const start = Number(path.dataset["topologyPathStart"]);
      const end = Number(path.dataset["topologyPathEnd"]);
      const duration = Math.max(end - start, 0.001);
      const localProgressAt = (progress: number): number =>
        clamp((progress - start) / duration, 0, 1);
      const role = path.dataset["topologyPathRole"];

      if (role === "leading-band") {
        const bandStart = Number(path.dataset["topologyLeadStart"]);
        const bandEnd = Number(path.dataset["topologyLeadEnd"]);
        const localBandStart = localProgressAt(revealProgress + leadingBuffer * bandStart);
        const localBandEnd = localProgressAt(revealProgress + leadingBuffer * bandEnd);
        const bandLength = Math.max(localBandEnd - localBandStart, 0);
        path.style.visibility = bandLength > 0.0001 ? "visible" : "hidden";
        path.style.strokeDasharray = `${bandLength} 1`;
        path.style.strokeDashoffset = String(-localBandStart);
        continue;
      }

      const pathRevealProgress =
        role === "clearance" ? revealProgress + leadingBuffer : revealProgress;
      const localProgress = localProgressAt(pathRevealProgress);
      path.style.visibility = localProgress > 0.0001 ? "visible" : "hidden";
      path.style.strokeDasharray = "1";
      path.style.strokeDashoffset = String(1 - localProgress);
    }

    for (const node of revealNodes) {
      const nodeProgress = Number(node.dataset["topologyNodeProgress"]);
      const nodeFadeDuration = 0.018;
      const nodeFadeStart = Math.max(nodeProgress - nodeFadeDuration, 0);
      const nodeOpacity =
        nodeProgress === 0 ? 1 : clamp((revealProgress - nodeFadeStart) / nodeFadeDuration, 0, 1);
      node.style.opacity = String(nodeOpacity);
    }
  };

  const scheduleRender = (): void => {
    if (pendingAnimationFrame !== undefined) {
      return;
    }
    pendingAnimationFrame = window.requestAnimationFrame(renderReveal);
  };

  window.addEventListener("scroll", scheduleRender, {
    passive: true,
    signal: lifecycle.signal,
  });
  window.addEventListener("resize", scheduleRender, { signal: lifecycle.signal });
  reducedMotionQuery.addEventListener("change", scheduleRender, { signal: lifecycle.signal });
  scheduleRender();

  return (): void => {
    lifecycle.abort();
    if (pendingAnimationFrame !== undefined) {
      window.cancelAnimationFrame(pendingAnimationFrame);
    }
  };
}
