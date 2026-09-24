import { isChapterStepId, type ChapterStepId } from "./chapter-ids";
import {
  chapterStepRequestedEventName,
  createChapterStepEvent,
  readChapterStepEventStepId,
  sceneStepReachedEventName,
} from "./chapter-step-events";

// Tab semantics follow the retired product plate's proven contract: static and
// disabled until the whole step/panel correspondence validates, then roving
// focus, arrows/Home/End, and aria-selected. Scene progress selects a step
// without moving focus; a visitor's selection asks the scene to seek there.

const stepSelector = "[data-chapter-step]";
/**
 * Below Tailwind's `lg` boundary (`--breakpoint-lg: 64rem`) the chapter glass
 * stacks (title, stage, steps) and the steps render as a horizontal dot row.
 * ChapterSurface.astro styles the row under the same query.
 */
export const chapterStackedLayoutMediaQuery = "(width < 64rem)";

type StepListOrientation = "horizontal" | "vertical";
const panelSelector = "[data-chapter-step-panel]";

export type ChapterStepState = "passed" | "current" | "upcoming";

interface ChapterStepElements {
  readonly panel: HTMLElement;
  readonly selector: HTMLButtonElement;
  readonly stepId: ChapterStepId;
}

interface ChapterStepsDomContract {
  readonly list: HTMLElement;
  readonly root: HTMLElement;
  readonly steps: readonly ChapterStepElements[];
}

export interface ChapterStepsController {
  readonly destroy: () => void;
}

type StepMovement = "first" | "last" | "next" | "previous";

function validateChapterStepsDom(root: HTMLElement): ChapterStepsDomContract {
  const list = root.querySelector<HTMLElement>("[data-chapter-step-list]");
  if (list === null) {
    throw new Error("Chapter steps markup is missing its step list.");
  }
  const selectors = Array.from(list.querySelectorAll(stepSelector));
  const panels = Array.from(root.querySelectorAll<HTMLElement>(panelSelector));
  if (selectors.length === 0 || selectors.length !== panels.length) {
    throw new Error("Chapter steps markup has mismatched steps and panels.");
  }
  const seenStepIds = new Set<ChapterStepId>();
  const steps = selectors.map((selector): ChapterStepElements => {
    const stepId = selector.getAttribute("data-chapter-step") ?? "";
    if (!(selector instanceof HTMLButtonElement) || !isChapterStepId(stepId)) {
      throw new Error(`Chapter step selector is invalid: ${stepId}`);
    }
    if (seenStepIds.has(stepId)) {
      throw new Error(`Chapter step is duplicated: ${stepId}`);
    }
    const panel = panels.find((candidate) => candidate.dataset["chapterStepPanel"] === stepId);
    if (panel === undefined) {
      throw new Error(`Chapter step has no panel: ${stepId}`);
    }
    seenStepIds.add(stepId);
    return { panel, selector, stepId };
  });
  return { list, root, steps };
}

function stepStateFor(stepIndex: number, selectedIndex: number): ChapterStepState {
  if (stepIndex === selectedIndex) {
    return "current";
  }
  return stepIndex < selectedIndex ? "passed" : "upcoming";
}

function renderStaticContract(contract: ChapterStepsDomContract): void {
  contract.list.removeAttribute("role");
  contract.list.removeAttribute("aria-orientation");
  contract.steps.forEach(({ panel, selector }, stepIndex): void => {
    selector.disabled = true;
    selector.tabIndex = -1;
    selector.removeAttribute("role");
    selector.removeAttribute("aria-controls");
    selector.removeAttribute("aria-selected");
    selector.dataset["stepState"] = stepStateFor(stepIndex, 0);
    panel.hidden = stepIndex !== 0;
    panel.removeAttribute("role");
    panel.removeAttribute("aria-labelledby");
    panel.removeAttribute("tabindex");
  });
  contract.root.dataset["enhanced"] = "false";
}

function renderSelectedStep(
  contract: ChapterStepsDomContract,
  selectedIndex: number,
  orientation: StepListOrientation,
): void {
  const idPrefix = `chapter-step-${contract.root.dataset["chapterStepsRoot"] ?? "chapter"}`;
  contract.list.setAttribute("role", "tablist");
  contract.list.setAttribute("aria-orientation", orientation);
  contract.steps.forEach(({ panel, selector, stepId }, stepIndex): void => {
    const isSelected = stepIndex === selectedIndex;
    selector.disabled = false;
    selector.id = `${idPrefix}-tab-${stepId}`;
    selector.tabIndex = isSelected ? 0 : -1;
    selector.setAttribute("role", "tab");
    selector.setAttribute("aria-controls", `${idPrefix}-panel-${stepId}`);
    selector.setAttribute("aria-selected", String(isSelected));
    selector.dataset["stepState"] = stepStateFor(stepIndex, selectedIndex);
    panel.id = `${idPrefix}-panel-${stepId}`;
    panel.hidden = !isSelected;
    panel.tabIndex = 0;
    panel.setAttribute("role", "tabpanel");
    panel.setAttribute("aria-labelledby", selector.id);
  });
  contract.root.dataset["enhanced"] = "true";
}

