import { buildBridgeWorkerReadyHealthEvent } from './bridge-comm-worker-protocol.js';
import { canRenderBridgeWorkerReviewContentForSemantics } from './bridge-comm-worker-review-runtime.js';
import {
	createBridgeCommWorkerStore,
	type BridgeCommWorkerRow,
	type BridgeCommWorkerStore,
} from './bridge-comm-worker-store.js';
import type { BridgeCommWorkerTelemetryRecorder } from './bridge-comm-worker-telemetry.js';
import type {
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerFileViewContentRequestDescriptor,
	BridgeWorkerFileViewSourceUpdateCommand,
	BridgeWorkerMainToServerMessage,
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerReviewContentRequestDescriptor,
	BridgeWorkerReviewInvalidateCommand,
	BridgeWorkerReviewRenderSemantics,
	BridgeWorkerReviewSourceUpdateCommand,
	BridgeWorkerSelectCommand,
	BridgeWorkerServerToMainMessage,
	BridgeWorkerViewportCommand,
} from './bridge-worker-contracts.js';

export interface BridgeCommWorkerReviewRuntimeSource {
	readonly contentItems: readonly BridgeWorkerReviewContentMetadata[];
	readonly contentRequestDescriptors: readonly BridgeWorkerReviewContentRequestDescriptor[];
	readonly renderSemantics: readonly BridgeWorkerReviewRenderSemantics[];
	readonly rows: readonly BridgeCommWorkerRow[];
}

export interface BridgeCommWorkerFileViewRuntimeSource {
	readonly contentItems: readonly BridgeWorkerFileViewContentMetadata[];
	readonly contentRequestDescriptors: readonly BridgeWorkerFileViewContentRequestDescriptor[];
	readonly rows: readonly BridgeCommWorkerRow[];
}

export interface CreateBridgeCommWorkerCommandHandlerProps {
	readonly contentItems: readonly BridgeWorkerReviewContentMetadata[];
	readonly contentRequestDescriptors?: readonly BridgeWorkerReviewContentRequestDescriptor[];
	readonly renderSemantics?: readonly BridgeWorkerReviewRenderSemantics[];
	readonly rows: readonly BridgeCommWorkerRow[];
	readonly createSequence?: () => number;
	readonly now?: () => number;
	readonly scheduleDemandExecution?: (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	) => void;
	readonly scheduleReviewSourceUpdate?: (
		request: BridgeCommWorkerReviewSourceUpdateScheduleRequest,
	) => void;
	readonly scheduleSelectedReviewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	) => void;
	readonly scheduleSelectedFileViewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
	) => void;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
	readonly updateReviewRuntimeSource?: (source: BridgeCommWorkerReviewRuntimeSource) => void;
	readonly updateFileViewRuntimeSource?: (source: BridgeCommWorkerFileViewRuntimeSource) => void;
}

export interface BridgeCommWorkerDemandExecutionScheduleRequest {
	readonly cause: 'reviewInvalidate' | 'reviewSourceUpdate' | 'viewport';
	readonly affectedItemIds?: readonly string[];
	readonly epoch: number;
	readonly forceExecutionItemIds?: readonly string[];
	readonly store: BridgeCommWorkerStore;
}

export interface BridgeCommWorkerReviewSourceUpdateScheduleRequest {
	readonly affectedItemIds: readonly string[];
	readonly epoch: number;
	readonly nextReviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource;
	readonly previousReviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource;
	readonly store: BridgeCommWorkerStore;
}

export interface BridgeCommWorkerSelectedReviewContentReadyPreparationRequest {
	readonly epoch: number;
	readonly itemId: string;
	readonly store: BridgeCommWorkerStore;
}

export interface BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest {
	readonly epoch: number;
	readonly itemId: string;
	readonly store: BridgeCommWorkerStore;
}

export interface BridgeCommWorkerCommandHandler {
	readonly handleMessage: (
		message: BridgeWorkerMainToServerMessage,
	) => readonly BridgeWorkerServerToMainMessage[];
}

