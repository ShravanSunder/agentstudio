import { bridgeContentDemandExecutionPolicy } from '../demand/bridge-content-demand-policy.js';
import type {
	BridgeCommWorkerDemandExecutionScheduleRequest,
	BridgeCommWorkerReviewMetadataResetScheduleRequest,
	BridgeCommWorkerReviewRuntimeSource,
	BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
} from './bridge-comm-worker-command-handler.js';
import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import {
	planBridgeCommWorkerDemandExecution,
	type BridgeCommWorkerDemandBackoff,
	type BridgeCommWorkerDemandMember,
} from './bridge-comm-worker-executor.js';
import {
	enqueueBridgeWorkerReviewContentReadyPreparation,
	enqueueSelectedBridgeWorkerReviewContentReadyPreparation,
	selectedReviewPreparationIdentity,
	type BridgeWorkerReviewContentReadyPreparationTicket,
} from './bridge-comm-worker-review-preparation.js';
import { canRenderBridgeWorkerReviewContentForSemantics } from './bridge-comm-worker-review-runtime.js';
import { enqueueBridgeCommWorkerReviewSourceReset } from './bridge-comm-worker-review-source-reset.js';
import { readBridgeCommWorkerRuntimeNowMilliseconds } from './bridge-comm-worker-runtime-support.js';
import type {
	BridgeCommWorkerStore,
	BridgeCommWorkerStoreState,
} from './bridge-comm-worker-store.js';
import type { BridgeCommWorkerTelemetryRecorder } from './bridge-comm-worker-telemetry.js';
import type { WorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from './bridge-worker-pierre-render-job.js';
import {
	createSharedBridgeWorkerReviewContentResourceFetch,
	type BridgeWorkerReviewContentOpen,
	type BridgeWorkerReviewContentResourceFetch,
} from './bridge-worker-review-content-fetch.js';

interface CreateBridgeCommWorkerReviewDemandSchedulingProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly createSequence: () => number;
	readonly isWorkAdmitted?: () => boolean;
	readonly markPreparationDrainRequired: () => void;
	readonly now?: () => number;
	readonly openReviewContent?: BridgeWorkerReviewContentOpen;
	readonly port: BridgeCommWorkerPort;
	readonly pump: WorkerContentPreparationPump;
	readonly recordPreparationCompletion: (completion: Promise<void>) => void;
	readonly requestPreparationDrain: () => void;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
	readonly usesProductTransport: boolean;
	readonly workSignal?: () => AbortSignal;
}

export interface BridgeCommWorkerReviewDemandScheduling {
	readonly resume: () => void;
	readonly scheduleDemandExecution: (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	) => boolean;
	readonly scheduleMetadataReset: (
		request: BridgeCommWorkerReviewMetadataResetScheduleRequest,
	) => void;
	readonly scheduleSelectedContentReadyPreparation: (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	) => void;
	readonly suspend: () => void;
	readonly updateRuntimeSource: (source: BridgeCommWorkerReviewRuntimeSource) => void;
	readonly updateWorkerDerivationEpoch: (workerDerivationEpoch: number) => void;
}

export interface BridgeCommWorkerVisibleSourceChurnIdentity {
	readonly epoch: number;
	readonly sourceChurnRevision: number | null;
}

export interface BridgeCommWorkerVisibleSourceChurnDedupeState {
	readonly currentIdentity: BridgeCommWorkerVisibleSourceChurnIdentity | null;
	readonly markedItemIds: ReadonlySet<string>;
}

interface RecordBridgeCommWorkerVisibleSourceChurnProps {
	readonly affectedItemIds: readonly string[];
	readonly identity: BridgeCommWorkerVisibleSourceChurnIdentity;
	readonly state: BridgeCommWorkerVisibleSourceChurnDedupeState;
}

export interface BridgeCommWorkerVisibleSourceChurnRecordResult {
	readonly accepted: boolean;
	readonly state: BridgeCommWorkerVisibleSourceChurnDedupeState;
	readonly unmarkedAffectedItemIds: readonly string[];
}

export function createBridgeCommWorkerVisibleSourceChurnDedupeState(): BridgeCommWorkerVisibleSourceChurnDedupeState {
	return {
		currentIdentity: null,
		markedItemIds: new Set(),
	};
}

