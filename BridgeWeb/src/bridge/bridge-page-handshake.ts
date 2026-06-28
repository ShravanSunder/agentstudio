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
}

export interface BridgeIntakeReadyProps {
	readonly protocolId: string;
	readonly streamId?: string | null;
}

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
				props.onReady?.();
				target.dispatchEvent(new CustomEvent('__bridge_ready'));
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
							streamId: intakeReadyProps.streamId ?? null,
						},
					},
				}),
			);
			return true;
		},
		uninstall: (): void => {
			isInstalled = false;
			target.removeEventListener('__bridge_handshake', handleHandshake);
		},
	};
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
