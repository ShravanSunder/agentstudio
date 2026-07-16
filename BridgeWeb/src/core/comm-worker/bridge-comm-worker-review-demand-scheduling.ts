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
import {
	enqueueBridgeCommWorkerReviewSourceReset,
	type EnqueuedBridgeCommWorkerDemandPreparationTicket,
} from './bridge-comm-worker-review-source-reset.js';
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
	readonly markPreparationDrainRequired: () => void;
	readonly now?: () => number;
	readonly openReviewContent?: BridgeWorkerReviewContentOpen;
	readonly port: BridgeCommWorkerPort;
	readonly pump: WorkerContentPreparationPump;
	readonly recordPreparationCompletion: (completion: Promise<void>) => void;
	readonly requestPreparationDrain: () => void;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
	readonly usesProductTransport: boolean;
}

export interface BridgeCommWorkerReviewDemandScheduling {
	readonly scheduleDemandExecution: (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	) => boolean;
	readonly scheduleMetadataReset: (
		request: BridgeCommWorkerReviewMetadataResetScheduleRequest,
	) => void;
	readonly scheduleSelectedContentReadyPreparation: (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	) => void;
	readonly updateRuntimeSource: (source: BridgeCommWorkerReviewRuntimeSource) => void;
	readonly updateWorkerDerivationEpoch: (workerDerivationEpoch: number) => void;
}

export function createBridgeCommWorkerReviewDemandScheduling(
	props: CreateBridgeCommWorkerReviewDemandSchedulingProps,
): BridgeCommWorkerReviewDemandScheduling {
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
	const markedVisibleSourceChurnKeys = new Set<string>();
	const activeSelectedPreparationByItemId = new Map<
		string,
		{
			readonly identity: string;
			readonly ticket: BridgeWorkerReviewContentReadyPreparationTicket;
		}
	>();
	let latestDemandExecutionRequest: BridgeCommWorkerDemandExecutionScheduleRequest | null = null;
	let activeSourceResetEpoch: number | null = null;
	let activeWorkerDerivationEpoch: number | null = null;

	const markVisibleDemandSourceChurnFromRequest = (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	): ReadonlySet<string> => {
		const unmarkedAffectedItemIds = request.affectedItemIds?.filter((itemId) => {
			const churnKey = `${request.sourceChurnRevision ?? request.epoch}:${itemId}`;
			return !markedVisibleSourceChurnKeys.has(churnKey);
		});
		const sourceChurnItemIds = markVisibleReviewDemandSourceChurn({
			affectedItemIds: unmarkedAffectedItemIds,
			cause: request.cause,
			inFlightItemIds: demandInFlightItemIds,
			pendingRerunItemIds: pendingVisibleDemandRerunItemIds,
			store: request.store,
			visibleDemandGenerationByItemId,
		});
		for (const itemId of sourceChurnItemIds) {
			markedVisibleSourceChurnKeys.add(`${request.sourceChurnRevision ?? request.epoch}:${itemId}`);
		}
		return sourceChurnItemIds;
	};

	const enqueueVisibleDemandExecutionFromRequest = (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
		forcedSourceChurnItemIds: ReadonlySet<string> = new Set(),
		shouldMarkSourceChurn = true,
	): boolean => {
		latestDemandExecutionRequest = request;
		const workerDerivationEpoch = props.usesProductTransport
			? activeWorkerDerivationEpoch
			: request.epoch;
		if (workerDerivationEpoch === null) {
			return false;
		}
		const sourceChurnItemIds = shouldMarkSourceChurn
			? markVisibleDemandSourceChurnFromRequest(request)
			: new Set<string>();
		const forceExecutionItemIds = new Set([
			...sourceChurnItemIds,
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
			sourceChurnItemIds: forceExecutionItemIds,
			store: request.store,
			visibleDemandGenerationByItemId,
			workerDerivationEpoch,
		});
		let enqueued = false;
		let startedItemCount = 0;
		for (const ticket of tickets) {
			if (ticket.enqueued) {
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
		}
		return enqueued;
	};

	const scheduleSelectedContentReadyPreparation = (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	): void => {
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
				}
			});
			props.recordPreparationCompletion(trackedCompletion);
			props.markPreparationDrainRequired();
		}
	};

	return {
		scheduleDemandExecution: enqueueVisibleDemandExecutionFromRequest,
		scheduleMetadataReset: (request: BridgeCommWorkerReviewMetadataResetScheduleRequest): void => {
			activeSourceResetEpoch = request.epoch;
			markVisibleDemandSourceChurnFromRequest({
				affectedItemIds: request.affectedItemIds,
				cause: request.cause,
				epoch: request.epoch,
				store: request.store,
			});
			const ticket = enqueueBridgeCommWorkerReviewSourceReset({
				createSequence: props.createSequence,
				isCurrentResetEpoch: () => activeSourceResetEpoch === request.epoch,
				onResetComplete: () => {
					if (activeSourceResetEpoch === request.epoch) {
						activeSourceResetEpoch = null;
					}
				},
				pump: props.pump,
				request,
				requestPreparationDrain: props.requestPreparationDrain,
				scheduleDemandExecution: enqueueVisibleDemandExecutionFromRequest,
				scheduleSelectedReviewContentReadyPreparation: scheduleSelectedContentReadyPreparation,
			});
			if (ticket.enqueued) {
				props.markPreparationDrainRequired();
			}
		},
		scheduleSelectedContentReadyPreparation,
		updateRuntimeSource: (source: BridgeCommWorkerReviewRuntimeSource): void => {
			reviewRuntimeSource = source;
		},
		updateWorkerDerivationEpoch: (workerDerivationEpoch: number): void => {
			activeWorkerDerivationEpoch = workerDerivationEpoch;
		},
	};
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
	readonly sourceChurnItemIds: ReadonlySet<string>;
	readonly store: BridgeCommWorkerStore;
	readonly visibleDemandGenerationByItemId: ReadonlyMap<string, number>;
	readonly workerDerivationEpoch: number;
}

function enqueueVisibleBridgeCommWorkerReviewDemandExecution(
	props: EnqueueVisibleBridgeCommWorkerReviewDemandExecutionProps,
): readonly EnqueuedBridgeCommWorkerDemandPreparationTicket[] {
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
	const tickets: EnqueuedBridgeCommWorkerDemandPreparationTicket[] = [];
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
			tickets.push({ completion, enqueued: false });
			continue;
		}
		tickets.push({ completion, enqueued: true });
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
			!doesVisibleReviewDemandNeedExecution(props.store, itemId)
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

function doesVisibleReviewDemandNeedExecution(
	store: BridgeCommWorkerStore,
	itemId: string,
): boolean {
	const state = store.getState();
	const availability = state.availabilityByItemId.get(itemId);
	if (availability === 'failed' || availability === 'unavailable') {
		return false;
	}
	const fulfillment = store.renderFulfillmentRegistry.getItemState(itemId);
	if (fulfillment === null) {
		return true;
	}
	return fulfillment.stage === 'desired' || fulfillment.stage === 'retry_wait';
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
