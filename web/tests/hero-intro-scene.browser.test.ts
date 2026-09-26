import { gsap } from "gsap";
import { describe, expect, it } from "vitest";

import { buildHeroIntroScene } from "../src/hero-intro/hero-intro-scene";

describe("hero intro scene contract", () => {
  it("seeks to the CSS-owned final window and stack without moving their layout", () => {
    const fixtureStyle = document.createElement("style");
    fixtureStyle.textContent = `
      [data-hero-intro-fixture] { position: relative; width: 1000px; height: 700px; }
      [data-hero-intro-fixture] [data-hero-icon-stack] { position: absolute; left: 24px; top: 120px; width: 260px; height: 165px; transform: rotate(-2deg); }
      [data-hero-intro-fixture] [data-hero-icon-front],
      [data-hero-intro-fixture] [data-hero-icon-rear] { position: absolute; width: 260px; height: 165px; }
      [data-hero-intro-fixture] [data-hero-terminal-window] { position: absolute; left: 60px; top: 160px; width: 900px; height: 365px; border: 1px solid #89b4fa; border-radius: 16px; }
      [data-hero-intro-fixture] [data-hero-intro-spinner] { display: none; }
    `;
    const fixture = document.createElement("section");
    fixture.setAttribute("data-hero-intro-fixture", "");
    fixture.innerHTML = `
      <h1 data-hero-intro-copy>One window</h1>
      <div data-hero-icon-stack>
        <div data-hero-icon-rear="one"></div><div data-hero-icon-rear="two"></div>
        <div data-hero-icon-front><span data-hero-icon-cursor>_</span></div>
      </div>
      <div data-hero-terminal-window><div data-hero-intro-content>
        <div class="hero-transcript-row hero-transcript-row--user-band">set up Agent Studio</div>
        <div class="hero-transcript-row hero-transcript-row--tool-result" data-hero-intro-ready>Ready.</div>
        <div data-hero-intro-spinner>Brewing</div><span data-hero-intro-typed-input></span>
        <div class="hero-codex-footer">Ask Codex</div>
      </div></div>
      <div data-hero-intro-install>Install</div><p data-hero-intro-description>Description</p>
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
