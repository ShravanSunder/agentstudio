import { buildBridgeWorkerReadyHealthEvent } from './bridge-comm-worker-protocol.js';
import {
	createBridgeCommWorkerStore,
	type BridgeCommWorkerRow,
	type BridgeCommWorkerStore,
} from './bridge-comm-worker-store.js';
import type {
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

export interface CreateBridgeCommWorkerCommandHandlerProps {
	readonly contentItems: readonly BridgeWorkerReviewContentMetadata[];
	readonly rows: readonly BridgeCommWorkerRow[];
	readonly createSequence?: () => number;
	readonly scheduleSelectedReviewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	) => void;
	readonly updateReviewRuntimeSource?: (source: BridgeCommWorkerReviewRuntimeSource) => void;
}

export interface BridgeCommWorkerSelectedReviewContentReadyPreparationRequest {
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
				store,
				...(props.updateReviewRuntimeSource === undefined
					? {}
					: { updateReviewRuntimeSource: props.updateReviewRuntimeSource }),
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
	readonly store: BridgeCommWorkerStore;
	readonly updateReviewRuntimeSource?: (source: BridgeCommWorkerReviewRuntimeSource) => void;
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
		case 'hover':
		case 'markFileViewed':
		case 'mode':
			return [buildBridgeWorkerUnimplementedHealthEvent(props.message)];
		default:
			return assertNeverBridgeWorkerCommand(props.message);
	}
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
	if (shouldScheduleSelectedReviewContentReadyPreparation(props)) {
		props.scheduleSelectedReviewContentReadyPreparation({
			epoch: props.message.epoch,
			itemId: props.message.selectedItemId,
			store: props.store,
		});
	}
	return [
		...(slicePatch === null ? [] : [slicePatch]),
		buildBridgeWorkerReadyHealthEvent(props.message.requestId),
	];
}

function shouldScheduleSelectedReviewContentReadyPreparation(
	props: Pick<HandleBridgeWorkerSelectCommandProps, 'message' | 'store'>,
): boolean {
	return (
		props.store.getState().selectedId === props.message.selectedItemId &&
		props.store.getState().demandByKey.get(props.message.selectedItemId) ===
			`selected:${props.message.epoch}`
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
		props.store.getState().demandByKey.get(selectedId) === `selected:${props.message.epoch}`
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
