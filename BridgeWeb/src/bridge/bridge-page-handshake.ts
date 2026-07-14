import { z } from 'zod';

import { BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH } from '../core/comm-worker/bridge-product-contract-primitives.js';
import {
	bridgeProductSessionBootstrapSchema,
	type BridgeProductSessionBootstrap,
} from '../core/comm-worker/bridge-product-session-contracts.js';
import {
	bridgeTelemetryWorkerBootstrapSchema,
	type BridgeTelemetryWorkerBootstrap,
} from '../core/telemetry-worker/bridge-telemetry-worker-contracts.js';
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
	readonly requestProductSessionReplacement: () => void;
	readonly requestTelemetrySessionReplacement: () => void;
	readonly uninstall: () => void;
}

export interface BridgePageReadyError {
	readonly kind: 'ack_error' | 'ack_timeout';
	readonly message: string;
	readonly requestId: string;
}

export interface InstallBridgePageHandshakeSessionProps {
	readonly onProductSessionBootstrap?: (bootstrap: {
		readonly bootstrap: BridgeProductSessionBootstrap;
		readonly productCapability: ArrayBuffer;
	}) => void;
	readonly onReadyError?: (error: BridgePageReadyError) => void;
	readonly onTelemetrySessionBootstrap?: (
		result:
			| { readonly kind: 'available'; readonly workerBootstrap: BridgeTelemetryWorkerBootstrap }
			| { readonly kind: 'unavailable'; readonly reason: 'disabled' | 'failed' },
	) => void;
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

const bridgeTelemetrySessionBootstrapResultSchema = z.discriminatedUnion('kind', [
	z
		.object({
			kind: z.literal('available'),
			workerBootstrap: bridgeTelemetryWorkerBootstrapSchema,
		})
		.strict(),
	z
		.object({
			kind: z.literal('unavailable'),
			reason: z.enum(['disabled', 'failed']),
		})
		.strict(),
]);

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
	const deliveredProductWorkerInstanceIds = new Set<string>();
	const pendingProductBootstrapRequestIds = new Set<string>();
	const pendingTelemetryBootstrapRequestIds = new Set<string>();
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
	const handleProductSessionBootstrap = (event: Event): void => {
		if (!('detail' in event)) {
			return;
		}
		const detail = event.detail;
		if (
			typeof detail !== 'object' ||
			detail === null ||
			!('requestId' in detail) ||
			!('bootstrap' in detail) ||
			!('productCapability' in detail)
		) {
			return;
		}
		const parsedBootstrap = bridgeProductSessionBootstrapSchema.safeParse(detail.bootstrap);
		const productCapability = copyProductCapabilityIntoCurrentRealm(detail.productCapability);
		if (
			typeof detail.requestId !== 'string' ||
			!pendingProductBootstrapRequestIds.delete(detail.requestId) ||
			!parsedBootstrap.success ||
			productCapability === null
		) {
			return;
		}
		if (deliveredProductWorkerInstanceIds.has(parsedBootstrap.data.workerInstanceId)) {
			return;
		}
		deliveredProductWorkerInstanceIds.add(parsedBootstrap.data.workerInstanceId);
		props.onProductSessionBootstrap?.({
			bootstrap: parsedBootstrap.data,
			productCapability,
		});
	};
	const requestProductSessionBootstrap = (reason: 'initial' | 'workerReplacement'): void => {
		if (!isInstalled) {
			return;
		}
		const requestId = createProductSessionBootstrapRequestId();
		pendingProductBootstrapRequestIds.add(requestId);
		target.dispatchEvent(
			new CustomEvent('__bridge_product_session_bootstrap_request', {
				detail: { reason, requestId },
			}),
		);
	};
	const handleTelemetrySessionBootstrap = (event: Event): void => {
		if (!('detail' in event) || typeof event.detail !== 'object' || event.detail === null) {
			return;
		}
		const detail = event.detail;
		if (
			!('requestId' in detail) ||
			typeof detail.requestId !== 'string' ||
			!pendingTelemetryBootstrapRequestIds.delete(detail.requestId) ||
			!('result' in detail)
		) {
			return;
		}
		const decodedResult = bridgeTelemetrySessionBootstrapResultSchema.safeParse(detail.result);
		if (decodedResult.success) {
			props.onTelemetrySessionBootstrap?.(decodedResult.data);
		}
	};
	const requestTelemetrySessionBootstrap = (reason: 'initial' | 'sidecarReplacement'): void => {
		if (!isInstalled) {
			return;
		}
		const requestId = createTelemetrySessionBootstrapRequestId();
		pendingTelemetryBootstrapRequestIds.add(requestId);
		target.dispatchEvent(
			new CustomEvent('__bridge_telemetry_session_bootstrap_request', {
				detail: { reason, requestId },
			}),
		);
	};

