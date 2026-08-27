import type { z } from 'zod';

import {
	type BridgeCommWorkerAnnotationCatalog,
	type BridgeCommWorkerAnnotationCatalogApplicatorResult,
} from '../core/comm-worker/bridge-comm-worker-annotation-catalog-applicator.js';
import type { BridgeWorkerAnnotationProjectionSnapshot } from '../core/comm-worker/bridge-comm-worker-annotation-projection-decoder.js';
import {
	bridgeProductWorktreeAnnotationCommandOutcomeSchema,
	bridgeProductWorktreeAnnotationOutputHistorySummarySchema,
} from '../core/comm-worker/bridge-product-worktree-annotation-contracts.js';
import type { BridgeWorkerAnnotationCatalogStagingEvent } from '../core/comm-worker/bridge-worker-annotation-contracts.js';
import { WorktreeAnnotationCatalogStaging } from './worktree-annotation-catalog-staging.js';

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
	readonly operationCorrelationId: string | null;
	readonly presentationRevision: number;
	readonly readStatus:
		| { readonly kind: 'unknown' }
		| { readonly kind: 'ready' }
		| { readonly kind: 'refreshing' }
		| { readonly kind: 'unavailable'; readonly retryable: boolean };
	readonly recoveryStatus: 'available' | 'recovered_degraded' | 'unavailable';
	readonly revision: number | null;
	readonly sessions: readonly WorktreeAnnotationSessionSummary[];
	readonly sourceGeneration: number;
	readonly threads: readonly WorktreeAnnotationThreadProjection[];
	readonly worktreeId: string | null;
}

export type WorktreeAnnotationCatalogProjection =
	| { readonly kind: 'unknown' }
	| {
			readonly catalog: BridgeCommWorkerAnnotationCatalog;
			readonly kind: 'current' | 'stale';
	  };

export const emptyWorktreeAnnotationProjectionSnapshot: WorktreeAnnotationProjectionSnapshot = {
	commandOutcomes: [],
	outputHistory: [],
	operationCorrelationId: null,
	presentationRevision: 0,
	readStatus: { kind: 'unknown' },
	recoveryStatus: 'available',
	revision: null,
	sessions: [],
	sourceGeneration: 0,
	threads: [],
	worktreeId: null,
};

export class WorktreeAnnotationProjectionStore {
	#catalogProjection: WorktreeAnnotationCatalogProjection = { kind: 'unknown' };
	readonly #catalogStaging = new WorktreeAnnotationCatalogStaging();
	readonly #listeners = new Set<() => void>();
	#snapshot = emptyWorktreeAnnotationProjectionSnapshot;
	#sourceGeneration = -1;

	getSnapshot = (): WorktreeAnnotationProjectionSnapshot => this.#snapshot;

	getServerSnapshot = (): WorktreeAnnotationProjectionSnapshot => this.#snapshot;

	getCatalogSnapshot = (): WorktreeAnnotationCatalogProjection => this.#catalogProjection;

	subscribe = (listener: () => void): (() => void) => {
		this.#listeners.add(listener);
		return (): void => {
			this.#listeners.delete(listener);
		};
	};