export function createBridgeCommWorkerCommandHandler(
	props: CreateBridgeCommWorkerCommandHandlerProps,
): BridgeCommWorkerCommandHandler {
	const store = createBridgeCommWorkerStore({
		contentItems: props.contentItems,
		...(props.now === undefined ? {} : { now: props.now }),
		rows: props.rows,
		...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
	});
	const createSequence = props.createSequence ?? createBridgeWorkerSequenceCounter();
	const seenRequestIds = new Set<string>();
	let fileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource = {
		contentItems: [],
		contentRequestDescriptors: [],
		rows: [],
	};
	let reviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource = {
		contentItems: props.contentItems,
		contentRequestDescriptors: props.contentRequestDescriptors ?? [],
		renderSemantics: props.renderSemantics ?? [],
		rows: props.rows,
	};
	let currentEpoch = 0;

	return {
		handleMessage: (message: BridgeWorkerMainToServerMessage) => {
			const rejection = rejectStaleOrReplayedBridgeWorkerCommand({
				currentEpoch,
				message,
				seenRequestIds,
			});
			if (rejection !== null) {
				return [rejection];
			}
			seenRequestIds.add(message.requestId);
			currentEpoch = Math.max(currentEpoch, message.epoch);
			return handleBridgeWorkerCommand({
				createSequence,
				message,
				scheduleSelectedReviewContentReadyPreparation:
					props.scheduleSelectedReviewContentReadyPreparation,
				scheduleSelectedFileViewContentReadyPreparation:
					props.scheduleSelectedFileViewContentReadyPreparation,
				...(props.scheduleDemandExecution === undefined
					? {}
					: { scheduleDemandExecution: props.scheduleDemandExecution }),
				...(props.scheduleReviewSourceUpdate === undefined
					? {}
					: { scheduleReviewSourceUpdate: props.scheduleReviewSourceUpdate }),
				store,
				reviewRuntimeSource,
				fileViewRuntimeSource,
				updateReviewRuntimeSource: (source: BridgeCommWorkerReviewRuntimeSource): void => {
					reviewRuntimeSource = source;
					props.updateReviewRuntimeSource?.(source);
				},
				updateFileViewRuntimeSource: (source: BridgeCommWorkerFileViewRuntimeSource): void => {
					fileViewRuntimeSource = source;
					props.updateFileViewRuntimeSource?.(source);
				},
			});
		},
	};
}

interface HandleBridgeWorkerCommandProps {
	readonly createSequence: () => number;
	readonly message: BridgeWorkerMainToServerMessage;
	readonly scheduleSelectedReviewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	) => void;
	readonly scheduleSelectedFileViewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
	) => void;
	readonly scheduleDemandExecution?: (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	) => void;
	readonly scheduleReviewSourceUpdate?: (
		request: BridgeCommWorkerReviewSourceUpdateScheduleRequest,
	) => void;
	readonly store: BridgeCommWorkerStore;
	readonly reviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource;
	readonly fileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource;
	readonly updateReviewRuntimeSource: (source: BridgeCommWorkerReviewRuntimeSource) => void;
	readonly updateFileViewRuntimeSource: (source: BridgeCommWorkerFileViewRuntimeSource) => void;
}

function handleBridgeWorkerCommand(
	props: HandleBridgeWorkerCommandProps,
): readonly BridgeWorkerServerToMainMessage[] {
	switch (props.message.command) {
		case 'select':
			return handleBridgeWorkerSelectCommand({
				createSequence: props.createSequence,
				message: props.message,
				reviewRuntimeSource: props.reviewRuntimeSource,
				scheduleSelectedReviewContentReadyPreparation:
					props.scheduleSelectedReviewContentReadyPreparation,
				scheduleSelectedFileViewContentReadyPreparation:
					props.scheduleSelectedFileViewContentReadyPreparation,
				store: props.store,
			});
		case 'viewport':
			return handleBridgeWorkerViewportCommand({
				createSequence: props.createSequence,
				message: props.message,
				...(props.scheduleDemandExecution === undefined
					? {}
					: { scheduleDemandExecution: props.scheduleDemandExecution }),
				store: props.store,
			});
		case 'reviewInvalidate':
			return handleBridgeWorkerReviewInvalidateCommand({
				createSequence: props.createSequence,
				message: props.message,
				scheduleSelectedReviewContentReadyPreparation:
					props.scheduleSelectedReviewContentReadyPreparation,
				...(props.scheduleDemandExecution === undefined
					? {}
					: { scheduleDemandExecution: props.scheduleDemandExecution }),
				store: props.store,
			});
		case 'reviewSourceUpdate':
			return handleBridgeWorkerReviewSourceUpdateCommand({
				createSequence: props.createSequence,
				message: props.message,
				...(props.scheduleDemandExecution === undefined
					? {}
					: { scheduleDemandExecution: props.scheduleDemandExecution }),
				...(props.scheduleReviewSourceUpdate === undefined
					? {}
					: { scheduleReviewSourceUpdate: props.scheduleReviewSourceUpdate }),
				store: props.store,
				previousReviewRuntimeSource: props.reviewRuntimeSource,
				updateReviewRuntimeSource: props.updateReviewRuntimeSource,
			});
		case 'fileViewSourceUpdate':
			return handleBridgeWorkerFileViewSourceUpdateCommand({
				createSequence: props.createSequence,
				message: props.message,
				scheduleSelectedFileViewContentReadyPreparation:
					props.scheduleSelectedFileViewContentReadyPreparation,
				store: props.store,
				fileViewRuntimeSource: props.fileViewRuntimeSource,
				updateFileViewRuntimeSource: props.updateFileViewRuntimeSource,
			});
		case 'markFileViewed':
		case 'metadataInterestUpdate':
		case 'reviewIntakeReady':
		case 'activeViewerModeUpdate':
			return [buildBridgeWorkerReadyHealthEvent(props.message.requestId)];
		case 'hover':
		case 'mode':
			return [buildBridgeWorkerUnimplementedHealthEvent(props.message)];
		default:
			return assertNeverBridgeWorkerCommand(props.message);
	}
}

