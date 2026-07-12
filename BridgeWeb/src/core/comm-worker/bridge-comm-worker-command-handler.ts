import {
	assertNeverBridgeWorkerCommand,
	buildBridgeWorkerDegradedHealthEvent,
	buildBridgeWorkerUnimplementedHealthEvent,
	createBridgeWorkerSequenceCounter,
} from './bridge-comm-worker-command-support.js';
import type { BridgeCommWorkerFileViewRuntimeMutation } from './bridge-comm-worker-file-metadata-projection.js';
import {
	applyFileViewRuntimeMutationToSource,
	areFileViewContentRequestsEquivalent,
	findFileViewContentRequest,
	normalizeBridgeCommWorkerFileViewRuntimeSource,
	type BridgeCommWorkerFileViewRuntimeSource,
} from './bridge-comm-worker-file-view-runtime-source.js';
import type { BridgeCommWorkerFileMetadataDemand } from './bridge-comm-worker-product-controller.js';
import { buildBridgeWorkerReadyHealthEvent } from './bridge-comm-worker-protocol.js';
import {
	findChangedReviewRuntimeSourceItemIds,
	isReviewRuntimeSourceExecutableForItem,
	type BridgeCommWorkerReviewRuntimeSource,
} from './bridge-comm-worker-review-source-diff.js';
import {
	createBridgeCommWorkerStore,
	type BridgeCommWorkerRow,
	type BridgeCommWorkerStore,
	type BridgeCommWorkerViewportRange,
} from './bridge-comm-worker-store.js';
import type { BridgeCommWorkerTelemetryRecorder } from './bridge-comm-worker-telemetry.js';
import {
	isBridgeWorkerFileViewContentMetadata,
	type BridgeWorkerFileViewContentMetadata,
	type BridgeWorkerFileDisplayResyncCommand,
	type BridgeWorkerFileQueryUpdateCommand,
	type BridgeWorkerMainToServerMessage,
	type BridgeWorkerReviewContentMetadata,
	type BridgeWorkerReviewContentRequestDescriptor,
	type BridgeWorkerReviewInvalidateCommand,
	type BridgeWorkerReviewRenderSemantics,
	type BridgeWorkerReviewSourceUpdateCommand,
	type BridgeWorkerSelectCommand,
	type BridgeWorkerServerToMainMessage,
	type BridgeWorkerViewportCommand,
} from './bridge-worker-contracts.js';

