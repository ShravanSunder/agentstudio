export type PersistenceProofFrame = "before" | "restored";

export type PersistenceProofState = {
  readonly kind: "showing";
  readonly frame: PersistenceProofFrame;
};

export type PersistenceProofEvent =
  | { readonly kind: "select"; readonly frame: PersistenceProofFrame }
  | { readonly kind: "reset" };

export const initialPersistenceProofState: PersistenceProofState = {
  kind: "showing",
  frame: "before",
};

function unexpectedPersistenceProofEvent(event: never): never {
  throw new Error(`Unexpected persistence proof event: ${JSON.stringify(event)}`);
}

export function reducePersistenceProofState(
  state: PersistenceProofState,
  event: PersistenceProofEvent,
): PersistenceProofState {
  switch (event.kind) {
    case "reset":
      return initialPersistenceProofState;
    case "select":
      return event.frame === state.frame ? state : { kind: "showing", frame: event.frame };
    default:
      return unexpectedPersistenceProofEvent(event);
  }
}
