import { bridgeContentDemandExecutionPolicy } from '../demand/bridge-content-demand-policy.js';
import {
	createBridgeCommWorkerCommandHandler,
	type BridgeCommWorkerDemandExecutionScheduleRequest,
	type BridgeCommWorkerFileViewRuntimeSource,
	type BridgeCommWorkerReviewRuntimeSource,
	type BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
	type BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
} from './bridge-comm-worker-command-handler.js';
import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import {
	planBridgeCommWorkerDemandExecution,
	type BridgeCommWorkerDemandBackoff,
	type BridgeCommWorkerDemandMember,
} from './bridge-comm-worker-executor.js';
import { enqueueSelectedBridgeWorkerFileViewContentReadyPreparation } from './bridge-comm-worker-file-view-preparation.js';
import {
	enqueueBridgeWorkerReviewContentReadyPreparation,
	enqueueSelectedBridgeWorkerReviewContentReadyPreparation,
} from './bridge-comm-worker-review-preparation.js';
import {
	canRenderBridgeWorkerReviewContentForSemantics,
	type BridgeWorkerReviewContentResourceFetch,
} from './bridge-comm-worker-review-runtime.js';
import type {
	BridgeCommWorkerRow,
	BridgeCommWorkerStore,
	BridgeCommWorkerStoreState,
} from './bridge-comm-worker-store.js';
import {
	createWorkerContentPreparationPump,
	type WorkerContentPreparationPump,
	type WorkerContentPreparationPumpRunResult,
} from './bridge-worker-content-preparation-pump.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerMainToServerMessageSchema,
	type BridgeWorkerReviewContentMetadata,
	type BridgeWorkerReviewContentRequestDescriptor,
	type BridgeWorkerReviewRenderSemantics,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from './bridge-worker-pierre-render-job.js';
import {
	fetchBridgeWorkerReviewContentResource,
	type BridgeWorkerContentFetch,
} from './bridge-worker-review-content-fetch.js';

export type BridgeCommWorkerPreparationDrain = () => Promise<WorkerContentPreparationPumpRunResult>;

export interface RegisterBridgeCommWorkerRuntimePortProtocolProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly contentItems: readonly BridgeWorkerReviewContentMetadata[];
	readonly contentRequestDescriptors: readonly BridgeWorkerReviewContentRequestDescriptor[];
	readonly createSequence?: () => number;
	readonly fetchContent?: BridgeWorkerContentFetch;
	readonly maxPreparationSliceMs?: number;
	readonly now?: () => number;
	readonly pump?: WorkerContentPreparationPump;
	readonly renderSemantics: readonly BridgeWorkerReviewRenderSemantics[];
	readonly rows: readonly BridgeCommWorkerRow[];
	readonly schedulePreparationDrain?: (drain: BridgeCommWorkerPreparationDrain) => void;
}