export type { BridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-review-source-diff.js';

export type { BridgeCommWorkerFileViewRuntimeSource } from './bridge-comm-worker-file-view-runtime-source.js';

export type { BridgeCommWorkerFileMetadataDemand } from './bridge-comm-worker-product-controller.js';

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
	readonly updateFileMetadataDemand?: (demand: BridgeCommWorkerFileMetadataDemand) => void;
	readonly updateFileDisplayQuery?: (
		command: BridgeWorkerFileQueryUpdateCommand,
	) => readonly BridgeWorkerServerToMainMessage[];
	readonly requestFileDisplayResync?: (
		command: BridgeWorkerFileDisplayResyncCommand,
	) => readonly BridgeWorkerServerToMainMessage[];
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
	readonly applyFileViewRuntimeSource: (props: {
		readonly epoch: number;
		readonly source: BridgeCommWorkerFileViewRuntimeSource;
	}) => readonly BridgeWorkerServerToMainMessage[];
	readonly applyFileViewRuntimeMutation: (props: {
		readonly epoch: number;
		readonly mutation: BridgeCommWorkerFileViewRuntimeMutation;
	}) => readonly BridgeWorkerServerToMainMessage[];
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
		contentRequests: [],
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
		applyFileViewRuntimeSource: ({ epoch, source }) =>
			applyBridgeCommWorkerFileViewRuntimeSource({
				createSequence,
				demandEpoch: currentEpoch,
				epoch,
				nextFileViewRuntimeSource: source,
				previousFileViewRuntimeSource: fileViewRuntimeSource,
				scheduleSelectedFileViewContentReadyPreparation:
					props.scheduleSelectedFileViewContentReadyPreparation,
				store,
				...(props.updateFileMetadataDemand === undefined
					? {}
					: { updateFileMetadataDemand: props.updateFileMetadataDemand }),
				updateFileViewRuntimeSource: (nextSource): void => {
					fileViewRuntimeSource = normalizeBridgeCommWorkerFileViewRuntimeSource(nextSource);
					props.updateFileViewRuntimeSource?.(fileViewRuntimeSource);
				},
			}),
		applyFileViewRuntimeMutation: ({ epoch, mutation }) =>
			applyBridgeCommWorkerFileViewRuntimeMutation({
				createSequence,
				demandEpoch: currentEpoch,
				epoch,
				mutation,
				scheduleSelectedFileViewContentReadyPreparation:
					props.scheduleSelectedFileViewContentReadyPreparation,
				source: fileViewRuntimeSource,
				store,
				...(props.updateFileMetadataDemand === undefined
					? {}
					: { updateFileMetadataDemand: props.updateFileMetadataDemand }),
				updateFileViewRuntimeSource: (nextSource): void => {
					fileViewRuntimeSource = nextSource;
					props.updateFileViewRuntimeSource?.(nextSource);
				},
			}),
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
				fileViewRuntimeSource,
				...(props.scheduleDemandExecution === undefined
					? {}
					: { scheduleDemandExecution: props.scheduleDemandExecution }),
				...(props.scheduleReviewSourceUpdate === undefined
					? {}
					: { scheduleReviewSourceUpdate: props.scheduleReviewSourceUpdate }),
				store,
				reviewRuntimeSource,
				updateReviewRuntimeSource: (source: BridgeCommWorkerReviewRuntimeSource): void => {
					reviewRuntimeSource = source;
					props.updateReviewRuntimeSource?.(source);
				},
				updateFileViewRuntimeSource: (source: BridgeCommWorkerFileViewRuntimeSource): void => {
					fileViewRuntimeSource = source;
					props.updateFileViewRuntimeSource?.(source);
				},
				...(props.updateFileMetadataDemand === undefined
					? {}
					: { updateFileMetadataDemand: props.updateFileMetadataDemand }),
				...(props.updateFileDisplayQuery === undefined
					? {}
					: { updateFileDisplayQuery: props.updateFileDisplayQuery }),
				...(props.requestFileDisplayResync === undefined
					? {}
					: { requestFileDisplayResync: props.requestFileDisplayResync }),
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
	readonly updateFileMetadataDemand?: (demand: BridgeCommWorkerFileMetadataDemand) => void;
	readonly updateFileDisplayQuery?: (
		command: BridgeWorkerFileQueryUpdateCommand,
	) => readonly BridgeWorkerServerToMainMessage[];
	readonly requestFileDisplayResync?: (
		command: BridgeWorkerFileDisplayResyncCommand,
	) => readonly BridgeWorkerServerToMainMessage[];
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
				fileViewRuntimeSource: props.fileViewRuntimeSource,
				scheduleSelectedReviewContentReadyPreparation:
					props.scheduleSelectedReviewContentReadyPreparation,
				scheduleSelectedFileViewContentReadyPreparation:
					props.scheduleSelectedFileViewContentReadyPreparation,
				store: props.store,
				...(props.updateFileMetadataDemand === undefined
					? {}
					: { updateFileMetadataDemand: props.updateFileMetadataDemand }),
			});
		case 'viewport':
			return handleBridgeWorkerViewportCommand({
				createSequence: props.createSequence,
				message: props.message,
				fileViewRuntimeSource: props.fileViewRuntimeSource,
				...(props.scheduleDemandExecution === undefined
					? {}
					: { scheduleDemandExecution: props.scheduleDemandExecution }),
				store: props.store,
				...(props.updateFileMetadataDemand === undefined
					? {}
					: { updateFileMetadataDemand: props.updateFileMetadataDemand }),
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
				scheduleSelectedReviewContentReadyPreparation:
					props.scheduleSelectedReviewContentReadyPreparation,
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
		case 'fileQueryUpdate':
			return (
				props.updateFileDisplayQuery?.(props.message) ?? [
					buildBridgeWorkerUnimplementedHealthEvent(props.message),
				]
			);
		case 'fileDisplayResync':
			return (
				props.requestFileDisplayResync?.(props.message) ?? [
					buildBridgeWorkerUnimplementedHealthEvent(props.message),
				]
			);
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

function applyBridgeCommWorkerFileViewRuntimeSource(props: {
	readonly createSequence: () => number;
	readonly demandEpoch: number;
	readonly epoch: number;
	readonly nextFileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource;
	readonly previousFileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource;
	readonly scheduleSelectedFileViewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
	) => void;
	readonly store: BridgeCommWorkerStore;
	readonly updateFileViewRuntimeSource: (source: BridgeCommWorkerFileViewRuntimeSource) => void;
	readonly updateFileMetadataDemand?: (demand: BridgeCommWorkerFileMetadataDemand) => void;
}): readonly BridgeWorkerServerToMainMessage[] {
	const sourceUpdateResult = props.store.actions.applyFileViewSourceUpdateFact({
		contentItems: props.nextFileViewRuntimeSource.contentItems,
		epoch: props.epoch,
		rows: props.nextFileViewRuntimeSource.rows,
	});
	props.updateFileViewRuntimeSource(props.nextFileViewRuntimeSource);
	publishBridgeCommWorkerFileMetadataDemand({
		epoch: props.demandEpoch,
		fileViewRuntimeSource: props.nextFileViewRuntimeSource,
		store: props.store,
		...(props.updateFileMetadataDemand === undefined
			? {}
			: { updateFileMetadataDemand: props.updateFileMetadataDemand }),
	});
	const slicePatch = props.store.actions.takePendingSlicePatchEvent({
		epoch: props.epoch,
		sequence: props.createSequence(),
	});
	scheduleSelectedFileViewContentReadyPreparationForCurrentDemand({
		epoch: props.epoch,
		scheduleSelectedFileViewContentReadyPreparation:
			props.scheduleSelectedFileViewContentReadyPreparation,
		selectedContentMetadataChanged:
			sourceUpdateResult.selectedFileViewContentMetadataChanged === true,
		selectedContentRequestChanged: didSelectedFileViewContentRequestChange({
			nextFileViewRuntimeSource: props.nextFileViewRuntimeSource,
			previousFileViewRuntimeSource: props.previousFileViewRuntimeSource,
			selectedId: props.store.getState().selectedId,
		}),
		store: props.store,
	});
	return slicePatch === null ? [] : [slicePatch];
}

function applyBridgeCommWorkerFileViewRuntimeMutation(props: {
	readonly createSequence: () => number;
	readonly demandEpoch: number;
	readonly epoch: number;
	readonly mutation: BridgeCommWorkerFileViewRuntimeMutation;
	readonly scheduleSelectedFileViewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
	) => void;
	readonly source: BridgeCommWorkerFileViewRuntimeSource;
	readonly store: BridgeCommWorkerStore;
	readonly updateFileViewRuntimeSource: (source: BridgeCommWorkerFileViewRuntimeSource) => void;
	readonly updateFileMetadataDemand?: (demand: BridgeCommWorkerFileMetadataDemand) => void;
}): readonly BridgeWorkerServerToMainMessage[] {
	const selectedId = props.store.getState().selectedId;
	const previousSelectedRequest =
		selectedId === null ? null : findFileViewContentRequest(props.source, selectedId);
	const sourceUpdateResult = props.store.actions.applyFileViewSourceMutationFact({
		epoch: props.epoch,
		mutation: props.mutation,
	});
	const nextSource = applyFileViewRuntimeMutationToSource(props.source, props.mutation);
	props.updateFileViewRuntimeSource(nextSource);
	publishBridgeCommWorkerFileMetadataDemand({
		epoch: props.demandEpoch,
		fileViewRuntimeSource: nextSource,
		store: props.store,
		...(props.updateFileMetadataDemand === undefined
			? {}
			: { updateFileMetadataDemand: props.updateFileMetadataDemand }),
	});
	const slicePatch = props.store.actions.takePendingSlicePatchEvent({
		epoch: props.epoch,
		sequence: props.createSequence(),
	});
	const nextSelectedRequest =
		selectedId === null ? null : findFileViewContentRequest(nextSource, selectedId);
	scheduleSelectedFileViewContentReadyPreparationForCurrentDemand({
		epoch: props.epoch,
		scheduleSelectedFileViewContentReadyPreparation:
			props.scheduleSelectedFileViewContentReadyPreparation,
		selectedContentMetadataChanged:
			sourceUpdateResult.selectedFileViewContentMetadataChanged === true,
		selectedContentRequestChanged: !areFileViewContentRequestsEquivalent(
			previousSelectedRequest,
			nextSelectedRequest,
		),
		store: props.store,
	});
	return slicePatch === null ? [] : [slicePatch];
}

