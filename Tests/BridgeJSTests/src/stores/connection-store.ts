import { createStore } from "zustand/vanilla";

export interface ConnectionState {
  health: "connected" | "disconnected" | "error";
  latencyMs: number;
  lastRevision: number;
}

export const createConnectionStore = () =>
  createStore<ConnectionState>(() => ({
    health: "disconnected",
    latencyMs: 0,
    lastRevision: 0,
  }));

export type ConnectionStore = ReturnType<typeof createConnectionStore>;
