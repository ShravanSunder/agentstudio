import { defineBrowserCommand } from "@vitest/browser-playwright";

interface FinaleSample {
  readonly time: number | "settled";
  readonly firstLine: number;
  readonly secondLine: number;
  readonly firstPayoff: number;
  readonly secondPayoff: number;
  readonly payoffOverflow: number;
  readonly installTransform: string;
  readonly installOpacity: number;
  readonly realCommandLines: readonly string[];
  readonly visibleDecodeLines: number;
  readonly copyOpacity: number;
  readonly railClip: string;
  readonly railRevealY: number;
  readonly heroNodeY: number;
  readonly introDotOpacities: readonly number[];
  readonly heroBranchDashOffset: number;
  readonly forkDashOffsets: readonly number[];
  readonly rowOpacity: readonly number[];
  readonly appTop: number;
  readonly windowHeight: number;
  readonly chapterNodeY: number;
}

export interface FinaleObservation {
  readonly samples: readonly FinaleSample[];
  readonly resizeRailClip: string;
  readonly resizeRailStyle: string | null;
  readonly resizeSceneInlineStyles: number;
  readonly resizeRailIntroMarkers: number;
  readonly skipRailClip: string;
  readonly skipFinaleOpacity: readonly number[];
  readonly skipSceneInlineStyles: number;
  readonly skipRailIntroMarkers: number;
  readonly reducedRailClip: string;
  readonly reducedFinaleOpacity: readonly number[];
  readonly reducedRailIntroMarkers: number;
}

