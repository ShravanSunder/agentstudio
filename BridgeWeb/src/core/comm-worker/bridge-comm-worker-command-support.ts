import type {
	BridgeWorkerMainToServerMessage,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

export function buildBridgeWorkerUnimplementedHealthEvent(
	message: BridgeWorkerMainToServerMessage,
): BridgeWorkerServerToMainMessage {
	return buildBridgeWorkerDegradedHealthEvent({
		message: `Bridge comm worker command ${message.command} is not implemented.`,
		requestId: message.requestId,
	});
}

export function buildBridgeWorkerDegradedHealthEvent(props: {
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

export function createBridgeWorkerSequenceCounter(): () => number {
	let nextSequence = 1;
	return (): number => {
		const sequence = nextSequence;
		nextSequence += 1;
		return sequence;
	};
}

export function assertNeverBridgeWorkerCommand(_message: never): never {
	throw new Error('Unhandled bridge worker command.');
}
