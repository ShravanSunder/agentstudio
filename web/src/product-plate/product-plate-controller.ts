import { productPlateStoryIds, type ProductPlateStoryId } from "./product-plate-contract";
import {
  initialProductPlateState,
  parseProductPlateStoryId,
  reduceProductPlateState,
  type ProductPlateEvent,
  type ProductPlateState,
} from "./product-plate-state";

interface ProductPlateDomContract {
  readonly root: HTMLElement;
  readonly selectorGroup: HTMLElement;
  readonly selectorsByStoryId: ReadonlyMap<ProductPlateStoryId, HTMLButtonElement>;
  readonly panelsByStoryId: ReadonlyMap<ProductPlateStoryId, HTMLElement>;
}

interface ProductPlateController {
  readonly destroy: () => void;
}

function requiredHtmlElement(parent: ParentNode, selector: string): HTMLElement {
  const element = parent.querySelector(selector);

  if (!(element instanceof HTMLElement)) {
    throw new Error(`Product plate markup is missing required element: ${selector}`);
  }

  return element;
}

function requiredButton(parent: ParentNode, selector: string): HTMLButtonElement {
  const element = parent.querySelector(selector);

  if (!(element instanceof HTMLButtonElement)) {
    throw new Error(`Product plate markup is missing required button: ${selector}`);
  }

  return element;
}

function validateProductPlateDom(root: HTMLElement): ProductPlateDomContract {
  const selectorGroup = requiredHtmlElement(root, "[data-product-plate-selectors]");
  const selectorsByStoryId = new Map<ProductPlateStoryId, HTMLButtonElement>();
  const panelsByStoryId = new Map<ProductPlateStoryId, HTMLElement>();

  for (const storyId of productPlateStoryIds) {
    const selector = requiredButton(selectorGroup, `[data-product-plate-selector="${storyId}"]`);
    const panel = requiredHtmlElement(root, `[data-product-plate-panel="${storyId}"]`);

    if (selectorsByStoryId.has(storyId) || panelsByStoryId.has(storyId)) {
      throw new Error(`Product plate story is duplicated: ${storyId}`);
    }

    selectorsByStoryId.set(storyId, selector);
    panelsByStoryId.set(storyId, panel);
  }

  const selectorCount = selectorGroup.querySelectorAll("[data-product-plate-selector]").length;
  const panelCount = root.querySelectorAll("[data-product-plate-panel]").length;

  if (selectorCount !== productPlateStoryIds.length || panelCount !== productPlateStoryIds.length) {
    throw new Error("Product plate markup contains an unknown selector or panel.");
  }

  return { root, selectorGroup, selectorsByStoryId, panelsByStoryId };
}

function renderStaticContract(contract: ProductPlateDomContract): void {
  contract.selectorGroup.removeAttribute("role");

  for (const storyId of productPlateStoryIds) {
    const selector = contract.selectorsByStoryId.get(storyId);
    const panel = contract.panelsByStoryId.get(storyId);

    if (selector === undefined || panel === undefined) {
      continue;
    }

    selector.disabled = true;
    selector.tabIndex = -1;
    selector.removeAttribute("role");
    selector.removeAttribute("aria-controls");
    selector.removeAttribute("aria-selected");
    panel.hidden = storyId !== "parallel-work";
    panel.removeAttribute("role");
    panel.removeAttribute("aria-labelledby");
  }

  contract.root.dataset["enhanced"] = "false";
}

function renderActiveState(contract: ProductPlateDomContract, state: ProductPlateState): void {
  if (state.kind !== "active") {
    renderStaticContract(contract);
    return;
  }

  contract.selectorGroup.setAttribute("role", "tablist");

  for (const storyId of productPlateStoryIds) {
    const selector = contract.selectorsByStoryId.get(storyId);
    const panel = contract.panelsByStoryId.get(storyId);

    if (selector === undefined || panel === undefined) {
      throw new Error(`Validated product plate story disappeared: ${storyId}`);
    }

    const isSelected = storyId === state.selectedStoryId;
    selector.disabled = false;
    selector.id = `product-plate-selector-${storyId}`;
    selector.tabIndex = isSelected ? 0 : -1;
    selector.setAttribute("role", "tab");
    selector.setAttribute("aria-controls", `product-plate-panel-${storyId}`);
    selector.setAttribute("aria-selected", String(isSelected));
    panel.id = `product-plate-panel-${storyId}`;
    panel.hidden = !isSelected;
    panel.setAttribute("role", "tabpanel");
    panel.setAttribute("aria-labelledby", selector.id);
  }

  contract.root.dataset["enhanced"] = "true";
}

function movementEvent(key: string): ProductPlateEvent | null {
  switch (key) {
    case "ArrowLeft":
    case "ArrowUp":
      return { kind: "move", direction: "previous" };
    case "ArrowRight":
    case "ArrowDown":
      return { kind: "move", direction: "next" };
    case "Home":
      return { kind: "move", direction: "first" };
    case "End":
      return { kind: "move", direction: "last" };
    default:
      return null;
  }
}

export function initializeProductPlate(root: HTMLElement): ProductPlateController {
  let state = initialProductPlateState;
  const lifecycle = new AbortController();
  let contract: ProductPlateDomContract | null = null;

  try {
    const validatedContract = validateProductPlateDom(root);
    contract = validatedContract;
    state = reduceProductPlateState(state, { kind: "activate" });
    renderActiveState(validatedContract, state);

    validatedContract.selectorGroup.addEventListener(
      "click",
      (event: MouseEvent): void => {
        const target = event.target;

        if (!(target instanceof Element)) {
          return;
        }

        const selector = target.closest<HTMLButtonElement>("[data-product-plate-selector]");
        const storyId = parseProductPlateStoryId(selector?.dataset["productPlateSelector"] ?? "");

        if (selector === null || storyId === null) {
          return;
        }

        state = reduceProductPlateState(state, { kind: "select", storyId });
        renderActiveState(validatedContract, state);
      },
      { signal: lifecycle.signal },
    );

    validatedContract.selectorGroup.addEventListener(
      "keydown",
      (event: KeyboardEvent): void => {
        const movement = movementEvent(event.key);

        if (movement === null) {
          return;
        }

        event.preventDefault();
        state = reduceProductPlateState(state, movement);
        renderActiveState(validatedContract, state);
        validatedContract.selectorsByStoryId.get(state.selectedStoryId)?.focus();
      },
      { signal: lifecycle.signal },
    );
  } catch (error: unknown) {
    lifecycle.abort();
    state = reduceProductPlateState(state, { kind: "rollback" });

    if (contract !== null) {
      renderStaticContract(contract);
    } else {
      root.dataset["enhanced"] = "false";
    }

    console.error("Product plate enhancement failed; static state preserved.", error);
  }

  return {
    destroy: (): void => {
      lifecycle.abort();
      state = reduceProductPlateState(state, { kind: "rollback" });

      if (contract !== null) {
        renderStaticContract(contract);
      }
    },
  };
}
