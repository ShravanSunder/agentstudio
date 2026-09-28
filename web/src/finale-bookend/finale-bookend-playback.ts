import { gsap } from "gsap";

export const finaleBookendReadyEventName = "finale-bookend-ready";

export interface FinaleBookendControl {
  readonly duration: number;
  pause(): void;
  seek(seconds: number): void;
  finish(): void;
}

function railDrawFraction(seconds: number): number {
  const progress = Math.min(Math.max(seconds / 0.35, 0), 1);
  return progress < 0.5 ? 4 * progress ** 3 : 1 - (-2 * progress + 2) ** 3 / 2;
}

function renderTerminalRail(root: HTMLElement, seconds: number): void {
  const route = root.ownerDocument.querySelector<SVGGElement>("[data-topology-terminal-route]");
  if (route === null) return;
  const fraction = railDrawFraction(seconds);
  for (const path of route.querySelectorAll<SVGPathElement>("[data-topology-path-role]")) {
    const length = path.getTotalLength();
    path.style.strokeDasharray = String(length);
    path.style.strokeDashoffset = String(length * (1 - fraction));
  }
  const node = route.querySelector<SVGGElement>("[data-topology-terminal-node]");
  if (node !== null) node.style.opacity = fraction >= 1 ? "1" : "0";
}

function clearTerminalRail(root: HTMLElement): void {
  const route = root.ownerDocument.querySelector<SVGGElement>("[data-topology-terminal-route]");
  if (route === null) return;
  for (const path of route.querySelectorAll<SVGPathElement>("[data-topology-path-role]")) {
    path.style.removeProperty("stroke-dasharray");
    path.style.removeProperty("stroke-dashoffset");
  }
  route
    .querySelector<SVGGElement>("[data-topology-terminal-node]")
    ?.style.removeProperty("opacity");
}

function requiredPart<TElement extends Element>(root: HTMLElement, selector: string): TElement {
  const part = root.querySelector<TElement>(selector);
  if (part === null) throw new Error(`Finale bookend is missing ${selector}`);
  return part;
}

function tracePillBorder(pill: HTMLElement, trace: SVGPathElement): number {
  const { width, height } = pill.getBoundingClientRect();
  const borderCenter = 0.5;
  const radius = height / 2 - borderCenter;
  const centreY = height / 2;
  trace.setAttribute(
    "d",
    `M ${borderCenter} ${centreY} A ${radius} ${radius} 0 0 1 ${height / 2} ${borderCenter} H ${width - height / 2} A ${radius} ${radius} 0 0 1 ${width - height / 2} ${height - borderCenter} H ${height / 2} A ${radius} ${radius} 0 0 1 ${borderCenter} ${centreY}`,
  );
  trace.closest("svg")?.setAttribute("viewBox", `0 0 ${width} ${height}`);
  return trace.getTotalLength();
}

function fitSplitPillLabels(root: HTMLElement, pill: HTMLElement): void {
  const compactViewport = window.matchMedia("(width < 38.75rem)").matches;
  root.toggleAttribute("data-short-labels", compactViewport);
  if (!compactViewport && pill.scrollWidth > pill.clientWidth + 0.5)
    root.setAttribute("data-short-labels", "");
}