interface HandleBridgeWorkerFileViewSourceUpdateCommandProps {
	readonly createSequence: () => number;
	readonly message: BridgeWorkerFileViewSourceUpdateCommand;
	readonly scheduleSelectedFileViewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
	) => void;
	readonly store: BridgeCommWorkerStore;
	readonly fileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource;
	readonly updateFileViewRuntimeSource: (source: BridgeCommWorkerFileViewRuntimeSource) => void;
}

function handleBridgeWorkerFileViewSourceUpdateCommand(
	props: HandleBridgeWorkerFileViewSourceUpdateCommandProps,
): readonly BridgeWorkerServerToMainMessage[] {
	const previousFileViewRuntimeSource = props.fileViewRuntimeSource;
	const nextFileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource = {
		contentItems: props.message.contentItems,
		contentRequestDescriptors: props.message.contentRequestDescriptors,
		rows: props.message.rows,
	};
	const sourceUpdateResult = props.store.actions.applyFileViewSourceUpdateFact({
		contentItems: props.message.contentItems,
		epoch: props.message.epoch,
		rows: props.message.rows,
	});
	props.updateFileViewRuntimeSource(nextFileViewRuntimeSource);
	const slicePatch = props.store.actions.takePendingSlicePatchEvent({
		epoch: props.message.epoch,
		sequence: props.createSequence(),
	});
	scheduleSelectedFileViewContentReadyPreparationForCurrentDemand({
		epoch: props.message.epoch,
		scheduleSelectedFileViewContentReadyPreparation:
			props.scheduleSelectedFileViewContentReadyPreparation,
		selectedContentMetadataChanged:
			sourceUpdateResult.selectedFileViewContentMetadataChanged === true,
		selectedContentRequestDescriptorChanged: didSelectedFileViewContentRequestDescriptorChange({
			nextFileViewRuntimeSource,
			previousFileViewRuntimeSource,
			selectedId: props.store.getState().selectedId,
		}),
		store: props.store,
	});
	return [
		...(slicePatch === null ? [] : [slicePatch]),
		buildBridgeWorkerReadyHealthEvent(props.message.requestId),
	];
}

interface HandleBridgeWorkerReviewSourceUpdateCommandProps {
	readonly createSequence: () => number;
	readonly message: BridgeWorkerReviewSourceUpdateCommand;
	readonly previousReviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource;
	readonly scheduleDemandExecution?: (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	) => void;
	readonly scheduleReviewSourceUpdate?: (
		request: BridgeCommWorkerReviewSourceUpdateScheduleRequest,
	) => void;
	readonly store: BridgeCommWorkerStore;
	readonly updateReviewRuntimeSource: (source: BridgeCommWorkerReviewRuntimeSource) => void;
}

