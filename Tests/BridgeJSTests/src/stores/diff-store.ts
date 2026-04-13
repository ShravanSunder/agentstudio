import { createStore } from "zustand/vanilla";

export interface FileManifest {
  id: string;
  version: number;
  path: string;
  changeType: string;
  additions: number;
  deletions: number;
}

export interface DiffState {
  status: string;
  error: string | null;
  epoch: number;
  files: Record<string, FileManifest>;
  lastRevision: number;
  lastEpoch: number;
}

export const createDiffStore = () =>
  createStore<DiffState>(() => ({
    status: "idle",
    error: null,
    epoch: 0,
    files: {},
    lastRevision: 0,
    lastEpoch: -1,
  }));

export type DiffStore = ReturnType<typeof createDiffStore>;