export function recordBridgeCommWorkerVisibleSourceChurn(
	props: RecordBridgeCommWorkerVisibleSourceChurnProps,
): BridgeCommWorkerVisibleSourceChurnRecordResult {
	const identityOrder = compareBridgeCommWorkerVisibleSourceChurnIdentity(
		props.identity,
		props.state.currentIdentity,
	);
	if (identityOrder < 0) {
		return {
			accepted: false,
			state: props.state,
			unmarkedAffectedItemIds: [],
		};
	}
	const affectedItemIds = [...new Set(props.affectedItemIds)];
	if (identityOrder > 0) {
		return {
			accepted: true,
			state: {
				currentIdentity: props.identity,
				markedItemIds: new Set(affectedItemIds),
			},
			unmarkedAffectedItemIds: affectedItemIds,
		};
	}
	const unmarkedAffectedItemIds = affectedItemIds.filter(
		(itemId) => !props.state.markedItemIds.has(itemId),
	);
	if (unmarkedAffectedItemIds.length === 0) {
		return {
			accepted: true,
			state: props.state,
			unmarkedAffectedItemIds,
		};
	}
	return {
		accepted: true,
		state: {
			currentIdentity: props.state.currentIdentity,
			markedItemIds: new Set([...props.state.markedItemIds, ...unmarkedAffectedItemIds]),
		},
		unmarkedAffectedItemIds,
	};
}

function compareBridgeCommWorkerVisibleSourceChurnIdentity(
	incomingIdentity: BridgeCommWorkerVisibleSourceChurnIdentity,
	currentIdentity: BridgeCommWorkerVisibleSourceChurnIdentity | null,
): number {
	if (currentIdentity === null) return 1;
	if (incomingIdentity.epoch !== currentIdentity.epoch) {
		return incomingIdentity.epoch > currentIdentity.epoch ? 1 : -1;
	}
	if (incomingIdentity.sourceChurnRevision === currentIdentity.sourceChurnRevision) return 0;
	if (incomingIdentity.sourceChurnRevision === null) return -1;
	if (currentIdentity.sourceChurnRevision === null) return 1;
	return incomingIdentity.sourceChurnRevision > currentIdentity.sourceChurnRevision ? 1 : -1;
}

interface BridgeCommWorkerVisibleSourceChurnAdmission {
	readonly accepted: boolean;
	readonly sourceChurnItemIds: ReadonlySet<string>;
}

