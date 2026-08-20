import {
  initialPersistenceProofState,
  reducePersistenceProofState,
  type PersistenceProofFrame,
  type PersistenceProofState,
} from "./persistence-proof-state";

const persistenceProofFrames = [
  "before",
  "restored",
] as const satisfies readonly PersistenceProofFrame[];

interface PersistenceProofDomContract {
  readonly root: HTMLElement;
  readonly buttonsByFrame: ReadonlyMap<PersistenceProofFrame, HTMLButtonElement>;
  readonly panelsByFrame: ReadonlyMap<PersistenceProofFrame, HTMLElement>;
}

interface PersistenceProofController {
  readonly destroy: () => void;
}

function parsePersistenceProofFrame(candidate: string): PersistenceProofFrame | null {
  switch (candidate) {
    case "before":
    case "restored":
      return candidate;
    default:
      return null;
  }
}

function requiredButton(root: ParentNode, selector: string): HTMLButtonElement {
  const element = root.querySelector(selector);

  if (!(element instanceof HTMLButtonElement)) {
    throw new Error(`Persistence proof is missing required button: ${selector}`);
  }

  return element;
}

function requiredPanel(root: ParentNode, selector: string): HTMLElement {
  const element = root.querySelector(selector);

  if (!(element instanceof HTMLElement)) {
    throw new Error(`Persistence proof is missing required panel: ${selector}`);
  }

  return element;
}

function validatePersistenceProofDom(root: HTMLElement): PersistenceProofDomContract {
  const buttonsByFrame = new Map<PersistenceProofFrame, HTMLButtonElement>();
  const panelsByFrame = new Map<PersistenceProofFrame, HTMLElement>();

  for (const frame of persistenceProofFrames) {
    buttonsByFrame.set(frame, requiredButton(root, `[data-persistence-proof-button="${frame}"]`));
    panelsByFrame.set(frame, requiredPanel(root, `[data-persistence-frame="${frame}"]`));
  }

  return { root, buttonsByFrame, panelsByFrame };
}

function renderPersistenceProof(
  contract: PersistenceProofDomContract,
  state: PersistenceProofState,
): void {
  for (const frame of persistenceProofFrames) {
    const button = contract.buttonsByFrame.get(frame);
    const panel = contract.panelsByFrame.get(frame);

    if (button === undefined || panel === undefined) {
      throw new Error(`Validated persistence proof frame disappeared: ${frame}`);
    }

    const isSelected = frame === state.frame;
    button.disabled = false;
    button.setAttribute("aria-pressed", String(isSelected));
    panel.hidden = !isSelected;
  }

  contract.root.dataset["enhanced"] = "true";
}

export function initializePersistenceProof(root: HTMLElement): PersistenceProofController {
  const lifecycle = new AbortController();
  const contract = validatePersistenceProofDom(root);
  let state = initialPersistenceProofState;

  renderPersistenceProof(contract, state);

  root.addEventListener(
    "click",
    (event: MouseEvent): void => {
      const target = event.target;

      if (!(target instanceof Element)) {
        return;
      }

      const button = target.closest<HTMLButtonElement>("[data-persistence-proof-button]");
      const frame = parsePersistenceProofFrame(button?.dataset["persistenceProofButton"] ?? "");

      if (button === null || frame === null) {
        return;
      }

      state = reducePersistenceProofState(state, { kind: "select", frame });
      renderPersistenceProof(contract, state);
    },
    { signal: lifecycle.signal },
  );

  return {
    destroy: (): void => {
      lifecycle.abort();
      state = reducePersistenceProofState(state, { kind: "reset" });
    },
  };
}
