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

		expect(loaded.readText()).toBe('hello bridge');
		expect(loaded.handle).toEqual(handle);
	});

	test('loads text from streamed response chunks without using whole-body text()', async () => {
		const handle = makeBridgeContentHandle('item-source', 'head');
		const loaded = await loadBridgeContentResource({
			handle,
			fetchContent: async (url: string): Promise<Response> => {
				expect(url).toBe(handle.resourceUrl);
				return chunkedTextResponse(['hello ', 'streamed ', 'bridge']);
			},
		});

		expect(loaded.readText()).toBe('hello streamed bridge');
		expect(loaded.handle).toEqual(handle);
	});

	test('preserves preview-only stream authority and byte length from descriptor integrity', async () => {
		const handle = makeBridgeContentHandle('item-source', 'head');
		const loaded = await loadBridgeContentResource({
			handle,
			integrity: { kind: 'previewOnly' },
			fetchContent: async (url: string): Promise<Response> => {
				expect(url).toBe(handle.resourceUrl);
				return chunkedTextResponse(['preview ', 'only']);
			},
		});

		expect(loaded).toMatchObject({
			authoritative: false,
			byteLength: 12,
			handle,
		});
		expect(loaded.readText()).toBe('preview only');
	});

	test('rejects streamed text that exceeds the descriptor byte limit', async () => {
		const handle = makeBridgeContentHandle('item-source', 'head');

		await expect(
			loadBridgeContentResource({
				handle,
				maxBytes: 5,
				fetchContent: async (): Promise<Response> => chunkedTextResponse(['abcd', 'ef']),
			}),
		).rejects.toThrow('Bridge text resource stream exceeded issued max bytes');
	});

	test('rejects streamed text that fails whole-body integrity validation', async () => {
		const handle = makeBridgeContentHandle('item-source', 'head');

		await expect(
			loadBridgeContentResource({
				handle,
				integrity: {
					kind: 'wholeHash',
					algorithm: 'sha256',
					value: 'sha256:3173778af72bee80065ddb3dc0fa2319fcaca233bdfd4591d1b3a4ca5115d5a9',
				},
				fetchContent: async (): Promise<Response> => chunkedTextResponse(['tampered ', 'bridge']),
			}),
		).rejects.toThrow('Bridge text resource stream failed whole-body integrity validation');
	});

	test('rejects untrusted content URLs before fetch', async () => {
		const handle = {
			...makeBridgeContentHandle('item-source', 'head'),
			resourceUrl: 'https://example.com/content',
		};
		let fetchCount = 0;

		await expect(
			loadBridgeContentResource({
				handle,
				fetchContent: async (): Promise<Response> => {
					fetchCount += 1;
					return new Response('should not load');
				},
			}),
		).rejects.toThrow('Bridge content resource URL is not allowed');
		expect(fetchCount).toBe(0);
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

		expect(loaded.readText()).toBe('hello bridge');
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
		expect(flushForces).toEqual([true]);
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

		expect(loaded.readText()).toBe('hello despite telemetry failure');
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

function chunkedTextResponse(chunks: readonly string[]): Response {
	const encoder = new TextEncoder();
	const body = new ReadableStream<Uint8Array>({
		start(controller): void {
			for (const chunk of chunks) {
				controller.enqueue(encoder.encode(chunk));
			}
			controller.close();
		},
	});
	return Object.assign(new Response(body), {
		text: async (): Promise<string> => {
			throw new Error('whole body text() should not be used for Bridge content resources');
		},
	});
}