function handleBridgeWorkerReviewSourceUpdateCommand(
	props: HandleBridgeWorkerReviewSourceUpdateCommandProps,
): readonly BridgeWorkerServerToMainMessage[] {
	const nextReviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource = {
		contentItems: props.message.contentItems,
		contentRequestDescriptors: props.message.contentRequestDescriptors,
		renderSemantics: props.message.renderSemantics,
		rows: props.message.rows,
	};
	const affectedItemIds = findChangedReviewRuntimeSourceItemIds({
		nextSource: nextReviewRuntimeSource,
		previousSource: props.previousReviewRuntimeSource,
	});
	if (props.scheduleReviewSourceUpdate !== undefined) {
		props.updateReviewRuntimeSource(nextReviewRuntimeSource);
		let appliedTerminalAvailability = false;
		const visibleItemIds = new Set(props.store.getState().visibleIds);
		for (const itemId of affectedItemIds) {
			if (!visibleItemIds.has(itemId)) {
				continue;
			}
			if (isReviewRuntimeSourceExecutableForItem(nextReviewRuntimeSource, itemId)) {
				continue;
			}
			props.store.actions.applyContentTerminalAvailability({
				itemId,
				reason: 'source_reset',
				sourceEpoch: props.message.epoch,
				state: 'unavailable',
			});
			appliedTerminalAvailability = true;
		}
		props.scheduleReviewSourceUpdate({
			affectedItemIds,
			epoch: props.message.epoch,
			nextReviewRuntimeSource,
			previousReviewRuntimeSource: props.previousReviewRuntimeSource,
			store: props.store,
		});
		const slicePatch = appliedTerminalAvailability
			? props.store.actions.takePendingSlicePatchEvent({
					epoch: props.message.epoch,
					sequence: props.createSequence(),
				})
			: null;
		return [
			...(slicePatch === null ? [] : [slicePatch]),
			buildBridgeWorkerReadyHealthEvent(props.message.requestId),
		];
	}
	props.store.actions.applyReviewSourceUpdateFact({
		contentItems: props.message.contentItems,
		rows: props.message.rows,
	});
	props.updateReviewRuntimeSource(nextReviewRuntimeSource);
	let appliedTerminalAvailability = false;
	const visibleItemIds = new Set(props.store.getState().visibleIds);
	for (const itemId of affectedItemIds) {
		if (!visibleItemIds.has(itemId)) {
			continue;
		}
		if (isReviewRuntimeSourceExecutableForItem(nextReviewRuntimeSource, itemId)) {
			continue;
		}
		props.store.actions.applyContentTerminalAvailability({
			itemId,
			reason: 'source_reset',
			sourceEpoch: props.message.epoch,
			state: 'unavailable',
		});
		appliedTerminalAvailability = true;
	}
	props.scheduleDemandExecution?.({
		affectedItemIds,
		cause: 'reviewSourceUpdate',
		epoch: props.message.epoch,
		store: props.store,
	});
	const slicePatch = appliedTerminalAvailability
		? props.store.actions.takePendingSlicePatchEvent({
				epoch: props.message.epoch,
				sequence: props.createSequence(),
			})
		: null;
	return [
		...(slicePatch === null ? [] : [slicePatch]),
		buildBridgeWorkerReadyHealthEvent(props.message.requestId),
	];
}

interface HandleBridgeWorkerSelectCommandProps {
	readonly createSequence: () => number;
	readonly message: BridgeWorkerSelectCommand;
	readonly reviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource;
	readonly scheduleSelectedReviewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	) => void;
	readonly scheduleSelectedFileViewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
	) => void;
	readonly store: BridgeCommWorkerStore;
}

function handleBridgeWorkerSelectCommand(
	props: HandleBridgeWorkerSelectCommandProps,
): readonly BridgeWorkerServerToMainMessage[] {
	applySelectedReviewRuntimeSourceItemIfNeeded({
		itemId: props.message.selectedItemId,
		reviewRuntimeSource: props.reviewRuntimeSource,
		store: props.store,
	});
	props.store.actions.applySelectedFact({
		epoch: props.message.epoch,
		itemId: props.message.selectedItemId,
	});
	const slicePatch = props.store.actions.takePendingSlicePatchEvent({
		epoch: props.message.epoch,
		sequence: props.createSequence(),
	});
	scheduleSelectedContentReadyPreparationForSelection(props);
	return [
		...(slicePatch === null ? [] : [slicePatch]),
		buildBridgeWorkerReadyHealthEvent(props.message.requestId),
	];
}