	apply(
		snapshot: BridgeWorkerAnnotationProjectionSnapshot,
		operationCorrelationId: string,
		contentSessionIds?: readonly string[],
		expectedContentSessionIds: readonly string[] = contentSessionIds ?? [],
	): void {
		const catalogProjection = this.#catalogProjection;
		if (catalogProjection.kind !== 'current') return;
		if (snapshot.worktreeId !== catalogProjection.catalog.authority.worktreeId) return;
		if (
			snapshot.sessions.some(
				(session) => !catalogProjection.catalog.sessionsById.has(session.sessionId),
			)
		) {
			return;
		}
		if (
			contentSessionIds?.some((sessionId) => !catalogProjection.catalog.sessionsById.has(sessionId))
		) {
			return;
		}
		if (
			contentSessionIds !== undefined &&
			!annotationProjectionContentMatchesCatalog(
				catalogProjection.catalog,
				snapshot.threads,
				contentSessionIds,
			)
		) {
			return;
		}
		const currentRevision = this.#snapshot.revision ?? -1;
		if (snapshot.projectionRevision < currentRevision) return;
		if (
			snapshot.projectionRevision === currentRevision &&
			snapshot.sourceGeneration < this.#sourceGeneration
		) {
			return;
		}
		this.#sourceGeneration = snapshot.sourceGeneration;
		const installsControlOnly = contentSessionIds?.length === 0;
		const threads = installsControlOnly
			? this.#snapshot.threads
			: mergeAnnotationContentThreads({
					catalog: catalogProjection.catalog,
					currentThreads: this.#snapshot.threads,
					incomingThreads: snapshot.threads,
					requestedSessionIds: contentSessionIds,
				});
		this.#publish({
			commandOutcomes: this.#snapshot.commandOutcomes,
			outputHistory: this.#snapshot.outputHistory,
			operationCorrelationId,
			readStatus:
				installsControlOnly && expectedContentSessionIds.length > 0
					? { kind: 'refreshing' }
					: { kind: 'ready' },
			recoveryStatus: snapshot.recoveryStatus,
			revision: snapshot.projectionRevision,
			sessions: snapshot.sessions,
			sourceGeneration: snapshot.sourceGeneration,
			threads,
			worktreeId: snapshot.worktreeId,
		});
	}

	applyCatalogStaging(
		event: BridgeWorkerAnnotationCatalogStagingEvent,
	): BridgeCommWorkerAnnotationCatalogApplicatorResult {
		const authorityReplaced = this.#catalogStaging.replaceExpectedAuthority(event.authority);
		if (authorityReplaced && this.#catalogProjection.kind === 'current') {
			this.#catalogProjection = { ...this.#catalogProjection, kind: 'stale' };
			this.#publish({ ...this.#snapshot, readStatus: { kind: 'refreshing' } });
		}
		const result = this.#catalogStaging.accept(event);
		if (result.status !== 'completed') return result;
		this.#catalogProjection = { catalog: result.catalog, kind: 'current' };
		this.#publish({
			...this.#snapshot,
			outputHistory: this.#snapshot.outputHistory.filter((summary) =>
				result.catalog.sessionsById.has(summary.sessionId),
			),
			readStatus: { kind: 'refreshing' },
			threads: this.#snapshot.threads.filter((thread) => {
				const sessionId = annotationThreadSessionId(result.catalog, thread);
				return sessionId !== null && result.catalog.sessionsById.has(sessionId);
			}),
		});
		return result;
	}

	prepareForWorkerReplacement(): void {
		this.#catalogStaging.retireExpectedAuthority();
		if (this.#catalogProjection.kind !== 'current') return;
		this.#catalogProjection = { ...this.#catalogProjection, kind: 'stale' };
		this.#publish({ ...this.#snapshot, readStatus: { kind: 'refreshing' } });
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

	replaceOutputHistoryForSession(
		sessionId: string,
		outputHistory: readonly WorktreeAnnotationOutputHistorySummary[],
	): void {
		const retainedHistory = this.#snapshot.outputHistory.filter(
			(summary) => summary.sessionId !== sessionId,
		);
		const matchingHistory = outputHistory.filter((summary) => summary.sessionId === sessionId);
		this.#publish({
			...this.#snapshot,
			outputHistory: [...retainedHistory, ...matchingHistory],
		});
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

function mergeAnnotationContentThreads(props: {
	readonly catalog: BridgeCommWorkerAnnotationCatalog;
	readonly currentThreads: readonly WorktreeAnnotationThreadProjection[];
	readonly incomingThreads: readonly WorktreeAnnotationThreadProjection[];
	readonly requestedSessionIds: readonly string[] | undefined;
}): readonly WorktreeAnnotationThreadProjection[] {
	if (props.requestedSessionIds === undefined) {
		return props.incomingThreads.toSorted(compareAnnotationThreads);
	}
	const requestedSessionIds = new Set(props.requestedSessionIds);
	const retainedThreads = props.currentThreads.filter((thread) => {
		const sessionId = annotationThreadSessionId(props.catalog, thread);
		return sessionId !== null && !requestedSessionIds.has(sessionId);
	});
	return [...retainedThreads, ...props.incomingThreads].toSorted(compareAnnotationThreads);
}

function annotationThreadSessionId(
	catalog: BridgeCommWorkerAnnotationCatalog,
	thread: WorktreeAnnotationThreadProjection,
): string | null {
	return (
		catalog.threadsById.get(thread.context.threadId)?.sessionId ??
		thread.messages[0]?.sessionId ??
		null
	);
}

function annotationProjectionContentMatchesCatalog(
	catalog: BridgeCommWorkerAnnotationCatalog,
	threads: readonly WorktreeAnnotationThreadProjection[],
	contentSessionIds: readonly string[],
): boolean {
	const demandedSessionIds = new Set(contentSessionIds);
	for (const thread of threads) {
		const catalogThread = catalog.threadsById.get(thread.context.threadId);
		if (catalogThread === undefined || !demandedSessionIds.has(catalogThread.sessionId))
			return false;
		for (const message of thread.messages) {
			const catalogMessage = catalog.messagesById.get(message.messageId);
			if (
				catalogMessage === undefined ||
				catalogMessage.threadId !== thread.context.threadId ||
				message.threadId !== thread.context.threadId ||
				message.sessionId !== catalogThread.sessionId
			) {
				return false;
			}
		}
	}
	return true;
}
