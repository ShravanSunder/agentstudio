import { describe, expect, test } from 'vitest';

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
						scenario: 'package_apply_content_fetch_v1',
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

		expect(scenarios).toEqual(['package_apply_content_fetch_v1']);
		expect(session.getTelemetryConfig()?.scenario).toBe('package_apply_content_fetch_v1');
	});

	test('notifies ready callback before dispatching bridge ready', async () => {
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

		expect(events).toEqual(['ready-callback:push-1', 'ready-event']);
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
