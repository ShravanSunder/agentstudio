import { buildBridgeWorkerReadyHealthEvent } from './bridge-comm-worker-protocol.js';
import {
	createBridgeCommWorkerStore,
	type BridgeCommWorkerRow,
	type BridgeCommWorkerStore,
} from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerMainToServerMessage,
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerSelectCommand,
	BridgeWorkerServerToMainMessage,
	BridgeWorkerViewportCommand,
} from './bridge-worker-contracts.js';

export interface CreateBridgeCommWorkerCommandHandlerProps {
	readonly contentItems: readonly BridgeWorkerReviewContentMetadata[];
	readonly rows: readonly BridgeCommWorkerRow[];
	readonly createSequence?: () => number;
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
				store,
			});
		},
	};
}

interface HandleBridgeWorkerCommandProps {
	readonly createSequence: () => number;
	readonly message: BridgeWorkerMainToServerMessage;
	readonly store: BridgeCommWorkerStore;
}

function handleBridgeWorkerCommand(
	props: HandleBridgeWorkerCommandProps,
): readonly BridgeWorkerServerToMainMessage[] {
	switch (props.message.command) {
		case 'select':
			return handleBridgeWorkerSelectCommand({
				createSequence: props.createSequence,
				message: props.message,
				store: props.store,
			});
		case 'viewport':
			return handleBridgeWorkerViewportCommand({
				createSequence: props.createSequence,
				message: props.message,
				store: props.store,
			});
		case 'hover':
		case 'markFileViewed':
		case 'mode':
			return [buildBridgeWorkerUnimplementedHealthEvent(props.message)];
		default:
			return assertNeverBridgeWorkerCommand(props.message);
	}
}

interface HandleBridgeWorkerSelectCommandProps {
	readonly createSequence: () => number;
	readonly message: BridgeWorkerSelectCommand;
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
