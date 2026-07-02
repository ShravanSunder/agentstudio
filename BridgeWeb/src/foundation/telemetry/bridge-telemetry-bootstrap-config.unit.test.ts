import { describe, expect, test } from 'vitest';

import { decodeBridgeTelemetryBootstrapConfig } from './bridge-telemetry-bootstrap-config.js';

describe('bridge telemetry bootstrap config', () => {
	test('decodes enabled scope config from the Swift handshake', () => {
		const config = decodeBridgeTelemetryBootstrapConfig({
			enabledScopes: ['web', 'webkit'],
			maxSamplesPerBatch: 64,
			maxEncodedBatchBytes: 16_384,
			minimumFlushIntervalMilliseconds: 250,
			rpcMethodName: 'system.bridgeTelemetry',
			scenario: 'bridge-runtime',
		});

		expect(config?.enabledScopes.has('web')).toBe(true);
		expect(config?.rpcMethodName).toBe('system.bridgeTelemetry');
	});

	test('decodes the native viewer-open anchor for time-to-first-interaction', () => {
		const config = decodeBridgeTelemetryBootstrapConfig({
			enabledScopes: ['web'],
			maxSamplesPerBatch: 64,
			maxEncodedBatchBytes: 16_384,
			minimumFlushIntervalMilliseconds: 250,
			rpcMethodName: 'system.bridgeTelemetry',
			scenario: 'bridge-runtime',
			viewerOpenEpochUnixMillis: 1_750_000_000_000,
			viewerOpenTraceparent: '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01',
		});

		expect(config?.viewerOpenEpochUnixMillis).toBe(1_750_000_000_000);
		expect(config?.viewerOpenTraceparent).toBe(
			'00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01',
		);
	});

	test('rejects absent or empty config as disabled telemetry', () => {
		expect(decodeBridgeTelemetryBootstrapConfig(null)).toBeNull();
		expect(
			decodeBridgeTelemetryBootstrapConfig({
				enabledScopes: [],
				maxSamplesPerBatch: 64,
				maxEncodedBatchBytes: 16_384,
				minimumFlushIntervalMilliseconds: 250,
				rpcMethodName: 'system.bridgeTelemetry',
				scenario: 'bridge-runtime',
			}),
		).toBeNull();
	});
});
