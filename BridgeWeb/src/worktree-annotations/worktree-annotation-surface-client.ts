import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type { BridgeProductWorktreeAnnotationOperation } from '../core/comm-worker/bridge-product-call-contracts.js';
import type {
	BridgeProductCallRequest,
	BridgeProductCallResult,
} from '../core/comm-worker/bridge-product-call-contracts.js';
import type { BridgeProductAnnotationOutputContentDescriptor } from '../core/comm-worker/bridge-product-content-contracts.js';
import type { BridgeWorkerServerToMainMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import {
	WorktreeAnnotationProjectionStore,
	type WorktreeAnnotationCommandOutcome,
	type WorktreeAnnotationProjectionSnapshot,
} from './worktree-annotation-projection-store.js';

const noopUnsubscribe = (): void => {};
const maximumRetainedOrphanCorrelationCount = 128;
export {
	emptyWorktreeAnnotationProjectionSnapshot,
	WorktreeAnnotationProjectionStore,
} from './worktree-annotation-projection-store.js';
export type {
	WorktreeAnnotationCommandOutcome,
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationOutputHistorySummary,
	WorktreeAnnotationProjectionSnapshot,
	WorktreeAnnotationSessionSummary,
	WorktreeAnnotationThreadContext,
	WorktreeAnnotationThreadProjection,
} from './worktree-annotation-projection-store.js';

export interface WorktreeAnnotationOutputInspection {
	readonly descriptor: BridgeProductAnnotationOutputContentDescriptor;
	readonly exactBytes: Uint8Array;
}

export interface WorktreeAnnotationSurfaceClient {
	readonly acquireSession: (sessionId: string) => () => void;
	readonly dispose: () => void;
	readonly execute: (
		operation: BridgeProductWorktreeAnnotationOperation,
	) => Promise<WorktreeAnnotationCommandOutcome>;
	readonly getServerSnapshot: () => WorktreeAnnotationProjectionSnapshot;
	readonly getSnapshot: () => WorktreeAnnotationProjectionSnapshot;
	readonly inspectOutput: (attemptId: string) => Promise<WorktreeAnnotationOutputInspection>;
	readonly queryOutputCandidates: (
		query: BridgeProductCallRequest<'file.annotations.output.candidates.query'>,
	) => Promise<BridgeProductCallResult<'file.annotations.output.candidates.query'>>;
	readonly retryProjection: () => void;
	readonly subscribe: (listener: () => void) => () => void;
	readonly waitForSnapshot: <TResult>(
		select: (snapshot: WorktreeAnnotationProjectionSnapshot) => TResult | null,
	) => Promise<TResult>;
}

interface PendingAnnotationCommand {
	readonly reject: (error: Error) => void;
	readonly resolve: (outcome: WorktreeAnnotationCommandOutcome) => void;
	productRequestId: string | null;
}

interface PendingAnnotationOutputInspection {
	readonly reject: (error: Error) => void;
	readonly resolve: (inspection: WorktreeAnnotationOutputInspection) => void;
}

interface PendingAnnotationOutputCandidateQuery {
	readonly reject: (error: Error) => void;
	readonly resolve: (
		page: BridgeProductCallResult<'file.annotations.output.candidates.query'>,
	) => void;
}

export function createWorktreeAnnotationSurfaceClient(
	surfaceClient: BridgePaneSurfaceClient,
): WorktreeAnnotationSurfaceClient {
	const pendingCommandsByWorkerRequestId = new Map<string, PendingAnnotationCommand>();
	const pendingOutputInspectionsByWorkerRequestId = new Map<
		string,
		PendingAnnotationOutputInspection
	>();
	const pendingOutputCandidateQueriesByWorkerRequestId = new Map<
		string,
		PendingAnnotationOutputCandidateQuery
	>();
	const pendingWorkerRequestIdByProductRequestId = new Map<string, string>();
	const acceptedProductRequestIdByWorkerRequestId = new Map<string, string>();
	const outcomesByProductRequestId = new Map<string, WorktreeAnnotationCommandOutcome>();
	const degradedFailureByWorkerRequestId = new Map<string, Error>();
	const demandCountBySessionId = new Map<string, number>();
	const rejectPendingSnapshotWaiters = new Set<(error: Error) => void>();
	let isDisposed = false;
	let observedSurfaceEpoch = currentSurfaceEpoch(surfaceClient);
	let nextSourceRefreshEpoch = 0;
	const projectionStore = new WorktreeAnnotationProjectionStore();

	const settleProductOutcome = (outcome: WorktreeAnnotationCommandOutcome): void => {
		projectionStore.recordCommandOutcome(outcome);
		if (outcome.status.kind === 'history') {
			projectionStore.replaceOutputHistory(outcome.status.summaries);
		}
		retainBoundedOrphanCorrelation(outcomesByProductRequestId, outcome.requestId, outcome);
		const workerRequestId = pendingWorkerRequestIdByProductRequestId.get(outcome.requestId);
		if (workerRequestId === undefined) return;
		const pendingCommand = pendingCommandsByWorkerRequestId.get(workerRequestId);
		if (pendingCommand === undefined) return;
		pendingCommandsByWorkerRequestId.delete(workerRequestId);
		pendingWorkerRequestIdByProductRequestId.delete(outcome.requestId);
		outcomesByProductRequestId.delete(outcome.requestId);
		pendingCommand.resolve(outcome);
	};

	const acceptProductRequest = (workerRequestId: string, productRequestId: string): void => {
		const pendingCommand = pendingCommandsByWorkerRequestId.get(workerRequestId);
		if (pendingCommand === undefined) {
			retainBoundedOrphanCorrelation(
				acceptedProductRequestIdByWorkerRequestId,
				workerRequestId,
				productRequestId,
			);
			return;
		}
		pendingCommand.productRequestId = productRequestId;
		pendingWorkerRequestIdByProductRequestId.set(productRequestId, workerRequestId);
		const existingOutcome = outcomesByProductRequestId.get(productRequestId);
		if (existingOutcome !== undefined) settleProductOutcome(existingOutcome);
	};

	const failWorkerRequest = (workerRequestId: string, error: Error): void => {
		const pendingCommand = pendingCommandsByWorkerRequestId.get(workerRequestId);
		const pendingOutputInspection = pendingOutputInspectionsByWorkerRequestId.get(workerRequestId);
		const pendingCandidateQuery =
			pendingOutputCandidateQueriesByWorkerRequestId.get(workerRequestId);
		if (
			pendingCommand === undefined &&
			pendingOutputInspection === undefined &&
			pendingCandidateQuery === undefined
		) {
			retainBoundedOrphanCorrelation(degradedFailureByWorkerRequestId, workerRequestId, error);
			return;
		}
		if (pendingCommand !== undefined) {
			pendingCommandsByWorkerRequestId.delete(workerRequestId);
			if (pendingCommand.productRequestId !== null) {
				pendingWorkerRequestIdByProductRequestId.delete(pendingCommand.productRequestId);
			}
			pendingCommand.reject(error);
		}
		if (pendingOutputInspection !== undefined) {
			pendingOutputInspectionsByWorkerRequestId.delete(workerRequestId);
			pendingOutputInspection.reject(error);
		}
		if (pendingCandidateQuery !== undefined) {
			pendingOutputCandidateQueriesByWorkerRequestId.delete(workerRequestId);
			pendingCandidateQuery.reject(error);
		}
	};

	const unsubscribeMessages = surfaceClient.subscribeMessages(
		(message: BridgeWorkerServerToMainMessage): void => {
			if (isDisposed) return;
			if (message.kind === 'annotationOutputInspection') {
				const pendingInspection = pendingOutputInspectionsByWorkerRequestId.get(message.requestId);
				if (pendingInspection === undefined) return;
				pendingOutputInspectionsByWorkerRequestId.delete(message.requestId);
				pendingInspection.resolve({
					descriptor: message.descriptor,
					exactBytes: new Uint8Array(message.exactBytes),
				});
				return;
			}
			if (message.kind === 'annotationOutputCandidatesPage') {
				const pendingQuery = pendingOutputCandidateQueriesByWorkerRequestId.get(message.requestId);
				if (pendingQuery === undefined) return;
				pendingOutputCandidateQueriesByWorkerRequestId.delete(message.requestId);
				pendingQuery.resolve(message.page);
				return;
			}
			if (message.kind === 'annotationCommandAccepted') {
				acceptProductRequest(message.requestId, message.productRequestId);
				if (message.outcome !== undefined) settleProductOutcome(message.outcome);
				return;
			}
			if (message.kind === 'annotationProjectionConvergence') {
				if (message.state.kind === 'ready') projectionStore.apply(message.state.snapshot);
				else if (message.state.kind === 'refreshing') projectionStore.markRefreshing();
				else projectionStore.markUnavailable(message.state.retryable);
				return;
			}
			if (
				message.kind === 'health' &&
				message.status === 'degraded' &&
				message.requestId !== undefined
			) {
				failWorkerRequest(
					message.requestId,
					new Error(message.message ?? 'Bridge annotation command failed.'),
				);
			}
		},
	);

	const execute = (
		operation: BridgeProductWorktreeAnnotationOperation,
	): Promise<WorktreeAnnotationCommandOutcome> => {
		if (isDisposed) return Promise.reject(new Error('Annotation surface client is disposed.'));
		const workerRequestId = surfaceClient.send({
			command: 'annotationCommand',
			epoch: currentSurfaceEpoch(surfaceClient),
			operation,
			surface: surfaceClient.surface,
		});
		return new Promise<WorktreeAnnotationCommandOutcome>((resolve, reject): void => {
			const pendingCommand: PendingAnnotationCommand = {
				productRequestId: null,
				reject,
				resolve,
			};
			pendingCommandsByWorkerRequestId.set(workerRequestId, pendingCommand);
			const degradedFailure = degradedFailureByWorkerRequestId.get(workerRequestId);
			if (degradedFailure !== undefined) {
				degradedFailureByWorkerRequestId.delete(workerRequestId);
				failWorkerRequest(workerRequestId, degradedFailure);
				return;
			}
			const acceptedProductRequestId =
				acceptedProductRequestIdByWorkerRequestId.get(workerRequestId);
			if (acceptedProductRequestId !== undefined) {
				acceptedProductRequestIdByWorkerRequestId.delete(workerRequestId);
				acceptProductRequest(workerRequestId, acceptedProductRequestId);
			}
		});
	};
	const inspectOutput = (attemptId: string): Promise<WorktreeAnnotationOutputInspection> => {
		if (isDisposed) return Promise.reject(new Error('Annotation surface client is disposed.'));
		const workerRequestId = surfaceClient.send({
			attemptId,
			command: 'annotationOutputInspect',
			epoch: currentSurfaceEpoch(surfaceClient),
			surface: surfaceClient.surface,
		});
		return new Promise<WorktreeAnnotationOutputInspection>((resolve, reject): void => {
			pendingOutputInspectionsByWorkerRequestId.set(workerRequestId, { reject, resolve });
			const degradedFailure = degradedFailureByWorkerRequestId.get(workerRequestId);
			if (degradedFailure === undefined) return;
			degradedFailureByWorkerRequestId.delete(workerRequestId);
			failWorkerRequest(workerRequestId, degradedFailure);
		});
	};
	const queryOutputCandidates = (
		query: BridgeProductCallRequest<'file.annotations.output.candidates.query'>,
	): Promise<BridgeProductCallResult<'file.annotations.output.candidates.query'>> => {
		if (isDisposed) return Promise.reject(new Error('Annotation surface client is disposed.'));
		const workerRequestId = surfaceClient.send({
			command: 'annotationOutputCandidatesQuery',
			epoch: currentSurfaceEpoch(surfaceClient),
			query,
			surface: surfaceClient.surface,
		});
		return new Promise((resolve, reject): void => {
			pendingOutputCandidateQueriesByWorkerRequestId.set(workerRequestId, { reject, resolve });
			const degradedFailure = degradedFailureByWorkerRequestId.get(workerRequestId);
			if (degradedFailure === undefined) return;
			degradedFailureByWorkerRequestId.delete(workerRequestId);
			failWorkerRequest(workerRequestId, degradedFailure);
		});
	};
	const waitForSnapshot = <TResult>(
		select: (snapshot: WorktreeAnnotationProjectionSnapshot) => TResult | null,
	): Promise<TResult> => {
		if (isDisposed) return Promise.reject(new Error('Annotation surface client is disposed.'));
		const currentResult = select(projectionStore.getSnapshot());
		if (currentResult !== null) return Promise.resolve(currentResult);
		return new Promise<TResult>((resolve, reject): void => {
			let unsubscribe = noopUnsubscribe;
			const rejectWaiter = (error: Error): void => {
				unsubscribe();
				rejectPendingSnapshotWaiters.delete(rejectWaiter);
				reject(error);
			};
			rejectPendingSnapshotWaiters.add(rejectWaiter);
			unsubscribe = projectionStore.subscribe((): void => {
				const result = select(projectionStore.getSnapshot());
				if (result === null) return;
				unsubscribe();
				rejectPendingSnapshotWaiters.delete(rejectWaiter);
				resolve(result);
			});
		});
	};
	const refreshDemandedSession = (sessionId: string): void => {
		nextSourceRefreshEpoch += 1;
		void execute({
			kind: 'source.refresh',
			sessionId,
			sourceEpoch: nextSourceRefreshEpoch,
		}).catch((): void => {});
	};
	const unsubscribeSourceEpoch = surfaceClient.renderStore.subscribe((): void => {
		const currentEpoch = currentSurfaceEpoch(surfaceClient);
		if (currentEpoch === observedSurfaceEpoch) return;
		observedSurfaceEpoch = currentEpoch;
		for (const sessionId of demandCountBySessionId.keys()) refreshDemandedSession(sessionId);
	});

	return {
		acquireSession: (sessionId): (() => void) => {
			const currentDemandCount = demandCountBySessionId.get(sessionId) ?? 0;
			demandCountBySessionId.set(sessionId, currentDemandCount + 1);
			if (currentDemandCount === 0) {
				void execute({ kind: 'demand.acquire', sessionId }).catch((): void => {});
				refreshDemandedSession(sessionId);
				void execute({ kind: 'output.history', sessionId }).catch((): void => {});
			}
			let isReleased = false;
			return (): void => {
				if (isReleased || isDisposed) return;
				isReleased = true;
				const nextDemandCount = (demandCountBySessionId.get(sessionId) ?? 1) - 1;
				if (nextDemandCount > 0) {
					demandCountBySessionId.set(sessionId, nextDemandCount);
					return;
				}
				demandCountBySessionId.delete(sessionId);
				void execute({ kind: 'demand.release', sessionId }).catch((): void => {});
			};
		},
		dispose: (): void => {
			if (isDisposed) return;
			isDisposed = true;
			unsubscribeMessages();
			unsubscribeSourceEpoch();
			const disposalError = new Error('Annotation surface client is disposed.');
			for (const pendingCommand of pendingCommandsByWorkerRequestId.values()) {
				pendingCommand.reject(disposalError);
			}
			pendingCommandsByWorkerRequestId.clear();
			for (const pendingInspection of pendingOutputInspectionsByWorkerRequestId.values()) {
				pendingInspection.reject(disposalError);
			}
			pendingOutputInspectionsByWorkerRequestId.clear();
			for (const pendingQuery of pendingOutputCandidateQueriesByWorkerRequestId.values()) {
				pendingQuery.reject(disposalError);
			}
			pendingOutputCandidateQueriesByWorkerRequestId.clear();
			pendingWorkerRequestIdByProductRequestId.clear();
			outcomesByProductRequestId.clear();
			acceptedProductRequestIdByWorkerRequestId.clear();
			degradedFailureByWorkerRequestId.clear();
			for (const rejectWaiter of rejectPendingSnapshotWaiters) rejectWaiter(disposalError);
			rejectPendingSnapshotWaiters.clear();
			demandCountBySessionId.clear();
		},
		execute,
		getServerSnapshot: projectionStore.getServerSnapshot,
		getSnapshot: projectionStore.getSnapshot,
		inspectOutput,
		queryOutputCandidates,
		retryProjection: (): void => {
			if (isDisposed) return;
			surfaceClient.send({
				command: 'annotationProjectionRetry',
				epoch: currentSurfaceEpoch(surfaceClient),
				surface: surfaceClient.surface,
			});
		},
		subscribe: projectionStore.subscribe,
		waitForSnapshot,
	};
}

function retainBoundedOrphanCorrelation<TKey, TValue>(
	map: Map<TKey, TValue>,
	key: TKey,
	value: TValue,
): void {
	map.set(key, value);
	if (map.size <= maximumRetainedOrphanCorrelationCount) return;
	const oldestKey = map.keys().next().value;
	if (oldestKey !== undefined) map.delete(oldestKey);
}

function currentSurfaceEpoch(surfaceClient: BridgePaneSurfaceClient): number {
	const renderSnapshot = surfaceClient.renderStore.getSnapshot();
	return surfaceClient.surface === 'fileView'
		? (renderSnapshot.fileDisplayFreshness?.epoch ?? 0)
		: (renderSnapshot.reviewDisplayFreshness?.epoch ?? 0);
}
