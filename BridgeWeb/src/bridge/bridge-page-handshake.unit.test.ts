import { describe, expect, test, vi } from 'vitest';

import {
	installBridgePageHandshake,
	installBridgePageHandshakeSession,
} from './bridge-page-handshake.js';

describe('bridge page handshake', () => {
	test('requests handshake replay and emits bridge ready after handshake with nonce arrives', async () => {
		const target = new EventTarget();
		const eventNames: string[] = [];

		target.addEventListener('__bridge_handshake_request', () => {
			eventNames.push('__bridge_handshake_request');
			target.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
			);
		});
		target.addEventListener('__bridge_ready', () => {
			eventNames.push('__bridge_ready');
		});

		const uninstall = installBridgePageHandshake(target);
		expect(eventNames).toEqual(['__bridge_handshake_request']);
		await Promise.resolve();
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-2' } }),
		);
		uninstall();

		expect(eventNames).toEqual(['__bridge_handshake_request', '__bridge_ready']);
	});

	test('does not emit bridge ready until the handshake carries a push nonce', async () => {
		const target = new EventTarget();
		const eventNames: string[] = [];

		target.addEventListener('__bridge_ready', () => {
			eventNames.push('__bridge_ready');
		});

		const session = installBridgePageHandshakeSession(target);
		target.dispatchEvent(new CustomEvent('__bridge_handshake'));
		expect(eventNames).toEqual([]);

		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		expect(eventNames).toEqual([]);
		await Promise.resolve();
		session.uninstall();

		expect(session.getPushNonce()).toBe('push-1');
		expect(eventNames).toEqual(['__bridge_ready']);
	});

	test('retains the first push nonce from the bridge handshake', () => {
		const target = new EventTarget();

		target.addEventListener('__bridge_handshake_request', () => {
			target.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
			);
		});

		const session = installBridgePageHandshakeSession(target);
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-2' } }),
		);
		session.uninstall();

		expect(session.getPushNonce()).toBe('push-1');
	});

	test('retains telemetry config from the first valid handshake config', () => {
		const target = new EventTarget();

		target.addEventListener('__bridge_handshake_request', () => {
			target.dispatchEvent(
				new CustomEvent('__bridge_handshake', {
					detail: {
						pushNonce: 'push-1',
						telemetryConfig: {
							enabledScopes: ['web', 'webkit'],
							maxSamplesPerBatch: 64,
							maxEncodedBatchBytes: 16_384,
							minimumFlushIntervalMilliseconds: 250,
							rpcMethodName: 'system.bridgeTelemetry',
							scenario: 'bridge-runtime',
						},
					},
				}),
			);
		});

		const session = installBridgePageHandshakeSession(target);
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', {
				detail: {
					pushNonce: 'push-2',
					telemetryConfig: null,
				},
			}),
		);
		session.uninstall();

		expect(session.getTelemetryConfig()?.enabledScopes.has('web')).toBe(true);
		expect(session.getTelemetryConfig()?.rpcMethodName).toBe('system.bridgeTelemetry');
	});

	test('notifies when the first valid telemetry config arrives after install', () => {
		const target = new EventTarget();
		const scenarios: string[] = [];

		const session = installBridgePageHandshakeSession(target, {
			onTelemetryConfig: (telemetryConfig): void => {
				scenarios.push(telemetryConfig.scenario);
			},
		});
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', {
				detail: {
					pushNonce: 'push-1',
					telemetryConfig: {
						enabledScopes: ['web'],
						maxSamplesPerBatch: 8,
						maxEncodedBatchBytes: 16_384,
						minimumFlushIntervalMilliseconds: 1,
						rpcMethodName: 'system.bridgeTelemetry',
						scenario: 'metadata_apply_content_fetch_v1',
					},
				},
			}),
		);
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', {
				detail: {
					pushNonce: 'push-2',
					telemetryConfig: {
						enabledScopes: ['web'],
						maxSamplesPerBatch: 8,
						maxEncodedBatchBytes: 16_384,
						minimumFlushIntervalMilliseconds: 1,
						rpcMethodName: 'system.bridgeTelemetry',
						scenario: 'ignored_later_config',
					},
				},
			}),
		);
		session.uninstall();

		expect(scenarios).toEqual(['metadata_apply_content_fetch_v1']);
		expect(session.getTelemetryConfig()?.scenario).toBe('metadata_apply_content_fetch_v1');
	});

	test('notifies ready callback after dispatching bridge ready', async () => {
		const target = new EventTarget();
		const events: string[] = [];

		target.addEventListener('__bridge_ready', () => {
			events.push('ready-event');
		});

		const session = installBridgePageHandshakeSession(target, {
			onReady: (): void => {
				events.push(`ready-callback:${session.getPushNonce() ?? 'missing'}`);
			},
		});
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		await Promise.resolve();
		session.uninstall();

		expect(events).toEqual(['ready-event', 'ready-callback:push-1']);
	});

	test('waits for bridge-ready response before notifying ready callback when command nonce is available', async () => {
		const target = new EventTarget();
		const events: string[] = [];
		let bridgeReadyRequestId: string | null = null;

		target.addEventListener('__bridge_ready', () => {
			events.push('ready-event');
		});
		target.addEventListener('__bridge_command', (event: Event): void => {
			const detail = 'detail' in event ? event.detail : null;
			const commandId = bridgeReadyCommandId(detail);
			if (commandId === null) {
				return;
			}
			bridgeReadyRequestId = commandId;
			events.push('bridge-ready-command');
		});

		const session = installBridgePageHandshakeSession(target, {
			getBridgeCommandNonce: (): string => 'bridge-command-nonce',
			onReady: (): void => {
				events.push(`ready-callback:${session.getPushNonce() ?? 'missing'}`);
			},
		});
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		await Promise.resolve();

		expect(events).toEqual(['ready-event', 'bridge-ready-command']);
		if (bridgeReadyRequestId === null) {
			throw new Error('Expected bridge ready request id');
		}
		target.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: { jsonrpc: '2.0', id: bridgeReadyRequestId, result: null, nonce: 'push-1' },
			}),
		);
		session.uninstall();

		expect(events).toEqual(['ready-event', 'bridge-ready-command', 'ready-callback:push-1']);
	});

	test('rejects bridge-ready error responses without notifying ready callback', async () => {
		const target = new EventTarget();
		const events: string[] = [];
		let bridgeReadyRequestId: string | null = null;

		target.addEventListener('__bridge_command', (event: Event): void => {
			bridgeReadyRequestId = bridgeReadyCommandId('detail' in event ? event.detail : null);
			events.push('bridge-ready-command');
		});

		const session = installBridgePageHandshakeSession(target, {
			getBridgeCommandNonce: (): string => 'bridge-command-nonce',
			onReady: (): void => {
				events.push('ready-callback');
			},
			onReadyError: (error: Error): void => {
				events.push(error.message);
			},
		});
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		await Promise.resolve();

		if (bridgeReadyRequestId === null) {
			throw new Error('Expected bridge ready request id');
		}
		target.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: {
					id: bridgeReadyRequestId,
					error: { code: -32_004, message: 'bridge_not_ready' },
				},
			}),
		);
		session.uninstall();

		expect(events).toEqual([
			'bridge-ready-command',
			'Bridge ready command failed: bridge_not_ready',
		]);
	});

	test('times out waiting for bridge-ready response without notifying ready callback', async () => {
		vi.useFakeTimers();
		try {
			const target = new EventTarget();
			const events: string[] = [];

			const session = installBridgePageHandshakeSession(target, {
				getBridgeCommandNonce: (): string => 'bridge-command-nonce',
				onReady: (): void => {
					events.push('ready-callback');
				},
				onReadyError: (error: Error): void => {
					events.push(error.message);
				},
				readyResponseTimeoutMilliseconds: 25,
			});
			target.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
			);
			await Promise.resolve();

			await vi.advanceTimersByTimeAsync(25);
			session.uninstall();

			expect(events).toEqual(['Bridge ready command timed out']);
		} finally {
			vi.useRealTimers();
		}
	});

	test('emits intake-ready as a control command after handshake and command nonce are available', () => {
		const target = new EventTarget();
		const commands: unknown[] = [];
		const session = installBridgePageHandshakeSession(target, {
			getBridgeCommandNonce: (): string => 'bridge-command-nonce',
		});
		target.addEventListener('__bridge_command', (event: Event): void => {
			commands.push('detail' in event ? event.detail : null);
		});

		const didSendBeforeHandshake = session.markIntakeReady({
			protocolId: 'review',
			streamId: 'review:pane-1',
		});
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		const didSendAfterHandshake = session.markIntakeReady({
			protocolId: 'review',
			streamId: 'review:pane-1',
		});
		session.uninstall();

		expect(didSendBeforeHandshake).toBe(false);
		expect(didSendAfterHandshake).toBe(true);
		expect(commands).toEqual([
			{
				__nonce: 'bridge-command-nonce',
				jsonrpc: '2.0',
				method: 'bridge.intakeReady',
				params: {
					protocolId: 'review',
					streamId: 'review:pane-1',
				},
			},
		]);
	});
});

function bridgeReadyCommandId(value: unknown): string | null {
	if (typeof value !== 'object' || value === null) {
		return null;
	}
	if (!('method' in value) || value.method !== 'bridge.ready') {
		return null;
	}
	if (!('id' in value) || typeof value.id !== 'string') {
		return null;
	}
	return value.id;
}
