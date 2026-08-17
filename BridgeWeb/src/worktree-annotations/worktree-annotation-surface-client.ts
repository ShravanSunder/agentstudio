import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type { BridgeProductWorktreeAnnotationOperation } from '../core/comm-worker/bridge-product-call-contracts.js';
import type { BridgeProductAnnotationOutputContentDescriptor } from '../core/comm-worker/bridge-product-content-contracts.js';
import type { BridgeProductWorktreeAnnotationEvent } from '../core/comm-worker/bridge-product-worktree-annotation-contracts.js';
import type { BridgeWorkerServerToMainMessage } from '../core/comm-worker/bridge-worker-contracts.js';

type WorktreeAnnotationProjectionStateEvent = Extract<
	BridgeProductWorktreeAnnotationEvent,
	{ readonly eventKind: 'projection.state' }
>;
type WorktreeAnnotationMessageBatchEvent = Extract<
	BridgeProductWorktreeAnnotationEvent,
	{ readonly eventKind: 'message.batch' }
>;

export type WorktreeAnnotationCommandOutcome =
	WorktreeAnnotationProjectionStateEvent['payload']['commandOutcomes'][number];
export type WorktreeAnnotationOutputHistorySummary =
	WorktreeAnnotationProjectionStateEvent['payload']['outputHistory'][number];
export type WorktreeAnnotationSessionSummary =
	WorktreeAnnotationProjectionStateEvent['payload']['sessions'][number];
export type WorktreeAnnotationMessageEntry =
	WorktreeAnnotationMessageBatchEvent['payload']['messages'][number];
export type WorktreeAnnotationThreadContext =
	WorktreeAnnotationMessageBatchEvent['payload']['context'];

export interface WorktreeAnnotationThreadProjection {
	readonly context: WorktreeAnnotationThreadContext;
	readonly messages: readonly WorktreeAnnotationMessageEntry[];
}

export interface WorktreeAnnotationOutputInspection {
	readonly descriptor: BridgeProductAnnotationOutputContentDescriptor;
	readonly exactBytes: Uint8Array;
}

export interface WorktreeAnnotationProjectionSnapshot {
	readonly commandOutcomes: readonly WorktreeAnnotationCommandOutcome[];
	readonly outputHistory: readonly WorktreeAnnotationOutputHistorySummary[];
	readonly presentationRevision: number;
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
	recoveryStatus: 'available',
	revision: null,
	sessions: [],
	threads: [],
	worktreeId: null,
};

export class WorktreeAnnotationProjectionStore {
	readonly #listeners = new Set<() => void>();
	readonly #messagesByThreadId = new Map<string, Map<string, WorktreeAnnotationMessageEntry>>();
	readonly #publishedThreadsById = new Map<string, WorktreeAnnotationThreadProjection>();
	#snapshot = emptyWorktreeAnnotationProjectionSnapshot;

	getSnapshot = (): WorktreeAnnotationProjectionSnapshot => this.#snapshot;

	getServerSnapshot = (): WorktreeAnnotationProjectionSnapshot => this.#snapshot;

	subscribe = (listener: () => void): (() => void) => {
		this.#listeners.add(listener);
		return (): void => {
			this.#listeners.delete(listener);
		};
	};

	apply(event: BridgeProductWorktreeAnnotationEvent): void {
		if (event.eventKind === 'projection.state') {
			this.#applyProjectionState(event);
			return;
		}
		this.#applyMessageBatch(event);
	}

