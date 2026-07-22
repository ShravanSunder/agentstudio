import type { BridgeWorkerServerToMainMessage } from '../core/comm-worker/bridge-worker-contracts.js';

export function resolveBridgeWorkerMarkFileViewedFailureCallbacks(props: {
	readonly failureCallbacksByRequestId: Map<string, () => void>;
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
}): void {
	for (const message of props.messages) {
		if (message.kind !== 'health' || message.requestId === undefined) {
			continue;
		}
		const onDeliveryFailure = props.failureCallbacksByRequestId.get(message.requestId);
		if (onDeliveryFailure === undefined) {
			continue;
		}
		props.failureCallbacksByRequestId.delete(message.requestId);
		if (message.status === 'degraded') {
			onDeliveryFailure();
		}
	}
}

export function resolveBridgeWorkerMetadataInterestRequestResolvers(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly resolversByRequestId: Map<string, (didSend: boolean) => void>;
}): void {
	resolveBridgeWorkerBooleanRequestResolvers(props);
}

export function resolveBridgeWorkerReviewIntakeReadyRequestResolvers(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly resolversByRequestId: Map<string, (didSend: boolean) => void>;
}): void {
	resolveBridgeWorkerBooleanRequestResolvers(props);
}

function resolveBridgeWorkerBooleanRequestResolvers(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly resolversByRequestId: Map<string, (didSend: boolean) => void>;
}): void {
	for (const message of props.messages) {
		if (message.kind !== 'health' || message.requestId === undefined) {
			continue;
		}
		const resolve = props.resolversByRequestId.get(message.requestId);
		if (resolve === undefined) {
			continue;
		}
		props.resolversByRequestId.delete(message.requestId);
		resolve(message.status === 'ready');
	}
}