export function createBridgeCommWorkerReviewDemandScheduling(
	props: CreateBridgeCommWorkerReviewDemandSchedulingProps,
): BridgeCommWorkerReviewDemandScheduling {
	const defaultWorkSignal = new AbortController().signal;
	const isWorkAdmitted = props.isWorkAdmitted ?? bridgeCommWorkerWorkIsAdmitted;
	const paneWorkSignal = props.workSignal ?? ((): AbortSignal => defaultWorkSignal);
	let surfaceActive = false;
	let surfaceWorkLifecycle = createBridgeCommWorkerReviewSurfaceWorkLifecycle(paneWorkSignal());
	const isReviewWorkAdmitted = (): boolean => surfaceActive && isWorkAdmitted();
	const workSignal = (): AbortSignal => surfaceWorkLifecycle.signal;
	let reviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource = {
		contentItems: [],
		contentRequestDescriptors: [],
		renderSemantics: [],
		rows: [],
	};
	const fetchReviewContentResource = createSharedBridgeWorkerReviewContentResourceFetch({
		openContent: props.openReviewContent,
	});
	const demandBackoffByItemId = new Map<string, BridgeCommWorkerDemandBackoff>();
	const demandInFlightItemIds = new Set<string>();
	const pendingVisibleDemandRerunItemIds = new Set<string>();
	const visibleDemandGenerationByItemId = new Map<string, number>();
	let visibleSourceChurnDedupeState = createBridgeCommWorkerVisibleSourceChurnDedupeState();
	const activeSelectedPreparationByItemId = new Map<
		string,
		{
			readonly identity: string;
			readonly ticket: BridgeWorkerReviewContentReadyPreparationTicket;
		}
	>();
	const activeVisiblePreparations = new Set<BridgeWorkerReviewContentReadyPreparationTicket>();
	const activeSpeculativePreparationsByItemId = new Map<
		string,
		ActiveSpeculativeReviewPreparation
	>();
	const latestSelectedPreparationByItemId = new Map<
		string,
		BridgeCommWorkerSelectedReviewContentReadyPreparationRequest
	>();
	const retriedSelectedPreparationRequests =
		new WeakSet<BridgeCommWorkerSelectedReviewContentReadyPreparationRequest>();
	let latestDemandExecutionRequest: BridgeCommWorkerDemandExecutionScheduleRequest | null = null;
	let latestMetadataResetRequest: BridgeCommWorkerReviewMetadataResetScheduleRequest | null = null;
	let activeSourceResetEpoch: number | null = null;
	let activeWorkerDerivationEpoch: number | null = null;

	const markVisibleDemandSourceChurnFromRequest = (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	): BridgeCommWorkerVisibleSourceChurnAdmission => {
		if (request.cause !== 'reviewInvalidate' && request.cause !== 'reviewMetadata') {
			return { accepted: true, sourceChurnItemIds: new Set() };
		}
		const visibleItemIds = visibleReviewDemandItemIdsFromState(request.store.getState());
		const affectedItemIdSet = new Set(request.affectedItemIds ?? visibleItemIds);
		const visibleAffectedItemIds = visibleItemIds.filter((itemId) => affectedItemIdSet.has(itemId));
		const dedupeResult = recordBridgeCommWorkerVisibleSourceChurn({
			affectedItemIds: visibleAffectedItemIds,
			identity: {
				epoch: request.epoch,
				sourceChurnRevision: request.sourceChurnRevision ?? null,
			},
			state: visibleSourceChurnDedupeState,
		});
		if (!dedupeResult.accepted) {
			return { accepted: false, sourceChurnItemIds: new Set() };
		}
		visibleSourceChurnDedupeState = dedupeResult.state;
		const sourceChurnItemIds = markVisibleReviewDemandSourceChurn({
			affectedItemIds: dedupeResult.unmarkedAffectedItemIds,
			cause: request.cause,
			inFlightItemIds: demandInFlightItemIds,
			pendingRerunItemIds: pendingVisibleDemandRerunItemIds,
			store: request.store,
			visibleDemandGenerationByItemId,
		});
		return { accepted: true, sourceChurnItemIds };
	};

	const enqueueVisibleDemandExecutionFromRequest = (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
		forcedSourceChurnItemIds: ReadonlySet<string> = new Set(),
		shouldMarkSourceChurn = true,
	): boolean => {
		latestDemandExecutionRequest = request;
		if (!isReviewWorkAdmitted()) {
			return false;
		}
		const workerDerivationEpoch = props.usesProductTransport
			? activeWorkerDerivationEpoch
			: request.epoch;
		if (workerDerivationEpoch === null) {
			return false;
		}
		const sourceChurnAdmission = shouldMarkSourceChurn
			? markVisibleDemandSourceChurnFromRequest(request)
			: { accepted: true, sourceChurnItemIds: new Set<string>() };
		if (!sourceChurnAdmission.accepted) {
			return false;
		}
		const admittedWorkSignal = workSignal();
		const forceExecutionItemIds = new Set([
			...sourceChurnAdmission.sourceChurnItemIds,
			...(request.forceExecutionItemIds ?? []),
			...forcedSourceChurnItemIds,
		]);
		const tickets = enqueueVisibleBridgeCommWorkerReviewDemandExecution({
			backoffByItemId: demandBackoffByItemId,
			budget: props.budget,
			createSequence: props.createSequence,
			epoch: request.epoch,
			...(props.openReviewContent === undefined ? {} : { openContent: props.openReviewContent }),
			fetchReviewContentResource,
			inFlightItemIds: demandInFlightItemIds,
			nowMilliseconds: readBridgeCommWorkerRuntimeNowMilliseconds(props.now),
			pendingRerunItemIds: pendingVisibleDemandRerunItemIds,
			port: props.port,
			pump: props.pump,
			requestPreparationDrain: props.requestPreparationDrain,
			requestVisibleDemandRerun: (itemId: string): void => {
				if (latestDemandExecutionRequest === null) {
					return;
				}
				if (
					enqueueVisibleDemandExecutionFromRequest(latestDemandExecutionRequest, new Set([itemId]))
				) {
					props.requestPreparationDrain();
				}
			},
			reviewRuntimeSource,
			signal: admittedWorkSignal,
			sourceChurnItemIds: forceExecutionItemIds,
			store: request.store,
			visibleDemandGenerationByItemId,
			workerDerivationEpoch,
		});
		let enqueued = reconcileSpeculativeReviewDemandExecution({
			activePreparationsByItemId: activeSpeculativePreparationsByItemId,
			budget: props.budget,
			createSequence: props.createSequence,
			epoch: request.epoch,
			...(props.openReviewContent === undefined ? {} : { openContent: props.openReviewContent }),
			fetchReviewContentResource,
			port: props.port,
			pump: props.pump,
			recordPreparationCompletion: props.recordPreparationCompletion,
			onPreparationSettled: rederiveLatestDemandExecution,
			requestPreparationDrain: props.requestPreparationDrain,
			reviewRuntimeSource,
			signal: admittedWorkSignal,
			store: request.store,
			workerDerivationEpoch,
		});
		let startedItemCount = 0;
		for (const ticket of tickets) {
			if (ticket.enqueued) {
				activeVisiblePreparations.add(ticket);
				void ticket.completion.finally((): void => {
					activeVisiblePreparations.delete(ticket);
				});
				props.recordPreparationCompletion(ticket.completion);
				enqueued = true;
				startedItemCount += 1;
			}
		}
		if (startedItemCount > 0) {
			void Promise.allSettled(tickets.map((ticket) => ticket.completion)).then(() => {
				if (
					enqueueVisibleDemandExecutionFromRequest(
						{ ...request, forceExecutionItemIds: [] },
						new Set(),
						false,
					)
				) {
					props.requestPreparationDrain();
				}
			});
		} else if (
			activeVisiblePreparations.size === 0 &&
			activeSpeculativePreparationsByItemId.size === 0 &&
			latestDemandExecutionRequest === request
		) {
			latestDemandExecutionRequest = null;
		}
		return enqueued;
	};

	function rederiveLatestDemandExecution(): void {
		if (activeSelectedPreparationByItemId.size > 0 || latestDemandExecutionRequest === null) {
			return;
		}
		if (enqueueVisibleDemandExecutionFromRequest(latestDemandExecutionRequest)) {
			props.requestPreparationDrain();
		}
	}

	const scheduleSelectedContentReadyPreparation = (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	): void => {
		cancelSpeculativeReviewPreparations(activeSpeculativePreparationsByItemId);
		latestSelectedPreparationByItemId.set(request.itemId, request);
		if (!isReviewWorkAdmitted()) {
			return;
		}
		const workerDerivationEpoch = props.usesProductTransport
			? activeWorkerDerivationEpoch
			: request.epoch;
		if (workerDerivationEpoch === null) {
			return;
		}
		const preparationIdentity = selectedReviewPreparationIdentity({
			epoch: request.epoch,
			itemId: request.itemId,
			source: reviewRuntimeSource,
			workerDerivationEpoch,
		});
		const activePreparation = activeSelectedPreparationByItemId.get(request.itemId);
		if (activePreparation?.identity === preparationIdentity) {
			return;
		}
		activePreparation?.ticket.cancel();
		const ticket = enqueueSelectedBridgeWorkerReviewContentReadyPreparation({
			bridgeDemandRank: props.bridgeDemandRank,
			budget: props.budget,
			contentRequestDescriptors: reviewRuntimeSource.contentRequestDescriptors,
			epoch: request.epoch,
			...(props.openReviewContent === undefined ? {} : { openContent: props.openReviewContent }),
			fetchReviewContentResource,
			itemId: request.itemId,
			port: props.port,
			pump: props.pump,
			renderSemantics: reviewRuntimeSource.renderSemantics,
			requestPreparationDrain: props.requestPreparationDrain,
			sequence: props.createSequence(),
			signal: workSignal(),
			store: request.store,
			workerDerivationEpoch,
			...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
		});
		if (ticket.enqueued) {
			activeSelectedPreparationByItemId.set(request.itemId, {
				identity: preparationIdentity,
				ticket,
			});
			const trackedCompletion = ticket.completion.finally(() => {
				if (activeSelectedPreparationByItemId.get(request.itemId)?.ticket === ticket) {
					activeSelectedPreparationByItemId.delete(request.itemId);
					if (latestSelectedPreparationByItemId.get(request.itemId) === request) {
						if (!isReviewWorkAdmitted()) {
							return;
						}
						if (request.store.getState().selectedId !== request.itemId) {
							latestSelectedPreparationByItemId.delete(request.itemId);
						} else if (
							request.store.getState().availabilityByItemId.get(request.itemId) === 'failed' &&
							!retriedSelectedPreparationRequests.has(request)
						) {
							retriedSelectedPreparationRequests.add(request);
							scheduleSelectedContentReadyPreparation(request);
							props.requestPreparationDrain();
						} else {
							latestSelectedPreparationByItemId.delete(request.itemId);
						}
					}
				}
				rederiveLatestDemandExecution();
			});
			props.recordPreparationCompletion(trackedCompletion);
			props.markPreparationDrainRequired();
		} else {
			rederiveLatestDemandExecution();
		}
	};

	const scheduleMetadataReset = (
		request: BridgeCommWorkerReviewMetadataResetScheduleRequest,
	): void => {
		latestMetadataResetRequest = request;
		if (!isReviewWorkAdmitted()) return;
		const sourceChurnAdmission = markVisibleDemandSourceChurnFromRequest({
			affectedItemIds: request.affectedItemIds,
			cause: request.cause,
			epoch: request.epoch,
			store: request.store,
		});
		if (!sourceChurnAdmission.accepted) return;
		activeSourceResetEpoch = request.epoch;
		const ticket = enqueueBridgeCommWorkerReviewSourceReset({
			createSequence: props.createSequence,
			isCurrentResetEpoch: () => isReviewWorkAdmitted() && activeSourceResetEpoch === request.epoch,
			onResetComplete: () => {
				if (activeSourceResetEpoch === request.epoch) {
					activeSourceResetEpoch = null;
					if (latestMetadataResetRequest === request) {
						latestMetadataResetRequest = null;
					}
				}
			},
			pump: props.pump,
			request,
			requestPreparationDrain: props.requestPreparationDrain,
			scheduleDemandExecution: enqueueVisibleDemandExecutionFromRequest,
			scheduleSelectedReviewContentReadyPreparation: scheduleSelectedContentReadyPreparation,
		});
		if (ticket.enqueued) props.markPreparationDrainRequired();
	};

	const suspend = (): void => {
		surfaceActive = false;
		surfaceWorkLifecycle.abort('review_surface_suspended');
		for (const activePreparation of activeSelectedPreparationByItemId.values()) {
			activePreparation.ticket.cancel();
		}
		activeSelectedPreparationByItemId.clear();
		for (const ticket of activeVisiblePreparations) ticket.cancel();
		activeVisiblePreparations.clear();
		cancelSpeculativeReviewPreparations(activeSpeculativePreparationsByItemId);
		demandInFlightItemIds.clear();
		if (activeSourceResetEpoch !== null) {
			props.pump.cancel(`review-source-reset:${activeSourceResetEpoch}`);
			activeSourceResetEpoch = null;
		}
		pendingVisibleDemandRerunItemIds.clear();
	};

	const resume = (): void => {
		surfaceActive = true;
		if (!isWorkAdmitted()) return;
		if (surfaceWorkLifecycle.signal.aborted) {
			surfaceWorkLifecycle = createBridgeCommWorkerReviewSurfaceWorkLifecycle(paneWorkSignal());
		}
		if (surfaceWorkLifecycle.signal.aborted) return;
		if (latestMetadataResetRequest !== null) scheduleMetadataReset(latestMetadataResetRequest);
		if (latestDemandExecutionRequest !== null) {
			enqueueVisibleDemandExecutionFromRequest(latestDemandExecutionRequest);
		}
		for (const [itemId, request] of latestSelectedPreparationByItemId) {
			if (request.store.getState().selectedId === itemId) {
				scheduleSelectedContentReadyPreparation(request);
			}
		}
		if (props.pump.getPendingWorkIds().length > 0) props.requestPreparationDrain();
	};

	return {
		resume,
		scheduleDemandExecution: enqueueVisibleDemandExecutionFromRequest,
		scheduleMetadataReset,
		scheduleSelectedContentReadyPreparation,
		suspend,
		updateRuntimeSource: (source: BridgeCommWorkerReviewRuntimeSource): void => {
			reviewRuntimeSource = source;
		},
		updateWorkerDerivationEpoch: (workerDerivationEpoch: number): void => {
			activeWorkerDerivationEpoch = workerDerivationEpoch;
		},
	};
}

