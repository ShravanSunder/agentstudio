import { buildBridgeWorkerReadyHealthEvent } from './bridge-comm-worker-protocol.js';
import {
	createBridgeCommWorkerStore,
	type BridgeCommWorkerRow,
	type BridgeCommWorkerStore,
} from './bridge-comm-worker-store.js';
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
	readonly rows: readonly BridgeCommWorkerRow[];
	readonly createSequence?: () => number;
	readonly scheduleSelectedReviewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	) => void;
	readonly scheduleSelectedFileViewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
	) => void;
	readonly updateReviewRuntimeSource?: (source: BridgeCommWorkerReviewRuntimeSource) => void;
	readonly updateFileViewRuntimeSource?: (source: BridgeCommWorkerFileViewRuntimeSource) => void;
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
		rows: props.rows,
	});
	const createSequence = props.createSequence ?? createBridgeWorkerSequenceCounter();
	const seenRequestIds = new Set<string>();
	let fileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource = {
		contentItems: [],
		contentRequestDescriptors: [],
		rows: [],
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
				store,
				fileViewRuntimeSource,
				...(props.updateReviewRuntimeSource === undefined
					? {}
					: { updateReviewRuntimeSource: props.updateReviewRuntimeSource }),
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
	readonly store: BridgeCommWorkerStore;
	readonly fileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource;
	readonly updateReviewRuntimeSource?: (source: BridgeCommWorkerReviewRuntimeSource) => void;
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
				store: props.store,
			});
		case 'reviewInvalidate':
			return handleBridgeWorkerReviewInvalidateCommand({
				createSequence: props.createSequence,
				message: props.message,
				scheduleSelectedReviewContentReadyPreparation:
					props.scheduleSelectedReviewContentReadyPreparation,
				store: props.store,
			});
		case 'reviewSourceUpdate':
			return handleBridgeWorkerReviewSourceUpdateCommand({
				message: props.message,
				store: props.store,
				...(props.updateReviewRuntimeSource === undefined
					? {}
					: { updateReviewRuntimeSource: props.updateReviewRuntimeSource }),
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
		case 'hover':
		case 'markFileViewed':
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
	readonly message: BridgeWorkerReviewSourceUpdateCommand;
	readonly store: BridgeCommWorkerStore;
	readonly updateReviewRuntimeSource?: (source: BridgeCommWorkerReviewRuntimeSource) => void;
}

function handleBridgeWorkerReviewSourceUpdateCommand(
	props: HandleBridgeWorkerReviewSourceUpdateCommandProps,
): readonly BridgeWorkerServerToMainMessage[] {
	props.store.actions.applyReviewSourceUpdateFact({
		contentItems: props.message.contentItems,
		rows: props.message.rows,
	});
	props.updateReviewRuntimeSource?.({
		contentItems: props.message.contentItems,
		contentRequestDescriptors: props.message.contentRequestDescriptors,
		renderSemantics: props.message.renderSemantics,
		rows: props.message.rows,
	});
	return [buildBridgeWorkerReadyHealthEvent(props.message.requestId)];
}

interface HandleBridgeWorkerSelectCommandProps {
	readonly createSequence: () => number;
	readonly message: BridgeWorkerSelectCommand;
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
	return [
		...(slicePatch === null ? [] : [slicePatch]),
		buildBridgeWorkerReadyHealthEvent(props.message.requestId),
	];
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