function movementForKey(key: string): StepMovement | null {
  switch (key) {
    case "ArrowLeft":
    case "ArrowUp":
      return "previous";
    case "ArrowRight":
    case "ArrowDown":
      return "next";
    case "Home":
      return "first";
    case "End":
      return "last";
    default:
      return null;
  }
}

function movedIndex(selectedIndex: number, movement: StepMovement, stepCount: number): number {
  switch (movement) {
    case "first":
      return 0;
    case "last":
      return stepCount - 1;
    case "next":
      return (selectedIndex + 1) % stepCount;
    case "previous":
      return (selectedIndex - 1 + stepCount) % stepCount;
    default:
      return selectedIndex;
  }
}

export function initializeChapterSteps(root: HTMLElement): ChapterStepsController {
  const lifecycle = new AbortController();
  let contract: ChapterStepsDomContract | null = null;

  try {
    const validatedContract = validateChapterStepsDom(root);
    contract = validatedContract;
    let selectedIndex = 0;
    const stepRowQuery = window.matchMedia(chapterStackedLayoutMediaQuery);
    const currentOrientation = (): StepListOrientation =>
      stepRowQuery.matches ? "horizontal" : "vertical";

    const selectStep = (stepIndex: number): void => {
      selectedIndex = stepIndex;
      renderSelectedStep(validatedContract, selectedIndex, currentOrientation());
    };

    // The row turns vertical again on wider screens; keep the announced
    // orientation in step with the layout.
    stepRowQuery.addEventListener(
      "change",
      (): void => {
        validatedContract.list.setAttribute("aria-orientation", currentOrientation());
      },
      { signal: lifecycle.signal },
    );

    // A visitor's choice: select, then ask the scene to seek and play there.
    const chooseStep = (stepIndex: number): void => {
      selectStep(stepIndex);
      const chosenStep = validatedContract.steps[stepIndex];
      if (chosenStep !== undefined) {
        root.dispatchEvent(
          createChapterStepEvent(chapterStepRequestedEventName, chosenStep.stepId),
        );
      }
    };

    selectStep(0);

    validatedContract.list.addEventListener(
      "click",
      (event: MouseEvent): void => {
        const target = event.target;
        if (!(target instanceof Element)) {
          return;
        }
        const selector = target.closest<HTMLButtonElement>(stepSelector);
        const stepIndex = validatedContract.steps.findIndex((step) => step.selector === selector);
        if (stepIndex >= 0) {
          chooseStep(stepIndex);
        }
      },
      { signal: lifecycle.signal },
    );

    validatedContract.list.addEventListener(
      "keydown",
      (event: KeyboardEvent): void => {
        const movement = movementForKey(event.key);
        if (movement === null) {
          return;
        }
        event.preventDefault();
        // Scene progress moves the selection without moving focus, so arrows
        // move from the tab the visitor is on, not from the selected one.
        const focusedIndex = validatedContract.steps.findIndex(
          (step) =>
            (event.target instanceof Node && step.selector.contains(event.target)) ||
            step.selector === document.activeElement,
        );
        const originIndex = focusedIndex >= 0 ? focusedIndex : selectedIndex;
        chooseStep(movedIndex(originIndex, movement, validatedContract.steps.length));
        validatedContract.steps[selectedIndex]?.selector.focus();
      },
      { signal: lifecycle.signal },
    );

    // Scene progress: follow along, never steal focus, ignore unknown steps.
    root.addEventListener(
      sceneStepReachedEventName,
      (event: Event): void => {
        const stepId = readChapterStepEventStepId(event);
        const stepIndex = validatedContract.steps.findIndex((step) => step.stepId === stepId);
        if (stepIndex >= 0 && stepIndex !== selectedIndex) {
          selectStep(stepIndex);
        }
      },
      { signal: lifecycle.signal },
    );
  } catch (error: unknown) {
    lifecycle.abort();
    if (contract !== null) {
      renderStaticContract(contract);
    } else {
      root.dataset["enhanced"] = "false";
    }
    console.error("Chapter step enhancement failed; static steps preserved.", error);
  }

  return {
    destroy: (): void => {
      lifecycle.abort();
      if (contract !== null) {
        renderStaticContract(contract);
      }
    },
  };
}
