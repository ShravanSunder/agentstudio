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
	readonly uninstall: () => void;
}

export interface InstallBridgePageHandshakeSessionProps {
	readonly onTelemetryConfig?: (telemetryConfig: BridgeTelemetryBootstrapConfig) => void;
}

export function installBridgePageHandshake(target: BridgeHandshakeTarget = document): () => void {
	return installBridgePageHandshakeSession(target).uninstall;
}

export function installBridgePageHandshakeSession(
	target: BridgeHandshakeTarget = document,
	props: InstallBridgePageHandshakeSessionProps = {},
): BridgePageHandshakeSession {
	let didSendReady = false;
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
		target.dispatchEvent(new CustomEvent('__bridge_ready'));
	};

	target.addEventListener('__bridge_handshake', handleHandshake);
	target.dispatchEvent(new CustomEvent('__bridge_handshake_request'));

	return {
		getPushNonce: (): string | null => pushNonce,
		getTelemetryConfig: (): BridgeTelemetryBootstrapConfig | null => telemetryConfig,
		uninstall: (): void => {
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
