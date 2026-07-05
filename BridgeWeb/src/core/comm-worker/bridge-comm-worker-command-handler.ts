import { buildBridgeWorkerReadyHealthEvent } from './bridge-comm-worker-protocol.js';
import {
	createBridgeCommWorkerStore,
	type BridgeCommWorkerRow,
	type BridgeCommWorkerStore,
} from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerMainToServerMessage,
	BridgeWorkerSelectCommand,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

export interface CreateBridgeCommWorkerCommandHandlerProps {
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
	const store = createBridgeCommWorkerStore({ rows: props.rows });
	const createSequence = props.createSequence ?? createBridgeWorkerSequenceCounter();

	return {
		handleMessage: (message: BridgeWorkerMainToServerMessage) =>
			handleBridgeWorkerCommand({
				createSequence,
				message,
				store,
			}),
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
		case 'hover':
		case 'markFileViewed':
		case 'mode':
			return [buildBridgeWorkerReadyHealthEvent(props.message.requestId)];
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