interface ReconcileSpeculativeReviewDemandExecutionProps {
	readonly activePreparationsByItemId: Map<string, ActiveSpeculativeReviewPreparation>;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly createSequence: () => number;
	readonly epoch: number;
	readonly fetchReviewContentResource?: BridgeWorkerReviewContentResourceFetch;
	readonly openContent?: BridgeWorkerReviewContentOpen;
	readonly onPreparationSettled: () => void;
	readonly port: BridgeCommWorkerPort;
	readonly pump: WorkerContentPreparationPump;
	readonly recordPreparationCompletion: (completion: Promise<void>) => void;
	readonly requestPreparationDrain: () => void;
	readonly reviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource;
	readonly signal: AbortSignal;
	readonly store: BridgeCommWorkerStore;
	readonly workerDerivationEpoch: number;
}

interface ActiveSpeculativeReviewPreparation {
	readonly abortController: AbortController;
	readonly detachParentAbort: () => void;
	readonly ticket: BridgeWorkerReviewContentReadyPreparationTicket;
}

function reconcileSpeculativeReviewDemandExecution(
	props: ReconcileSpeculativeReviewDemandExecutionProps,
): boolean {
	const hoveredItemId = speculativeReviewDemandItemIdFromState(props.store.getState());
	for (const [itemId, preparation] of props.activePreparationsByItemId) {
		if (itemId === hoveredItemId) continue;
		cancelSpeculativeReviewPreparation(preparation);
		props.activePreparationsByItemId.delete(itemId);
	}
	if (
		hoveredItemId === null ||
		props.activePreparationsByItemId.has(hoveredItemId) ||
		props.activePreparationsByItemId.size >=
			bridgeContentDemandExecutionPolicy.speculativeStartConcurrency ||
		!doesReviewDemandNeedExecution(props.store, hoveredItemId) ||
		!hasReviewRuntimeSourceContent(props.reviewRuntimeSource, hoveredItemId)
	) {
		return false;
	}
	const abortContext = createSpeculativeReviewAbortContext(props.signal);
	const ticket = enqueueBridgeWorkerReviewContentReadyPreparation({
		bridgeDemandRank: { lane: 'speculative', priority: 1 },
		budget: {
			className: 'background',
			maxBytes: props.budget.maxBytes,
			maxWindowLines: props.budget.maxWindowLines,
		},
		contentRequestDescriptors: props.reviewRuntimeSource.contentRequestDescriptors,
		demandKey: 'speculative',
		epoch: props.epoch,
		...(props.fetchReviewContentResource === undefined
			? {}
			: { fetchReviewContentResource: props.fetchReviewContentResource }),
		...(props.openContent === undefined ? {} : { openContent: props.openContent }),
		isDemandCurrent: (): boolean =>
			props.store.getState().demandByKey.get(hoveredItemId) === 'speculative',
		itemId: hoveredItemId,
		port: props.port,
		preparationRank: 'speculative',
		pump: props.pump,
		renderSemantics: props.reviewRuntimeSource.renderSemantics,
		requestPreparationDrain: props.requestPreparationDrain,
		sequence: props.createSequence(),
		signal: abortContext.abortController.signal,
		store: props.store,
		workerDerivationEpoch: props.workerDerivationEpoch,
	});
	if (!ticket.enqueued) {
		abortContext.detachParentAbort();
		return false;
	}
	const preparation: ActiveSpeculativeReviewPreparation = {
		...abortContext,
		ticket,
	};
	props.activePreparationsByItemId.set(hoveredItemId, preparation);
	const trackedCompletion = ticket.completion.finally((): void => {
		abortContext.detachParentAbort();
		if (props.activePreparationsByItemId.get(hoveredItemId) === preparation) {
			props.activePreparationsByItemId.delete(hoveredItemId);
		}
		props.onPreparationSettled();
	});
	props.recordPreparationCompletion(trackedCompletion);
	props.requestPreparationDrain();
	return true;
}

