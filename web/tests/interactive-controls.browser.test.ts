import { afterEach, describe, expect, it, vi } from "vitest";

import { createScrollAutoplayVideoController } from "../src/home-page/scroll-autoplay-video-controller";
import { initializeInstallCommand } from "../src/install-command/install-command-controller";
import { marketingCopy } from "../src/marketing-copy";
import { initializePersistenceProof } from "../src/product-plate/persistence-proof-controller";
import { productPlateStoryIds } from "../src/product-plate/product-plate-contract";
import { initializeProductPlate } from "../src/product-plate/product-plate-controller";

const fixtures: HTMLElement[] = [];

function requiredHtmlElement(parent: ParentNode, selector: string): HTMLElement {
  const element = parent.querySelector(selector);
  if (!(element instanceof HTMLElement)) {
    throw new Error(`Browser fixture is missing required element: ${selector}`);
  }
  return element;
}

function requiredButton(parent: ParentNode, selector: string): HTMLButtonElement {
  const element = parent.querySelector(selector);
  if (!(element instanceof HTMLButtonElement)) {
    throw new Error(`Browser fixture is missing required button: ${selector}`);
  }
  return element;
}

function addFixture(markup: string): HTMLElement {
  const fixture = document.createElement("div");
  fixture.innerHTML = markup;
  document.body.append(fixture);
  fixtures.push(fixture);
  return fixture;
}

function createProductPlateFixture(): HTMLElement {
  const fixture = addFixture(`
    <section data-product-plate-root>
      <button data-product-plate-previous disabled>Previous</button>
      <div data-product-plate-selectors>
        ${productPlateStoryIds
          .map(
            (storyId) =>
              `<button data-product-plate-selector="${storyId}" disabled>${storyId}</button>`,
          )
          .join("")}
      </div>
      <button data-product-plate-next disabled>Next</button>
      ${productPlateStoryIds
        .map(
          (storyId, index) =>
            `<section data-product-plate-panel="${storyId}" ${index === 0 ? "" : "hidden"}>${storyId}</section>`,
        )
        .join("")}
    </section>
  `);
  return requiredHtmlElement(fixture, "[data-product-plate-root]");
}

interface ControllableVideoFixture {
  readonly finishPlayback: () => void;
  readonly pauseManually: () => void;
  readonly paused: () => boolean;
  readonly playManually: () => void;
  readonly playSpy: ReturnType<typeof vi.spyOn>;
  readonly pauseSpy: ReturnType<typeof vi.spyOn>;
  readonly root: HTMLElement;
}

function createControllableVideoFixture(): ControllableVideoFixture {
  const root = addFixture(`
    <section>
      <video
        data-scroll-autoplay-video
        data-scroll-autoplay-start-progress="0.95"
        data-scroll-autoplay-stop-progress="0.9"
        data-scroll-autoplay-replay-delay-ms="3000"
      ></video>
    </section>
  `);
  const video = root.querySelector("video");
  if (!(video instanceof HTMLVideoElement)) {
    throw new Error("Autoplay fixture is missing its video");
  }

  let videoPaused = true;
  let videoEnded = false;
  Object.defineProperty(video, "paused", {
    configurable: true,
    get: (): boolean => videoPaused,
  });
  Object.defineProperty(video, "ended", {
    configurable: true,
    get: (): boolean => videoEnded,
  });

  const playSpy = vi.spyOn(video, "play").mockImplementation((): Promise<void> => {
    videoPaused = false;
    video.dispatchEvent(new Event("play"));
    return Promise.resolve();
  });
  const pauseSpy = vi.spyOn(video, "pause").mockImplementation((): void => {
    videoPaused = true;
    video.dispatchEvent(new Event("pause"));
  });

  return {
    finishPlayback: (): void => {
      videoPaused = true;
      videoEnded = true;
      video.dispatchEvent(new Event("ended"));
      videoEnded = false;
    },
    pauseManually: (): void => {
      videoPaused = true;
      video.dispatchEvent(new Event("pause"));
    },
    paused: (): boolean => videoPaused,
    playManually: (): void => {
      videoPaused = false;
      video.dispatchEvent(new Event("play"));
    },
    playSpy,
    pauseSpy,
    root,
  };
}