function applySelectedReviewRuntimeSourceItemIfNeeded(props: {
	readonly itemId: string;
	readonly reviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource;
	readonly store: BridgeCommWorkerStore;
}): void {
	const contentItem =
		props.reviewRuntimeSource.contentItems.find((candidate) => candidate.itemId === props.itemId) ??
		null;
	const row =
		props.reviewRuntimeSource.rows.find((candidate) => candidate.id === props.itemId) ?? null;
	if (contentItem === null || row === null) {
		return;
	}
	props.store.actions.applyReviewSourceUpdateFact({
		contentItems: [contentItem],
		resetComplete: false,
		rows: [row],
	});
}

function scheduleSelectedContentReadyPreparationForSelection(
	props: Pick<
		HandleBridgeWorkerSelectCommandProps,
		| 'message'
		| 'scheduleSelectedFileViewContentReadyPreparation'
		| 'scheduleSelectedReviewContentReadyPreparation'
		| 'store'
	>,
): void {
	const selectedItemId = props.message.selectedItemId;
	if (
		!isSelectedContentReadyPreparationCurrent({
			epoch: props.message.epoch,
			itemId: selectedItemId,
			store: props.store,
		})
	) {
		return;
	}
	const metadata = props.store.getState().contentMetadataByItemId.get(selectedItemId) ?? null;
	if (isBridgeWorkerFileViewContentMetadata(metadata)) {
		props.scheduleSelectedFileViewContentReadyPreparation({
			epoch: props.message.epoch,
			itemId: selectedItemId,
			store: props.store,
		});
		return;
	}
	if (isBridgeWorkerReviewContentMetadata(metadata)) {
		props.scheduleSelectedReviewContentReadyPreparation({
			epoch: props.message.epoch,
			itemId: selectedItemId,
			store: props.store,
		});
	}
}

function scheduleSelectedFileViewContentReadyPreparationForCurrentDemand(props: {
	readonly epoch: number;
	readonly scheduleSelectedFileViewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
	) => void;
	readonly selectedContentMetadataChanged: boolean;
	readonly selectedContentRequestDescriptorChanged: boolean;
	readonly store: BridgeCommWorkerStore;
}): void {
	const selectedId = props.store.getState().selectedId;
	if (
		selectedId === null ||
		!isSelectedContentReadyPreparationCurrent({
			epoch: props.epoch,
			itemId: selectedId,
			store: props.store,
		})
	) {
		return;
	}
	const metadata = props.store.getState().contentMetadataByItemId.get(selectedId) ?? null;
	if (!isBridgeWorkerFileViewContentMetadata(metadata)) {
		return;
	}
	const availability = props.store.getState().availabilityByItemId.get(selectedId);
	if (
		availability === 'ready' &&
		!props.selectedContentMetadataChanged &&
		!props.selectedContentRequestDescriptorChanged
	) {
		return;
	}
	if (availability !== 'loading' && availability !== 'stale' && availability !== 'ready') {
		return;
	}
	props.scheduleSelectedFileViewContentReadyPreparation({
		epoch: props.epoch,
		itemId: selectedId,
		store: props.store,
	});
}

function didSelectedFileViewContentRequestDescriptorChange(props: {
	readonly nextFileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource;
	readonly previousFileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource;
	readonly selectedId: string | null;
}): boolean {
	if (props.selectedId === null) {
		return false;
	}
	return !areFileViewContentRequestDescriptorsEquivalent(
		findFileViewContentRequestDescriptor(props.previousFileViewRuntimeSource, props.selectedId),
		findFileViewContentRequestDescriptor(props.nextFileViewRuntimeSource, props.selectedId),
	);
}

function findFileViewContentRequestDescriptor(
	source: BridgeCommWorkerFileViewRuntimeSource,
	itemId: string,
): BridgeWorkerFileViewContentRequestDescriptor | null {
	return (
		source.contentRequestDescriptors.find((descriptor) => descriptor.itemId === itemId) ?? null
	);
}

function areFileViewContentRequestDescriptorsEquivalent(
	left: BridgeWorkerFileViewContentRequestDescriptor | null,
	right: BridgeWorkerFileViewContentRequestDescriptor | null,
): boolean {
	if (left === null || right === null) {
		return left === right;
	}
	return (
		left.itemId === right.itemId &&
		left.path === right.path &&
		left.handleId === right.handleId &&
		left.descriptorId === right.descriptorId &&
		left.resourceKind === right.resourceKind &&
		left.resourceUrl === right.resourceUrl &&
		(left.contentHash ?? null) === (right.contentHash ?? null) &&
		(left.contentHashAlgorithm ?? null) === (right.contentHashAlgorithm ?? null) &&
		left.language === right.language &&
		left.sizeBytes === right.sizeBytes &&
		left.maxBytes === right.maxBytes &&
		left.isBinary === right.isBinary
	);
}