function cancelSpeculativeReviewPreparations(
	activePreparationsByItemId: Map<string, ActiveSpeculativeReviewPreparation>,
): void {
	for (const preparation of activePreparationsByItemId.values()) {
		cancelSpeculativeReviewPreparation(preparation);
	}
	activePreparationsByItemId.clear();
}

function cancelSpeculativeReviewPreparation(preparation: ActiveSpeculativeReviewPreparation): void {
	preparation.abortController.abort('review_hover_changed');
	preparation.ticket.cancel();
	preparation.detachParentAbort();
}

function createSpeculativeReviewAbortContext(
	parentSignal: AbortSignal,
): Pick<ActiveSpeculativeReviewPreparation, 'abortController' | 'detachParentAbort'> {
	const abortController = new AbortController();
	const abortFromParent = (): void => {
		abortController.abort(parentSignal.reason);
	};
	if (parentSignal.aborted) {
		abortFromParent();
	} else {
		parentSignal.addEventListener('abort', abortFromParent, { once: true });
	}
	return {
		abortController,
		detachParentAbort: (): void => {
			parentSignal.removeEventListener('abort', abortFromParent);
		},
	};
}

function speculativeReviewDemandItemIdFromState(state: BridgeCommWorkerStoreState): string | null {
	for (const [itemId, demandKey] of state.demandByKey) {
		if (demandKey === 'speculative') return itemId;
	}
	return null;
}

