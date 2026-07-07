import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../foundation/telemetry/bridge-telemetry-event.js';
import type {
	BridgeTelemetryFlushProps,
	BridgeTelemetryRecorder,
} from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTelemetryScope } from '../foundation/telemetry/bridge-telemetry-scope.js';
import commandNotificationFixture from '../test-fixtures/bridge-contract-fixtures/valid/rpc-command-notification.json' with { type: 'json' };
import commandWithIdFixture from '../test-fixtures/bridge-contract-fixtures/valid/rpc-command-with-id.json' with { type: 'json' };
import { createBridgeRPCClient } from './bridge-rpc-client.js';
import { bridgeRPCCommandSchema } from './bridge-rpc-client.js';
import { sendBridgeRPCRequest } from './bridge-rpc-client.js';

describe('bridge RPC client', () => {
	test('posts JSON-RPC commands to the scheme endpoint with command id', () => {
		const fetchCalls: BridgeRPCFetchCall[] = [];
		const client = createBridgeRPCClient({
			createCommandId: () => 'cmd-fixed',
			fetch: recordBridgeRPCFetch(fetchCalls),
		});

		const didSend = client.sendCommand({
			id: commandWithIdFixture.id,
			method: 'review.markFileViewed',
			params: commandWithIdFixture.params,
		});

		expect(didSend).toBe(true);
		expect(fetchCalls).toHaveLength(1);
		expect(fetchCalls[0]?.input).toBe('agentstudio://rpc/command');
		expect(fetchCalls[0]?.init?.method).toBe('POST');
		expect(fetchCalls[0]?.init?.headers).toEqual({ 'Content-Type': 'application/json' });
		expect(decodeBridgeRPCFetchBody(fetchCalls[0])).toEqual({
			...commandWithIdFixture,
			__commandId: String(commandWithIdFixture.id),
		});
	});

	test('posts JSON-RPC notifications from shared contract fixtures', () => {
		const fetchCalls: BridgeRPCFetchCall[] = [];
		const client = createBridgeRPCClient({
			createCommandId: () => 'cmd-fixed-notification',
			fetch: recordBridgeRPCFetch(fetchCalls),
		});

		const didSend = client.sendCommand({
			method: 'review.markFileViewed',
			params: commandNotificationFixture.params,
		});

		expect(didSend).toBe(true);
		expect(fetchCalls).toHaveLength(1);
		expect(decodeBridgeRPCFetchBody(fetchCalls[0])).toEqual({
			...commandNotificationFixture,
			__commandId: 'cmd-fixed-notification',
		});
	});

	test('awaits scheme RPC delivery when command completion is a gate', async () => {
		const fetchCalls: BridgeRPCFetchCall[] = [];
		const client = createBridgeRPCClient({
			createCommandId: () => 'cmd-fixed-notification',
			fetch: recordBridgeRPCFetch(fetchCalls),
		});

		const didSend = await client.sendCommandAndWait({
			method: 'bridge.intakeReady',
			params: {
				protocolId: 'review',
				streamId: 'review:pane-1',
			},
		});

		expect(didSend).toBe(true);
		expect(fetchCalls).toHaveLength(1);
		expect(decodeBridgeRPCFetchBody(fetchCalls[0])).toEqual({
			jsonrpc: '2.0',
			id: 'cmd-fixed-notification',
			method: 'bridge.intakeReady',
			params: {
				protocolId: 'review',
				streamId: 'review:pane-1',
			},
			__commandId: 'cmd-fixed-notification',
		});
	});

	test('reports awaited scheme RPC delivery failure', async () => {
		const client = createBridgeRPCClient({
			createCommandId: () => 'cmd-fixed-notification',
			fetch: (): Promise<Response> => Promise.reject(new Error('scheme down')),
		});

		const didSend = await client.sendCommandAndWait({
			method: 'bridge.intakeReady',
			params: {
				protocolId: 'review',
				streamId: 'review:pane-1',
			},
		});

		expect(didSend).toBe(false);
	});

	test('reports awaited JSON-RPC error envelopes as delivery failure', async () => {
		const client = createBridgeRPCClient({
			createCommandId: () => 'cmd-fixed-notification',
			fetch: (): Promise<Response> =>
				Promise.resolve(
					new Response(
						JSON.stringify({
							jsonrpc: '2.0',
							id: 'cmd-fixed-notification',
							error: { code: -32_004, message: 'Bridge not ready' },
						}),
						{ status: 200 },
					),
				),
		});

		const didSend = await client.sendCommandAndWait({
			method: 'bridge.intakeReady',
			params: {
				protocolId: 'review',
				streamId: 'review:pane-1',
			},
		});

		expect(didSend).toBe(false);
	});

	test('reports awaited scheme RPC timeout as delivery failure', async () => {
		const client = createBridgeRPCClient({
			commandTimeoutMilliseconds: 1,
			createCommandId: () => 'cmd-timeout',
			fetch: (_input, init): Promise<Response> =>
				new Promise((_resolve, reject): void => {
					init?.signal?.addEventListener('abort', (): void => {
						reject(new DOMException('aborted', 'AbortError'));
					});
				}),
		});

		const result = await Promise.race([
			client.sendCommandAndWait({
				method: 'bridge.intakeReady',
				params: {
					protocolId: 'review',
					streamId: 'review:pane-1',
				},
			}),
			new Promise<'did-not-timeout'>((resolve) => {
				globalThis.setTimeout((): void => {
					resolve('did-not-timeout');
				}, 25);
			}),
		]);

		expect(result).toBe(false);
	});

	test('reports async notification delivery failure', async () => {
		const failures: string[] = [];
		const client = createBridgeRPCClient({
			createCommandId: () => 'cmd-failed-notification',
			fetch: (): Promise<Response> => Promise.reject(new Error('scheme down')),
			onCommandDeliveryFailure: (failure): void => {
				failures.push(`${failure.commandId}:${failure.command.method}:${failure.message}`);
			},
		});

		const didSend = client.sendCommand({
			method: 'bridge.metadata_interest.update',
			params: {
				protocol: 'review',
				itemIds: ['item-source'],
				lane: 'foreground',
			},
		});

		await Promise.resolve();

		expect(didSend).toBe(true);
		expect(failures).toEqual([
			'cmd-failed-notification:bridge.metadata_interest.update:scheme down',
		]);
	});

	test('awaited scheme RPC uses global timers in worker-like contexts', async () => {
		const windowDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'window');
		Reflect.deleteProperty(globalThis, 'window');
		try {
			await expect(
				sendBridgeRPCRequest({
					command: {
						id: 'cmd-worker-timer',
						method: 'bridge.intakeReady',
						params: {
							protocolId: 'review',
							streamId: 'review:pane-1',
						},
					},
					fetch: (): Response =>
						new Response(JSON.stringify({ jsonrpc: '2.0', id: 'cmd-worker-timer', result: null }), {
							status: 200,
						}),
					timeoutMilliseconds: 1000,
				}),
			).resolves.toBeNull();
		} finally {
			if (windowDescriptor !== undefined) {
				Object.defineProperty(globalThis, 'window', windowDescriptor);
			}
		}
	});

	test('does not require a page-world bridge nonce for scheme RPC', () => {
		const fetchCalls: BridgeRPCFetchCall[] = [];
		const client = createBridgeRPCClient({
			getBridgeNonce: () => null,
			createCommandId: () => 'cmd-fixed',
			fetch: recordBridgeRPCFetch(fetchCalls),
		});

		const didSend = client.sendCommand({
			method: 'review.markFileViewed',
			params: { fileId: 'item-source' },
		});

		expect(didSend).toBe(true);
		expect(decodeBridgeRPCFetchBody(fetchCalls[0])).toEqual({
			jsonrpc: '2.0',
			method: 'review.markFileViewed',
			params: { fileId: 'item-source' },
			__commandId: 'cmd-fixed',
		});
	});

	test('rejects non-Bridge RPC methods at the schema boundary', () => {
		expect(() =>
			bridgeRPCCommandSchema.parse({
				method: 'inbox.post',
				params: { title: 'wrong lane' },
			}),
		).toThrow();
	});

	test('accepts compact review metadata interest commands with demand lanes', () => {
		expect(
			bridgeRPCCommandSchema.parse({
				method: 'bridge.metadata_interest.update',
				params: {
					protocol: 'review',
					streamId: 'review:pane-1',
					generation: 3,
					itemIds: ['item-source'],
					lane: 'foreground',
				},
			}),
		).toEqual({
			method: 'bridge.metadata_interest.update',
			params: {
				protocol: 'review',
				streamId: 'review:pane-1',
				generation: 3,
				itemIds: ['item-source'],
				lane: 'foreground',
			},
		});
		expect(
			bridgeRPCCommandSchema.safeParse({
				method: 'bridge.metadata_interest.update',
				params: {
					protocol: 'review',
					itemIds: ['item-source'],
					lane: 'worktree_visible',
				},
			}).success,
		).toBe(false);
	});

	test('dispatches active viewer mode update notifications', () => {
		const fetchCalls: BridgeRPCFetchCall[] = [];
		const client = createBridgeRPCClient({
			createCommandId: () => 'cmd-active-viewer-mode',
			fetch: recordBridgeRPCFetch(fetchCalls),
		});

		const didSend = client.sendCommand({
			method: 'bridge.activeViewerMode.update',
			params: {
				sessionId: 'session-1',
				sequence: 1,
				mode: 'file',
				activeSource: {
					protocol: 'worktree-file',
					streamId: 'worktree-file:pane-1',
					generation: 3,
				},
			},
		});

		expect(didSend).toBe(true);
		expect(decodeBridgeRPCFetchBody(fetchCalls[0])).toEqual({
			jsonrpc: '2.0',
			method: 'bridge.activeViewerMode.update',
			params: {
				sessionId: 'session-1',
				sequence: 1,
				mode: 'file',
				activeSource: {
					protocol: 'worktree-file',
					streamId: 'worktree-file:pane-1',
					generation: 3,
				},
			},
			__commandId: 'cmd-active-viewer-mode',
		});
	});

	test('does not force telemetry flush while sending interactive commands', () => {
		const fetchCalls: BridgeRPCFetchCall[] = [];
		const recordedSamples: BridgeTelemetrySample[] = [];
		let flushCount = 0;
		const flushForces: Array<boolean | undefined> = [];
		const client = createBridgeRPCClient({
			createCommandId: () => 'cmd-fixed',
			getTraceContext: () => ({
				traceId: '11111111111111111111111111111111',
				spanId: '2222222222222222',
				parentSpanId: null,
				sampled: true,
			}),
			telemetryRecorder: makeRecorder(recordedSamples, (flushProps): boolean => {
				flushCount += 1;
				flushForces.push(flushProps?.force);
				return true;
			}),
			fetch: recordBridgeRPCFetch(fetchCalls),
		});

		const didSend = client.sendCommand({
			method: 'review.markFileViewed',
			params: { fileId: 'item-source' },
		});

		expect(didSend).toBe(true);
		expect(decodeBridgeRPCFetchBody(fetchCalls[0])).toEqual({
			jsonrpc: '2.0',
			method: 'review.markFileViewed',
			params: { fileId: 'item-source' },
			__traceContext: {
				traceId: '11111111111111111111111111111111',
				spanId: '2222222222222222',
				parentSpanId: null,
				sampled: true,
			},
			__commandId: 'cmd-fixed',
		});
		expect(recordedSamples.map((sample: BridgeTelemetrySample): string => sample.name)).toEqual([
			'performance.bridge.web.rpc_send',
		]);
		expect(recordedSamples[0]?.stringAttributes['agentstudio.bridge.rpc.method_class']).toBe(
			'review',
		);
		expect(recordedSamples[0]?.stringAttributes).toMatchObject({
			'agentstudio.bridge.plane': 'control',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.slice': 'review_rpc',
		});
		expect(recordedSamples[0]?.stringAttributes).not.toHaveProperty(
			['agentstudio', 'bridge', 'lane'].join('.'),
		);
		expect(flushCount).toBe(0);
		expect(flushForces).toEqual([]);
	});

	test('rejects telemetry batches from the interactive RPC schema', () => {
		expect(
			bridgeRPCCommandSchema.safeParse({
				method: 'system.bridgeTelemetry',
				params: { schemaVersion: 1, scenario: 'bridge-runtime', sequence: 1, samples: [] },
			}).success,
		).toBe(false);
	});
});

function makeRecorder(
	samples: BridgeTelemetrySample[],
	flushRecorder: (props?: BridgeTelemetryFlushProps) => boolean = (): boolean => true,
): BridgeTelemetryRecorder {
	return {
		isEnabled: (scope: BridgeTelemetryScope): boolean => scope === 'web',
		record: (sample: BridgeTelemetrySample): void => {
			samples.push(sample);
		},
		measure: (props) => props.operation(),
		flush: flushRecorder,
	};
}

interface BridgeRPCFetchCall {
	readonly input: RequestInfo | URL;
	readonly init: RequestInit | undefined;
}

function recordBridgeRPCFetch(fetchCalls: BridgeRPCFetchCall[]): typeof fetch {
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

function decodeBridgeRPCFetchBody(fetchCall: BridgeRPCFetchCall | undefined): unknown {
	expect(fetchCall).toBeDefined();
	const body = fetchCall?.init?.body;
	if (typeof body !== 'string') {
		throw new Error('expected string RPC request body');
	}
	return JSON.parse(body);
}
