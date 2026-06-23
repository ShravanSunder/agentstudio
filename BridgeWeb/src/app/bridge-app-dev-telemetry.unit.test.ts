import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	createBridgeAppDevTelemetryBootstrapConfig,
	installBridgeAppDevTelemetryHost,
} from './bridge-app-dev-telemetry.js';

describe('Bridge app dev telemetry host', () => {
	afterEach(() => {
		vi.restoreAllMocks();
	});

	test('responds to the Bridge handshake with web telemetry config', () => {
		const target = new EventTarget();
		const handshakeDetails: unknown[] = [];
		target.addEventListener('__bridge_handshake', (event: Event): void => {
			handshakeDetails.push('detail' in event ? event.detail : null);
		});
		const host = installBridgeAppDevTelemetryHost({
			scenario: 'vite-dev-current-worktree',
			target,
		});

		target.dispatchEvent(new CustomEvent('__bridge_handshake_request'));

		expect(handshakeDetails).toEqual([
			{
				telemetryConfig: {
					enabledScopes: ['web'],
					maxEncodedBatchBytes: 64 * 1024,
					maxSamplesPerBatch: 128,
					minimumFlushIntervalMilliseconds: 250,
					rpcMethodName: 'system.bridgeTelemetry',
					scenario: 'vite-dev-current-worktree',
				},
			},
		]);

		host.dispose();
	});

	test('forwards system.bridgeTelemetry batches to the Vite telemetry endpoint', () => {
		const target = new EventTarget();
		const fetchTelemetryBatch = vi.fn((): boolean => true);
		const host = installBridgeAppDevTelemetryHost({
			fetchTelemetryBatch,
			scenario: 'vite-dev-current-worktree',
			target,
		});
		const telemetryBatch = {
			schemaVersion: 1,
			scenario: 'vite-dev-current-worktree',
			samples: [
				{
					scope: 'web',
					name: 'performance.bridge.web.first_render',
					durationMilliseconds: 12,
					traceContext: null,
					stringAttributes: {
						'agentstudio.bridge.phase': 'render',
						'agentstudio.bridge.plane': 'data',
						'agentstudio.bridge.priority': 'hot',
						'agentstudio.bridge.slice': 'diff_package_metadata',
						'agentstudio.bridge.transport': 'push',
					},
					numericAttributes: {},
					booleanAttributes: {},
				},
			],
		};

		target.dispatchEvent(
			new CustomEvent('__bridge_command', {
				detail: {
					jsonrpc: '2.0',
					method: 'system.bridgeTelemetry',
					params: telemetryBatch,
				},
			}),
		);

		expect(fetchTelemetryBatch).toHaveBeenCalledWith(telemetryBatch);

		host.dispose();
	});

	test('can leave handshake responses to the selected dev backend', () => {
		const target = new EventTarget();
		const handshakeDetails: unknown[] = [];
		target.addEventListener('__bridge_handshake', (event: Event): void => {
			handshakeDetails.push('detail' in event ? event.detail : null);
		});
		const host = installBridgeAppDevTelemetryHost({
			respondToHandshakeRequests: false,
			scenario: 'vite-dev-current-worktree',
			target,
		});

		target.dispatchEvent(new CustomEvent('__bridge_handshake_request'));

		expect(handshakeDetails).toEqual([]);

		host.dispose();
	});

	test('builds the expected default telemetry config', () => {
		expect(createBridgeAppDevTelemetryBootstrapConfig('vite-dev-large-diffshub')).toEqual({
			enabledScopes: ['web'],
			maxEncodedBatchBytes: 64 * 1024,
			maxSamplesPerBatch: 128,
			minimumFlushIntervalMilliseconds: 250,
			rpcMethodName: 'system.bridgeTelemetry',
			scenario: 'vite-dev-large-diffshub',
		});
	});
});
