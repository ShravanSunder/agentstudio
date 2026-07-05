import { z } from 'zod';

import {
	decodeBridgeTelemetryBootstrapConfig,
	type BridgeTelemetryBootstrapConfig,
} from '../foundation/telemetry/bridge-telemetry-bootstrap-config.js';

type BridgeHandshakeTarget = Pick<
	EventTarget,
	'addEventListener' | 'dispatchEvent' | 'removeEventListener'
>;

export interface BridgePageHandshakeSession {
	readonly getPushNonce: () => string | null;
	readonly getTelemetryConfig: () => BridgeTelemetryBootstrapConfig | null;
	readonly markIntakeReady: (props: BridgeIntakeReadyProps) => boolean;
	readonly uninstall: () => void;
}

export interface InstallBridgePageHandshakeSessionProps {
	readonly getBridgeCommandNonce?: () => string | null;
	readonly onTelemetryConfig?: (telemetryConfig: BridgeTelemetryBootstrapConfig) => void;
	readonly onReady?: () => void;
	readonly onReadyError?: (error: Error) => void;
	readonly readyResponseTimeoutMilliseconds?: number;
}

export interface BridgeIntakeReadyProps {
	readonly protocolId: string;
	readonly reason?: string | null;
	readonly streamId?: string | null;
}

const bridgeReadyRPCErrorSchema = z
	.object({
		code: z.number().int(),
		message: z.string().min(1),
	})
	.strict();
const bridgeReadyRPCResponseSchema = z
	.object({
		jsonrpc: z.literal('2.0').optional(),
		id: z.union([z.string(), z.number()]),
		result: z.unknown().optional(),
		error: bridgeReadyRPCErrorSchema.optional(),
	})
	.passthrough();
const defaultReadyResponseTimeoutMilliseconds = 10_000;

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
	let disposeBridgeReadyResponseListener: (() => void) | null = null;

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
		queueMicrotask((): void => {
			if (isInstalled) {
				target.dispatchEvent(new CustomEvent('__bridge_ready'));
				const bridgeNonce = (props.getBridgeCommandNonce ?? readBridgeCommandNonce)();
				if (bridgeNonce === null) {
					props.onReady?.();
					return;
				}
				const requestId = createBridgeReadyRequestId();
				const timeoutId = setTimeout((): void => {
					disposeBridgeReadyResponseListener?.();
					disposeBridgeReadyResponseListener = null;
					if (isInstalled) {
						props.onReadyError?.(new Error('Bridge ready command timed out'));
					}
				}, props.readyResponseTimeoutMilliseconds ?? defaultReadyResponseTimeoutMilliseconds);
				const handleBridgeReadyResponse = (responseEvent: Event): void => {
					const detail = 'detail' in responseEvent ? responseEvent.detail : null;
					const parsedResponse = bridgeReadyRPCResponseSchema.safeParse(detail);
					if (!parsedResponse.success || String(parsedResponse.data.id) !== requestId) {
						return;
					}
					disposeBridgeReadyResponseListener?.();
					disposeBridgeReadyResponseListener = null;
					clearTimeout(timeoutId);
					if (parsedResponse.data.error !== undefined) {
						if (isInstalled) {
							props.onReadyError?.(
								new Error(`Bridge ready command failed: ${parsedResponse.data.error.message}`),
							);
						}
						return;
					}
					if (isInstalled) {
						props.onReady?.();
					}
				};
				target.addEventListener('__bridge_response', handleBridgeReadyResponse);
				disposeBridgeReadyResponseListener = (): void => {
					clearTimeout(timeoutId);
					target.removeEventListener('__bridge_response', handleBridgeReadyResponse);
				};
				target.dispatchEvent(
					new CustomEvent('__bridge_command', {
						detail: {
							__nonce: bridgeNonce,
							__commandId: requestId,
							jsonrpc: '2.0',
							id: requestId,
							method: 'bridge.ready',
							params: {},
						},
					}),
				);
			}
		});
	};

	target.addEventListener('__bridge_handshake', handleHandshake);
	target.dispatchEvent(new CustomEvent('__bridge_handshake_request'));

	return {
		getPushNonce: (): string | null => pushNonce,
		getTelemetryConfig: (): BridgeTelemetryBootstrapConfig | null => telemetryConfig,
		markIntakeReady: (intakeReadyProps: BridgeIntakeReadyProps): boolean => {
			if (pushNonce === null) {
				return false;
			}
			const bridgeNonce = (props.getBridgeCommandNonce ?? readBridgeCommandNonce)();
			if (bridgeNonce === null) {
				return false;
			}
			target.dispatchEvent(
				new CustomEvent('__bridge_command', {
					detail: {
						__nonce: bridgeNonce,
						jsonrpc: '2.0',
						method: 'bridge.intakeReady',
						params: {
							protocolId: intakeReadyProps.protocolId,
							reason: intakeReadyProps.reason ?? null,
							streamId: intakeReadyProps.streamId ?? null,
						},
					},
				}),
			);
			return true;
		},
		uninstall: (): void => {
			isInstalled = false;
			disposeBridgeReadyResponseListener?.();
			disposeBridgeReadyResponseListener = null;
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

function readBridgeCommandNonce(): string | null {
	return typeof document === 'undefined'
		? null
		: document.documentElement.getAttribute('data-bridge-nonce');
}
