// Relative imports keep this module loadable by the Vitest unit project.
import { kitTypedAttribute, scenePartSelector } from "../../recreation-kit/recreation-kit-dom";
import { createSeededRandom, type SceneTimeline } from "../scene-contract";

/** Thrown before any tween exists when scene markup lacks a part a module needs. */
export class ScenePartMissingError extends Error {
  constructor(readonly scenePart: string) {
    super(`Scene markup is missing part "${scenePart}".`);
    this.name = "ScenePartMissingError";
  }
}

export function requireScenePart(root: HTMLElement, scenePart: string): HTMLElement {
  const element = root.querySelector(scenePartSelector(scenePart));
  if (!(element instanceof HTMLElement)) {
    throw new ScenePartMissingError(scenePart);
  }
  return element;
}

/** Terminal lines in document order, read from the kit's data-line markup. */
export function requireTerminalLines(
  terminal: HTMLElement,
  scenePart: string,
  minimumLineCount: number,
): readonly HTMLElement[] {
  const lines = Array.from(terminal.querySelectorAll<HTMLElement>("[data-line]"));
  if (lines.length < minimumLineCount) {
    throw new ScenePartMissingError(`${scenePart} line ${String(lines.length)}`);
  }
  return lines;
}

export function requireLine(lines: readonly HTMLElement[], lineIndex: number): HTMLElement {
  const line = lines[lineIndex];
  if (line === undefined) {
    throw new ScenePartMissingError(`line ${String(lineIndex)}`);
  }
  return line;
}

interface RevealOptions {
  readonly duration?: number;
  readonly fromY?: number;
  /** Offset as a share of the element's own height; needs no layout read. */
  readonly fromYPercent?: number;
  readonly fromX?: number;
  readonly fromScale?: number;
  readonly ease?: string;
}

interface FadeOptions {
  readonly duration?: number;
  readonly ease?: string;
}

interface VariableTweenProps {
  readonly name: `--scene-${string}`;
  readonly from: number;
  readonly to: number;
  readonly at: number;
  readonly duration: number;
  readonly ease?: string;
}

const hiddenClip = "inset(0% 100% 0% 0%)";
const shownClip = "inset(0% 0% 0% 0%)";

interface TransformOffset {
  x?: number;
  y?: number;
  yPercent?: number;
  scale?: number;
}

// Only the transforms a call asks for are tweened, so untouched elements keep
// no inline transform and the settled frame stays equal to the markup.
function offsetTransform(options: RevealOptions): TransformOffset {
  return {
    ...(options.fromX === undefined ? {} : { x: options.fromX }),
    ...(options.fromY === undefined ? {} : { y: options.fromY }),
    ...(options.fromYPercent === undefined ? {} : { yPercent: options.fromYPercent }),
    ...(options.fromScale === undefined ? {} : { scale: options.fromScale }),
  };
}

function settledTransform(options: RevealOptions): TransformOffset {
  return {
    ...(options.fromX === undefined ? {} : { x: 0 }),
    ...(options.fromY === undefined ? {} : { y: 0 }),
    ...(options.fromYPercent === undefined ? {} : { yPercent: 0 }),
    ...(options.fromScale === undefined ? {} : { scale: 1 }),
  };
}

/**
 * Adds tweens to a host-owned paused timeline. Markup is the settled frame, so
 * every tween is a fromTo that ends on the markup's own values.
 *
 * GSAP renders a fromTo's start values at creation when immediateRender is
 * true. Only an element's first tween may do that; a later tween rendering its
 * start at build time would overwrite the frame at time zero. The builder
 * tracks animated elements so each scene cannot get this wrong per call site.
 */
export class SceneTimelineBuilder {
  private readonly animatedElements = new Set<Element>();
  private readonly animatedVariables = new Set<string>();
  private readonly random: () => number;

  constructor(
    private readonly timeline: SceneTimeline,
    seed: number,
  ) {
    this.random = createSeededRandom(seed);
  }

  label(timelineLabel: string, at: number): void {
    this.timeline.addLabel(timelineLabel, at);
  }

  /** Seeded variation so typing does not look metronomic; same seed, same timeline. */
  vary(baseValue: number, spreadFraction: number): number {
    const offset = (this.random() * 2 - 1) * spreadFraction;
    return Math.round(baseValue * (1 + offset) * 1000) / 1000;
  }