export function registerBridgeCommWorkerRuntimePortProtocol(
	port: BridgeCommWorkerPort,
	props: RegisterBridgeCommWorkerRuntimePortProtocolProps,
): void {
	const createSequence = props.createSequence ?? createBridgeWorkerRuntimeSequenceCounter();
	const pump =
		props.pump ??
		createWorkerContentPreparationPump({
			maxSliceMs: props.maxPreparationSliceMs ?? 8,
			...(props.now === undefined ? {} : { now: props.now }),
		});
	const schedulePreparationDrain =
		props.schedulePreparationDrain ?? scheduleDefaultBridgeCommWorkerPreparationDrain;
	const preparationCompletions: Promise<void>[] = [];
	let drainScheduled = false;
	let shouldRequestDrainAfterMessage = false;
	let reviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource = {
		contentItems: props.contentItems,
		contentRequestDescriptors: props.contentRequestDescriptors,
		renderSemantics: props.renderSemantics,
		rows: props.rows,
	};
	let fileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource = {
		contentItems: [],
		contentRequestDescriptors: [],
		rows: [],
	};
	const fetchReviewContentResource = createSharedBridgeWorkerReviewContentResourceFetch({
		fetchContent: props.fetchContent,
	});
	const demandBackoffByItemId = new Map<string, BridgeCommWorkerDemandBackoff>();
	const demandInFlightItemIds = new Set<string>();
	const pendingVisibleDemandRerunItemIds = new Set<string>();
	const visibleDemandGenerationByItemId = new Map<string, number>();
	let latestDemandExecutionRequest: BridgeCommWorkerDemandExecutionScheduleRequest | null = null;

	const drainPreparation: BridgeCommWorkerPreparationDrain = async () => {
		drainScheduled = false;
		const completions = preparationCompletions.splice(0, preparationCompletions.length);
		const runResult = pump.runUntilBudget();
		const completionResults = await Promise.allSettled(completions);
		const rejectedCompletion = completionResults.find(
			(result): result is PromiseRejectedResult => result.status === 'rejected',
		);
		if (rejectedCompletion !== undefined) {
			throw rejectedCompletion.reason;
		}
		if (pump.getPendingWorkIds().length > 0) {
			requestPreparationDrain();
		}
		return runResult;
	};

	const requestPreparationDrain = (): void => {
		if (drainScheduled) {
			return;
		}
		drainScheduled = true;
		schedulePreparationDrain(drainPreparation);
	};

	const enqueueVisibleDemandExecutionFromRequest = (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
		forcedSourceChurnItemIds: ReadonlySet<string> = new Set(),
	): boolean => {
		latestDemandExecutionRequest = request;
		const sourceChurnItemIds = markVisibleReviewDemandSourceChurn({
			affectedItemIds: request.affectedItemIds,
			cause: request.cause,
			inFlightItemIds: demandInFlightItemIds,
			pendingRerunItemIds: pendingVisibleDemandRerunItemIds,
			store: request.store,
			visibleDemandGenerationByItemId,
		});
		const forceExecutionItemIds = new Set([...sourceChurnItemIds, ...forcedSourceChurnItemIds]);
		const tickets = enqueueVisibleBridgeCommWorkerReviewDemandExecution({
			backoffByItemId: demandBackoffByItemId,
			budget: props.budget,
			createSequence,
			epoch: request.epoch,
			...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
			fetchReviewContentResource,
			inFlightItemIds: demandInFlightItemIds,
			nowMilliseconds: readBridgeCommWorkerRuntimeNowMilliseconds(props.now),
			pendingRerunItemIds: pendingVisibleDemandRerunItemIds,
			port,
			pump,
			requestPreparationDrain,
			requestVisibleDemandRerun: (itemId: string): void => {
				if (latestDemandExecutionRequest === null) {
					return;
				}
				if (
					enqueueVisibleDemandExecutionFromRequest(latestDemandExecutionRequest, new Set([itemId]))
				) {
					requestPreparationDrain();
				}
			},
			reviewRuntimeSource,
			sourceChurnItemIds: forceExecutionItemIds,
			store: request.store,
			visibleDemandGenerationByItemId,
		});
		let enqueued = false;
		for (const ticket of tickets) {
			if (ticket.enqueued) {
				preparationCompletions.push(ticket.completion);
				enqueued = true;
			}
		}
		return enqueued;
	};

	const handler = createBridgeCommWorkerCommandHandler({
		contentItems: props.contentItems,
		contentRequestDescriptors: props.contentRequestDescriptors,
		renderSemantics: props.renderSemantics,
		rows: props.rows,
		createSequence,
		scheduleSelectedReviewContentReadyPreparation: (
			request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
		): void => {
			const ticket = enqueueSelectedBridgeWorkerReviewContentReadyPreparation({
				bridgeDemandRank: props.bridgeDemandRank,
				budget: props.budget,
				contentRequestDescriptors: reviewRuntimeSource.contentRequestDescriptors,
				epoch: request.epoch,
				...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
				fetchReviewContentResource,
				itemId: request.itemId,
				port,
				pump,
				renderSemantics: reviewRuntimeSource.renderSemantics,
				requestPreparationDrain,
				sequence: createSequence(),
				store: request.store,
			});
			if (ticket.enqueued) {
				preparationCompletions.push(ticket.completion);
				shouldRequestDrainAfterMessage = true;
			}
		},
		scheduleSelectedFileViewContentReadyPreparation: (
			request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
		): void => {
			const ticket = enqueueSelectedBridgeWorkerFileViewContentReadyPreparation({
				bridgeDemandRank: props.bridgeDemandRank,
				budget: props.budget,
				contentRequestDescriptors: fileViewRuntimeSource.contentRequestDescriptors,
				epoch: request.epoch,
				...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
				itemId: request.itemId,
				port,
				pump,
				requestPreparationDrain,
				sequence: createSequence(),
				store: request.store,
			});
			if (ticket.enqueued) {
				preparationCompletions.push(ticket.completion);
				shouldRequestDrainAfterMessage = true;
			}
		},
		scheduleDemandExecution: (request: BridgeCommWorkerDemandExecutionScheduleRequest): void => {
			shouldRequestDrainAfterMessage =
				enqueueVisibleDemandExecutionFromRequest(request) || shouldRequestDrainAfterMessage;
		},
		updateReviewRuntimeSource: (source: BridgeCommWorkerReviewRuntimeSource): void => {
			reviewRuntimeSource = source;
		},
		updateFileViewRuntimeSource: (source: BridgeCommWorkerFileViewRuntimeSource): void => {
			fileViewRuntimeSource = source;
		},
	});

	port.addEventListener('message', (event: MessageEvent<unknown>): void => {
		const parsedMessage = bridgeWorkerMainToServerMessageSchema.safeParse(event.data);
		if (!parsedMessage.success) {
			port.postMessage(buildBridgeWorkerRuntimeDegradedHealthEvent());
			return;
		}

		shouldRequestDrainAfterMessage = false;
		for (const message of handler.handleMessage(parsedMessage.data)) {
			port.postMessage(message);
		}
		if (shouldRequestDrainAfterMessage) {
			requestPreparationDrain();
		}
	});
	port.start?.();
}

