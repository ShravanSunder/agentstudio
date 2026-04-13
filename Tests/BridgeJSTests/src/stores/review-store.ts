import { createStore } from "zustand/vanilla";

export interface ReviewThread {
  id: string;
  version: number;
  body: string;
}

export interface ReviewState {
  threads: Record<string, ReviewThread>;
  viewedFiles: Set<string>;
  lastRevision: number;
}

export const createReviewStore = () =>
  createStore<ReviewState>(() => ({
    threads: {},
    viewedFiles: new Set(),
    lastRevision: 0,
  }));

export type ReviewStore = ReturnType<typeof createReviewStore>;
