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
							endpointUrl: 'agentstudio://telemetry/batch',
							maxSamplesPerBatch: 64,
							maxEncodedBatchBytes: 16_384,
							minimumFlushIntervalMilliseconds: 250,
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
		expect(session.getTelemetryConfig()?.endpointUrl).toBe('agentstudio://telemetry/batch');
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
						endpointUrl: 'agentstudio://telemetry/batch',
						maxSamplesPerBatch: 8,
						maxEncodedBatchBytes: 16_384,
						minimumFlushIntervalMilliseconds: 1,
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
						endpointUrl: 'agentstudio://telemetry/batch',
						maxSamplesPerBatch: 8,
						maxEncodedBatchBytes: 16_384,
						minimumFlushIntervalMilliseconds: 1,
						scenario: 'ignored_later_config',
					},
				},
			}),
		);
		session.uninstall();

		expect(scenarios).toEqual(['metadata_apply_content_fetch_v1']);
		expect(session.getTelemetryConfig()?.scenario).toBe('metadata_apply_content_fetch_v1');
	});

	test('notifies ready callback only after native acknowledges bridge ready', async () => {
		const target = new EventTarget();
		const events: string[] = [];
		let readyRequestId: string | null = null;

		target.addEventListener('__bridge_ready', (event) => {
			readyRequestId = extractReadyRequestId(event);
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
		expect(events).toEqual(['ready-event']);
		expect(readyRequestId).not.toBeNull();
		target.dispatchEvent(
			new CustomEvent('__bridge_ready_ack', {
				detail: { jsonrpc: '2.0', id: readyRequestId, result: null },
			}),
		);
		session.uninstall();

		expect(events).toEqual(['ready-event', 'ready-callback:push-1']);
	});

	test('does not dispatch bridge-ready over ordinary page command RPC', async () => {
		const target = new EventTarget();
		const events: string[] = [];
		let readyRequestId: string | null = null;

		target.addEventListener('__bridge_ready', (event) => {
			readyRequestId = extractReadyRequestId(event);
			events.push('ready-event');
		});
		target.addEventListener('__bridge_command', (): void => {
			events.push('bridge-ready-command');
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
		target.dispatchEvent(
			new CustomEvent('__bridge_ready_ack', {
				detail: { jsonrpc: '2.0', id: readyRequestId, result: null },
			}),
		);
		session.uninstall();

		expect(events).toEqual(['ready-event', 'ready-callback:push-1']);
	});

	test('ignores bridge ready acknowledgements for a different request id', async () => {
		const target = new EventTarget();
		const events: string[] = [];
		let readyRequestId: string | null = null;

		target.addEventListener('__bridge_ready', (event) => {
			readyRequestId = extractReadyRequestId(event);
			events.push('ready-event');
		});

		const session = installBridgePageHandshakeSession(target, {
			onReady: (): void => {
				events.push('ready-callback');
			},
		});
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		await Promise.resolve();
		target.dispatchEvent(
			new CustomEvent('__bridge_ready_ack', {
				detail: { jsonrpc: '2.0', id: 'wrong-ready-id', result: null },
			}),
		);
		expect(events).toEqual(['ready-event']);
		target.dispatchEvent(
			new CustomEvent('__bridge_ready_ack', {
				detail: { jsonrpc: '2.0', id: readyRequestId, result: null },
			}),
		);
		session.uninstall();

		expect(events).toEqual(['ready-event', 'ready-callback']);
	});

	test('ignores malformed bridge ready acknowledgement envelopes', async () => {
		const target = new EventTarget();
		const events: string[] = [];
		let readyRequestId: string | null = null;

		target.addEventListener('__bridge_ready', (event) => {
			readyRequestId = extractReadyRequestId(event);
			events.push('ready-event');
		});

		const session = installBridgePageHandshakeSession(target, {
			onReady: (): void => {
				events.push('ready-callback');
			},
		});
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		await Promise.resolve();
		target.dispatchEvent(
			new CustomEvent('__bridge_ready_ack', {
				detail: { id: readyRequestId },
			}),
		);
		expect(events).toEqual(['ready-event']);
		target.dispatchEvent(
			new CustomEvent('__bridge_ready_ack', {
				detail: { jsonrpc: '2.0', id: readyRequestId, result: null },
			}),
		);
		session.uninstall();

		expect(events).toEqual(['ready-event', 'ready-callback']);
	});

	test('reports missing bridge ready acknowledgements instead of waiting forever', async () => {
		vi.useFakeTimers();
		const target = new EventTarget();
		const events: string[] = [];

		const session = installBridgePageHandshakeSession(target, {
			onReady: (): void => {
				events.push('ready-callback');
			},
			onReadyError: (error): void => {
				events.push(`${error.kind}:${error.requestId.length > 0 ? 'request' : 'missing'}`);
			},
			readyAcknowledgementTimeoutMilliseconds: 25,
		});
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		await Promise.resolve();

		vi.advanceTimersByTime(25);
		session.uninstall();
		vi.useRealTimers();

		expect(events).toEqual(['ack_timeout:request']);
	});

	test('notifies ready callback at most once for duplicate acknowledgements', async () => {
		const target = new EventTarget();
		const events: string[] = [];
		let readyRequestId: string | null = null;

		target.addEventListener('__bridge_ready', (event) => {
			readyRequestId = extractReadyRequestId(event);
		});

		const session = installBridgePageHandshakeSession(target, {
			onReady: (): void => {
				events.push('ready-callback');
			},
		});
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		await Promise.resolve();
		target.dispatchEvent(
			new CustomEvent('__bridge_ready_ack', {
				detail: { jsonrpc: '2.0', id: readyRequestId, result: null },
			}),
		);
		target.dispatchEvent(
			new CustomEvent('__bridge_ready_ack', {
				detail: { jsonrpc: '2.0', id: readyRequestId, result: null },
			}),
		);
		session.uninstall();

		expect(events).toEqual(['ready-callback']);
	});

	test('emits intake-ready through scheme RPC after handshake is available', async () => {
		const target = new EventTarget();
		const fetchCalls: BridgeHandshakeFetchCall[] = [];
		const session = installBridgePageHandshakeSession(target, {
			fetch: recordHandshakeFetch(fetchCalls),
		});

		const didSendBeforeHandshake = await session.markIntakeReady({
			protocolId: 'review',
			streamId: 'review:pane-1',
		});
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		const didSendAfterHandshake = await session.markIntakeReady({
			protocolId: 'review',
			streamId: 'review:pane-1',
		});
		session.uninstall();

		expect(didSendBeforeHandshake).toBe(false);
		expect(didSendAfterHandshake).toBe(true);
		expect(fetchCalls).toHaveLength(1);
		expect(fetchCalls[0]?.input).toBe('agentstudio://rpc/command');
		expect(decodeHandshakeFetchBody(fetchCalls[0])).toMatchObject({
			jsonrpc: '2.0',
			method: 'bridge.intakeReady',
			params: {
				protocolId: 'review',
				reason: null,
				streamId: 'review:pane-1',
			},
		});
	});

	test('reports intake-ready scheme RPC transport failure', async () => {
		const target = new EventTarget();
		const session = installBridgePageHandshakeSession(target, {
			fetch: (): Promise<Response> => Promise.reject(new Error('scheme down')),
		});
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);

		const didSend = await session.markIntakeReady({
			protocolId: 'review',
			streamId: 'review:pane-1',
		});
		session.uninstall();

		expect(didSend).toBe(false);
	});
});

interface BridgeHandshakeFetchCall {
	readonly input: RequestInfo | URL;
	readonly init: RequestInit | undefined;
}

function recordHandshakeFetch(fetchCalls: BridgeHandshakeFetchCall[]): typeof fetch {
	return (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
		fetchCalls.push({ input, init });
		const requestBody = typeof init?.body === 'string' ? JSON.parse(init.body) : {};
		return Promise.resolve(
			new Response(JSON.stringify({ jsonrpc: '2.0', id: requestBody.id, result: {} }), {
				status: 200,
			}),
		);
	};
}

function decodeHandshakeFetchBody(fetchCall: BridgeHandshakeFetchCall | undefined): unknown {
	expect(fetchCall).toBeDefined();
	const body = fetchCall?.init?.body;
	if (typeof body !== 'string') {
		throw new Error('expected string RPC request body');
	}
	return JSON.parse(body);
}

function extractReadyRequestId(event: Event): string {
	if (!('detail' in event)) {
		throw new Error('expected ready detail');
	}
	const detail = event.detail;
	if (typeof detail !== 'object' || detail === null || !('requestId' in detail)) {
		throw new Error('expected ready request id');
	}
	if (typeof detail.requestId !== 'string') {
		throw new Error('expected string ready request id');
	}
	return detail.requestId;
}