function isSelectedContentReadyPreparationCurrent(props: {
	readonly epoch: number;
	readonly itemId: string;
	readonly store: BridgeCommWorkerStore;
}): boolean {
	const state = props.store.getState();
	return (
		state.selectedId === props.itemId &&
		state.demandByKey.get(props.itemId) === `selected:${props.epoch}`
	);
}

interface HandleBridgeWorkerReviewInvalidateCommandProps {
	readonly createSequence: () => number;
	readonly message: BridgeWorkerReviewInvalidateCommand;
	readonly scheduleSelectedReviewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	) => void;
	readonly scheduleDemandExecution?: (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	) => void;
	readonly store: BridgeCommWorkerStore;
}

function handleBridgeWorkerReviewInvalidateCommand(
	props: HandleBridgeWorkerReviewInvalidateCommandProps,
): readonly BridgeWorkerServerToMainMessage[] {
	props.store.actions.applyReviewInvalidationFact({
		epoch: props.message.epoch,
		itemIds: props.message.itemIds,
		pathHints: props.message.pathHints,
		reason: props.message.reason,
		scope: props.message.scope,
	});
	const slicePatch = props.store.actions.takePendingSlicePatchEvent({
		epoch: props.message.epoch,
		sequence: props.createSequence(),
	});
	const selectedId = props.store.getState().selectedId;
	if (
		selectedId !== null &&
		props.store.getState().demandByKey.get(selectedId) === `selected:${props.message.epoch}` &&
		isBridgeWorkerReviewContentMetadata(
			props.store.getState().contentMetadataByItemId.get(selectedId) ?? null,
		)
	) {
		props.scheduleSelectedReviewContentReadyPreparation({
			epoch: props.message.epoch,
			itemId: selectedId,
			store: props.store,
		});
	}
	const affectedItemIds = resolveReviewInvalidationAffectedItemIds({
		message: props.message,
		store: props.store,
	});
	props.scheduleDemandExecution?.({
		...(affectedItemIds === undefined ? {} : { affectedItemIds }),
		cause: 'reviewInvalidate',
		epoch: props.message.epoch,
		store: props.store,
	});
	return [
		...(slicePatch === null ? [] : [slicePatch]),
		buildBridgeWorkerReadyHealthEvent(props.message.requestId),
	];
}

function isBridgeWorkerFileViewContentMetadata(
	metadata: BridgeWorkerReviewContentMetadata | BridgeWorkerFileViewContentMetadata | null,
): metadata is BridgeWorkerFileViewContentMetadata {
	return metadata !== null && 'contentHandle' in metadata;
}

function isBridgeWorkerReviewContentMetadata(
	metadata: BridgeWorkerReviewContentMetadata | BridgeWorkerFileViewContentMetadata | null,
): metadata is BridgeWorkerReviewContentMetadata {
	return metadata !== null && 'availableContentRoles' in metadata;
}

interface HandleBridgeWorkerViewportCommandProps {
	readonly createSequence: () => number;
	readonly message: BridgeWorkerViewportCommand;
	readonly scheduleDemandExecution?: (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	) => void;
	readonly store: BridgeCommWorkerStore;
}

function handleBridgeWorkerViewportCommand(
	props: HandleBridgeWorkerViewportCommandProps,
): readonly BridgeWorkerServerToMainMessage[] {
	props.store.actions.applyViewportFact({
		firstVisibleIndex: props.message.firstVisibleIndex,
		lastVisibleIndex: props.message.lastVisibleIndex,
		visibleItemIds: props.message.visibleItemIds,
	});
	const slicePatch = props.store.actions.takePendingSlicePatchEvent({
		epoch: props.message.epoch,
		sequence: props.createSequence(),
	});
	props.scheduleDemandExecution?.({
		cause: 'viewport',
		epoch: props.message.epoch,
		store: props.store,
	});
	return [
		...(slicePatch === null ? [] : [slicePatch]),
		buildBridgeWorkerReadyHealthEvent(props.message.requestId),
	];
}