interface HandleBridgeWorkerReviewSourceUpdateCommandProps {
	readonly createSequence: () => number;
	readonly message: BridgeWorkerReviewSourceUpdateCommand;
	readonly previousReviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource;
	readonly scheduleSelectedReviewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	) => void;
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
	const sourceUpdateResult = props.store.actions.applyReviewSourceUpdateFact({
		contentItems: props.message.contentItems,
		epoch: props.message.epoch,
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
	props.scheduleDemandExecution?.({
		affectedItemIds,
		cause: 'reviewSourceUpdate',
		epoch: props.message.epoch,
		store: props.store,
	});
	const repairedSelectedAvailability = sourceUpdateResult.touchedKeys.some((touchedKey) =>
		touchedKey.startsWith('availability:'),
	);
	const slicePatch =
		appliedTerminalAvailability || repairedSelectedAvailability
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
	readonly fileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource;
	readonly reviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource;
	readonly scheduleSelectedReviewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	) => void;
	readonly scheduleSelectedFileViewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
	) => void;
	readonly store: BridgeCommWorkerStore;
	readonly updateFileMetadataDemand?: (demand: BridgeCommWorkerFileMetadataDemand) => void;
}

function handleBridgeWorkerSelectCommand(
	props: HandleBridgeWorkerSelectCommandProps,
): readonly BridgeWorkerServerToMainMessage[] {
	applySelectedReviewRuntimeSourceItemIfNeeded({
		epoch: props.message.epoch,
		itemId: props.message.selectedItemId,
		reviewRuntimeSource: props.reviewRuntimeSource,
		store: props.store,
	});
	props.store.actions.applySelectedFact({
		epoch: props.message.epoch,
		itemId: props.message.selectedItemId,
	});
	publishBridgeCommWorkerFileMetadataDemand({
		epoch: props.message.epoch,
		fileViewRuntimeSource: props.fileViewRuntimeSource,
		store: props.store,
		...(props.updateFileMetadataDemand === undefined
			? {}
			: { updateFileMetadataDemand: props.updateFileMetadataDemand }),
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
	readonly epoch: number;
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
		epoch: props.epoch,
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
	readonly selectedContentRequestChanged: boolean;
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
		!props.selectedContentRequestChanged
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

function didSelectedFileViewContentRequestChange(props: {
	readonly nextFileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource;
	readonly previousFileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource;
	readonly selectedId: string | null;
}): boolean {
	if (props.selectedId === null) {
		return false;
	}
	return !areFileViewContentRequestsEquivalent(
		findFileViewContentRequest(props.previousFileViewRuntimeSource, props.selectedId),
		findFileViewContentRequest(props.nextFileViewRuntimeSource, props.selectedId),
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

function isBridgeWorkerReviewContentMetadata(
	metadata: BridgeWorkerReviewContentMetadata | BridgeWorkerFileViewContentMetadata | null,
): metadata is BridgeWorkerReviewContentMetadata {
	return metadata !== null && 'availableContentRoles' in metadata;
}

interface HandleBridgeWorkerViewportCommandProps {
	readonly createSequence: () => number;
	readonly fileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource;
	readonly message: BridgeWorkerViewportCommand;
	readonly scheduleDemandExecution?: (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	) => void;
	readonly store: BridgeCommWorkerStore;
	readonly updateFileMetadataDemand?: (demand: BridgeCommWorkerFileMetadataDemand) => void;
}

function handleBridgeWorkerViewportCommand(
	props: HandleBridgeWorkerViewportCommandProps,
): readonly BridgeWorkerServerToMainMessage[] {
	props.store.actions.applyViewportFact({
		firstVisibleIndex: props.message.firstVisibleIndex,
		lastVisibleIndex: props.message.lastVisibleIndex,
		visibleItemIds: props.message.visibleItemIds,
	});
	publishBridgeCommWorkerFileMetadataDemand({
		epoch: props.message.epoch,
		fileViewRuntimeSource: props.fileViewRuntimeSource,
		store: props.store,
		...(props.updateFileMetadataDemand === undefined
			? {}
			: { updateFileMetadataDemand: props.updateFileMetadataDemand }),
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

function publishBridgeCommWorkerFileMetadataDemand(props: {
	readonly epoch: number;
	readonly fileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource;
	readonly store: BridgeCommWorkerStore;
	readonly updateFileMetadataDemand?: (demand: BridgeCommWorkerFileMetadataDemand) => void;
}): void {
	if (props.updateFileMetadataDemand === undefined) return;
	const state = props.store.getState();
	if (state.selectedId === null && state.viewportRange === null) return;
	const filePathsByItemId = props.fileViewRuntimeSource.filePathsByItemId ?? new Map();
	const selectedPath =
		state.selectedId === null ? null : (filePathsByItemId.get(state.selectedId) ?? null);
	const visiblePaths = state.visibleIds.flatMap((itemId): readonly string[] => {
		const path = filePathsByItemId.get(itemId);
		return path === undefined ? [] : [path];
	});
	const nearbyPaths = bridgeCommWorkerNearbyFilePaths({
		filePathsByItemId,
		rows: props.fileViewRuntimeSource.rows,
		...(props.fileViewRuntimeSource.rowsByIndex === undefined
			? {}
			: { rowsByIndex: props.fileViewRuntimeSource.rowsByIndex }),
		viewportRange: state.viewportRange,
	});
	props.updateFileMetadataDemand({
		epoch: props.epoch,
		nearbyPaths,
		selectedPath,
		visiblePaths,
	});
}

function bridgeCommWorkerNearbyFilePaths(props: {
	readonly filePathsByItemId: ReadonlyMap<string, string>;
	readonly rows: readonly BridgeCommWorkerRow[];
	readonly rowsByIndex?: ReadonlyMap<number, BridgeCommWorkerRow>;
	readonly viewportRange: BridgeCommWorkerViewportRange | null;
}): readonly string[] {
	const viewportRange = props.viewportRange;
	if (viewportRange === null) return [];
	const nearbyLowerIndex = Math.max(0, viewportRange.firstVisibleIndex - 1);
	const nearbyUpperIndex = viewportRange.lastVisibleIndex + 1;
	if (props.rowsByIndex !== undefined) {
		const paths: string[] = [];
		for (let index = nearbyLowerIndex; index <= nearbyUpperIndex; index += 1) {
			if (index >= viewportRange.firstVisibleIndex && index <= viewportRange.lastVisibleIndex) {
				continue;
			}
			const row = props.rowsByIndex.get(index);
			const path = row === undefined ? undefined : props.filePathsByItemId.get(row.id);
			if (path !== undefined) paths.push(path);
		}
		return paths;
	}
	return props.rows.flatMap((row): readonly string[] => {
		if (
			row.index < nearbyLowerIndex ||
			row.index > nearbyUpperIndex ||
			(row.index >= viewportRange.firstVisibleIndex && row.index <= viewportRange.lastVisibleIndex)
		) {
			return [];
		}
		const path = props.filePathsByItemId.get(row.id);
		return path === undefined ? [] : [path];
	});
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
