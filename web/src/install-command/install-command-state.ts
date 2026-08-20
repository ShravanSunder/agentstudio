export type InstallCommandState =
  | { readonly kind: "idle" }
  | { readonly kind: "copied" }
  | { readonly kind: "failed"; readonly message: string };

export type InstallCommandEvent =
  | { readonly kind: "copy-succeeded" }
  | { readonly kind: "copy-failed"; readonly message: string }
  | { readonly kind: "reset" };

function unexpectedInstallCommandEvent(event: never): never {
  throw new Error(`Unexpected install command event: ${JSON.stringify(event)}`);
}

export function reduceInstallCommandState(
  state: InstallCommandState,
  event: InstallCommandEvent,
): InstallCommandState {
  switch (event.kind) {
    case "copy-succeeded":
      return { kind: "copied" };
    case "copy-failed":
      return { kind: "failed", message: event.message };
    case "reset":
      return state.kind === "idle" ? state : { kind: "idle" };
    default:
      return unexpectedInstallCommandEvent(event);
  }
}