  reveal(element: Element, at: number, options: RevealOptions = {}): number {
    const duration = options.duration ?? 0.35;
    this.timeline.fromTo(
      element,
      { autoAlpha: 0, ...offsetTransform(options) },
      {
        autoAlpha: 1,
        ...settledTransform(options),
        duration,
        ease: options.ease ?? "power2.out",
        immediateRender: this.claimFirstTween(element),
      },
      at,
    );
    return at + duration;
  }

  /**
   * Fades an element out in place. It takes no transform offset: a concealed
   * element's final geometry must stay the markup's, or the settled frame drifts.
   */
  conceal(element: Element, at: number, options: FadeOptions = {}): number {
    const duration = options.duration ?? 0.25;
    this.timeline.fromTo(
      element,
      { autoAlpha: 1 },
      {
        autoAlpha: 0,
        duration,
        ease: options.ease ?? "power2.in",
        immediateRender: this.claimFirstTween(element),
      },
      at,
    );
    return at + duration;
  }

  /** Grows a kit collapsible (grid-template-rows 0fr to 1fr) without reading layout. */
  expand(element: Element, at: number, duration = 0.4): number {
    this.timeline.fromTo(
      element,
      { gridTemplateRows: "0fr", autoAlpha: 0 },
      {
        gridTemplateRows: "1fr",
        autoAlpha: 1,
        duration,
        ease: "power2.inOut",
        immediateRender: this.claimFirstTween(element),
      },
      at,
    );
    return at + duration;
  }

  collapse(element: Element, at: number, duration = 0.4): number {
    this.timeline.fromTo(
      element,
      { gridTemplateRows: "1fr", autoAlpha: 1 },
      {
        gridTemplateRows: "0fr",
        autoAlpha: 0,
        duration,
        ease: "power2.inOut",
        immediateRender: this.claimFirstTween(element),
      },
      at,
    );
    return at + duration;
  }

  /**
   * Types the element's data-kit-typed text one character per step. Reads
   * only textContent, never layout, so the tween list depends on markup alone.
   */
  type(element: Element, at: number, charactersPerSecond: number): number {
    const typedText = element.matches(`[${kitTypedAttribute}]`)
      ? element
      : element.querySelector(`[${kitTypedAttribute}]`);
    if (typedText === null) {
      throw new ScenePartMissingError(`typed text in ${element.tagName.toLowerCase()}`);
    }
    const characterCount = Math.max(1, (typedText.textContent ?? "").trim().length);
    const duration = Math.round((characterCount / charactersPerSecond) * 1000) / 1000;
    this.timeline.fromTo(
      typedText,
      { clipPath: hiddenClip },
      {
        clipPath: shownClip,
        duration,
        ease: `steps(${String(characterCount)})`,
        immediateRender: this.claimFirstTween(typedText),
      },
      at,
    );
    return at + duration;
  }

  /** Shows a terminal line, then types its text; returns when typing ends. */
  showAndTypeLine(line: Element, at: number, charactersPerSecond: number): number {
    this.reveal(line, at, { duration: 0.05, ease: "none" });
    return this.type(line, at + 0.1, this.vary(charactersPerSecond, 0.15));
  }

  /**
   * Tweens a scene-level CSS custom property on the scene root. Scene CSS maps
   * one progress value to different visuals in the desktop and phone layouts.
   */
  variable(root: HTMLElement, props: VariableTweenProps): number {
    this.timeline.fromTo(
      root,
      { [props.name]: props.from },
      {
        [props.name]: props.to,
        duration: props.duration,
        ease: props.ease ?? "power2.inOut",
        immediateRender: this.claimFirstTween(root, props.name),
      },
      props.at,
    );
    return props.at + props.duration;
  }

  /** Extends the timeline so the settled frame holds before the host loops. */
  holdUntil(totalDuration: number): void {
    const remaining = totalDuration - this.timeline.duration();
    if (remaining > 0) {
      this.timeline.to({}, { duration: remaining }, this.timeline.duration());
    }
  }

  private claimFirstTween(element: Element, variableName?: string): boolean {
    if (variableName !== undefined) {
      const isFirst = !this.animatedVariables.has(variableName);
      this.animatedVariables.add(variableName);
      return isFirst;
    }
    const isFirst = !this.animatedElements.has(element);
    this.animatedElements.add(element);
    return isFirst;
  }
}