interface EnqueueVisibleBridgeCommWorkerReviewDemandExecutionProps {
	readonly backoffByItemId: ReadonlyMap<string, BridgeCommWorkerDemandBackoff>;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly createSequence: () => number;
	readonly epoch: number;
	readonly fetchReviewContentResource?: BridgeWorkerReviewContentResourceFetch;
	readonly openContent?: BridgeWorkerReviewContentOpen;
	readonly inFlightItemIds: Set<string>;
	readonly nowMilliseconds: number;
	readonly pendingRerunItemIds: Set<string>;
	readonly port: BridgeCommWorkerPort;
	readonly pump: WorkerContentPreparationPump;
	readonly requestPreparationDrain: () => void;
	readonly requestVisibleDemandRerun: (itemId: string) => void;
	readonly reviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource;
	readonly signal: AbortSignal;
	readonly sourceChurnItemIds: ReadonlySet<string>;
	readonly store: BridgeCommWorkerStore;
	readonly visibleDemandGenerationByItemId: ReadonlyMap<string, number>;
	readonly workerDerivationEpoch: number;
}

function enqueueVisibleBridgeCommWorkerReviewDemandExecution(
	props: EnqueueVisibleBridgeCommWorkerReviewDemandExecutionProps,
): readonly BridgeWorkerReviewContentReadyPreparationTicket[] {
	const membership = visibleReviewDemandMembersNeedingExecutionFromState({
		forceExecutionItemIds: props.sourceChurnItemIds,
		store: props.store,
	});
	if (membership.length === 0) {
		return [];
	}
	const executionPlan = planBridgeCommWorkerDemandExecution({
		backoffByItemId: props.backoffByItemId,
		inFlightItemIds: props.inFlightItemIds,
		maxStartCount: bridgeContentDemandExecutionPolicy.immediateStartConcurrency,
		membership,
		nowMilliseconds: props.nowMilliseconds,
	});
	const tickets: BridgeWorkerReviewContentReadyPreparationTicket[] = [];
	for (const itemId of executionPlan.startItemIds) {
		if (!hasReviewRuntimeSourceContent(props.reviewRuntimeSource, itemId)) {
			continue;
		}
		const visibleDemandGeneration = props.visibleDemandGenerationByItemId.get(itemId) ?? 0;
		props.inFlightItemIds.add(itemId);
		const ticket = enqueueBridgeWorkerReviewContentReadyPreparation({
			bridgeDemandRank: { lane: 'visible', priority: 1 },
			budget: {
				className: 'visible',
				maxBytes: props.budget.maxBytes,
				maxWindowLines: props.budget.maxWindowLines,
			},
			contentRequestDescriptors: props.reviewRuntimeSource.contentRequestDescriptors,
			demandKey: 'visible',
			epoch: props.epoch,
			...(props.fetchReviewContentResource === undefined
				? {}
				: { fetchReviewContentResource: props.fetchReviewContentResource }),
			...(props.openContent === undefined ? {} : { openContent: props.openContent }),
			isDemandCurrent: (): boolean =>
				(props.visibleDemandGenerationByItemId.get(itemId) ?? 0) === visibleDemandGeneration,
			itemId,
			port: props.port,
			preparationRank: 'visible',
			pump: props.pump,
			renderSemantics: props.reviewRuntimeSource.renderSemantics,
			requestPreparationDrain: props.requestPreparationDrain,
			sequence: props.createSequence(),
			signal: props.signal,
			store: props.store,
			workerDerivationEpoch: props.workerDerivationEpoch,
		});
		const completion = ticket.completion.finally(() => {
			props.inFlightItemIds.delete(itemId);
			if (props.pendingRerunItemIds.delete(itemId)) {
				props.requestVisibleDemandRerun(itemId);
			}
		});
		if (!ticket.enqueued) {
			props.inFlightItemIds.delete(itemId);
			tickets.push({ ...ticket, completion });
			continue;
		}
		tickets.push({ ...ticket, completion });
	}
	return tickets;
}