export function initializeFinaleBookend(root: HTMLElement): () => void {
  const pill = requiredPart<HTMLElement>(root, "[data-finale-split-pill]");
  const rearOne = requiredPart<HTMLElement>(root, "[data-finale-rear-one]");
  const rearTwo = requiredPart<HTMLElement>(root, "[data-finale-rear-two]");
  const front = requiredPart<HTMLElement>(root, "[data-finale-front]");
  const terminal = requiredPart<HTMLElement>(root, "[data-finale-terminal]");
  const logo = requiredPart<HTMLElement>(root, "[data-finale-logo]");
  const borderTrace = requiredPart<SVGPathElement>(root, "[data-finale-border-trace]");
  const starOutline = requiredPart<SVGPathElement>(root, "[data-finale-star-outline]");
  const starFill = requiredPart<SVGPathElement>(root, "[data-finale-star-fill]");
  const lifecycle = new AbortController();
  let timeline: gsap.core.Timeline | undefined = undefined;
  let started = false;
  let settled = false;
  let waitingForRail = false;
  let manualSeek = false;
  let railReached =
    document.querySelector("[data-full-page-topology][data-topology-end-reached]") !== null;

  const settle = (): void => {
    if (settled) return;
    settled = true;
    timeline?.kill();
    gsap
      .set([rearOne, rearTwo, front, terminal, logo, borderTrace, starOutline, starFill], {
        clearProps: "all",
      })
      .kill();
    clearTerminalRail(root);
    root.dataset["finaleState"] = "settled";
    root.dataset["finalePlayed"] = "true";
    root.dataset["finaleTime"] = "2.4";
    observer.disconnect();
  };

  const onRailReached = (): void => {
    railReached = true;
    if (waitingForRail && timeline !== undefined && !settled) {
      waitingForRail = false;
      timeline.play();
    }
  };
  document.addEventListener("topology-end-reached", onRailReached, { signal: lifecycle.signal });

  const observer = new IntersectionObserver(
    (entries): void => {
      if (started || settled || !entries.some((entry) => entry.isIntersecting)) return;
      started = true;
      root.dataset["finaleState"] = "playing";
      timeline?.play();
    },
    { threshold: 0.25 },
  );

  const measureLabels = (): void => {
    fitSplitPillLabels(root, pill);
    if (!started && !settled) tracePillBorder(pill, borderTrace);
  };
  const resizeObserver = new ResizeObserver(measureLabels);
  resizeObserver.observe(root);
  window.addEventListener("resize", settle, { signal: lifecycle.signal });
  root.addEventListener("pointerdown", settle, { signal: lifecycle.signal });
  window.addEventListener(
    "keydown",
    (event: KeyboardEvent): void => {
      if (event.key === "Escape") settle();
    },
    { signal: lifecycle.signal },
  );
  measureLabels();

  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || document.hidden) {
    settle();
    return (): void => {
      resizeObserver.disconnect();
      lifecycle.abort();
    };
  }

  root.dataset["finaleState"] = "ready";
  const borderLength = tracePillBorder(pill, borderTrace);
  const starLength = starOutline.getTotalLength();
  timeline = gsap.timeline({
    paused: true,
    onComplete: settle,
    onUpdate: (): void => {
      const currentTime = timeline?.time() ?? 0;
      root.dataset["finaleTime"] = currentTime.toFixed(3);
      renderTerminalRail(root, currentTime);
      if (!manualSeek && currentTime >= 0.35 && !railReached && !waitingForRail) {
        waitingForRail = true;
        timeline?.pause(0.35);
      }
    },
  });
  timeline.set(
    borderTrace,
    { strokeDasharray: borderLength, strokeDashoffset: borderLength, opacity: 0 },
    0,
  );
  timeline.set(starOutline, { strokeDasharray: starLength, strokeDashoffset: starLength }, 0);
  timeline.set(starFill, { opacity: 0 }, 0);
  timeline.set(logo, { opacity: 0 }, 0);
  timeline.set([rearOne, rearTwo, front, terminal], { opacity: 1 }, 0);
  timeline.set(borderTrace, { opacity: 1 }, 0.55);
  timeline.to(borderTrace, { strokeDashoffset: 0, duration: 0.6, ease: "power1.inOut" }, 0.55);
  timeline.to(borderTrace, { opacity: 0.6, duration: 0.01 }, 1.15);
  timeline.to(starOutline, { strokeDashoffset: 0, duration: 0.3, ease: "power1.inOut" }, 0.95);
  timeline.to(starFill, { opacity: 1, duration: 0.15 }, 1.25);
  timeline.to(
    terminal,
    { x: 1, y: 2, scale: 0.58, opacity: 0, duration: 0.8, ease: "power3.inOut" },
    1.4,
  );
  timeline.to(front, { scale: 0.75, opacity: 0, duration: 0.8, ease: "power3.inOut" }, 1.4);
  timeline.to(
    [rearOne, rearTwo],
    { scale: 0.75, opacity: 0, duration: 0.8, ease: "power3.inOut" },
    1.4,
  );
  timeline.to(logo, { opacity: 1, duration: 0.17, ease: "power1.out" }, 2.03);
  timeline.set(root, { "--finale-complete": 1 }, 2.4);
  root.setAttribute("data-finale-timeline-created", "");
  observer.observe(root);
  root.dispatchEvent(
    new CustomEvent<FinaleBookendControl>(finaleBookendReadyEventName, {
      bubbles: true,
      detail: {
        duration: 2.4,
        pause: (): void => {
          timeline?.pause();
        },
        seek: (seconds: number): void => {
          manualSeek = true;
          timeline?.pause().time(seconds);
          manualSeek = false;
        },
        finish: settle,
      },
    }),
  );

  return (): void => {
    observer.disconnect();
    resizeObserver.disconnect();
    lifecycle.abort();
    timeline?.kill();
  };
}
