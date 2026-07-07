import type { BridgeTelemetryBootstrapHandshakeConfig } from '../foundation/telemetry/bridge-telemetry-bootstrap-config.js';

export type BridgeAppDevTelemetryBootstrapConfig = BridgeTelemetryBootstrapHandshakeConfig;

export interface BridgeAppDevTelemetryHost {
	readonly dispose: () => void;
}

export interface InstallBridgeAppDevTelemetryHostProps {
	readonly respondToHandshakeRequests?: boolean;
	readonly scenario: string;
	readonly target?: EventTarget;
}

const devTelemetryEndpoint = '/__bridge-dev-telemetry/batch';

export function createBridgeAppDevTelemetryBootstrapConfig(
	scenario: string,
): BridgeAppDevTelemetryBootstrapConfig {
	return {
		enabledScopes: ['web'],
		endpointUrl: devTelemetryEndpoint,
		maxEncodedBatchBytes: 64 * 1024,
		maxSamplesPerBatch: 128,
		minimumFlushIntervalMilliseconds: 250,
		scenario,
	};
}

export function installBridgeAppDevTelemetryHost(
	props: InstallBridgeAppDevTelemetryHostProps,
): BridgeAppDevTelemetryHost {
	const target = props.target ?? document;
	const telemetryConfig = createBridgeAppDevTelemetryBootstrapConfig(props.scenario);
	const handleHandshakeRequest = (): void => {
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', {
				detail: { telemetryConfig },
			}),
		);
	};
	if (props.respondToHandshakeRequests ?? true) {
		target.addEventListener('__bridge_handshake_request', handleHandshakeRequest);
	}
	return {
		dispose: (): void => {
			if (props.respondToHandshakeRequests ?? true) {
				target.removeEventListener('__bridge_handshake_request', handleHandshakeRequest);
			}
		},
	};
}
