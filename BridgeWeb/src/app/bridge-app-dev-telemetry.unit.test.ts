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
			createTelemetrySessionId: (): string => 'dev-telemetry-test-session',
			scenario: 'vite-dev-current-worktree',
			target,
		});

		target.dispatchEvent(new CustomEvent('__bridge_handshake_request'));

		expect(handshakeDetails).toMatchObject([
			{
				telemetryConfig: {
					enabledScopes: ['web'],
					scenario: 'vite-dev-current-worktree',
					workerBootstrap: {
						endpointUrl: '/__bridge-dev-telemetry/batch',
						telemetrySessionId: 'dev-telemetry-test-session',
						telemetryCapability: 'dev-telemetry-capability-0123456789abcdef',
						policy: {
							initialSampleCredits: 128,
							batchMaxBytes: 64 * 1024,
							batchMaxSamples: 128,
							minimumFlushIntervalMilliseconds: 250,
						},
					},
				},
			},
		]);

		host.dispose();
	});

	test('does not forward script-message telemetry batches after fetch cutover', () => {
		const target = new EventTarget();
		const fetchTelemetryBatch = vi.spyOn(globalThis, 'fetch');
		const host = installBridgeAppDevTelemetryHost({
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
						'agentstudio.bridge.slice': 'review_metadata',
						'agentstudio.bridge.transport': 'intake',
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

		expect(fetchTelemetryBatch).not.toHaveBeenCalled();

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
		expect(
			createBridgeAppDevTelemetryBootstrapConfig(
				'vite-dev-large-diffshub',
				(): string => 'dev-telemetry-test-session',
			),
		).toMatchObject({
			enabledScopes: ['web'],
			scenario: 'vite-dev-large-diffshub',
			workerBootstrap: {
				endpointUrl: '/__bridge-dev-telemetry/batch',
				telemetrySessionId: 'dev-telemetry-test-session',
				policy: {
					initialControlCredits: 4,
					outboxMaxCount: 4,
				},
			},
		});
	});

	test('creates a distinct telemetry session for each dev config creation', () => {
		const createTelemetrySessionId = vi
			.fn<() => string>()
			.mockReturnValueOnce('dev-telemetry-reload-1')
			.mockReturnValueOnce('dev-telemetry-reload-2');

		const firstConfig = createBridgeAppDevTelemetryBootstrapConfig(
			'vite-dev-current-worktree',
			createTelemetrySessionId,
		);
		const secondConfig = createBridgeAppDevTelemetryBootstrapConfig(
			'vite-dev-current-worktree',
			createTelemetrySessionId,
		);

		expect(firstConfig.workerBootstrap).toMatchObject({
			telemetrySessionId: 'dev-telemetry-reload-1',
		});
		expect(secondConfig.workerBootstrap).toMatchObject({
			telemetrySessionId: 'dev-telemetry-reload-2',
		});
	});
});
