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

describe('bridge RPC client', () => {
	test('dispatches JSON-RPC commands with bridge nonce and command id', () => {
		const target = new EventTarget();
		const sentDetails: unknown[] = [];
		target.addEventListener('__bridge_command', (event: Event): void => {
			sentDetails.push(extractEventDetail(event));
		});
		const client = createBridgeRPCClient({
			target,
			getBridgeNonce: () => 'bridge-nonce',
			createCommandId: () => 'cmd-fixed',
		});

		const didSend = client.sendCommand({
			id: commandWithIdFixture.id,
			method: 'review.markFileViewed',
			params: commandWithIdFixture.params,
		});

		expect(didSend).toBe(true);
		expect(sentDetails).toEqual([
			{
				...commandWithIdFixture,
				__nonce: 'bridge-nonce',
				__commandId: 'cmd-fixed',
			},
		]);
	});

	test('dispatches JSON-RPC notifications from shared contract fixtures', () => {
		const target = new EventTarget();
		const sentDetails: unknown[] = [];
		target.addEventListener('__bridge_command', (event: Event): void => {
			sentDetails.push(extractEventDetail(event));
		});
		const client = createBridgeRPCClient({
			target,
			getBridgeNonce: () => 'bridge-nonce',
			createCommandId: () => 'cmd-fixed-notification',
		});

		const didSend = client.sendCommand({
			method: 'review.markFileViewed',
			params: commandNotificationFixture.params,
		});

		expect(didSend).toBe(true);
		expect(sentDetails).toEqual([
			{
				...commandNotificationFixture,
				__nonce: 'bridge-nonce',
				__commandId: 'cmd-fixed-notification',
			},
		]);
	});

	test('drops commands when bridge nonce is not available', () => {
		const target = new EventTarget();
		const sentDetails: unknown[] = [];
		target.addEventListener('__bridge_command', (event: Event): void => {
			sentDetails.push(extractEventDetail(event));
		});
		const client = createBridgeRPCClient({
			target,
			getBridgeNonce: () => null,
			createCommandId: () => 'cmd-fixed',
		});

		const didSend = client.sendCommand({
			method: 'review.markFileViewed',
			params: { fileId: 'item-source' },
		});

		expect(didSend).toBe(false);
		expect(sentDetails).toEqual([]);
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
		const target = new EventTarget();
		const sentDetails: unknown[] = [];
		target.addEventListener('__bridge_command', (event: Event): void => {
			sentDetails.push(extractEventDetail(event));
		});
		const client = createBridgeRPCClient({
			target,
			getBridgeNonce: () => 'bridge-nonce',
			createCommandId: () => 'cmd-active-viewer-mode',
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
		expect(sentDetails).toEqual([
			{
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
				__nonce: 'bridge-nonce',
				__commandId: 'cmd-active-viewer-mode',
			},
		]);
	});

	test('attaches trace context outside params and records generic RPC telemetry', () => {
		const target = new EventTarget();
		const sentDetails: unknown[] = [];
		const recordedSamples: BridgeTelemetrySample[] = [];
		let flushCount = 0;
		const flushForces: Array<boolean | undefined> = [];
		target.addEventListener('__bridge_command', (event: Event): void => {
			sentDetails.push(extractEventDetail(event));
		});
		const client = createBridgeRPCClient({
			target,
			getBridgeNonce: () => 'bridge-nonce',
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
		});

		const didSend = client.sendCommand({
			method: 'review.markFileViewed',
			params: { fileId: 'item-source' },
		});

		expect(didSend).toBe(true);
		expect(sentDetails).toEqual([
			{
				jsonrpc: '2.0',
				method: 'review.markFileViewed',
				params: { fileId: 'item-source' },
				__traceContext: {
					traceId: '11111111111111111111111111111111',
					spanId: '2222222222222222',
					parentSpanId: null,
					sampled: true,
				},
				__nonce: 'bridge-nonce',
				__commandId: 'cmd-fixed',
			},
		]);
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
		expect(flushCount).toBe(1);
		expect(flushForces).toEqual([true]);
	});

	test('dispatches RPC command when telemetry flush fails', () => {
		const target = new EventTarget();
		const sentDetails: unknown[] = [];
		const recordedSamples: BridgeTelemetrySample[] = [];
		target.addEventListener('__bridge_command', (event: Event): void => {
			sentDetails.push(extractEventDetail(event));
		});
		const client = createBridgeRPCClient({
			target,
			getBridgeNonce: () => 'bridge-nonce',
			createCommandId: () => 'cmd-fixed',
			telemetryRecorder: makeRecorder(recordedSamples, (): boolean => false),
		});

		const didSend = client.sendCommand({
			method: 'review.markFileViewed',
			params: { fileId: 'item-source' },
		});

		expect(didSend).toBe(true);
		expect(sentDetails).toEqual([
			{
				jsonrpc: '2.0',
				method: 'review.markFileViewed',
				params: { fileId: 'item-source' },
				__nonce: 'bridge-nonce',
				__commandId: 'cmd-fixed',
			},
		]);
		expect(recordedSamples.map((sample: BridgeTelemetrySample): string => sample.name)).toEqual([
			'performance.bridge.web.rpc_send',
		]);
	});

	test('does not attach trace context or record RPC telemetry for telemetry batches', () => {
		const target = new EventTarget();
		const sentDetails: unknown[] = [];
		const recordedSamples: BridgeTelemetrySample[] = [];
		target.addEventListener('__bridge_command', (event: Event): void => {
			sentDetails.push(extractEventDetail(event));
		});
		const client = createBridgeRPCClient({
			target,
			getBridgeNonce: () => 'bridge-nonce',
			createCommandId: () => 'cmd-fixed',
			getTraceContext: () => ({
				traceId: '11111111111111111111111111111111',
				spanId: '2222222222222222',
				parentSpanId: null,
				sampled: true,
			}),
			telemetryRecorder: makeRecorder(recordedSamples),
		});

		const didSend = client.sendCommand({
			method: 'system.bridgeTelemetry',
			params: { schemaVersion: 1, scenario: 'bridge-runtime', samples: [] },
		});

		expect(didSend).toBe(true);
		expect(sentDetails).toEqual([
			{
				jsonrpc: '2.0',
				method: 'system.bridgeTelemetry',
				params: { schemaVersion: 1, scenario: 'bridge-runtime', samples: [] },
				__nonce: 'bridge-nonce',
				__commandId: 'cmd-fixed',
			},
		]);
		expect(recordedSamples).toEqual([]);
	});
});

function extractEventDetail(event: Event): unknown {
	return 'detail' in event ? event.detail : null;
}

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
