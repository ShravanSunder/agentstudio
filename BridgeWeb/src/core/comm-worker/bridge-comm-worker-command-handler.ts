import {
	assertNeverBridgeWorkerCommand,
	buildBridgeWorkerDegradedHealthEvent,
	buildBridgeWorkerUnimplementedHealthEvent,
	createBridgeWorkerSequenceCounter,
} from './bridge-comm-worker-command-support.js';
import type { BridgeCommWorkerFileViewRuntimeMutation } from './bridge-comm-worker-file-metadata-projection.js';
import {
	applyFileViewRuntimeMutationTrackingSelectedRequest,
	didSelectedFileViewContentRequestChange,
	normalizeBridgeCommWorkerFileViewRuntimeSource,
	type BridgeCommWorkerFileViewRuntimeSource,
} from './bridge-comm-worker-file-view-runtime-source.js';
import type { BridgeCommWorkerFileMetadataDemand } from './bridge-comm-worker-product-controller.js';
import { buildBridgeWorkerReadyHealthEvent } from './bridge-comm-worker-protocol.js';
import {
	applyBridgeCommWorkerReviewMetadataApplication,
	type BridgeCommWorkerReviewMetadataApplication,
} from './bridge-comm-worker-review-metadata-applicator.js';
import type { BridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-review-source-diff.js';
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
	readonly scheduleReviewMetadataReset?: (
		request: BridgeCommWorkerReviewMetadataResetScheduleRequest,
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
	readonly cause: 'reviewInvalidate' | 'reviewMetadata' | 'viewport';
	readonly affectedItemIds?: readonly string[];
	readonly epoch: number;
	readonly forceExecutionItemIds?: readonly string[];
	readonly sourceChurnRevision?: number;
	readonly store: BridgeCommWorkerStore;
}

export interface BridgeCommWorkerReviewMetadataResetScheduleRequest {
	readonly affectedItemIds: readonly string[];
	readonly cause: 'reviewMetadata';
	readonly epoch: number;
	readonly readReviewRuntimeSource: () => BridgeCommWorkerReviewRuntimeSource;
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
	readonly applyReviewMetadataApplication: (
		application: BridgeCommWorkerReviewMetadataApplication,
	) => readonly BridgeWorkerServerToMainMessage[];
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
	const reviewStore = createBridgeCommWorkerStore({
		contentItems: props.contentItems,
		...(props.now === undefined ? {} : { now: props.now }),
		rows: props.rows,
		...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
	});
	const fileViewStore = createBridgeCommWorkerStore({
		contentItems: [],
		...(props.now === undefined ? {} : { now: props.now }),
		rows: [],
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
	const currentIntentEpochByDomain: Record<BridgeCommWorkerIntentEpochDomain, number> = {
		fileView: 0,
		pane: 0,
		review: 0,
	};

	return {
		applyReviewMetadataApplication: (application) =>
			applyBridgeCommWorkerReviewMetadataApplication({
				application,
				createSequence,
				readRuntimeSource: (): BridgeCommWorkerReviewRuntimeSource => reviewRuntimeSource,
				...(props.scheduleDemandExecution === undefined
					? {}
					: { scheduleDemandExecution: props.scheduleDemandExecution }),
				...(props.scheduleReviewMetadataReset === undefined
					? {}
					: { scheduleReset: props.scheduleReviewMetadataReset }),
				scheduleSelectedPreparation: props.scheduleSelectedReviewContentReadyPreparation,
				store: reviewStore,
				updateRuntimeSource: (source): void => {
					reviewRuntimeSource = source;
					props.updateReviewRuntimeSource?.(source);
				},
			}),
		applyFileViewRuntimeSource: ({ epoch, source }) =>
			applyBridgeCommWorkerFileViewRuntimeSource({
				createSequence,
				demandEpoch: currentIntentEpochByDomain.fileView,
				epoch,
				nextFileViewRuntimeSource: source,
				previousFileViewRuntimeSource: fileViewRuntimeSource,
				scheduleSelectedFileViewContentReadyPreparation:
					props.scheduleSelectedFileViewContentReadyPreparation,
				store: fileViewStore,
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
				demandEpoch: currentIntentEpochByDomain.fileView,
				epoch,
				mutation,
				scheduleSelectedFileViewContentReadyPreparation:
					props.scheduleSelectedFileViewContentReadyPreparation,
				source: fileViewRuntimeSource,
				store: fileViewStore,
				...(props.updateFileMetadataDemand === undefined
					? {}
					: { updateFileMetadataDemand: props.updateFileMetadataDemand }),
				updateFileViewRuntimeSource: (nextSource): void => {
					fileViewRuntimeSource = nextSource;
					props.updateFileViewRuntimeSource?.(nextSource);
				},
			}),
		handleMessage: (message: BridgeWorkerMainToServerMessage) => {
			const intentEpochDomain = bridgeCommWorkerIntentEpochDomain(message);
			const currentIntentEpoch = currentIntentEpochByDomain[intentEpochDomain];
			const commandStore = intentEpochDomain === 'fileView' ? fileViewStore : reviewStore;
			const rejection = rejectStaleOrReplayedBridgeWorkerCommand({
				currentEpoch: currentIntentEpoch,
				message,
				seenRequestIds,
			});
			if (rejection !== null) {
				return [rejection];
			}
			seenRequestIds.add(message.requestId);
			currentIntentEpochByDomain[intentEpochDomain] = Math.max(currentIntentEpoch, message.epoch);
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
				store: commandStore,
				reviewRuntimeSource,
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
	readonly store: BridgeCommWorkerStore;
	readonly reviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource;
	readonly fileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource;
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
	const selectedContentRequestChanged = didSelectedFileViewContentRequestChange({
		nextFileViewRuntimeSource: props.nextFileViewRuntimeSource,
		previousFileViewRuntimeSource: props.previousFileViewRuntimeSource,
		selectedId: props.store.getState().selectedId,
	});
	const sourceUpdateResult = props.store.actions.applyFileViewSourceUpdateFact({
		contentItems: props.nextFileViewRuntimeSource.contentItems,
		epoch: props.epoch,
		rows: props.nextFileViewRuntimeSource.rows,
		selectedContentRequestChanged,
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
		selectedContentRequestChanged,
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
	const { nextSource, selectedContentRequestChanged } =
		applyFileViewRuntimeMutationTrackingSelectedRequest({
			mutation: props.mutation,
			selectedId: props.store.getState().selectedId,
			source: props.source,
		});
	const sourceUpdateResult = props.store.actions.applyFileViewSourceMutationFact({
		epoch: props.epoch,
		mutation: props.mutation,
		selectedContentRequestChanged,
	});
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
	scheduleSelectedFileViewContentReadyPreparationForCurrentDemand({
		epoch: props.epoch,
		scheduleSelectedFileViewContentReadyPreparation:
			props.scheduleSelectedFileViewContentReadyPreparation,
		selectedContentMetadataChanged:
			sourceUpdateResult.selectedFileViewContentMetadataChanged === true,
		selectedContentRequestChanged,
		store: props.store,
	});
	return slicePatch === null ? [] : [slicePatch];
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
	if (props.message.surface === 'review') {
		applySelectedReviewRuntimeSourceItemIfNeeded({
			epoch: props.message.epoch,
			itemId: props.message.selectedItemId,
			reviewRuntimeSource: props.reviewRuntimeSource,
			store: props.store,
		});
	}
	props.store.actions.applySelectedFact({
		epoch: props.message.epoch,
		itemId: props.message.selectedItemId,
	});
	if (props.message.surface === 'fileView') {
		publishBridgeCommWorkerFileMetadataDemand({
			epoch: props.message.epoch,
			fileViewRuntimeSource: props.fileViewRuntimeSource,
			store: props.store,
			...(props.updateFileMetadataDemand === undefined
				? {}
				: { updateFileMetadataDemand: props.updateFileMetadataDemand }),
		});
	}
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
	if (props.message.surface === 'fileView' && isBridgeWorkerFileViewContentMetadata(metadata)) {
		props.scheduleSelectedFileViewContentReadyPreparation({
			epoch: props.message.epoch,
			itemId: selectedItemId,
			store: props.store,
		});
		return;
	}
	if (props.message.surface === 'review' && isBridgeWorkerReviewContentMetadata(metadata)) {
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
	if (!props.selectedContentMetadataChanged && !props.selectedContentRequestChanged) {
		return;
	}
	const availability = props.store.getState().availabilityByItemId.get(selectedId);
	if (availability !== 'loading' && availability !== 'stale' && availability !== 'ready') {
		return;
	}
	props.scheduleSelectedFileViewContentReadyPreparation({
		epoch: props.epoch,
		itemId: selectedId,
		store: props.store,
	});
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
	if (props.message.surface === 'fileView') {
		publishBridgeCommWorkerFileMetadataDemand({
			epoch: props.message.epoch,
			fileViewRuntimeSource: props.fileViewRuntimeSource,
			store: props.store,
			...(props.updateFileMetadataDemand === undefined
				? {}
				: { updateFileMetadataDemand: props.updateFileMetadataDemand }),
		});
	}
	const slicePatch = props.store.actions.takePendingSlicePatchEvent({
		epoch: props.message.epoch,
		sequence: props.createSequence(),
	});
	if (props.message.surface === 'review') {
		props.scheduleDemandExecution?.({
			cause: 'viewport',
			epoch: props.message.epoch,
			store: props.store,
		});
	}
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

type BridgeCommWorkerIntentEpochDomain = 'fileView' | 'pane' | 'review';

function bridgeCommWorkerIntentEpochDomain(
	message: BridgeWorkerMainToServerMessage,
): BridgeCommWorkerIntentEpochDomain {
	switch (message.command) {
		case 'hover':
		case 'select':
		case 'viewport':
			return message.surface;
		case 'fileDisplayResync':
		case 'fileQueryUpdate':
			return 'fileView';
		case 'markFileViewed':
		case 'metadataInterestUpdate':
		case 'reviewIntakeReady':
		case 'reviewInvalidate':
			return 'review';
		case 'activeViewerModeUpdate':
		case 'mode':
			return 'pane';
		default:
			return assertNeverBridgeWorkerCommand(message);
	}
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
