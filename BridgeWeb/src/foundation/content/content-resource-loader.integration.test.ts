import { describe, expect, test } from 'vitest';

import { makeBridgeContentHandle } from '../review-package/bridge-review-package-test-support.js';
import type { BridgeTelemetrySample } from '../telemetry/bridge-telemetry-event.js';
import type {
	BridgeTelemetryFlushProps,
	BridgeTelemetryRecorder,
} from '../telemetry/bridge-telemetry-recorder.js';
import type { BridgeTelemetryScope } from '../telemetry/bridge-telemetry-scope.js';
import { loadBridgeContentResource } from './content-resource-loader.js';

describe('content resource loader', () => {
	test('loads text from the scoped bridge content URL', async () => {
		const handle = makeBridgeContentHandle('item-source', 'head');
		const loaded = await loadBridgeContentResource({
			handle,
			fetchContent: async (url: string): Promise<Response> => {
				expect(url).toBe(handle.resourceUrl);
				return new Response('hello bridge');
			},
		});

		expect(loaded.text).toBe('hello bridge');
		expect(loaded.handle).toEqual(handle);
	});

	test('can attach traceparent headers when the WebKit proof lane enables them', async () => {
		const handle = makeBridgeContentHandle('item-source', 'head');
		const loaded = await loadBridgeContentResource({
			handle,
			traceContext: {
				traceId: '11111111111111111111111111111111',
				spanId: '2222222222222222',
				parentSpanId: null,
				sampled: true,
			},
			sendTraceparentHeader: true,
			fetchContent: async (url: string, init?: RequestInit): Promise<Response> => {
				expect(url).toBe(handle.resourceUrl);
				expect(init?.headers).toEqual({
					traceparent: '00-11111111111111111111111111111111-2222222222222222-01',
				});
				return new Response('hello bridge');
			},
		});

		expect(loaded.text).toBe('hello bridge');
	});

	test('does not attach traceparent headers by default', async () => {
		const handle = makeBridgeContentHandle('item-source', 'head');
		await loadBridgeContentResource({
			handle,
			traceContext: {
				traceId: '11111111111111111111111111111111',
				spanId: '2222222222222222',
				parentSpanId: null,
				sampled: true,
			},
			fetchContent: async (_url: string, init?: RequestInit): Promise<Response> => {
				expect(init).toBeUndefined();
				return new Response('hello bridge');
			},
		});
	});

	test('records content fetch telemetry with safe summary correlation attributes', async () => {
		const handle = makeBridgeContentHandle('item-source', 'head');
		const samples: BridgeTelemetrySample[] = [];
		let flushCount = 0;
		const flushForces: Array<boolean | undefined> = [];
		await loadBridgeContentResource({
			handle,
			traceContext: {
				traceId: '11111111111111111111111111111111',
				spanId: '2222222222222222',
				parentSpanId: null,
				sampled: true,
			},
			telemetryRecorder: makeRecorder(samples, (flushProps): boolean => {
				flushCount += 1;
				flushForces.push(flushProps?.force);
				return true;
			}),
			fetchContent: async (): Promise<Response> => new Response('hello bridge'),
		});

		expect(samples).toHaveLength(1);
		expect(samples[0]?.name).toBe('performance.bridge.web.content_fetch');
		expect(samples[0]?.stringAttributes['agentstudio.bridge.content.correlation_mode']).toBe(
			'summary',
		);
		expect(samples[0]?.stringAttributes).toMatchObject({
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.slice': 'content_fetch',
		});
		expect(samples[0]?.stringAttributes).not.toHaveProperty(
			['agentstudio', 'bridge', 'lane'].join('.'),
		);
		expect(samples[0]?.booleanAttributes['agentstudio.bridge.header_missing']).toBe(true);
		expect(flushCount).toBe(1);
		expect(flushForces).toEqual([undefined]);
	});

	test('loads content when telemetry flush fails', async () => {
		const handle = makeBridgeContentHandle('item-source', 'head');
		const samples: BridgeTelemetrySample[] = [];
		const loaded = await loadBridgeContentResource({
			handle,
			telemetryRecorder: makeRecorder(samples, (): boolean => false),
			fetchContent: async (url: string): Promise<Response> => {
				expect(url).toBe(handle.resourceUrl);
				return new Response('hello despite telemetry failure');
			},
		});

		expect(loaded.text).toBe('hello despite telemetry failure');
		expect(samples.map((sample: BridgeTelemetrySample): string => sample.name)).toEqual([
			'performance.bridge.web.content_fetch',
		]);
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
