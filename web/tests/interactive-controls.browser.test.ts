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

afterEach(() => {
  for (const fixture of fixtures.splice(0)) {
    fixture.remove();
  }
  vi.restoreAllMocks();
});

describe("interactive website controllers", () => {
  it("leaves visitor-controlled videos out of scroll autoplay", () => {
    const fixture = addFixture(`<video data-session-restore-video></video>`);
    const play = vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue();
    const controller = createScrollAutoplayVideoController(fixture);

    controller.synchronize(1, true);

    expect(play).not.toHaveBeenCalled();
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
    const parallelSelector = requiredButton(root, '[data-product-plate-selector="parallel-work"]');
    const watchSelector = requiredButton(root, '[data-product-plate-selector="watch-folder"]');
    const reviewSelector = requiredButton(root, '[data-product-plate-selector="review"]');

    expect(root.dataset["enhanced"]).toBe("true");
    expect(selectorGroup.getAttribute("role")).toBe("tablist");
    expect(parallelSelector.getAttribute("aria-selected")).toBe("true");

    requiredButton(root, "[data-product-plate-next]").click();

    expect(watchSelector.getAttribute("aria-selected")).toBe("true");
    expect(requiredHtmlElement(root, '[data-product-plate-panel="watch-folder"]').hidden).toBe(
      false,
    );
    expect(requiredHtmlElement(root, '[data-product-plate-panel="parallel-work"]').hidden).toBe(
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
