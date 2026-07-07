// oxlint-disable unicorn/require-post-message-target-origin -- WorkerGlobalScope.postMessage does not accept a targetOrigin argument.
import { createBridgeTelemetryEventSink } from '../../bridge/bridge-telemetry-event-sink.js';
import type { BridgeTelemetryBootstrapConfig } from '../../foundation/telemetry/bridge-telemetry-bootstrap-config.js';
import { buildBridgeWorkerReadyHealthEvent } from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type RegisterBridgeCommWorkerRuntimePortProtocolProps,
} from './bridge-comm-worker-runtime-protocol.js';
import { createBridgeCommWorkerTelemetryClient } from './bridge-comm-worker-telemetry.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeCommWorkerBootstrapRequestSchema,
	bridgeWorkerMainToServerMessageSchema,
	type BridgeCommWorkerBootstrapRequest,
	type BridgeCommWorkerTelemetryBootstrapConfig,
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
	readonly dispatchEvent?: (event: Event) => boolean;
	readonly start?: () => void;
}

export interface BridgeCommWorkerGlobalScope {
	postMessage(message: BridgeWorkerServerToMainMessage): void;
	postMessage(message: BridgeWorkerServerToMainMessage, transferList: Transferable[]): void;
	readonly addEventListener: (
		type: 'message',
		listener: (event: MessageEvent<unknown>) => void,
	) => void;
	readonly dispatchEvent?: (event: Event) => boolean;
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
		...(scope.dispatchEvent === undefined
			? {}
			: {
					dispatchEvent: (event: Event): boolean => scope.dispatchEvent?.(event) ?? false,
				}),
	};
}

export function bootstrapInertBridgeCommWorkerEntry(scope: BridgeCommWorkerGlobalScope): void {
	registerInertBridgeCommWorkerPortProtocol(createBridgeCommWorkerScopePortAdapter(scope));
}

export function bootstrapBridgeCommWorkerEntry(port: BridgeCommWorkerPort): void {
	let didBootstrapRuntime = false;
	const pendingMessagesBeforeBootstrap: unknown[] = [];

	port.addEventListener('message', (event: MessageEvent<unknown>): void => {
		const parsedBootstrap = bridgeCommWorkerBootstrapRequestSchema.safeParse(event.data);
		if (parsedBootstrap.success) {
			event.stopImmediatePropagation();
			if (didBootstrapRuntime) {
				port.postMessage(
					buildBridgeWorkerEntryDegradedHealthEvent({
						requestId: parsedBootstrap.data.requestId,
						message: 'Bridge comm worker runtime was already bootstrapped.',
					}),
				);
				return;
			}
			didBootstrapRuntime = true;
			registerBridgeCommWorkerRuntimePortProtocol(
				port,
				runtimePropsFromBootstrapRequest(parsedBootstrap.data),
			);
			port.postMessage(buildBridgeWorkerReadyHealthEvent(parsedBootstrap.data.requestId));
			for (const pendingMessage of pendingMessagesBeforeBootstrap.splice(
				0,
				pendingMessagesBeforeBootstrap.length,
			)) {
				dispatchPendingMessageToRuntime(port, pendingMessage);
			}
			return;
		}

		if (didBootstrapRuntime) {
			return;
		}

		const parsedCommand = bridgeWorkerMainToServerMessageSchema.safeParse(event.data);
		if (parsedCommand.success) {
			pendingMessagesBeforeBootstrap.push(parsedCommand.data);
			port.postMessage(
				buildBridgeWorkerEntryDegradedHealthEvent({
					requestId: parsedCommand.data.requestId,
					message: 'Bridge comm worker command received before bootstrap.',
				}),
			);
			return;
		}

		port.postMessage(
			buildBridgeWorkerEntryDegradedHealthEvent({
				message: 'Bridge comm worker received invalid bootstrap message.',
			}),
		);
	});
	port.start?.();
}

function runtimePropsFromBootstrapRequest(
	request: BridgeCommWorkerBootstrapRequest,
): RegisterBridgeCommWorkerRuntimePortProtocolProps {
	const telemetryClient =
		request.runtime.telemetryConfig === undefined
			? null
			: createBridgeCommWorkerTelemetryClient({
					config: bridgeTelemetryBootstrapConfigFromWorkerConfig(request.runtime.telemetryConfig),
					sink: createBridgeTelemetryEventSink({
						endpointUrl: request.runtime.telemetryConfig.endpointUrl,
					}),
				});
	return {
		bridgeDemandRank: request.runtime.bridgeDemandRank,
		budget: request.runtime.budget,
		contentItems: request.runtime.contentItems,
		contentRequestDescriptors: request.runtime.contentRequestDescriptors,
		...(request.runtime.maxPreparationSliceMs === undefined
			? {}
			: { maxPreparationSliceMs: request.runtime.maxPreparationSliceMs }),
		renderSemantics: request.runtime.renderSemantics,
		rows: request.runtime.rows,
		...(telemetryClient === null ? {} : { telemetryClient }),
	};
}

function bridgeTelemetryBootstrapConfigFromWorkerConfig(
	config: BridgeCommWorkerTelemetryBootstrapConfig,
): BridgeTelemetryBootstrapConfig {
	return {
		enabledScopes: new Set(config.enabledScopes),
		endpointUrl: config.endpointUrl,
		maxEncodedBatchBytes: config.maxEncodedBatchBytes,
		maxSamplesPerBatch: config.maxSamplesPerBatch,
		minimumFlushIntervalMilliseconds: config.minimumFlushIntervalMilliseconds,
		scenario: config.scenario,
	};
}

function dispatchPendingMessageToRuntime(port: BridgeCommWorkerPort, data: unknown): void {
	if (port.dispatchEvent === undefined) {
		return;
	}
	port.dispatchEvent(new MessageEvent('message', { data }));
}

function buildBridgeWorkerEntryDegradedHealthEvent(props: {
	readonly requestId?: string;
	readonly message: string;
}): BridgeWorkerServerToMainMessage {
	return {
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'serverWorkerToMain',
		transferDescriptors: [],
		kind: 'health',
		...(props.requestId === undefined ? {} : { requestId: props.requestId }),
		status: 'degraded',
		message: props.message,
	};
}

declare const self: BridgeCommWorkerGlobalScope | undefined;

if (typeof self !== 'undefined' && typeof self.addEventListener === 'function') {
	bootstrapBridgeCommWorkerEntry(createBridgeCommWorkerScopePortAdapter(self));
}
