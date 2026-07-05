// oxlint-disable unicorn/require-post-message-target-origin -- WorkerGlobalScope.postMessage does not accept a targetOrigin argument.
import { buildBridgeWorkerReadyHealthEvent } from './bridge-comm-worker-protocol.js';
import {
	bridgeWorkerMainToServerMessageSchema,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

export interface BridgeCommWorkerPort {
	readonly postMessage: (message: BridgeWorkerServerToMainMessage) => void;
	readonly addEventListener: (
		type: 'message',
		listener: (event: MessageEvent<unknown>) => void,
	) => void;
	readonly start?: () => void;
}

export interface BridgeCommWorkerGlobalScope {
	readonly postMessage: (message: BridgeWorkerServerToMainMessage) => void;
	readonly addEventListener: (
		type: 'message',
		listener: (event: MessageEvent<unknown>) => void,
	) => void;
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

export function bootstrapInertBridgeCommWorkerEntry(scope: BridgeCommWorkerGlobalScope): void {
	registerInertBridgeCommWorkerPortProtocol({
		postMessage: (message: BridgeWorkerServerToMainMessage): void => {
			scope.postMessage(message);
		},
		addEventListener: (type: 'message', listener: (event: MessageEvent<unknown>) => void): void => {
			scope.addEventListener(type, listener);
		},
	});
}

declare const self: BridgeCommWorkerGlobalScope | undefined;

if (typeof self !== 'undefined' && typeof self.addEventListener === 'function') {
	bootstrapInertBridgeCommWorkerEntry(self);
}
