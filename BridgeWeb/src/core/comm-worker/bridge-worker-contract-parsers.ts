import {
	bridgeCommWorkerBootstrapRequestSchema,
	bridgeWorkerFileDisplayPatchEventSchema,
	bridgeWorkerMainToServerMessageSchema,
	bridgeWorkerServerToMainMessageSchema,
	type BridgeCommWorkerBootstrapRequest,
	type BridgeWorkerFileDisplayPatchEvent,
	type BridgeWorkerMainToServerMessage,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

export function parseBridgeWorkerMainToServerMessage(
	value: unknown,
): BridgeWorkerMainToServerMessage {
	return bridgeWorkerMainToServerMessageSchema.parse(value);
}

export function parseBridgeWorkerServerToMainMessage(
	value: unknown,
): BridgeWorkerServerToMainMessage {
	return bridgeWorkerServerToMainMessageSchema.parse(value);
}

export function parseBridgeWorkerFileDisplayPatchEvent(
	value: unknown,
): BridgeWorkerFileDisplayPatchEvent {
	return bridgeWorkerFileDisplayPatchEventSchema.parse(value);
}

export function parseBridgeCommWorkerBootstrapRequest(
	value: unknown,
): BridgeCommWorkerBootstrapRequest {
	return bridgeCommWorkerBootstrapRequestSchema.parse(value);
}