function visibleReviewDemandMembersNeedingExecutionFromState(props: {
	readonly forceExecutionItemIds: ReadonlySet<string>;
	readonly store: BridgeCommWorkerStore;
}): readonly BridgeCommWorkerDemandMember[] {
	const membership: BridgeCommWorkerDemandMember[] = [];
	const state = props.store.getState();
	for (const itemId of visibleReviewDemandItemIdsFromState(state)) {
		if (
			!props.forceExecutionItemIds.has(itemId) &&
			!doesReviewDemandNeedExecution(props.store, itemId)
		) {
			continue;
		}
		membership.push({ itemId, role: 'visible' });
	}
	return membership;
}

function visibleReviewDemandItemIdsFromState(state: BridgeCommWorkerStoreState): readonly string[] {
	const itemIds: string[] = [];
	for (const [itemId, demandKey] of state.demandByKey) {
		if (demandKey !== 'visible') {
			continue;
		}
		const metadata = state.contentMetadataByItemId.get(itemId) ?? null;
		if (metadata === null || !('availableContentRoles' in metadata)) {
			continue;
		}
		itemIds.push(itemId);
	}
	return itemIds;
}

function doesReviewDemandNeedExecution(store: BridgeCommWorkerStore, itemId: string): boolean {
	const availability = store.getState().availabilityByItemId.get(itemId);
	if (availability === 'failed' || availability === 'unavailable') return false;
	const fulfillment = store.renderFulfillmentRegistry.getItemState(itemId);
	return (
		fulfillment === null || fulfillment.stage === 'desired' || fulfillment.stage === 'retry_wait'
	);
}

