import { marketingCopy } from "../marketing-copy";
import { reduceInstallCommandState, type InstallCommandState } from "./install-command-state";

interface InstallCommandControllerElements {
  readonly button: HTMLButtonElement;
  readonly status: HTMLElement;
}

function unexpectedInstallCommandState(state: never): never {
  throw new Error(`Unexpected install command state: ${JSON.stringify(state)}`);
}

function copyStatusText(state: InstallCommandState): string {
  switch (state.kind) {
    case "idle":
      return "";
    case "copied":
      return marketingCopy.installation.copiedStatus;
    case "failed":
      return state.message;
    default:
      return unexpectedInstallCommandState(state);
  }
}

function resolveControllerElements(root: HTMLElement): InstallCommandControllerElements {
  const button = root.querySelector<HTMLButtonElement>("[data-install-copy]");
  const status = root.querySelector<HTMLElement>("[data-install-status]");

  if (button === null || status === null) {
    throw new Error("Install command markup is incomplete.");
  }

  return { button, status };
}

export function initializeInstallCommand(root: HTMLElement): () => void {
  const { button, status } = resolveControllerElements(root);
  const lifecycle = new AbortController();
  let state: InstallCommandState = { kind: "idle" };

  button.addEventListener(
    "click",
    (): void => {
      const command = root.dataset["installCommand"];

      if (command === undefined) {
        state = reduceInstallCommandState(state, {
          kind: "copy-failed",
          message: marketingCopy.installation.failedStatus,
        });
        status.textContent = copyStatusText(state);
        return;
      }

      void navigator.clipboard
        .writeText(command)
        .then((): void => {
          state = reduceInstallCommandState(state, { kind: "copy-succeeded" });
          status.textContent = copyStatusText(state);
        })
        .catch((): void => {
          state = reduceInstallCommandState(state, {
            kind: "copy-failed",
            message: marketingCopy.installation.failedStatus,
          });
          status.textContent = copyStatusText(state);
        });
    },
    { signal: lifecycle.signal },
  );

  return (): void => lifecycle.abort();
}
