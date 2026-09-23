import { afterEach, describe, expect, it, vi } from "vitest";

import { initializeChapterSteps } from "../src/chapters/chapter-step-controller";
import {
  chapterStepRequestedEventName,
  readChapterStepEventStepId,
} from "../src/chapters/chapter-step-events";

const fixtures: HTMLElement[] = [];
const stepIds = ["task-drawers", "git-context", "files"] as const;

function requiredHtmlElement(parent: ParentNode, selector: string): HTMLElement {
  const element = parent.querySelector(selector);
  if (!(element instanceof HTMLElement)) {
    throw new Error(`Chapter step fixture is missing required element: ${selector}`);
  }
  return element;
}

function requiredButton(parent: ParentNode, selector: string): HTMLButtonElement {
  const element = parent.querySelector(selector);
  if (!(element instanceof HTMLButtonElement)) {
    throw new Error(`Chapter step fixture is missing required button: ${selector}`);
  }
  return element;
}

// Mirrors ChapterSurface's static markup: the first step is shown, selectors are
// disabled and carry no tab semantics until the controller validates the DOM.
function createChapterStepsFixture(): HTMLElement {
  const fixture = document.createElement("div");
  fixture.innerHTML = `
    <section data-chapter-steps-root="context-with-task">
      <div data-chapter-step-list>
        ${stepIds
          .map(
            (stepId, index) => `
              <button
                type="button"
                data-chapter-step="${stepId}"
                data-step-state="${index === 0 ? "current" : "upcoming"}"
                disabled
                tabindex="-1"
              >${stepId}</button>`,
          )
          .join("")}
      </div>
      ${stepIds
        .map(
          (stepId, index) =>
            `<div data-chapter-step-panel="${stepId}" ${index === 0 ? "" : "hidden"}>${stepId} copy</div>`,
        )
        .join("")}
      <div data-scene-root="chapter-context-with-task"></div>
    </section>
  `;
  document.body.append(fixture);
  fixtures.push(fixture);
  return requiredHtmlElement(fixture, "[data-chapter-steps-root]");
}

function selectedStepId(root: HTMLElement): string | undefined {
  return (
    root.querySelector<HTMLElement>('[data-chapter-step][aria-selected="true"]')?.dataset[
      "chapterStep"
    ] ?? undefined
  );
}

function reportSceneStep(root: HTMLElement, stepId: string): void {
  requiredHtmlElement(root, "[data-scene-root]").dispatchEvent(
    new CustomEvent("agentstudio:scene-step-reached", { bubbles: true, detail: { stepId } }),
  );
}

afterEach(() => {
  for (const fixture of fixtures.splice(0)) {
    fixture.remove();
  }
  vi.restoreAllMocks();
});

