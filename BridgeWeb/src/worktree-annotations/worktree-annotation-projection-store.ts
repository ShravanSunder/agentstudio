import type { z } from 'zod';

import type { BridgeWorkerAnnotationProjectionSnapshot } from '../core/comm-worker/bridge-comm-worker-annotation-projection-decoder.js';
import {
	bridgeProductWorktreeAnnotationCommandOutcomeSchema,
	bridgeProductWorktreeAnnotationOutputHistorySummarySchema,
} from '../core/comm-worker/bridge-product-worktree-annotation-contracts.js';

export type WorktreeAnnotationCommandOutcome = z.infer<
	typeof bridgeProductWorktreeAnnotationCommandOutcomeSchema
>;
export type WorktreeAnnotationSessionSummary =
	BridgeWorkerAnnotationProjectionSnapshot['sessions'][number];
export type WorktreeAnnotationMessageEntry =
	BridgeWorkerAnnotationProjectionSnapshot['threads'][number]['messages'][number];
export type WorktreeAnnotationThreadContext =
	BridgeWorkerAnnotationProjectionSnapshot['threads'][number]['context'];

export type WorktreeAnnotationOutputHistorySummary = z.infer<
	typeof bridgeProductWorktreeAnnotationOutputHistorySummarySchema
>;

export interface WorktreeAnnotationThreadProjection {
	readonly context: WorktreeAnnotationThreadContext;
	readonly messages: readonly WorktreeAnnotationMessageEntry[];
}

export interface WorktreeAnnotationProjectionSnapshot {
	readonly commandOutcomes: readonly WorktreeAnnotationCommandOutcome[];
	readonly outputHistory: readonly WorktreeAnnotationOutputHistorySummary[];
	readonly presentationRevision: number;
	readonly readStatus:
		| { readonly kind: 'ready' }
		| { readonly kind: 'refreshing' }
		| { readonly kind: 'unavailable'; readonly retryable: boolean };
	readonly recoveryStatus: 'available' | 'recovered_degraded' | 'unavailable';
	readonly revision: number | null;
	readonly sessions: readonly WorktreeAnnotationSessionSummary[];
	readonly threads: readonly WorktreeAnnotationThreadProjection[];
	readonly worktreeId: string | null;
}

export const emptyWorktreeAnnotationProjectionSnapshot: WorktreeAnnotationProjectionSnapshot = {
	commandOutcomes: [],
	outputHistory: [],
	presentationRevision: 0,
	readStatus: { kind: 'ready' },
	recoveryStatus: 'available',
	revision: null,
	sessions: [],
	threads: [],
	worktreeId: null,
};

export class WorktreeAnnotationProjectionStore {
	readonly #listeners = new Set<() => void>();
	#snapshot = emptyWorktreeAnnotationProjectionSnapshot;
	#sourceGeneration = -1;

	getSnapshot = (): WorktreeAnnotationProjectionSnapshot => this.#snapshot;

	getServerSnapshot = (): WorktreeAnnotationProjectionSnapshot => this.#snapshot;

	subscribe = (listener: () => void): (() => void) => {
		this.#listeners.add(listener);
		return (): void => {
			this.#listeners.delete(listener);
		};
	};

	apply(snapshot: BridgeWorkerAnnotationProjectionSnapshot): void {
		const currentRevision = this.#snapshot.revision ?? -1;
		if (snapshot.projectionRevision < currentRevision) return;
		if (
			snapshot.projectionRevision === currentRevision &&
			snapshot.sourceGeneration < this.#sourceGeneration
		) {
			return;
		}
		this.#sourceGeneration = snapshot.sourceGeneration;
		this.#publish({
			commandOutcomes: this.#snapshot.commandOutcomes,
			outputHistory: this.#snapshot.outputHistory,
			readStatus: { kind: 'ready' },
			recoveryStatus: snapshot.recoveryStatus,
			revision: snapshot.projectionRevision,
			sessions: snapshot.sessions,
			threads: snapshot.threads.toSorted(compareAnnotationThreads),
			worktreeId: snapshot.worktreeId,
		});
	}

	markRefreshing(): void {
		if (this.#snapshot.readStatus.kind === 'refreshing') return;
		this.#publish({ ...this.#snapshot, readStatus: { kind: 'refreshing' } });
	}

	markUnavailable(retryable: boolean): void {
		if (
			this.#snapshot.readStatus.kind === 'unavailable' &&
			this.#snapshot.readStatus.retryable === retryable
		) {
			return;
		}
		this.#publish({
			...this.#snapshot,
			readStatus: { kind: 'unavailable', retryable },
		});
	}

	recordCommandOutcome(outcome: WorktreeAnnotationCommandOutcome): void {
		const retainedOutcomes = this.#snapshot.commandOutcomes.filter(
			(candidate) => candidate.requestId !== outcome.requestId,
		);
		this.#publish({
			...this.#snapshot,
			commandOutcomes: [...retainedOutcomes, outcome].slice(-128),
		});
	}

	replaceOutputHistory(outputHistory: readonly WorktreeAnnotationOutputHistorySummary[]): void {
		this.#publish({ ...this.#snapshot, outputHistory });
	}

	#publish(snapshot: Omit<WorktreeAnnotationProjectionSnapshot, 'presentationRevision'>): void {
		this.#snapshot = {
			...snapshot,
			presentationRevision: this.#snapshot.presentationRevision + 1,
		};
		for (const listener of this.#listeners) listener();
	}
}

function compareAnnotationThreads(
	left: WorktreeAnnotationThreadProjection,
	right: WorktreeAnnotationThreadProjection,
): number {
	const leftKey = [
		left.context.path,
		left.context.startLine,
		left.context.endLine,
		left.context.threadId,
	];
	const rightKey = [
		right.context.path,
		right.context.startLine,
		right.context.endLine,
		right.context.threadId,
	];
	return JSON.stringify(leftKey).localeCompare(JSON.stringify(rightKey));
}
