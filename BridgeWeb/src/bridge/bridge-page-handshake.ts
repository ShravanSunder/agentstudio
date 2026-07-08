import { z } from 'zod';

import {
	decodeBridgeTelemetryBootstrapConfig,
	type BridgeTelemetryBootstrapConfig,
} from '../foundation/telemetry/bridge-telemetry-bootstrap-config.js';
import { bridgeRPCErrorPayloadSchema, bridgeRPCIdSchema } from './bridge-rpc-client.js';

type BridgeHandshakeTarget = Pick<
	EventTarget,
	'addEventListener' | 'dispatchEvent' | 'removeEventListener'
>;

export interface BridgePageHandshakeSession {
	readonly getPushNonce: () => string | null;
	readonly getTelemetryConfig: () => BridgeTelemetryBootstrapConfig | null;
	readonly uninstall: () => void;
}

export interface BridgePageReadyError {
	readonly kind: 'ack_error' | 'ack_timeout';
	readonly message: string;
	readonly requestId: string;
}

export interface InstallBridgePageHandshakeSessionProps {
	readonly onReadyError?: (error: BridgePageReadyError) => void;
	readonly onTelemetryConfig?: (telemetryConfig: BridgeTelemetryBootstrapConfig) => void;
	readonly onReady?: () => void;
	readonly readyAcknowledgementTimeoutMilliseconds?: number;
}

const bridgeReadyAcknowledgementSchema = z
	.union([
		z
			.object({
				jsonrpc: z.literal('2.0'),
				id: bridgeRPCIdSchema,
				result: z.unknown(),
			})
			.strict(),
		z
			.object({
				jsonrpc: z.literal('2.0'),
				id: bridgeRPCIdSchema,
				error: bridgeRPCErrorPayloadSchema,
			})
			.strict(),
	])
	.readonly();

export function installBridgePageHandshake(target: BridgeHandshakeTarget = document): () => void {
	return installBridgePageHandshakeSession(target).uninstall;
}

export function installBridgePageHandshakeSession(
	target: BridgeHandshakeTarget = document,
	props: InstallBridgePageHandshakeSessionProps = {},
): BridgePageHandshakeSession {
	let didSendReady = false;
	let isInstalled = true;
	let pushNonce: string | null = null;
	let telemetryConfig: BridgeTelemetryBootstrapConfig | null = null;
	let readyRequestId: string | null = null;
	let didResolveReadyRequest = false;
	let readyAcknowledgementTimeout: ReturnType<typeof globalThis.setTimeout> | null = null;
	const readyAcknowledgementTimeoutMilliseconds =
		props.readyAcknowledgementTimeoutMilliseconds ?? 5000;

	const clearReadyAcknowledgementTimeout = (): void => {
		if (readyAcknowledgementTimeout === null) {
			return;
		}
		globalThis.clearTimeout(readyAcknowledgementTimeout);
		readyAcknowledgementTimeout = null;
	};

	const failReadyRequest = (error: BridgePageReadyError): void => {
		if (didResolveReadyRequest) {
			return;
		}
		didResolveReadyRequest = true;
		clearReadyAcknowledgementTimeout();
		props.onReadyError?.(error);
	};

	const handleReadyAcknowledgement = (event: Event): void => {
		if (readyRequestId === null || didResolveReadyRequest || !('detail' in event)) {
			return;
		}
		const parsedAcknowledgement = bridgeReadyAcknowledgementSchema.safeParse(event.detail);
		if (!parsedAcknowledgement.success) {
			return;
		}
		const acknowledgement = parsedAcknowledgement.data;
		if (String(acknowledgement.id) !== readyRequestId || 'error' in acknowledgement) {
			if (String(acknowledgement.id) === readyRequestId && 'error' in acknowledgement) {
				failReadyRequest({
					kind: 'ack_error',
					message: acknowledgement.error.message,
					requestId: readyRequestId,
				});
			}
			return;
		}
		didResolveReadyRequest = true;
		clearReadyAcknowledgementTimeout();
		props.onReady?.();
	};

	const handleHandshake = (event: Event): void => {
		if (pushNonce === null) {
			pushNonce = extractPushNonce(event);
		}
		if (telemetryConfig === null) {
			const nextTelemetryConfig = extractTelemetryConfig(event);
			if (nextTelemetryConfig !== null) {
				telemetryConfig = nextTelemetryConfig;
				props.onTelemetryConfig?.(nextTelemetryConfig);
			}
		}
		if (didSendReady || pushNonce === null) {
			return;
		}

		didSendReady = true;
		readyRequestId = createBridgeReadyRequestId();
		queueMicrotask((): void => {
			if (!isInstalled || readyRequestId === null) {
				return;
			}
			const requestId = readyRequestId;
			readyAcknowledgementTimeout = globalThis.setTimeout((): void => {
				failReadyRequest({
					kind: 'ack_timeout',
					message: 'Bridge ready acknowledgement timed out',
					requestId,
				});
			}, readyAcknowledgementTimeoutMilliseconds);
			target.dispatchEvent(
				new CustomEvent('__bridge_ready', {
					detail: { requestId },
				}),
			);
		});
	};

	target.addEventListener('__bridge_ready_ack', handleReadyAcknowledgement);
	target.addEventListener('__bridge_handshake', handleHandshake);
	target.dispatchEvent(new CustomEvent('__bridge_handshake_request'));

	return {
		getPushNonce: (): string | null => pushNonce,
		getTelemetryConfig: (): BridgeTelemetryBootstrapConfig | null => telemetryConfig,
		uninstall: (): void => {
			isInstalled = false;
			clearReadyAcknowledgementTimeout();
			target.removeEventListener('__bridge_ready_ack', handleReadyAcknowledgement);
			target.removeEventListener('__bridge_handshake', handleHandshake);
		},
	};
}

let bridgeReadyRequestSequence = 0;

function createBridgeReadyRequestId(): string {
	bridgeReadyRequestSequence = (bridgeReadyRequestSequence + 1) % Number.MAX_SAFE_INTEGER;
	return `bridge-ready-${Date.now().toString(36)}-${bridgeReadyRequestSequence.toString(36)}`;
}

function extractPushNonce(event: Event): string | null {
	if (!('detail' in event)) {
		return null;
	}
	const detail = event.detail;
	if (typeof detail !== 'object' || detail === null || !('pushNonce' in detail)) {
		return null;
	}
	const pushNonce = detail.pushNonce;
	return typeof pushNonce === 'string' && pushNonce.length > 0 ? pushNonce : null;
}

function extractTelemetryConfig(event: Event): BridgeTelemetryBootstrapConfig | null {
	if (!('detail' in event)) {
		return null;
	}
	const detail = event.detail;
	if (typeof detail !== 'object' || detail === null || !('telemetryConfig' in detail)) {
		return null;
	}
	return decodeBridgeTelemetryBootstrapConfig(detail.telemetryConfig);
}