describe("chapter step tabs", () => {
  it("enhances the static steps into a vertical tablist with synchronized panels", () => {
    const root = createChapterStepsFixture();
    const list = requiredHtmlElement(root, "[data-chapter-step-list]");
    const firstStep = requiredButton(root, '[data-chapter-step="task-drawers"]');

    expect(firstStep.disabled).toBe(true);
    expect(list.hasAttribute("role")).toBe(false);

    const controller = initializeChapterSteps(root);

    expect(root.dataset["enhanced"]).toBe("true");
    expect(list.getAttribute("role")).toBe("tablist");
    expect(list.getAttribute("aria-orientation")).toBe("vertical");
    expect(firstStep.getAttribute("role")).toBe("tab");
    expect(firstStep.getAttribute("aria-selected")).toBe("true");
    expect(firstStep.tabIndex).toBe(0);
    const firstPanel = requiredHtmlElement(root, '[data-chapter-step-panel="task-drawers"]');
    expect(firstPanel.getAttribute("role")).toBe("tabpanel");
    expect(firstPanel.getAttribute("aria-labelledby")).toBe(firstStep.id);
    expect(firstStep.getAttribute("aria-controls")).toBe(firstPanel.id);

    controller.destroy();

    expect(root.dataset["enhanced"]).toBe("false");
    expect(list.hasAttribute("role")).toBe(false);
    expect(firstStep.disabled).toBe(true);
  });

  it("selects a clicked step, shows its panel, and asks the scene to seek there", () => {
    const root = createChapterStepsFixture();
    const requestedSteps: string[] = [];
    root.addEventListener(chapterStepRequestedEventName, (event: Event): void => {
      requestedSteps.push(readChapterStepEventStepId(event) ?? "unreadable");
    });
    const controller = initializeChapterSteps(root);

    requiredButton(root, '[data-chapter-step="git-context"]').click();

    expect(selectedStepId(root)).toBe("git-context");
    expect(requiredHtmlElement(root, '[data-chapter-step-panel="git-context"]').hidden).toBe(false);
    expect(requiredHtmlElement(root, '[data-chapter-step-panel="task-drawers"]').hidden).toBe(true);
    expect(
      requiredHtmlElement(root, '[data-chapter-step="task-drawers"]').dataset["stepState"],
    ).toBe("passed");
    expect(requiredHtmlElement(root, '[data-chapter-step="files"]').dataset["stepState"]).toBe(
      "upcoming",
    );
    expect(requestedSteps).toEqual(["git-context"]);

    controller.destroy();
  });

  it("moves selection and focus with arrow, Home, and End keys", () => {
    const root = createChapterStepsFixture();
    const list = requiredHtmlElement(root, "[data-chapter-step-list]");
    const controller = initializeChapterSteps(root);
    const pressKey = (key: string): void => {
      list.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key }));
    };

    requiredButton(root, '[data-chapter-step="task-drawers"]').focus();
    pressKey("ArrowDown");
    expect(selectedStepId(root)).toBe("git-context");
    expect(document.activeElement).toBe(requiredButton(root, '[data-chapter-step="git-context"]'));

    pressKey("End");
    expect(selectedStepId(root)).toBe("files");
    expect(document.activeElement).toBe(requiredButton(root, '[data-chapter-step="files"]'));

    pressKey("ArrowDown");
    expect(selectedStepId(root)).toBe("task-drawers");

    pressKey("ArrowUp");
    expect(selectedStepId(root)).toBe("files");

    pressKey("Home");
    expect(selectedStepId(root)).toBe("task-drawers");
    expect(requiredButton(root, '[data-chapter-step="files"]').tabIndex).toBe(-1);

    controller.destroy();
  });

  it("follows scene progress without moving focus and keeps the last valid step", () => {
    const root = createChapterStepsFixture();
    const requestedSteps: string[] = [];
    root.addEventListener(chapterStepRequestedEventName, (): void => {
      requestedSteps.push("requested");
    });
    const controller = initializeChapterSteps(root);
    const outsideButton = document.createElement("button");
    document.body.append(outsideButton);
    outsideButton.focus();

    reportSceneStep(root, "files");
    expect(selectedStepId(root)).toBe("files");
    expect(document.activeElement).toBe(outsideButton);

    reportSceneStep(root, "not-a-step");
    expect(selectedStepId(root)).toBe("files");

    reportSceneStep(root, "review-diff");
    expect(selectedStepId(root)).toBe("files");
    expect(requestedSteps).toEqual([]);

    outsideButton.remove();
    controller.destroy();
  });

  it("keeps the static contract when the markup is incomplete", () => {
    const root = createChapterStepsFixture();
    requiredHtmlElement(root, '[data-chapter-step-panel="files"]').remove();
    vi.spyOn(console, "error").mockImplementation((): void => undefined);

    initializeChapterSteps(root);

    expect(root.dataset["enhanced"]).toBe("false");
    expect(requiredButton(root, '[data-chapter-step="task-drawers"]').disabled).toBe(true);
    expect(requiredHtmlElement(root, "[data-chapter-step-list]").hasAttribute("role")).toBe(false);
  });
});
