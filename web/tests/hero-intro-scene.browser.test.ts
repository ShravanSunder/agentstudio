import { gsap } from "gsap";
import { describe, expect, it } from "vitest";

import { buildHeroIntroScene } from "../src/hero-intro/hero-intro-scene";

describe("hero intro scene contract", () => {
  it("seeks to the CSS-owned final window and stack without moving their layout", () => {
    const fixtureStyle = document.createElement("style");
    fixtureStyle.textContent = `
      [data-hero-intro-fixture] { position: relative; width: 1000px; height: 700px; }
      [data-hero-intro-fixture] [data-hero-icon-stack] { position: absolute; left: 24px; top: 120px; width: 260px; height: 165px; }
      [data-hero-intro-fixture] [data-hero-icon-front],
      [data-hero-intro-fixture] [data-hero-icon-rear] { position: absolute; width: 260px; height: 165px; }
      [data-hero-intro-fixture] [data-hero-terminal-window] { position: absolute; left: 60px; top: 160px; width: 900px; height: 365px; border: 1px solid #89b4fa; border-radius: 16px; }
      [data-hero-intro-fixture] [data-hero-intro-spinner] { opacity: 0; }
    `;
    const fixture = document.createElement("section");
    fixture.setAttribute("data-hero-intro-fixture", "");
    fixture.innerHTML = `
      <p><span data-hero-intro-eyebrow-settled>Native macOS.</span></p>
      <h1 data-hero-intro-copy><span data-hero-intro-headline-first>One</span><span data-hero-intro-headline-second>window</span><span data-hero-intro-payoff-first>Stay oriented.</span><span data-hero-intro-payoff-second> Miss nothing.</span></h1>
      <div data-hero-icon-stack>
        <div data-hero-icon-rear="one"></div><div data-hero-icon-rear="two"></div>
        <div data-hero-icon-front><span data-hero-icon-cursor>_</span></div>
      </div>
      <div data-hero-terminal-window><div data-hero-intro-content>
        <div class="hero-transcript-row hero-transcript-row--user-band">set up Agent Studio</div>
        <div class="hero-transcript-row hero-transcript-row--tool-result" data-hero-intro-ready>Ready. Copy it below <span data-hero-intro-ready-arrow>↓</span></div>
        <div data-hero-intro-spinner>Brewing</div><span data-hero-intro-typed-input></span>
        <div class="hero-codex-footer">Ask Codex</div>
      </div></div>
      <div data-hero-intro-install><code><span>$ brew tap ShravanSunder/agentstudio<span data-install-decode-line aria-hidden="true"></span></span><span>$ brew install --cask agent-studio<span data-install-decode-line aria-hidden="true"></span></span></code><button data-install-copy>COPY</button></div><p data-hero-intro-description>Description</p>
      <div data-hero-intro-glow></div>
    `;
    document.head.append(fixtureStyle);
    document.body.append(fixture);
    try {
      const windowNode = fixture.querySelector<HTMLElement>("[data-hero-terminal-window]");
      const stack = fixture.querySelector<HTMLElement>("[data-hero-icon-stack]");
      if (windowNode === null || stack === null) throw new Error("Hero fixture is incomplete");
      const settledWindow = windowNode.getBoundingClientRect();
      const settledStack = stack.getBoundingClientRect();
      const timeline = gsap.timeline({ paused: true });
      buildHeroIntroScene(fixture, timeline, { width: 1600, height: 1000, seed: 0 });
      expect(timeline.paused()).toBe(true);
      expect(
        Object.keys(timeline.labels).filter((label) => label.startsWith("beat:")).length,
      ).toBeLessThanOrEqual(9);
      const tweenStarts = timeline
        .getChildren(false, true, false)
        .map((child) => child.startTime());
      expect(tweenStarts.filter((start) => start > 2.4 && start < 2.6)).toEqual([]);
      expect(tweenStarts.filter((start) => start > 5.0 && start < 5.6)).toEqual([]);
      timeline.time(0.3);
      expect(
        fixture.querySelector("[data-hero-intro-eyebrow-typed], [data-hero-intro-eyebrow-cursor]"),
      ).toBeNull();
      const headlineFirst = fixture.querySelector<HTMLElement>("[data-hero-intro-headline-first]");
      const payoffFirst = fixture.querySelector<HTMLElement>("[data-hero-intro-payoff-first]");
      if (headlineFirst === null || payoffFirst === null)
        throw new Error("Hero text targets are missing");
      expect(Number(getComputedStyle(headlineFirst).opacity)).toBeGreaterThan(0);
      timeline.time(5.8);
      expect(Number(getComputedStyle(payoffFirst).opacity)).toBe(0);
      timeline.time(6.8);
      for (const payoff of fixture.querySelectorAll<HTMLElement>(
        "[data-hero-intro-payoff-first], [data-hero-intro-payoff-second]",
      )) {
        expect(Number(getComputedStyle(payoff).opacity)).toBeCloseTo(1, 1);
      }
      const fourth = fixture.querySelector<HTMLElement>("[data-hero-intro-fourth-plane]");
      if (fourth === null) throw new Error("Fourth plane missing");
      const planeLefts = [1.45, 1.65, 1.9, 2.2].map((time) => {
        timeline.time(time);
        return fourth.getBoundingClientRect().left;
      });
      expect(planeLefts).toEqual([...planeLefts].sort((left, right) => left - right));
      for (const second of [0, 3.5, 4.2, 4.6, 5.6]) {
        timeline.time(second);
        expect(windowNode.getBoundingClientRect().height, `window height at ${second}s`).toBe(
          settledWindow.height,
        );
      }
      timeline.time(4.2);
      const spinner = fixture.querySelector<HTMLElement>("[data-hero-intro-spinner]");
      expect(spinner === null ? "missing" : getComputedStyle(spinner).display).not.toBe("none");
      const arrow = fixture.querySelector<HTMLElement>("[data-hero-intro-ready-arrow]");
      const install = fixture.querySelector<HTMLElement>("[data-hero-intro-install]");
      const glow = fixture.querySelector<HTMLElement>("[data-hero-intro-glow]");
      if (arrow === null || install === null || glow === null)
        throw new Error("Intro timing targets are missing");
      timeline.time(4.55);
      expect(Number(getComputedStyle(arrow).opacity)).toBeCloseTo(0.35, 1);
      timeline.time(4.7);
      expect(Number(getComputedStyle(install).opacity)).toBeCloseTo(1, 1);
      expect(getComputedStyle(install).transform).toBe("none");
      timeline.time(4.75);
      expect(Number(getComputedStyle(arrow).opacity)).toBeCloseTo(1, 1);
      timeline.time(5.3);
      const overlays = [...fixture.querySelectorAll<HTMLElement>("[data-install-decode-line]")];
      expect(overlays.every((line) => Number(getComputedStyle(line).opacity) === 0)).toBe(true);
      expect(overlays.map((line) => line.parentElement?.textContent).join(" ")).toContain(
        "brew tap ShravanSunder/agentstudio",
      );
      for (const second of [0, 4.6, 4.9, 5.2, 5.3, 6.8]) {
        timeline.time(second);
        expect(install.textContent).toContain("brew tap ShravanSunder/agentstudio");
        expect(getComputedStyle(install).transform).toBe("none");
      }
      timeline.time(5.0);
      expect(Number(getComputedStyle(glow).opacity)).toBeCloseTo(1, 1);
      timeline.time(5.6);
      const sceneWindow = windowNode.getBoundingClientRect();
      const sceneStack = stack.getBoundingClientRect();
      for (const [actual, expected] of [
        [sceneWindow, settledWindow],
        [sceneStack, settledStack],
      ] as const) {
        expect(Math.abs(actual.left - expected.left)).toBeLessThanOrEqual(1);
        expect(Math.abs(actual.top - expected.top)).toBeLessThanOrEqual(1);
        expect(Math.abs(actual.width - expected.width)).toBeLessThanOrEqual(1);
        expect(Math.abs(actual.height - expected.height)).toBeLessThanOrEqual(1);
      }
      timeline.kill();
    } finally {
      fixture.remove();
      fixtureStyle.remove();
    }
  });
});