	target.addEventListener('__bridge_ready_ack', handleReadyAcknowledgement);
	target.addEventListener('__bridge_handshake', handleHandshake);
	target.addEventListener('__bridge_product_session_bootstrap', handleProductSessionBootstrap);
	target.addEventListener('__bridge_telemetry_session_bootstrap', handleTelemetrySessionBootstrap);
	requestProductSessionBootstrap('initial');
	requestTelemetrySessionBootstrap('initial');
	target.dispatchEvent(new CustomEvent('__bridge_handshake_request'));

	return {
		getPushNonce: (): string | null => pushNonce,
		getTelemetryConfig: (): BridgeTelemetryBootstrapConfig | null => telemetryConfig,
		requestProductSessionReplacement: (): void => {
			requestProductSessionBootstrap('workerReplacement');
		},
		requestTelemetrySessionReplacement: (): void => {
			requestTelemetrySessionBootstrap('sidecarReplacement');
		},
		uninstall: (): void => {
			isInstalled = false;
			pendingProductBootstrapRequestIds.clear();
			pendingTelemetryBootstrapRequestIds.clear();
			clearReadyAcknowledgementTimeout();
			target.removeEventListener('__bridge_ready_ack', handleReadyAcknowledgement);
			target.removeEventListener('__bridge_handshake', handleHandshake);
			target.removeEventListener(
				'__bridge_product_session_bootstrap',
				handleProductSessionBootstrap,
			);
			target.removeEventListener(
				'__bridge_telemetry_session_bootstrap',
				handleTelemetrySessionBootstrap,
			);
		},
	};
}

function copyProductCapabilityIntoCurrentRealm(value: unknown): ArrayBuffer | null {
	try {
		if (Object.prototype.toString.call(value) !== '[object ArrayBuffer]') {
			return null;
		}
		const isolatedWorldBytes = new Uint8Array(value as ArrayBuffer);
		if (isolatedWorldBytes.byteLength !== BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH) {
			return null;
		}
		const currentRealmCapability = Uint8Array.from(isolatedWorldBytes).buffer;
		isolatedWorldBytes.fill(0);
		return currentRealmCapability;
	} catch {
		return null;
	}
}

let bridgeReadyRequestSequence = 0;
let productSessionBootstrapRequestSequence = 0;
let telemetrySessionBootstrapRequestSequence = 0;

function createBridgeReadyRequestId(): string {
	bridgeReadyRequestSequence = (bridgeReadyRequestSequence + 1) % Number.MAX_SAFE_INTEGER;
	return `bridge-ready-${Date.now().toString(36)}-${bridgeReadyRequestSequence.toString(36)}`;
}

function createProductSessionBootstrapRequestId(): string {
	productSessionBootstrapRequestSequence =
		(productSessionBootstrapRequestSequence + 1) % Number.MAX_SAFE_INTEGER;
	return `bridge-product-bootstrap-${Date.now().toString(36)}-${productSessionBootstrapRequestSequence.toString(36)}`;
}

function createTelemetrySessionBootstrapRequestId(): string {
	telemetrySessionBootstrapRequestSequence =
		(telemetrySessionBootstrapRequestSequence + 1) % Number.MAX_SAFE_INTEGER;
	return `bridge-telemetry-bootstrap-${Date.now().toString(36)}-${telemetrySessionBootstrapRequestSequence.toString(36)}`;
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