	#applyProjectionState(event: WorktreeAnnotationProjectionStateEvent): void {
		if (this.#snapshot.revision !== null && event.payload.revision < this.#snapshot.revision) {
			return;
		}
		this.#messagesByThreadId.clear();
		this.#publishedThreadsById.clear();
		this.#publish({
			commandOutcomes: event.payload.commandOutcomes,
			outputHistory: event.payload.outputHistory,
			recoveryStatus: event.payload.recoveryStatus,
			revision: event.payload.revision,
			sessions: event.payload.sessions,
			threads: [],
			worktreeId: event.payload.worktreeId,
		});
	}

	#applyMessageBatch(event: WorktreeAnnotationMessageBatchEvent): void {
		if (event.payload.revision !== this.#snapshot.revision) return;
		const threadId = event.payload.context.threadId;
		const messagesById = this.#messagesByThreadId.get(threadId) ?? new Map();
		for (const message of event.payload.messages) messagesById.set(message.messageId, message);
		this.#messagesByThreadId.set(threadId, messagesById);
		if (!event.payload.isLastBatchForThread) return;

		this.#publishedThreadsById.set(threadId, {
			context: event.payload.context,
			messages: [...messagesById.values()].sort(
				(left, right): number => left.ordinal - right.ordinal,
			),
		});
		this.#publish({
			...this.#snapshot,
			threads: [...this.#publishedThreadsById.values()].sort(compareAnnotationThreads),
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

export interface WorktreeAnnotationSurfaceClient {
	readonly acquireSession: (sessionId: string) => () => void;
	readonly dispose: () => void;
	readonly execute: (
		operation: BridgeProductWorktreeAnnotationOperation,
	) => Promise<WorktreeAnnotationCommandOutcome>;
	readonly getServerSnapshot: () => WorktreeAnnotationProjectionSnapshot;
	readonly getSnapshot: () => WorktreeAnnotationProjectionSnapshot;
	readonly inspectOutput: (attemptId: string) => Promise<WorktreeAnnotationOutputInspection>;
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

export function createWorktreeAnnotationSurfaceClient(
	surfaceClient: BridgePaneSurfaceClient,
): WorktreeAnnotationSurfaceClient {
	const projectionStore = new WorktreeAnnotationProjectionStore();
	const pendingCommandsByWorkerRequestId = new Map<string, PendingAnnotationCommand>();
	const pendingOutputInspectionsByWorkerRequestId = new Map<
		string,
		PendingAnnotationOutputInspection
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

	const settleProductOutcome = (outcome: WorktreeAnnotationCommandOutcome): void => {
		outcomesByProductRequestId.set(outcome.requestId, outcome);
		const workerRequestId = pendingWorkerRequestIdByProductRequestId.get(outcome.requestId);
		if (workerRequestId === undefined) return;
		const pendingCommand = pendingCommandsByWorkerRequestId.get(workerRequestId);
		if (pendingCommand === undefined) return;
		pendingCommandsByWorkerRequestId.delete(workerRequestId);
		pendingWorkerRequestIdByProductRequestId.delete(outcome.requestId);
		pendingCommand.resolve(outcome);
	};

	const acceptProductRequest = (workerRequestId: string, productRequestId: string): void => {
		const pendingCommand = pendingCommandsByWorkerRequestId.get(workerRequestId);
		if (pendingCommand === undefined) {
			acceptedProductRequestIdByWorkerRequestId.set(workerRequestId, productRequestId);
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
		if (pendingCommand === undefined && pendingOutputInspection === undefined) {
			degradedFailureByWorkerRequestId.set(workerRequestId, error);
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
	};

	const unsubscribeMessages = surfaceClient.subscribeMessages(
		(message: BridgeWorkerServerToMainMessage): void => {
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
			if (message.kind === 'annotationCommandAccepted') {
				acceptProductRequest(message.requestId, message.productRequestId);
				return;
			}
			if (message.kind === 'annotationProjection') {
				projectionStore.apply(message.event);
				if (message.event.eventKind === 'projection.state') {
					for (const outcome of message.event.payload.commandOutcomes) {
						settleProductOutcome(outcome);
					}
				}
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
	const waitForSnapshot = <TResult>(
		select: (snapshot: WorktreeAnnotationProjectionSnapshot) => TResult | null,
	): Promise<TResult> => {
		if (isDisposed) return Promise.reject(new Error('Annotation surface client is disposed.'));
		const currentResult = select(projectionStore.getSnapshot());
		if (currentResult !== null) return Promise.resolve(currentResult);
		return new Promise<TResult>((resolve, reject): void => {
			let unsubscribe = (): void => {};
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
			pendingWorkerRequestIdByProductRequestId.clear();
			for (const rejectWaiter of rejectPendingSnapshotWaiters) rejectWaiter(disposalError);
			rejectPendingSnapshotWaiters.clear();
			demandCountBySessionId.clear();
		},
		execute,
		getServerSnapshot: projectionStore.getServerSnapshot,
		getSnapshot: projectionStore.getSnapshot,
		inspectOutput,
		subscribe: projectionStore.subscribe,
		waitForSnapshot,
	};
}

function currentSurfaceEpoch(surfaceClient: BridgePaneSurfaceClient): number {
	const renderSnapshot = surfaceClient.renderStore.getSnapshot();
	return surfaceClient.surface === 'fileView'
		? (renderSnapshot.fileDisplayFreshness?.epoch ?? 0)
		: (renderSnapshot.reviewDisplayFreshness?.epoch ?? 0);
}

function compareAnnotationThreads(
	left: WorktreeAnnotationThreadProjection,
	right: WorktreeAnnotationThreadProjection,
): number {
	const leftKey = [
		left.context.path ?? '',
		left.context.startLine ?? -1,
		left.context.endLine ?? -1,
		left.context.threadId,
	];
	const rightKey = [
		right.context.path ?? '',
		right.context.startLine ?? -1,
		right.context.endLine ?? -1,
		right.context.threadId,
	];
	return JSON.stringify(leftKey).localeCompare(JSON.stringify(rightKey));
}