function markVisibleReviewDemandSourceChurn(props: {
	readonly affectedItemIds: readonly string[] | undefined;
	readonly cause: BridgeCommWorkerDemandExecutionScheduleRequest['cause'];
	readonly inFlightItemIds: ReadonlySet<string>;
	readonly pendingRerunItemIds: Set<string>;
	readonly store: BridgeCommWorkerStore;
	readonly visibleDemandGenerationByItemId: Map<string, number>;
}): ReadonlySet<string> {
	if (props.cause !== 'reviewInvalidate' && props.cause !== 'reviewMetadata') {
		return new Set();
	}
	const affectedItemIds =
		props.affectedItemIds === undefined
			? visibleReviewDemandItemIdsFromState(props.store.getState())
			: props.affectedItemIds;
	const affectedItemIdSet = new Set(affectedItemIds);
	const churnedVisibleItemIds = new Set<string>();
	for (const itemId of visibleReviewDemandItemIdsFromState(props.store.getState())) {
		if (!affectedItemIdSet.has(itemId)) {
			continue;
		}
		churnedVisibleItemIds.add(itemId);
		props.visibleDemandGenerationByItemId.set(
			itemId,
			(props.visibleDemandGenerationByItemId.get(itemId) ?? 0) + 1,
		);
		if (props.inFlightItemIds.has(itemId)) {
			props.pendingRerunItemIds.add(itemId);
		}
	}
	return churnedVisibleItemIds;
}

function hasReviewRuntimeSourceContent(
	source: BridgeCommWorkerReviewRuntimeSource,
	itemId: string,
): boolean {
	const semantics = source.renderSemantics.find((candidate) => candidate.itemId === itemId) ?? null;
	return (
		source.contentItems.some((metadata) => metadata.itemId === itemId) &&
		semantics !== null &&
		canRenderBridgeWorkerReviewContentForSemantics({
			descriptors: source.contentRequestDescriptors,
			semantics,
		})
	);
}

interface BridgeCommWorkerReviewSurfaceWorkLifecycle {
	readonly abort: (reason: unknown) => void;
	readonly signal: AbortSignal;
}

function createBridgeCommWorkerReviewSurfaceWorkLifecycle(
	paneWorkSignal: AbortSignal,
): BridgeCommWorkerReviewSurfaceWorkLifecycle {
	const abortController = new AbortController();
	const detachPaneAbort = (): void => {
		paneWorkSignal.removeEventListener('abort', abortFromPane);
	};
	const abort = (reason: unknown): void => {
		detachPaneAbort();
		if (!abortController.signal.aborted) abortController.abort(reason);
	};
	const abortFromPane = (): void => {
		abort(paneWorkSignal.reason);
	};
	if (paneWorkSignal.aborted) {
		abortFromPane();
	} else {
		paneWorkSignal.addEventListener('abort', abortFromPane, { once: true });
	}
	return { abort, signal: abortController.signal };
}

function bridgeCommWorkerWorkIsAdmitted(): boolean {
	return true;
}