afterEach(() => {
  for (const fixture of fixtures.splice(0)) {
    fixture.remove();
  }
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("interactive website controllers", () => {
  it("starts and stops marked videos with scroll-progress hysteresis", () => {
    const fixture = createControllableVideoFixture();
    const controller = createScrollAutoplayVideoController(fixture.root);

    controller.synchronize(0.94, true);
    expect(fixture.playSpy).not.toHaveBeenCalled();

    controller.synchronize(0.95, true);
    expect(fixture.playSpy).toHaveBeenCalledTimes(1);
    expect(fixture.paused()).toBe(false);

    controller.synchronize(0.92, true);
    expect(fixture.pauseSpy).not.toHaveBeenCalled();

    controller.synchronize(0.89, true);
    expect(fixture.pauseSpy).toHaveBeenCalledTimes(1);
    expect(fixture.paused()).toBe(true);

    controller.synchronize(0.95, true);
    expect(fixture.playSpy).toHaveBeenCalledTimes(2);
    expect(fixture.paused()).toBe(false);

    controller.dispose();
  });

  it("preserves manual video intent until the visitor leaves the autoplay zone", () => {
    const fixture = createControllableVideoFixture();
    const controller = createScrollAutoplayVideoController(fixture.root);

    controller.synchronize(0.95, true);
    fixture.pauseManually();
    controller.synchronize(1, true);
    expect(fixture.playSpy).toHaveBeenCalledTimes(1);
    expect(fixture.paused()).toBe(true);

    controller.synchronize(0.89, true);
    controller.synchronize(0.95, true);
    expect(fixture.playSpy).toHaveBeenCalledTimes(2);

    controller.synchronize(0.89, true);
    fixture.playManually();
    controller.synchronize(0.2, true);
    expect(fixture.pauseSpy).toHaveBeenCalledTimes(1);
    expect(fixture.paused()).toBe(false);

    controller.dispose();
  });

  it("replays a completed autoplay video once after the configured delay", () => {
    vi.useFakeTimers();
    const fixture = createControllableVideoFixture();
    const controller = createScrollAutoplayVideoController(fixture.root);

    controller.synchronize(0.95, true);
    fixture.finishPlayback();

    vi.advanceTimersByTime(2999);
    expect(fixture.playSpy).toHaveBeenCalledTimes(1);

    vi.advanceTimersByTime(1);
    expect(fixture.playSpy).toHaveBeenCalledTimes(2);
    expect(fixture.paused()).toBe(false);

    controller.dispose();
  });

  it("enhances the product stories with synchronized tabs, panels, and keyboard movement", () => {
    vi.spyOn(window, "matchMedia").mockImplementation(
      (query): MediaQueryList =>
        ({
          addEventListener: vi.fn(),
          addListener: vi.fn(),
          dispatchEvent: vi.fn(() => true),
          matches: query === "(prefers-reduced-motion: reduce)",
          media: query,
          onchange: null,
          removeEventListener: vi.fn(),
          removeListener: vi.fn(),
        }) satisfies MediaQueryList,
    );
    const root = createProductPlateFixture();
    const controller = initializeProductPlate(root);
    const selectorGroup = requiredHtmlElement(root, "[data-product-plate-selectors]");
    const watchSelector = requiredButton(root, '[data-product-plate-selector="watch-folder"]');
    const parallelSelector = requiredButton(root, '[data-product-plate-selector="parallel-work"]');
    const reviewSelector = requiredButton(root, '[data-product-plate-selector="review"]');

    expect(root.dataset["enhanced"]).toBe("true");
    expect(selectorGroup.getAttribute("role")).toBe("tablist");
    expect(watchSelector.getAttribute("aria-selected")).toBe("true");

    requiredButton(root, "[data-product-plate-next]").click();

    expect(parallelSelector.getAttribute("aria-selected")).toBe("true");
    expect(requiredHtmlElement(root, '[data-product-plate-panel="parallel-work"]').hidden).toBe(
      false,
    );
    expect(requiredHtmlElement(root, '[data-product-plate-panel="watch-folder"]').hidden).toBe(
      true,
    );

    watchSelector.focus();
    selectorGroup.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "End" }));

    expect(reviewSelector.getAttribute("aria-selected")).toBe("true");
    expect(document.activeElement).toBe(reviewSelector);

    controller.destroy();

    expect(root.dataset["enhanced"]).toBe("false");
    expect(selectorGroup.hasAttribute("role")).toBe(false);
    expect(parallelSelector.disabled).toBe(true);
  });

  it("keeps persistence buttons and frames synchronized", () => {
    const fixture = addFixture(`
      <section data-persistence-proof-root>
        <button data-persistence-proof-button="before">Before</button>
        <button data-persistence-proof-button="restored">Restored</button>
        <div data-persistence-frame="before">Before frame</div>
        <div data-persistence-frame="restored" hidden>Restored frame</div>
      </section>
    `);
    const root = requiredHtmlElement(fixture, "[data-persistence-proof-root]");
    const controller = initializePersistenceProof(root);
    const beforeButton = requiredButton(root, '[data-persistence-proof-button="before"]');
    const restoredButton = requiredButton(root, '[data-persistence-proof-button="restored"]');
    const restoredFrame = requiredHtmlElement(root, '[data-persistence-frame="restored"]');

    expect(beforeButton.getAttribute("aria-pressed")).toBe("true");
    restoredButton.click();

    expect(beforeButton.getAttribute("aria-pressed")).toBe("false");
    expect(restoredButton.getAttribute("aria-pressed")).toBe("true");
    expect(restoredFrame.hidden).toBe(false);

    controller.destroy();
  });

  it("reports copy success and preserves a useful clipboard failure fallback", async () => {
    const fixture = addFixture(`
      <div data-install-root data-install-command="brew install --cask agent-studio">
        <button data-install-copy>Copy</button>
        <span data-install-status></span>
      </div>
    `);
    const root = requiredHtmlElement(fixture, "[data-install-root]");
    const writeText = vi.spyOn(navigator.clipboard, "writeText").mockResolvedValue();
    const dispose = initializeInstallCommand(root);
    const button = requiredButton(root, "[data-install-copy]");
    const status = requiredHtmlElement(root, "[data-install-status]");

    button.click();
    await vi.waitFor(() =>
      expect(status.textContent).toBe(marketingCopy.installation.copiedStatus),
    );
    expect(writeText).toHaveBeenCalledWith("brew install --cask agent-studio");

    writeText.mockRejectedValueOnce(new Error("clipboard unavailable"));
    button.click();
    await vi.waitFor(() =>
      expect(status.textContent).toBe(marketingCopy.installation.failedStatus),
    );

    dispose();
  });
});