function findChangedReviewRuntimeSourceItemIds(props: {
	readonly nextSource: BridgeCommWorkerReviewRuntimeSource;
	readonly previousSource: BridgeCommWorkerReviewRuntimeSource;
}): readonly string[] {
	const candidateItemIds = new Set<string>();
	for (const source of [props.previousSource, props.nextSource]) {
		for (const metadata of source.contentItems) {
			candidateItemIds.add(metadata.itemId);
		}
		for (const descriptor of source.contentRequestDescriptors) {
			candidateItemIds.add(descriptor.itemId);
		}
		for (const semantics of source.renderSemantics) {
			candidateItemIds.add(semantics.itemId);
		}
	}
	return Array.from(candidateItemIds).filter(
		(itemId) =>
			!areReviewContentMetadataEquivalent(
				findReviewContentMetadata(props.previousSource, itemId),
				findReviewContentMetadata(props.nextSource, itemId),
			) ||
			!areReviewContentRequestDescriptorsEquivalent(
				findReviewContentRequestDescriptors(props.previousSource, itemId),
				findReviewContentRequestDescriptors(props.nextSource, itemId),
			) ||
			!areReviewRenderSemanticsEquivalent(
				findReviewRenderSemantics(props.previousSource, itemId),
				findReviewRenderSemantics(props.nextSource, itemId),
			),
	);
}

function findReviewContentMetadata(
	source: BridgeCommWorkerReviewRuntimeSource,
	itemId: string,
): BridgeWorkerReviewContentMetadata | null {
	return source.contentItems.find((metadata) => metadata.itemId === itemId) ?? null;
}

function findReviewContentRequestDescriptors(
	source: BridgeCommWorkerReviewRuntimeSource,
	itemId: string,
): readonly BridgeWorkerReviewContentRequestDescriptor[] {
	return source.contentRequestDescriptors.filter((descriptor) => descriptor.itemId === itemId);
}

function findReviewRenderSemantics(
	source: BridgeCommWorkerReviewRuntimeSource,
	itemId: string,
): BridgeWorkerReviewRenderSemantics | null {
	return source.renderSemantics.find((semantics) => semantics.itemId === itemId) ?? null;
}

function isReviewRuntimeSourceExecutableForItem(
	source: BridgeCommWorkerReviewRuntimeSource,
	itemId: string,
): boolean {
	const metadata = findReviewContentMetadata(source, itemId);
	const semantics = findReviewRenderSemantics(source, itemId);
	return (
		metadata !== null &&
		metadata.availableContentRoles.length > 0 &&
		semantics !== null &&
		canRenderBridgeWorkerReviewContentForSemantics({
			descriptors: source.contentRequestDescriptors,
			semantics,
		})
	);
}

function areReviewContentMetadataEquivalent(
	left: BridgeWorkerReviewContentMetadata | null,
	right: BridgeWorkerReviewContentMetadata | null,
): boolean {
	if (left === null || right === null) {
		return left === right;
	}
	return (
		left.itemId === right.itemId &&
		left.path === right.path &&
		left.language === right.language &&
		left.cacheKey === right.cacheKey &&
		left.sizeBytes === right.sizeBytes &&
		areStringArraysEquivalent(left.availableContentRoles, right.availableContentRoles) &&
		left.contentLineCountsByRole.base === right.contentLineCountsByRole.base &&
		left.contentLineCountsByRole.head === right.contentLineCountsByRole.head &&
		left.contentLineCountsByRole.diff === right.contentLineCountsByRole.diff
	);
}

function areReviewContentRequestDescriptorsEquivalent(
	left: readonly BridgeWorkerReviewContentRequestDescriptor[],
	right: readonly BridgeWorkerReviewContentRequestDescriptor[],
): boolean {
	if (left.length !== right.length) {
		return false;
	}
	return left.every((leftDescriptor, index) =>
		areReviewContentRequestDescriptorEquivalent(leftDescriptor, right[index] ?? null),
	);
}

function areReviewContentRequestDescriptorEquivalent(
	left: BridgeWorkerReviewContentRequestDescriptor,
	right: BridgeWorkerReviewContentRequestDescriptor | null,
): boolean {
	return (
		right !== null &&
		left.itemId === right.itemId &&
		left.role === right.role &&
		left.handleId === right.handleId &&
		left.reviewGeneration === right.reviewGeneration &&
		left.resourceUrl === right.resourceUrl &&
		left.contentHash === right.contentHash &&
		left.contentHashAlgorithm === right.contentHashAlgorithm &&
		left.language === right.language &&
		left.sizeBytes === right.sizeBytes &&
		(left.expectedBytes ?? null) === (right.expectedBytes ?? null) &&
		left.maxBytes === right.maxBytes &&
		left.isBinary === right.isBinary
	);
}