export const verifyHeroIntroFinale = defineBrowserCommand(
  async (
    { context },
    pageUrl: string,
    width: number,
    height: number,
  ): Promise<FinaleObservation> => {
    const page = await context.newPage();
    const reducedPage = await context.newPage();
    try {
      await page.setViewportSize({ width, height });
      await page.addInitScript(() => {
        Object.defineProperty(document, "hidden", { configurable: true, get: () => false });
        Object.defineProperty(document, "visibilityState", {
          configurable: true,
          get: () => "visible",
        });
        let resolveReady: (control: {
          pause(): void;
          seek(seconds: number): void;
          finish(): void;
        }) => void = () => {};
        const ready = new Promise<{ pause(): void; seek(seconds: number): void; finish(): void }>(
          (resolve) => {
            resolveReady = resolve;
          },
        );
        (window as Window & { finaleReady?: typeof ready }).finaleReady = ready;
        document.addEventListener("hero-intro-playback-ready", (event) => {
          if (!(event instanceof CustomEvent)) return;
          const control = event.detail as Awaited<typeof ready>;
          control.pause();
          resolveReady(control);
        });
      });
      await page.goto(pageUrl, { waitUntil: "commit" });
      await page.evaluate(
        async () => await (window as Window & { finaleReady?: Promise<unknown> }).finaleReady,
      );
      await page.waitForSelector('[data-topology-chapter-node="many-agents"] circle', {
        state: "attached",
      });
      const samples = await page.evaluate(async (): Promise<FinaleSample[]> => {
        await document.fonts.ready;
        const control = await (
          window as Window & {
            finaleReady?: Promise<{ seek(seconds: number): void; finish(): void }>;
          }
        ).finaleReady;
        if (control === undefined) throw new Error("Finale control missing");
        const observe = (time: number | "settled"): FinaleSample => {
          const root = document.querySelector<HTMLElement>("[data-hero-intro-root]");
          const rail = document.querySelector<SVGSVGElement>("[data-full-page-topology]");
          const app = document.querySelector<HTMLElement>("[data-hero-app-frame]");
          const windowNode = root?.querySelector<HTMLElement>("[data-hero-terminal-window]");
          const chapterNode = rail?.querySelector<SVGCircleElement>(
            '[data-topology-chapter-node="many-agents"] circle',
          );
          if (
            root === null ||
            rail === null ||
            app === null ||
            windowNode === null ||
            windowNode === undefined ||
            chapterNode === null ||
            chapterNode === undefined
          )
            throw new Error("Finale geometry missing");
          const target = (selector: string): HTMLElement => {
            const element = root.querySelector<HTMLElement>(selector);
            if (element === null) throw new Error(`Finale target missing: ${selector}`);
            return element;
          };
          const opacity = (selector: string): number =>
            Number(getComputedStyle(target(selector)).opacity);
          const pane = innerWidth < 1024 ? "claude" : "codex";
          const railClip = getComputedStyle(rail).clipPath;
          const bottomInset = /([\d.]+)%\)/u.exec(railClip);
          const heroNode = rail.querySelector<SVGGElement>('[data-topology-chapter-node="hero"]');
          const heroBranch = rail.querySelector<SVGPathElement>(
            '[data-route-anchor="hero"] [data-topology-path-role="core"]',
          );
          const heroNodeY = Number(heroNode?.querySelector("circle")?.getAttribute("cy"));
          const branchStartY = heroBranch?.getPointAtLength(0).y ?? Number.NaN;
          const introNodes = [
            ...rail.querySelectorAll<SVGGElement>("[data-topology-node-progress]"),
          ]
            .filter((node) => {
              const y = Number(node.querySelector("circle")?.getAttribute("cy"));
              return y >= heroNodeY && y <= branchStartY;
            })
            .sort(
              (left, right) =>
                Number(left.querySelector("circle")?.getAttribute("cy")) -
                Number(right.querySelector("circle")?.getAttribute("cy")),
            );
          const install = target("[data-hero-intro-install]");
          const payoff = target("[data-hero-intro-payoff-first]").parentElement;
          if (payoff === null) throw new Error("Payoff wrapper missing");
          const realCommandLines = [
            ...install.querySelectorAll<HTMLElement>(".install-command__line"),
          ].map((line) =>
            [...line.childNodes]
              .filter(
                (node) =>
                  !(node instanceof HTMLElement && node.hasAttribute("data-install-decode-line")),
              )
              .map((node) => node.textContent ?? "")
              .join(""),
          );
          return {
            time,
            firstLine: opacity("[data-hero-intro-headline-first]"),
            secondLine: opacity("[data-hero-intro-headline-second]"),
            firstPayoff: opacity("[data-hero-intro-payoff-first]"),
            secondPayoff: opacity("[data-hero-intro-payoff-second]"),
            payoffOverflow: payoff.scrollWidth - payoff.clientWidth,
            installTransform: getComputedStyle(install).transform,
            installOpacity: Number(getComputedStyle(install).opacity),
            realCommandLines,
            visibleDecodeLines: [
              ...install.querySelectorAll<HTMLElement>("[data-install-decode-line]"),
            ].filter((line) => Number(getComputedStyle(line).opacity) > 0.05).length,
            copyOpacity: Number(getComputedStyle(target("[data-install-copy]")).opacity),
            railClip,
            heroNodeY: rail.getBoundingClientRect().top + heroNodeY,
            introDotOpacities: introNodes.map((node) => Number(getComputedStyle(node).opacity)),
            heroBranchDashOffset:
              heroBranch === null
                ? Number.NaN
                : Number.parseFloat(getComputedStyle(heroBranch).strokeDashoffset),
            forkDashOffsets: [
              ...rail.querySelectorAll<SVGPathElement>(
                '[data-route-kind="worktree"] [data-topology-path-role="core"]',
              ),
            ]
              .filter((path) => path.getPointAtLength(0).y <= branchStartY)
              .map((path) => Number.parseFloat(getComputedStyle(path).strokeDashoffset)),
            railRevealY:
              bottomInset === null
                ? Number.POSITIVE_INFINITY
                : rail.getBoundingClientRect().top +
                  rail.getBoundingClientRect().height * (1 - Number(bottomInset[1]) / 100),
            rowOpacity: [
              ...root.querySelectorAll<HTMLElement>(
                `.hero-terminal-pane--${pane} [data-hero-intro-finale-row]`,
              ),
            ].map((row) => Number(getComputedStyle(row).opacity)),
            appTop: app.getBoundingClientRect().top,
            windowHeight: windowNode.getBoundingClientRect().height,
            chapterNodeY: rail.getBoundingClientRect().top + Number(chapterNode.getAttribute("cy")),
          };
        };
        const observations: FinaleSample[] = [];
        for (const second of [
          0, 0.2, 0.3, 0.45, 0.8, 0.9, 1.5, 2.2, 2.5, 3.2, 3.5, 4.3, 4.9, 5.2, 5.4, 5.5, 5.8, 5.85,
          6.1, 6.25, 6.4, 6.5, 6.63, 6.75, 6.8, 7.0,
        ]) {
          control.seek(second);
          observations.push(observe(second));
        }
        control.finish();
        observations.push(observe("settled"));
        return observations;
      });
      await page.reload({ waitUntil: "commit" });
      await page.evaluate(
        async () => await (window as Window & { finaleReady?: Promise<unknown> }).finaleReady,
      );
      await page.evaluate(async () =>
        (
          await (window as Window & { finaleReady?: Promise<{ seek(seconds: number): void }> })
            .finaleReady
        )?.seek(6.4),
      );
      await page.setViewportSize({ width: width < 1024 ? 430 : 1200, height });
      await page.waitForSelector('[data-hero-intro-state="settled"]');
      const resize = await page.evaluate(() => {
        const rail = document.querySelector<SVGSVGElement>("[data-full-page-topology]");
        if (rail === null) throw new Error("Resized rail missing");
        const sceneTargets = document.querySelectorAll<HTMLElement>(
          "[data-hero-intro-eyebrow-settled], [data-hero-intro-headline-first], [data-hero-intro-headline-second], [data-hero-intro-payoff-first], [data-hero-intro-payoff-second], [data-hero-intro-finale-row]",
        );
        return {
          clip: getComputedStyle(rail).clipPath,
          style: rail.getAttribute("style"),
          sceneInlineStyles: [...sceneTargets].filter((target) => target.hasAttribute("style"))
            .length,
          introMarkers: rail.querySelectorAll(
            "[data-hero-intro-rail-node], [data-hero-intro-rail-path]",
          ).length,
        };
      });
      await page.reload({ waitUntil: "commit" });
      await page.evaluate(
        async () => await (window as Window & { finaleReady?: Promise<unknown> }).finaleReady,
      );
      await page.evaluate(async () =>
        (
          await (window as Window & { finaleReady?: Promise<{ seek(seconds: number): void }> })
            .finaleReady
        )?.seek(6.4),
      );
      await page.keyboard.press("Escape");
      await page.waitForSelector('[data-hero-intro-state="settled"]');
      const skipped = await page.evaluate(() => {
        const rail = document.querySelector<SVGSVGElement>("[data-full-page-topology]");
        if (rail === null) throw new Error("Skipped rail missing");
        const pane = innerWidth < 1024 ? "claude" : "codex";
        return {
          clip: getComputedStyle(rail).clipPath,
          rowOpacity: [
            ...document.querySelectorAll<HTMLElement>(
              `.hero-terminal-pane--${pane} [data-hero-intro-finale-row]`,
            ),
          ].map((row) => Number(getComputedStyle(row).opacity)),
          sceneInlineStyles: document.querySelectorAll(
            "[data-hero-intro-eyebrow-settled][style], [data-hero-intro-headline-first][style], [data-hero-intro-headline-second][style], [data-hero-intro-payoff-first][style], [data-hero-intro-payoff-second][style], [data-hero-intro-finale-row][style]",
          ).length,
          introMarkers: rail.querySelectorAll(
            "[data-hero-intro-rail-node], [data-hero-intro-rail-path]",
          ).length,
        };
      });
      await reducedPage.emulateMedia({ reducedMotion: "reduce" });
      await reducedPage.setViewportSize({ width, height });
      await reducedPage.goto(pageUrl, { waitUntil: "domcontentloaded" });
      const reduced = await reducedPage.evaluate(() => {
        const rail = document.querySelector<SVGSVGElement>("[data-full-page-topology]");
        if (rail === null) throw new Error("Reduced-motion rail missing");
        const pane = innerWidth < 1024 ? "claude" : "codex";
        return {
          clip: getComputedStyle(rail).clipPath,
          rowOpacity: [
            ...document.querySelectorAll<HTMLElement>(
              `.hero-terminal-pane--${pane} [data-hero-intro-finale-row]`,
            ),
          ].map((row) => Number(getComputedStyle(row).opacity)),
          introMarkers: rail.querySelectorAll(
            "[data-hero-intro-rail-node], [data-hero-intro-rail-path]",
          ).length,
        };
      });
      return {
        samples,
        resizeRailClip: resize.clip,
        resizeRailStyle: resize.style,
        resizeSceneInlineStyles: resize.sceneInlineStyles,
        resizeRailIntroMarkers: resize.introMarkers,
        skipRailClip: skipped.clip,
        skipFinaleOpacity: skipped.rowOpacity,
        skipSceneInlineStyles: skipped.sceneInlineStyles,
        skipRailIntroMarkers: skipped.introMarkers,
        reducedRailClip: reduced.clip,
        reducedFinaleOpacity: reduced.rowOpacity,
        reducedRailIntroMarkers: reduced.introMarkers,
      };
    } finally {
      await page.close();
      await reducedPage.close();
    }
  },
);