function buildBridgeWorkerRuntimeDegradedHealthEvent(): BridgeWorkerServerToMainMessage {
	return {
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'serverWorkerToMain',
		transferDescriptors: [],
		kind: 'health',
		status: 'degraded',
		message: 'Bridge comm worker received invalid message.',
	};
}

function createBridgeWorkerRuntimeSequenceCounter(): () => number {
	let nextSequence = 1;
	return (): number => {
		const sequence = nextSequence;
		nextSequence += 1;
		return sequence;
	};
}

function createSharedBridgeWorkerReviewContentResourceFetch(props: {
	readonly fetchContent: BridgeWorkerContentFetch | undefined;
}): BridgeWorkerReviewContentResourceFetch {
	const inFlightResourcesByUrl = new Map<
		string,
		ReturnType<BridgeWorkerReviewContentResourceFetch>
	>();
	return async (descriptor: BridgeWorkerReviewContentRequestDescriptor) => {
		const resourceKey = sharedBridgeWorkerReviewContentResourceKey(descriptor);
		const existingResource = inFlightResourcesByUrl.get(resourceKey);
		if (existingResource !== undefined) {
			return await existingResource;
		}
		const resourcePromise = fetchBridgeWorkerReviewContentResource({
			descriptor,
			...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
		});
		inFlightResourcesByUrl.set(resourceKey, resourcePromise);
		try {
			return await resourcePromise;
		} finally {
			inFlightResourcesByUrl.delete(resourceKey);
		}
	};
}

function sharedBridgeWorkerReviewContentResourceKey(
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
): string {
	return [
		descriptor.resourceUrl,
		descriptor.itemId,
		descriptor.role,
		descriptor.contentHashAlgorithm,
		descriptor.contentHash,
		descriptor.language ?? '',
		descriptor.sizeBytes,
		descriptor.isBinary,
	].join('\u0000');
}

interface EnqueueVisibleBridgeCommWorkerReviewDemandExecutionProps {
	readonly backoffByItemId: ReadonlyMap<string, BridgeCommWorkerDemandBackoff>;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly createSequence: () => number;
	readonly epoch: number;
	readonly fetchContent?: BridgeWorkerContentFetch;
	readonly fetchReviewContentResource?: BridgeWorkerReviewContentResourceFetch;
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
}

interface EnqueuedBridgeCommWorkerDemandPreparationTicket {
	readonly completion: Promise<void>;
	readonly enqueued: boolean;
}

function enqueueVisibleBridgeCommWorkerReviewDemandExecution(
	props: EnqueueVisibleBridgeCommWorkerReviewDemandExecutionProps,
): readonly EnqueuedBridgeCommWorkerDemandPreparationTicket[] {
	const membership = visibleReviewDemandMembersNeedingExecutionFromState({
		forceExecutionItemIds: props.sourceChurnItemIds,
		state: props.store.getState(),
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
			...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
			...(props.fetchReviewContentResource === undefined
				? {}
				: { fetchReviewContentResource: props.fetchReviewContentResource }),
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
	readonly state: BridgeCommWorkerStoreState;
}): readonly BridgeCommWorkerDemandMember[] {
	const membership: BridgeCommWorkerDemandMember[] = [];
	for (const itemId of visibleReviewDemandItemIdsFromState(props.state)) {
		if (
			!props.forceExecutionItemIds.has(itemId) &&
			!doesVisibleReviewDemandNeedExecution(props.state, itemId)
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
	state: BridgeCommWorkerStoreState,
	itemId: string,
): boolean {
	const availability = state.availabilityByItemId.get(itemId);
	return availability !== 'ready' && availability !== 'failed' && availability !== 'unavailable';
}

function markVisibleReviewDemandSourceChurn(props: {
	readonly affectedItemIds: readonly string[] | undefined;
	readonly cause: BridgeCommWorkerDemandExecutionScheduleRequest['cause'];
	readonly inFlightItemIds: ReadonlySet<string>;
	readonly pendingRerunItemIds: Set<string>;
	readonly store: BridgeCommWorkerStore;
	readonly visibleDemandGenerationByItemId: Map<string, number>;
}): ReadonlySet<string> {
	if (props.cause !== 'reviewInvalidate' && props.cause !== 'reviewSourceUpdate') {
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

function readBridgeCommWorkerRuntimeNowMilliseconds(now: (() => number) | undefined): number {
	if (now !== undefined) {
		return now();
	}
	return performance.now();
}

function scheduleDefaultBridgeCommWorkerPreparationDrain(
	drain: BridgeCommWorkerPreparationDrain,
): void {
	queueMicrotask(() => {
		void drain();
	});
}
