// oxlint-disable unicorn/require-post-message-target-origin -- WorkerGlobalScope.postMessage does not accept a targetOrigin argument.
import { buildBridgeWorkerReadyHealthEvent } from './bridge-comm-worker-protocol.js';
import {
	bridgeWorkerMainToServerMessageSchema,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type { PreparedBridgeWorkerStructuredMessage } from './bridge-worker-transfer-list.js';

export interface BridgeCommWorkerPort {
	postMessage(message: BridgeWorkerServerToMainMessage): void;
	postMessage(message: BridgeWorkerServerToMainMessage, transferList: Transferable[]): void;
	readonly addEventListener: (
		type: 'message',
		listener: (event: MessageEvent<unknown>) => void,
	) => void;
	readonly start?: () => void;
}

export interface BridgeCommWorkerGlobalScope {
	postMessage(message: BridgeWorkerServerToMainMessage): void;
	postMessage(message: BridgeWorkerServerToMainMessage, transferList: Transferable[]): void;
	readonly addEventListener: (
		type: 'message',
		listener: (event: MessageEvent<unknown>) => void,
	) => void;
}

export function postPreparedBridgeCommWorkerMessage(
	port: BridgeCommWorkerPort,
	preparedMessage: PreparedBridgeWorkerStructuredMessage<BridgeWorkerServerToMainMessage>,
): void {
	port.postMessage(preparedMessage.message, [...preparedMessage.transferList]);
}

export function registerInertBridgeCommWorkerPortProtocol(port: BridgeCommWorkerPort): void {
	port.addEventListener('message', (event: MessageEvent<unknown>): void => {
		const parsedMessage = bridgeWorkerMainToServerMessageSchema.safeParse(event.data);
		if (!parsedMessage.success) {
			port.postMessage({
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				status: 'degraded',
				message: 'Bridge comm worker received invalid message.',
			});
			return;
		}
		port.postMessage(buildBridgeWorkerReadyHealthEvent(parsedMessage.data.requestId));
	});
	port.start?.();
}

export function createBridgeCommWorkerScopePortAdapter(
	scope: BridgeCommWorkerGlobalScope,
): BridgeCommWorkerPort {
	return {
		postMessage: (
			message: BridgeWorkerServerToMainMessage,
			transferList?: Transferable[],
		): void => {
			if (transferList === undefined) {
				scope.postMessage(message);
				return;
			}
			scope.postMessage(message, transferList);
		},
		addEventListener: (type: 'message', listener: (event: MessageEvent<unknown>) => void): void => {
			scope.addEventListener(type, listener);
		},
	};
}

export function bootstrapInertBridgeCommWorkerEntry(scope: BridgeCommWorkerGlobalScope): void {
	registerInertBridgeCommWorkerPortProtocol(createBridgeCommWorkerScopePortAdapter(scope));
}

declare const self: BridgeCommWorkerGlobalScope | undefined;

if (typeof self !== 'undefined' && typeof self.addEventListener === 'function') {
	bootstrapInertBridgeCommWorkerEntry(self);
}
