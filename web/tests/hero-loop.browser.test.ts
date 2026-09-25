import { afterEach, describe, expect, it, vi } from "vitest";

import { initializeHeroLoop } from "../src/home-page/hero-loop-controller";

const fixtures: HTMLElement[] = [];

function stubReducedMotion(reduced: boolean): void {
  vi.spyOn(window, "matchMedia").mockImplementation(
    (query): MediaQueryList =>
      ({
        addEventListener: vi.fn(),
        addListener: vi.fn(),
        dispatchEvent: vi.fn(() => true),
        matches: reduced && query === "(prefers-reduced-motion: reduce)",
        media: query,
        onchange: null,
        removeEventListener: vi.fn(),
        removeListener: vi.fn(),
      }) satisfies MediaQueryList,
  );
}

interface HeroLoopFixture {
  readonly paused: () => boolean;
  readonly playSpy: ReturnType<typeof vi.spyOn>;
  readonly root: HTMLElement;
  readonly toggle: HTMLButtonElement;
  readonly video: HTMLVideoElement;
}

// A muted loop whose play/pause are observable without decoding real media.
function createHeroLoopFixture(): HeroLoopFixture {
  const fixture = document.createElement("div");
  fixture.innerHTML = `
    <div data-hero-loop>
      <video data-hero-loop-video muted loop playsinline poster="poster.jpg"></video>
      <button
        type="button"
        data-hero-loop-toggle
        data-pause-label="Pause video"
        data-play-label="Play video"
        aria-label="Play video"
        hidden
      ></button>
    </div>
  `;
  document.body.append(fixture);
  fixtures.push(fixture);
  const root = fixture.querySelector<HTMLElement>("[data-hero-loop]");
  const video = fixture.querySelector("video");
  const toggle = fixture.querySelector("button");
  if (root === null || video === null || toggle === null) {
    throw new Error("Hero loop fixture is incomplete");
  }
  let videoPaused = true;
  Object.defineProperty(video, "paused", { configurable: true, get: (): boolean => videoPaused });
  const playSpy = vi.spyOn(video, "play").mockImplementation((): Promise<void> => {
    videoPaused = false;
    video.dispatchEvent(new Event("play"));
    return Promise.resolve();
  });
  vi.spyOn(video, "pause").mockImplementation((): void => {
    videoPaused = true;
    video.dispatchEvent(new Event("pause"));
  });
  return { paused: (): boolean => videoPaused, playSpy, root, toggle, video };
}

afterEach(() => {
  for (const fixture of fixtures.splice(0)) {
    fixture.remove();
  }
  vi.restoreAllMocks();
});

describe("hero loop", () => {
  it("plays the muted loop at once and offers a pause control", () => {
    // Arrange
    stubReducedMotion(false);
    const hero = createHeroLoopFixture();

    // Act
    const controller = initializeHeroLoop(hero.root);

    // Assert
    expect(hero.paused()).toBe(false);
    expect(hero.toggle.hidden).toBe(false);
    expect(hero.toggle.getAttribute("aria-label")).toBe("Pause video");
    controller.destroy();
  });

  it("keeps the visitor's pause", () => {
    // Arrange
    stubReducedMotion(false);
    const hero = createHeroLoopFixture();
    const controller = initializeHeroLoop(hero.root);

    // Act
    hero.toggle.click();

    // Assert
    expect(hero.paused()).toBe(true);
    expect(hero.playSpy).toHaveBeenCalledTimes(1);
    expect(hero.toggle.getAttribute("aria-label")).toBe("Play video");
    controller.destroy();
  });

  it("shows the poster under reduced motion and plays only when asked", () => {
    // Arrange
    stubReducedMotion(true);
    const hero = createHeroLoopFixture();
    const controller = initializeHeroLoop(hero.root);

    // Act
    const pausedBeforeRequest = hero.paused();
    hero.toggle.click();

    // Assert
    expect(pausedBeforeRequest).toBe(true);
    expect(hero.toggle.hidden).toBe(false);
    expect(hero.paused()).toBe(false);
    controller.destroy();
  });

  it("hides the control and keeps the poster when the media fails", () => {
    // Arrange
    stubReducedMotion(true);
    const hero = createHeroLoopFixture();
    const controller = initializeHeroLoop(hero.root);

    // Act
    hero.video.dispatchEvent(new Event("error"));

    // Assert
    expect(hero.toggle.hidden).toBe(true);
    expect(hero.video.getAttribute("poster")).toBe("poster.jpg");
    controller.destroy();
  });
});
