import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type {
	BridgeProductReviewAnnotationPublicationIdentity,
	BridgeProductWorktreeAnnotationOperation,
} from '../core/comm-worker/bridge-product-call-contracts.js';
import type { BridgeProductAnnotationOutputContentDescriptor } from '../core/comm-worker/bridge-product-content-contracts.js';
import type { BridgeWorkerServerToMainMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import { recordWorktreeAnnotationLifecycleTelemetry } from './worktree-annotation-lifecycle-telemetry.js';
import {
	WorktreeAnnotationProjectionStore,
	type WorktreeAnnotationCatalogProjection,
	type WorktreeAnnotationCommandOutcome,
	type WorktreeAnnotationProjectionSnapshot,
} from './worktree-annotation-projection-store.js';

const noopUnsubscribe = (): void => {};
const maximumRetainedOrphanCorrelationCount = 128;
const annotationCatalogStagingEncoder = new TextEncoder();
export {
	emptyWorktreeAnnotationProjectionSnapshot,
	WorktreeAnnotationProjectionStore,
} from './worktree-annotation-projection-store.js';
export type {
	WorktreeAnnotationCatalogProjection,
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
	readonly getCatalogSnapshot: () => WorktreeAnnotationCatalogProjection;
	readonly getSnapshot: () => WorktreeAnnotationProjectionSnapshot;
	readonly inspectOutput: (attemptId: string) => Promise<WorktreeAnnotationOutputInspection>;
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

export function createWorktreeAnnotationSurfaceClient(
	surfaceClient: BridgePaneSurfaceClient,
	telemetryRecorder?: BridgeTelemetryRecorder,
): WorktreeAnnotationSurfaceClient {
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
	const projectionStore = new WorktreeAnnotationProjectionStore();

	const settleProductOutcome = (outcome: WorktreeAnnotationCommandOutcome): void => {
		projectionStore.recordCommandOutcome(outcome);
		if (outcome.status.kind === 'history') {
			if (outcome.sessionId === null) {
				projectionStore.replaceOutputHistory(outcome.status.summaries);
			} else {
				projectionStore.replaceOutputHistoryForSession(outcome.sessionId, outcome.status.summaries);
			}
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
		if (pendingCommand === undefined && pendingOutputInspection === undefined) {
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
	};

	const unsubscribeMessages = surfaceClient.subscribeMessages(
		(message: BridgeWorkerServerToMainMessage): void => {
			if (isDisposed) return;
			if (message.kind === 'annotationCatalogStaging') {
				if (message.surface === surfaceClient.surface) {
					applyAnnotationCatalogStagingMessage({
						message,
						projectionStore,
						telemetryRecorder,
						viewer: surfaceClient.surface === 'fileView' ? 'file' : 'review',
					});
				}
				return;
			}
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
				if (message.outcome !== undefined) settleProductOutcome(message.outcome);
				return;
			}
			if (message.kind === 'annotationProjectionConvergence') {
				if (message.surface !== surfaceClient.surface) return;
				if (message.state.kind === 'ready') {
					if (message.operationCorrelationId !== null) {
						projectionStore.apply(
							message.state.snapshot,
							message.operationCorrelationId,
							message.state.contentSessionIds,
							[...demandCountBySessionId.keys()],
						);
						for (const sessionId of message.state.contentSessionIds) {
							if (!demandCountBySessionId.has(sessionId)) continue;
							void execute({ kind: 'output.history', sessionId }).catch((): void => {});
						}
						recordWorktreeAnnotationLifecycleTelemetry({
							operationCorrelationId: message.operationCorrelationId,
							phase: 'projection_store_terminal',
							recorder: telemetryRecorder,
							result: 'success',
							sourceGeneration: message.state.snapshot.sourceGeneration,
							transport: 'local',
							viewer: surfaceClient.surface === 'fileView' ? 'file' : 'review',
						});
						recordWorktreeAnnotationLifecycleTelemetry({
							operationCorrelationId: message.operationCorrelationId,
							phase: 'main_thread_install_terminal',
							recorder: telemetryRecorder,
							result: 'success',
							sourceGeneration: message.state.snapshot.sourceGeneration,
							transport: 'local',
							viewer: surfaceClient.surface === 'fileView' ? 'file' : 'review',
						});
					}
				} else if (message.state.kind === 'refreshing') {
					projectionStore.markRefreshing();
				} else {
					if (message.state.catalogAuthorityRetired) {
						projectionStore.prepareForWorkerReplacement();
					}
					projectionStore.markUnavailable(message.state.retryable);
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
		let workerRequestId: string;
		try {
			workerRequestId =
				surfaceClient.surface === 'fileView'
					? surfaceClient.send({
							command: 'annotationCommand',
							epoch: currentSurfaceEpoch(surfaceClient),
							operation,
							surface: 'fileView',
						})
					: sendReviewAnnotationCommand(surfaceClient, operation);
		} catch (error) {
			return Promise.reject(
				error instanceof Error ? error : new Error('Review annotation command admission failed.'),
			);
		}
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
	const unsubscribeWorkerReplacement =
		surfaceClient.subscribeWorkerReplacement?.((): void => {
			projectionStore.prepareForWorkerReplacement();
		}) ?? noopUnsubscribe;

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
			unsubscribeWorkerReplacement();
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
			outcomesByProductRequestId.clear();
			acceptedProductRequestIdByWorkerRequestId.clear();
			degradedFailureByWorkerRequestId.clear();
			for (const rejectWaiter of rejectPendingSnapshotWaiters) rejectWaiter(disposalError);
			rejectPendingSnapshotWaiters.clear();
			demandCountBySessionId.clear();
		},
		execute,
		getCatalogSnapshot: projectionStore.getCatalogSnapshot,
		getServerSnapshot: projectionStore.getServerSnapshot,
		getSnapshot: projectionStore.getSnapshot,
		inspectOutput,
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

function applyAnnotationCatalogStagingMessage(props: {
	readonly message: Extract<
		BridgeWorkerServerToMainMessage,
		{ readonly kind: 'annotationCatalogStaging' }
	>;
	readonly projectionStore: WorktreeAnnotationProjectionStore;
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
	readonly viewer: 'file' | 'review';
}): void {
	if (props.telemetryRecorder?.isEnabled('web') !== true) {
		props.projectionStore.applyCatalogStaging(props.message);
		return;
	}
	const presentationRevisionBefore = props.projectionStore.getSnapshot().presentationRevision;
	const result = props.projectionStore.applyCatalogStaging(props.message);
	const presentationRevisionAfter = props.projectionStore.getSnapshot().presentationRevision;
	const common = {
		catalogRevision: props.message.transfer.catalogRevision,
		encodedUnitByteCount: annotationCatalogStagingEncoder.encode(JSON.stringify(props.message))
			.byteLength,
		presentationRevisionAfter,
		presentationRevisionBefore,
	};
	const lifecycle = {
		operationCorrelationId: props.message.operationCorrelationId,
		recorder: props.telemetryRecorder,
		result: result.status === 'rejected' ? ('failure' as const) : ('success' as const),
		transport: 'local' as const,
		viewer: props.viewer,
	};
	switch (props.message.transfer.kind) {
		case 'catalog.begin':
			recordWorktreeAnnotationLifecycleTelemetry({
				...lifecycle,
				catalogStaging: {
					...common,
					entryCount: props.message.transfer.expectedEntryCount,
					kind: 'begin',
				},
				phase: 'annotation_catalog_main_begin',
			});
			return;
		case 'catalog.commit':
			recordWorktreeAnnotationLifecycleTelemetry({
				...lifecycle,
				catalogStaging: {
					...common,
					entryCount: props.message.transfer.entryCount,
					kind: 'commit',
					windowCount: props.message.transfer.windowCount,
				},
				phase: 'annotation_catalog_main_commit',
			});
			return;
		case 'catalog.window':
			recordWorktreeAnnotationLifecycleTelemetry({
				...lifecycle,
				catalogStaging: {
					...common,
					entryCount: props.message.transfer.entries.length,
					kind: 'window',
					windowOrdinal: props.message.transfer.windowOrdinal,
				},
				phase: 'annotation_catalog_main_window',
			});
	}
}

function sendReviewAnnotationCommand(
	surfaceClient: BridgePaneSurfaceClient,
	operation: BridgeProductWorktreeAnnotationOperation,
): string {
	const activeIdentity = surfaceClient.renderStore.getReviewRefreshPresentation().activeIdentity;
	if (activeIdentity === null) {
		throw new Error('Review annotation command has no installed publication identity.');
	}
	const reviewPublicationIdentity = {
		packageId: activeIdentity.packageId,
		publicationId: activeIdentity.publicationId,
		reviewGeneration: activeIdentity.generation,
		revision: activeIdentity.revision,
		sourceIdentity: activeIdentity.sourceIdentity,
	} satisfies BridgeProductReviewAnnotationPublicationIdentity;
	return surfaceClient.send({
		command: 'annotationCommand',
		epoch: currentSurfaceEpoch(surfaceClient),
		operation,
		reviewPublicationIdentity,
		surface: 'review',
	});
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
