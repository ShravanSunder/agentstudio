import type { BridgeTelemetryBootstrapHandshakeConfig } from '../foundation/telemetry/bridge-telemetry-bootstrap-config.js';
import { bridgeTelemetryBatchSchema } from '../foundation/telemetry/bridge-telemetry-event.js';
import type { BridgeTelemetryBatch } from '../foundation/telemetry/bridge-telemetry-event.js';

export type BridgeAppDevTelemetryBootstrapConfig = BridgeTelemetryBootstrapHandshakeConfig;

export interface BridgeAppDevTelemetryHost {
	readonly dispose: () => void;
}

export interface InstallBridgeAppDevTelemetryHostProps {
	readonly fetchTelemetryBatch?: (batch: BridgeTelemetryBatch) => boolean;
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
		maxEncodedBatchBytes: 64 * 1024,
		maxSamplesPerBatch: 128,
		minimumFlushIntervalMilliseconds: 250,
		rpcMethodName: 'system.bridgeTelemetry',
		scenario,
	};
}

export function installBridgeAppDevTelemetryHost(
	props: InstallBridgeAppDevTelemetryHostProps,
): BridgeAppDevTelemetryHost {
	const target = props.target ?? document;
	const fetchTelemetryBatch = props.fetchTelemetryBatch ?? postBridgeAppDevTelemetryBatch;
	const telemetryConfig = createBridgeAppDevTelemetryBootstrapConfig(props.scenario);
	const handleHandshakeRequest = (): void => {
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', {
				detail: { telemetryConfig },
			}),
		);
	};
	const handleBridgeCommand = (event: Event): void => {
		const detail = 'detail' in event ? event.detail : null;
		const batch = extractBridgeTelemetryBatch(detail);
		if (batch !== null) {
			fetchTelemetryBatch(batch);
		}
	};
	if (props.respondToHandshakeRequests ?? true) {
		target.addEventListener('__bridge_handshake_request', handleHandshakeRequest);
	}
	target.addEventListener('__bridge_command', handleBridgeCommand);
	return {
		dispose: (): void => {
			if (props.respondToHandshakeRequests ?? true) {
				target.removeEventListener('__bridge_handshake_request', handleHandshakeRequest);
			}
			target.removeEventListener('__bridge_command', handleBridgeCommand);
		},
	};
}

function extractBridgeTelemetryBatch(detail: unknown): BridgeTelemetryBatch | null {
	if (!isRecord(detail) || detail['method'] !== 'system.bridgeTelemetry') {
		return null;
	}
	const parsedBatch = bridgeTelemetryBatchSchema.safeParse(detail['params']);
	return parsedBatch.success ? parsedBatch.data : null;
}

function postBridgeAppDevTelemetryBatch(batch: BridgeTelemetryBatch): boolean {
	void fetch(devTelemetryEndpoint, {
		body: JSON.stringify(batch),
		headers: { 'content-type': 'application/json' },
		method: 'POST',
	});
	return true;
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null;
}
