import { describe, expect, test, vi } from 'vitest';

import {
	buildBridgeDevTelemetryLogRecord,
	createBridgeDevTelemetrySink,
} from './bridge-dev-telemetry.js';

describe('Bridge dev telemetry sink', () => {
	test('builds scrubbed OTLP log records for BridgeWeb browser batches', () => {
		const record = buildBridgeDevTelemetryLogRecord({
			batch: makeTelemetryBatch(),
			marker: 'vite-dev-proof-1',
			receivedAtUnixNano: '1782218790000000000',
			sample: makeTelemetryBatch().samples[0],
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});

		expect(record).toEqual({
			body: { stringValue: 'performance.bridge.web.first_render' },
			attributes: expect.arrayContaining([
				{ key: 'agent.proof.marker', value: { stringValue: 'vite-dev-proof-1' } },
				{
					key: 'agentstudio.bridge.test.scenario',
					value: { stringValue: 'vite-dev-current-worktree' },
				},
				{ key: 'agentstudio.bridge.phase', value: { stringValue: 'render' } },
				{ key: 'agentstudio.bridge.slice', value: { stringValue: 'diff_package_metadata' } },
				{ key: 'agentstudio.performance.elapsed_ms', value: { intValue: '12' } },
				{ key: 'dev.worktree.hash', value: { stringValue: 'wt-hash' } },
			]),
			severityNumber: 9,
			severityText: 'info',
			timeUnixNano: '1782218790000000000',
		});
		expect(JSON.stringify(record)).not.toContain('/Users/');
	});

	test('posts telemetry batches to the configured collector endpoint', async () => {
		const fetchImpl = vi.fn(async (): Promise<Response> => new Response('', { status: 200 }));
		const sink = createBridgeDevTelemetrySink({
			fetchImpl,
			marker: 'vite-dev-proof-1',
			nowUnixNano: () => '1782218790000000000',
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});

		await sink.ingest(makeTelemetryBatch());

		expect(fetchImpl).toHaveBeenCalledWith(
			'http://127.0.0.1:4318/v1/logs',
			expect.objectContaining({
				body: expect.stringContaining('performance.bridge.web.first_render'),
				headers: { 'content-type': 'application/json' },
				method: 'POST',
			}),
		);
		expect(sink.snapshot()).toEqual({
			acceptedBatchCount: 1,
			acceptedSampleCount: 1,
			failedBatchCount: 0,
			lastError: null,
			marker: 'vite-dev-proof-1',
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});
	});

	test('rejects browser telemetry batches with unsafe attribute values before OTLP export', async () => {
		const fetchImpl = vi.fn(async (): Promise<Response> => new Response('', { status: 200 }));
		const sink = createBridgeDevTelemetrySink({
			fetchImpl,
			marker: 'vite-dev-proof-1',
			nowUnixNano: () => '1782218790000000000',
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});
		const unsafeBatch = {
			...makeTelemetryBatch(),
			samples: [
				{
					...makeTelemetryBatch().samples[0],
					stringAttributes: {
						'agentstudio.bridge.phase': 'render',
						'agentstudio.bridge.raw_path': '/Users/shravansunder/private/file.ts',
						'agentstudio.bridge.capability_url':
							'agentstudio://resource/review/content/descriptor-secret',
						'agentstudio.bridge.prompt': 'prompt-canary',
					},
				},
			],
		};

		await expect(sink.ingest(unsafeBatch)).resolves.toBe(false);

		expect(fetchImpl).not.toHaveBeenCalled();
		expect(sink.snapshot()).toEqual({
			acceptedBatchCount: 0,
			acceptedSampleCount: 0,
			failedBatchCount: 1,
			lastError: 'unsafe_attributes',
			marker: 'vite-dev-proof-1',
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});
	});

	test('accepts telemetry drop samples emitted by BridgeApp', async () => {
		const fetchImpl = vi.fn(async (): Promise<Response> => new Response('', { status: 200 }));
		const sink = createBridgeDevTelemetrySink({
			fetchImpl,
			marker: 'vite-dev-proof-1',
			nowUnixNano: () => '1782218790000000000',
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});
		const dropBatch = {
			...makeTelemetryBatch(),
			samples: [
				{
					...makeTelemetryBatch().samples[0],
					name: 'performance.bridge.web.telemetry_drop',
					stringAttributes: {
						'agentstudio.bridge.phase': 'telemetry',
						'agentstudio.bridge.plane': 'observability',
						'agentstudio.bridge.priority': 'best_effort',
						'agentstudio.bridge.slice': 'telemetry_drop',
						'agentstudio.bridge.telemetry.drop_reason': 'queue_full',
						'agentstudio.bridge.transport': 'push',
					},
					numericAttributes: {
						'agentstudio.bridge.telemetry.dropped_count': 4,
					},
				},
			],
		};

		await expect(sink.ingest(dropBatch)).resolves.toBe(true);

		expect(fetchImpl).toHaveBeenCalledOnce();
		expect(sink.snapshot()).toMatchObject({
			acceptedBatchCount: 1,
			acceptedSampleCount: 1,
			failedBatchCount: 0,
			lastError: null,
		});
	});

	test('accepts Review startup stream chunk metrics without treating them as unsafe', async () => {
		const fetchImpl = vi.fn(async (): Promise<Response> => new Response('', { status: 200 }));
		const sink = createBridgeDevTelemetrySink({
			fetchImpl,
			marker: 'vite-dev-proof-1',
			nowUnixNano: () => '1782218790000000000',
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});
		const chunkBatch = {
			...makeTelemetryBatch(),
			samples: [
				{
					...makeTelemetryBatch().samples[0],
					name: 'performance.bridge.web.review_package_first_chunk',
					stringAttributes: {
						'agentstudio.bridge.phase': 'review_package_first_chunk',
						'agentstudio.bridge.plane': 'data',
						'agentstudio.bridge.priority': 'hot',
						'agentstudio.bridge.result': 'success',
						'agentstudio.bridge.slice': 'review_snapshot',
						'agentstudio.bridge.transport': 'content',
					},
					numericAttributes: {
						'agentstudio.bridge.content.chunk_byte_count': 65_536,
						'agentstudio.bridge.content.total_bytes_read': 65_536,
					},
				},
			],
		};

		await expect(sink.ingest(chunkBatch)).resolves.toBe(true);

		expect(fetchImpl).toHaveBeenCalledOnce();
		expect(sink.snapshot()).toMatchObject({
			acceptedBatchCount: 1,
			acceptedSampleCount: 1,
			failedBatchCount: 0,
			lastError: null,
		});
	});

	test('accepts scrubbed Worktree/File extent canary telemetry without path or capability fields', async () => {
		const postedBodies: string[] = [];
		const fetchImpl = vi.fn(
			async (_input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
				const body = init?.body;
				postedBodies.push(typeof body === 'string' ? body : '');
				return new Response('', { status: 200 });
			},
		);
		const sink = createBridgeDevTelemetrySink({
			fetchImpl,
			marker: 'vite-dev-proof-1',
			nowUnixNano: () => '1782218790000000000',
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});
		const extentBatch = {
			...makeTelemetryBatch(),
			samples: [
				{
					...makeTelemetryBatch().samples[0],
					name: 'performance.bridge.web.worktree_file_scroll_extent',
					stringAttributes: {
						'agentstudio.bridge.phase': 'render',
						'agentstudio.bridge.plane': 'data',
						'agentstudio.bridge.priority': 'hot',
						'agentstudio.bridge.projection.kind': 'worktree_file',
						'agentstudio.bridge.result': 'stable_extent',
						'agentstudio.bridge.slice': 'worktree_file_scroll_extent',
						'agentstudio.bridge.transport': 'push',
					},
					numericAttributes: {
						'agentstudio.bridge.worktree.content_height_delta_px': 0,
						'agentstudio.bridge.worktree.content_total_size_px': 5520,
						'agentstudio.bridge.worktree.descriptor_count': 419,
						'agentstudio.bridge.worktree.frame_count': 420,
						'agentstudio.bridge.worktree.tree_height_delta_px': 0,
						'agentstudio.bridge.worktree.tree_total_size_px': 10056,
					},
				},
			],
		};

		await expect(sink.ingest(extentBatch)).resolves.toBe(true);

		expect(fetchImpl).toHaveBeenCalledOnce();
		const postedBody = postedBodies[0] ?? '';
		expect(postedBody).toContain('performance.bridge.web.worktree_file_scroll_extent');
		expect(postedBody).not.toContain('/Users/');
		expect(postedBody).not.toContain('agentstudio://resource/');
		expect(postedBody).not.toContain('.github/workflows/ci.yml');
		expect(sink.snapshot()).toMatchObject({
			acceptedBatchCount: 1,
			acceptedSampleCount: 1,
			failedBatchCount: 0,
			lastError: null,
		});
	});
});

function makeTelemetryBatch(): {
	readonly schemaVersion: 1;
	readonly scenario: string;
	readonly samples: readonly [
		{
			readonly scope: 'web';
			readonly name: 'performance.bridge.web.first_render';
			readonly durationMilliseconds: 12;
			readonly traceContext: null;
			readonly stringAttributes: Readonly<Record<string, string>>;
			readonly numericAttributes: Readonly<Record<string, number>>;
			readonly booleanAttributes: Readonly<Record<string, boolean>>;
		},
	];
} {
	return {
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
}