function areReviewRenderSemanticsEquivalent(
	left: BridgeWorkerReviewRenderSemantics | null,
	right: BridgeWorkerReviewRenderSemantics | null,
): boolean {
	if (left === null || right === null) {
		return left === right;
	}
	return (
		left.itemId === right.itemId &&
		left.itemKind === right.itemKind &&
		left.changeKind === right.changeKind &&
		left.displayPath === right.displayPath &&
		left.basePath === right.basePath &&
		left.headPath === right.headPath &&
		left.language === right.language &&
		left.contentLineCountsByRole.base === right.contentLineCountsByRole.base &&
		left.contentLineCountsByRole.head === right.contentLineCountsByRole.head &&
		left.contentLineCountsByRole.diff === right.contentLineCountsByRole.diff
	);
}

function areStringArraysEquivalent(left: readonly string[], right: readonly string[]): boolean {
	return left.length === right.length && left.every((value, index) => value === right[index]);
}

function resolveReviewInvalidationAffectedItemIds(props: {
	readonly message: BridgeWorkerReviewInvalidateCommand;
	readonly store: BridgeCommWorkerStore;
}): readonly string[] | undefined {
	if (props.message.scope === 'package' || props.message.scope === 'treeWindow') {
		return undefined;
	}
	const itemIds = new Set(props.message.itemIds);
	for (const itemId of findReviewItemIdsByPathHints({
		pathHints: props.message.pathHints,
		store: props.store,
	})) {
		itemIds.add(itemId);
	}
	if (props.message.scope === 'items') {
		return Array.from(itemIds);
	}
	return Array.from(itemIds);
}

function findReviewItemIdsByPathHints(props: {
	readonly pathHints: readonly string[];
	readonly store: BridgeCommWorkerStore;
}): readonly string[] {
	const pathHints = new Set(props.pathHints);
	return Array.from(props.store.getState().contentMetadataByItemId.values())
		.filter(
			(metadata): metadata is BridgeWorkerReviewContentMetadata =>
				isBridgeWorkerReviewContentMetadata(metadata) && pathHints.has(metadata.path),
		)
		.map((metadata) => metadata.itemId);
}

interface RejectStaleOrReplayedBridgeWorkerCommandProps {
	readonly currentEpoch: number;
	readonly message: BridgeWorkerMainToServerMessage;
	readonly seenRequestIds: ReadonlySet<string>;
}

function rejectStaleOrReplayedBridgeWorkerCommand(
	props: RejectStaleOrReplayedBridgeWorkerCommandProps,
): BridgeWorkerServerToMainMessage | null {
	if (props.message.epoch < props.currentEpoch) {
		return buildBridgeWorkerDegradedHealthEvent({
			message: `Bridge comm worker rejected stale epoch ${props.message.epoch} after ${props.currentEpoch}.`,
			requestId: props.message.requestId,
		});
	}
	if (props.seenRequestIds.has(props.message.requestId)) {
		return buildBridgeWorkerDegradedHealthEvent({
			message: `Bridge comm worker rejected replayed request ${props.message.requestId}.`,
			requestId: props.message.requestId,
		});
	}
	return null;
}

function buildBridgeWorkerUnimplementedHealthEvent(
	message: BridgeWorkerMainToServerMessage,
): BridgeWorkerServerToMainMessage {
	return buildBridgeWorkerDegradedHealthEvent({
		message: `Bridge comm worker command ${message.command} is not implemented.`,
		requestId: message.requestId,
	});
}

function buildBridgeWorkerDegradedHealthEvent(props: {
	readonly requestId: string;
	readonly message: string;
}): BridgeWorkerServerToMainMessage {
	return {
		wireVersion: 1,
		direction: 'serverWorkerToMain',
		transferDescriptors: [],
		kind: 'health',
		requestId: props.requestId,
		status: 'degraded',
		message: props.message,
	};
}

function createBridgeWorkerSequenceCounter(): () => number {
	let nextSequence = 1;
	return (): number => {
		const sequence = nextSequence;
		nextSequence += 1;
		return sequence;
	};
}

function assertNeverBridgeWorkerCommand(_message: never): never {
	throw new Error('Unhandled bridge worker command.');
}
