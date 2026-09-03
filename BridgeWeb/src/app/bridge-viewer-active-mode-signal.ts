import type { BridgeActiveViewerSource } from '../core/comm-worker/bridge-product-control-contracts.js';
import type {
	BridgeWorkerHealthEvent,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';

export function bridgeActiveViewerSourcesEqual(
	left: BridgeActiveViewerSource | null,
	right: BridgeActiveViewerSource | null,
): boolean {
	return (
		left?.protocol === right?.protocol &&
		left?.streamId === right?.streamId &&
		left?.generation === right?.generation
	);
}

export function createBridgeActiveViewerModeSessionId(): string {
	return `active-viewer-${crypto.randomUUID()}`;
}

export function activeViewerModeRetryAttemptAvailable(props: {
	readonly retryAttemptsBySignalKey: Map<string, number>;
	readonly signalKey: string;
}): boolean {
	const currentAttemptCount = props.retryAttemptsBySignalKey.get(props.signalKey) ?? 0;
	if (currentAttemptCount >= 3) return false;
	props.retryAttemptsBySignalKey.set(props.signalKey, currentAttemptCount + 1);
	return true;
}

export function resolveBridgeWorkerActiveViewerModeRequestResolvers(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly resolversByRequestId: Map<string, (didSend: boolean) => void>;
	readonly settledResultsByRequestId: Map<string, boolean>;
}): void {
	for (const message of props.messages) {
		if (message.kind !== 'health' || message.requestId === undefined) continue;
		const resolve = props.resolversByRequestId.get(message.requestId);
		if (resolve === undefined) {
			props.settledResultsByRequestId.set(
				message.requestId,
				bridgeWorkerActiveViewerModeHealthDidSend(message),
			);
			continue;
		}
		props.resolversByRequestId.delete(message.requestId);
		resolve(bridgeWorkerActiveViewerModeHealthDidSend(message));
	}
}

export function resolvePendingBridgeWorkerActiveViewerModeRequests(props: {
	readonly didSend: boolean;
	readonly resolversByRequestId: Map<string, (didSend: boolean) => void>;
}): void {
	for (const resolve of props.resolversByRequestId.values()) resolve(props.didSend);
	props.resolversByRequestId.clear();
}

function bridgeWorkerActiveViewerModeHealthDidSend(message: BridgeWorkerHealthEvent): boolean {
	return message.status === 'ready' || message.deliveryStatus === 'unknownAfterDispatch';
}
