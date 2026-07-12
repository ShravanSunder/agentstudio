import { describe, expect, test, vi } from 'vitest';

import {
	BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
	BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
	BRIDGE_PRODUCT_WIRE_VERSION,
} from '../core/comm-worker/bridge-product-contract-primitives.js';
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

	test('correlates initial and replacement product bootstraps while ignoring duplicates', () => {
		const target = new EventTarget();
		const deliveredWorkerInstanceIds: string[] = [];
		const bootstrapRequests: Array<{ readonly reason: string; readonly requestId: string }> = [];
		target.addEventListener('__bridge_product_session_bootstrap_request', (event): void => {
			const request = extractProductBootstrapRequest(event);
			bootstrapRequests.push(request);
			const workerInstanceId = `worker-${bootstrapRequests.length.toString()}`;
			const detail = makeProductBootstrapDetail(request.requestId, workerInstanceId);
			target.dispatchEvent(new CustomEvent('__bridge_product_session_bootstrap', { detail }));
			target.dispatchEvent(new CustomEvent('__bridge_product_session_bootstrap', { detail }));
		});
		const session = installBridgePageHandshakeSession(target, {
			onProductSessionBootstrap: ({ bootstrap }): void => {
				deliveredWorkerInstanceIds.push(bootstrap.workerInstanceId);
			},
		});

		session.requestProductSessionReplacement();
		session.uninstall();

		expect(bootstrapRequests).toEqual([
			expect.objectContaining({ reason: 'initial' }),
			expect.objectContaining({ reason: 'workerReplacement' }),
		]);
		expect(bootstrapRequests[0]?.requestId).not.toBe(bootstrapRequests[1]?.requestId);
		expect(deliveredWorkerInstanceIds).toEqual(['worker-1', 'worker-2']);
	});
});

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

function extractProductBootstrapRequest(event: Event): {
	readonly reason: string;
	readonly requestId: string;
} {
	if (!('detail' in event)) {
		throw new Error('expected product bootstrap request detail');
	}
	const detail = event.detail;
	if (
		typeof detail !== 'object' ||
		detail === null ||
		!('reason' in detail) ||
		!('requestId' in detail) ||
		typeof detail.reason !== 'string' ||
		typeof detail.requestId !== 'string'
	) {
		throw new Error('expected typed product bootstrap request');
	}
	return { reason: detail.reason, requestId: detail.requestId };
}

function makeProductBootstrapDetail(requestId: string, workerInstanceId: string): object {
	return {
		requestId,
		bootstrap: {
			kind: 'productSession.bootstrap',
			paneSessionId: 'pane-session-1',
			policy: {
				maximumContentBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
				maximumRequestBodyBytes: BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
				maximumMetadataFrameBytes: BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
				maximumQueuedStreamBytes: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
				maximumQueuedStreamFrames: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
				terminalFrameReserve: BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
			},
			wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			workerInstanceId,
		},
		productCapability: new ArrayBuffer(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH),
	};
}
