import { describe, expect, test, vi } from 'vitest';

import type { BridgeTelemetryWorkerBatchRequest } from '../../src/core/telemetry-worker/bridge-telemetry-worker-contracts.js';
import type { BridgeTelemetrySample } from '../../src/foundation/telemetry/bridge-telemetry-event.js';
import {
	buildBridgeDevContentResponseTelemetryObservation,
	buildBridgeDevTelemetryLogRecord,
	createBridgeDevTelemetrySink,
} from './bridge-dev-telemetry.js';

describe('Bridge dev telemetry sink', () => {
	test('builds scrubbed OTLP log records for BridgeWeb browser batches', () => {
		const record = buildBridgeDevTelemetryLogRecord({
			marker: 'vite-dev-proof-1',
			observation: {
				scenario: 'bridge-worker-v2',
				samples: [makeTelemetrySample()],
			},
			receivedAtUnixNano: '1782218790000000000',
			sample: makeTelemetrySample(),
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});

		expect(record).toEqual({
			body: { stringValue: 'performance.bridge.web.first_render' },
			attributes: expect.arrayContaining([
				{ key: 'agent.proof.marker', value: { stringValue: 'vite-dev-proof-1' } },
				{
					key: 'agentstudio.bridge.test.scenario',
					value: { stringValue: 'bridge-worker-v2' },
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

		await expect(sink.ingestWorkerBatch(makeTelemetryBatch())).resolves.toMatchObject({
			type: 'accepted',
			acceptedSampleCount: 1,
		});

		expect(fetchImpl).toHaveBeenCalledWith(
			'http://127.0.0.1:4318/v1/logs',
			expect.objectContaining({
				body: expect.stringContaining('performance.bridge.web.first_render'),
				headers: { 'content-type': 'application/json' },
				method: 'POST',
			}),
		);
		expect(fetchImpl).toHaveBeenCalledWith(
			'http://127.0.0.1:4318/v1/metrics',
			expect.objectContaining({
				body: expect.stringContaining('agentstudio_performance_events_total'),
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
			recentSamples: [makeTelemetrySample()],
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});
	});

	test('rejects schema-v1 input and enforces v2 sequence admission', async () => {
		const fetchImpl = vi.fn(async (): Promise<Response> => new Response('', { status: 200 }));
		const sink = createBridgeDevTelemetrySink({ fetchImpl });

		await expect(
			sink.ingestWorkerBatch({
				schemaVersion: 1,
				scenario: 'legacy',
				streamId: 'page',
				samples: [makeTelemetrySample()],
			}),
		).rejects.toThrow('invalid_telemetry_batch');
		await expect(
			sink.ingestWorkerBatch(makeTelemetryBatch(makeTelemetrySample(), 2)),
		).resolves.toMatchObject({
			type: 'rejected',
			reason: 'sequence_gap',
			nextExpectedBatchSequence: 1,
		});
		await expect(sink.ingestWorkerBatch(makeTelemetryBatch())).resolves.toMatchObject({
			type: 'accepted',
		});
		await expect(sink.ingestWorkerBatch(makeTelemetryBatch())).resolves.toMatchObject({
			type: 'duplicate',
		});
		await expect(
			sink.ingestWorkerBatch(
				makeTelemetryBatch({
					...makeTelemetrySample(),
					name: 'performance.bridge.web.conflicting_sample',
				}),
			),
		).resolves.toMatchObject({
			type: 'rejected',
			reason: 'conflict',
		});

		expect(fetchImpl).toHaveBeenCalledTimes(2);
	});

	test('projects compact lifecycle telemetry without a v1 event wrapper', async () => {
		const fetchImpl = vi.fn(async (): Promise<Response> => new Response('', { status: 200 }));
		const sink = createBridgeDevTelemetrySink({ fetchImpl });
		const batch: BridgeTelemetryWorkerBatchRequest = {
			...makeTelemetryBatch(),
			samples: [
				{
					producerId: 'comm',
					producerSequence: 1,
					sample: {
						type: 'duration',
						metric: 'worker_task',
						durationMilliseconds: 8,
						timestampMilliseconds: 9,
						attemptId: 'attempt-1',
						interactionSequence: 3,
						surface: 'review',
					},
				},
			],
		};

		await expect(sink.ingestWorkerBatch(batch)).resolves.toMatchObject({ type: 'accepted' });

		expect(sink.snapshot().recentSamples).toEqual([
			expect.objectContaining({
				name: 'performance.bridge.web.interaction_duration',
				durationMilliseconds: 8,
				numericAttributes: {
					'agentstudio.bridge.interaction.sequence': 3,
				},
			}),
		]);
	});

	test('builds VictoriaMetrics-compatible performance metric payloads for BridgeWeb batches', async () => {
		const postedBodies: string[] = [];
		const fetchImpl = vi.fn(
			async (_input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
				postedBodies.push(typeof init?.body === 'string' ? init.body : '');
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

		await sink.ingestWorkerBatch(makeTelemetryBatch());

		const metricsBody = postedBodies.find((body) =>
			body.includes('agentstudio_performance_events_total'),
		);
		expect(metricsBody).toContain(
			'"service.name","value":{"stringValue":"AgentStudioBridgeWebDevServer"',
		);
		expect(metricsBody).toContain('"agent.proof.marker","value":{"stringValue":"vite-dev-proof-1"');
		expect(metricsBody).toContain('"name":"agentstudio_performance_events_total"');
		expect(metricsBody).toContain('"name":"agentstudio_performance_event_elapsed_ms"');
		expect(metricsBody).toContain('"name":"agentstudio_performance_event_elapsed_ms_max"');
		expect(metricsBody).toContain(
			'"key":"event","value":{"stringValue":"performance.bridge.web.first_render"',
		);
		expect(metricsBody).toContain('"key":"phase","value":{"stringValue":"render"');
		expect(metricsBody).toContain('"key":"plane","value":{"stringValue":"data"');
		expect(metricsBody).toContain('"key":"priority","value":{"stringValue":"hot"');
		expect(metricsBody).toContain('"key":"slice","value":{"stringValue":"diff_package_metadata"');
		expect(metricsBody).toContain('"key":"transport","value":{"stringValue":"push"');
		expect(metricsBody).toContain('"sum":12');
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
		const unsafeBatch = makeTelemetryBatch({
			...makeTelemetrySample(),
			stringAttributes: {
				...makeTelemetrySample().stringAttributes,
				'agentstudio.bridge.phase': 'render',
				'agentstudio.bridge.raw_path': '/Users/shravansunder/private/file.ts',
				'agentstudio.bridge.capability_url':
					'agentstudio://resource/review/content/descriptor-secret',
				'agentstudio.bridge.prompt': 'prompt-canary',
			},
		});

		await expect(sink.ingestWorkerBatch(unsafeBatch)).resolves.toMatchObject({
			type: 'rejected',
			reason: 'invalid_body',
		});

		expect(fetchImpl).not.toHaveBeenCalled();
		expect(sink.snapshot()).toEqual({
			acceptedBatchCount: 0,
			acceptedSampleCount: 0,
			failedBatchCount: 1,
			lastError: 'unsafe_attributes',
			marker: 'vite-dev-proof-1',
			recentSamples: [],
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});
	});

	test('keeps safe recent samples available when collector export fails', async () => {
		const fetchImpl = vi.fn(async (): Promise<Response> => new Response('', { status: 503 }));
		const sink = createBridgeDevTelemetrySink({
			fetchImpl,
			marker: 'vite-dev-proof-1',
			nowUnixNano: () => '1782218790000000000',
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});

		await expect(sink.ingestWorkerBatch(makeTelemetryBatch())).resolves.toMatchObject({
			type: 'rejected',
			reason: 'unavailable',
			retryable: true,
		});

		expect(sink.snapshot()).toMatchObject({
			acceptedBatchCount: 0,
			acceptedSampleCount: 0,
			failedBatchCount: 1,
			lastError: 'collector_logs_http_503',
			recentSamples: [makeTelemetrySample()],
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
		const dropBatch = makeTelemetryBatch({
			...makeTelemetrySample(),
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
		});

		await expect(sink.ingestWorkerBatch(dropBatch)).resolves.toMatchObject({
			type: 'accepted',
		});

		expect(fetchImpl).toHaveBeenCalledTimes(2);
		expect(sink.snapshot()).toMatchObject({
			acceptedBatchCount: 1,
			acceptedSampleCount: 1,
			failedBatchCount: 0,
			lastError: null,
		});
	});

	test('accepts Review content stream chunk metrics without treating them as unsafe', async () => {
		const fetchImpl = vi.fn(async (): Promise<Response> => new Response('', { status: 200 }));
		const sink = createBridgeDevTelemetrySink({
			fetchImpl,
			marker: 'vite-dev-proof-1',
			nowUnixNano: () => '1782218790000000000',
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});
		const chunkBatch = makeTelemetryBatch({
			...makeTelemetrySample(),
			name: 'performance.bridge.web.review_content_first_chunk',
			stringAttributes: {
				'agentstudio.bridge.phase': 'review_content_first_chunk',
				'agentstudio.bridge.plane': 'data',
				'agentstudio.bridge.priority': 'hot',
				'agentstudio.bridge.result': 'success',
				'agentstudio.bridge.slice': 'content_fetch',
				'agentstudio.bridge.transport': 'content',
			},
			numericAttributes: {
				'agentstudio.bridge.content.chunk_byte_count': 65_536,
				'agentstudio.bridge.content.total_bytes_read': 65_536,
			},
		});

		await expect(sink.ingestWorkerBatch(chunkBatch)).resolves.toMatchObject({
			type: 'accepted',
		});

		expect(fetchImpl).toHaveBeenCalledTimes(2);
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
		const extentBatch = makeTelemetryBatch({
			...makeTelemetrySample(),
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
		});

		await expect(sink.ingestWorkerBatch(extentBatch)).resolves.toMatchObject({
			type: 'accepted',
		});

		expect(fetchImpl).toHaveBeenCalledTimes(2);
		const postedBody =
			postedBodies.find((body) =>
				body.includes('performance.bridge.web.worktree_file_scroll_extent'),
			) ?? '';
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

	test('accepts scrubbed Worktree/File content fetch phase telemetry', async () => {
		const postedBodies: string[] = [];
		const fetchImpl = vi.fn(
			async (_input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
				postedBodies.push(typeof init?.body === 'string' ? init.body : '');
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
		const contentFetchBatch = makeTelemetryBatch({
			...makeTelemetrySample(),
			name: 'performance.bridge.web.content_fetch',
			durationMilliseconds: 92,
			stringAttributes: {
				'agentstudio.bridge.content.correlation_mode': 'summary',
				'agentstudio.bridge.content.role': 'file',
				'agentstudio.bridge.demand.lane': 'foreground',
				'agentstudio.bridge.file_size_bucket': 'medium',
				'agentstudio.bridge.generation_relation': 'current',
				'agentstudio.bridge.phase': 'fetch',
				'agentstudio.bridge.plane': 'data',
				'agentstudio.bridge.priority': 'hot',
				'agentstudio.bridge.protocol': 'worktree-file',
				'agentstudio.bridge.result': 'success',
				'agentstudio.bridge.result_reason': 'none',
				'agentstudio.bridge.slice': 'content_fetch',
				'agentstudio.bridge.transport': 'content',
				'agentstudio.bridge.viewer': 'file',
			},
			numericAttributes: {
				'agentstudio.bridge.content.byte_length': 4096,
				'agentstudio.bridge.content.estimated_bytes': 4096,
				'agentstudio.bridge.content.first_chunk_wait_ms': 1,
				'agentstudio.bridge.content.response_wait_ms': 88,
				'agentstudio.bridge.content.stream_read_ms': 2,
			},
			booleanAttributes: {
				'agentstudio.bridge.header_missing': true,
				'agentstudio.bridge.header_supported': false,
			},
		});

		await expect(sink.ingestWorkerBatch(contentFetchBatch)).resolves.toMatchObject({
			type: 'accepted',
		});

		expect(fetchImpl).toHaveBeenCalledTimes(2);
		const postedBody =
			postedBodies.find((body) => body.includes('performance.bridge.web.content_fetch')) ?? '';
		const metricsBody =
			postedBodies.find((body) => body.includes('agentstudio_performance_events_total')) ?? '';
		expect(postedBody).toContain('performance.bridge.web.content_fetch');
		expect(metricsBody).toContain('agentstudio_bridge_content_response_wait_ms');
		expect(postedBody).not.toContain('/Users/');
		expect(postedBody).not.toContain('agentstudio://resource/');
		expect(sink.snapshot()).toMatchObject({
			acceptedBatchCount: 1,
			acceptedSampleCount: 1,
			failedBatchCount: 0,
			lastError: null,
		});
	});

	test('builds a typed Vite dev-server content response observation', () => {
		const observation = buildBridgeDevContentResponseTelemetryObservation({
			byteLength: 4096,
			getProviderMilliseconds: 3,
			providerLoadMilliseconds: 88,
			responseTotalMilliseconds: 94,
			result: 'success',
			resultReason: 'none',
			scenario: 'vite-dev-worktree-current-worktree',
			viewer: 'file',
		});

		expect(observation).toEqual({
			source: 'server',
			scenario: 'vite-dev-worktree-current-worktree',
			samples: [
				expect.objectContaining({
					name: 'performance.bridge.web.dev_content_response',
					durationMilliseconds: 3,
					stringAttributes: expect.objectContaining({
						'agentstudio.bridge.phase': 'dev_content_get_provider',
						'agentstudio.bridge.protocol': 'worktree-file',
						'agentstudio.bridge.result': 'success',
						'agentstudio.bridge.result_reason': 'none',
						'agentstudio.bridge.viewer': 'file',
					}),
				}),
				expect.objectContaining({
					durationMilliseconds: 88,
					stringAttributes: expect.objectContaining({
						'agentstudio.bridge.phase': 'dev_content_provider_load',
					}),
				}),
				expect.objectContaining({
					durationMilliseconds: 94,
					numericAttributes: expect.objectContaining({
						'agentstudio.bridge.content.byte_length': 4096,
						'agentstudio.bridge.dev_server.get_provider_ms': 3,
						'agentstudio.bridge.dev_server.provider_load_ms': 88,
						'agentstudio.bridge.dev_server.response_total_ms': 94,
					}),
					stringAttributes: expect.objectContaining({
						'agentstudio.bridge.phase': 'dev_content_response_total',
					}),
				}),
			],
		});
	});

	test('builds a Review-tagged Vite dev-server content observation', () => {
		const observation = buildBridgeDevContentResponseTelemetryObservation({
			byteLength: 2048,
			getProviderMilliseconds: 5,
			providerLoadMilliseconds: 41,
			responseTotalMilliseconds: 49,
			result: 'success',
			resultReason: 'none',
			scenario: 'vite-dev-worktree-current-worktree',
			viewer: 'review',
		});

		expect(observation.samples).toEqual([
			expect.objectContaining({
				durationMilliseconds: 5,
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.phase': 'dev_content_get_provider',
					'agentstudio.bridge.protocol': 'review',
					'agentstudio.bridge.viewer': 'review',
				}),
			}),
			expect.objectContaining({
				durationMilliseconds: 41,
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.phase': 'dev_content_provider_load',
					'agentstudio.bridge.protocol': 'review',
					'agentstudio.bridge.viewer': 'review',
				}),
			}),
			expect.objectContaining({
				durationMilliseconds: 49,
				numericAttributes: expect.objectContaining({
					'agentstudio.bridge.content.byte_length': 2048,
					'agentstudio.bridge.dev_server.provider_load_ms': 41,
				}),
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.phase': 'dev_content_response_total',
					'agentstudio.bridge.protocol': 'review',
					'agentstudio.bridge.viewer': 'review',
				}),
			}),
		]);
	});

	test('records server timing through the native observation path', async () => {
		const fetchImpl = vi.fn(async (): Promise<Response> => new Response('', { status: 200 }));
		const sink = createBridgeDevTelemetrySink({
			fetchImpl,
			marker: 'vite-dev-proof-1',
			nowUnixNano: () => '1782218790000000000',
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});
		const observation = buildBridgeDevContentResponseTelemetryObservation({
			byteLength: 2048,
			getProviderMilliseconds: 5,
			providerLoadMilliseconds: 41,
			responseTotalMilliseconds: 49,
			result: 'success',
			resultReason: 'none',
			scenario: 'vite-dev-worktree-current-worktree',
			viewer: 'review',
		});

		await expect(sink.recordNativeObservation(observation)).resolves.toBe(true);

		expect(fetchImpl).toHaveBeenCalledTimes(2);
		expect(sink.snapshot()).toMatchObject({
			acceptedBatchCount: 1,
			acceptedSampleCount: 3,
			recentSamples: observation.samples,
		});
	});
});

function makeTelemetryBatch(
	sample: BridgeTelemetrySample = makeTelemetrySample(),
	batchSequence = 1,
): BridgeTelemetryWorkerBatchRequest {
	const type =
		sample.stringAttributes['agentstudio.bridge.priority'] === 'best_effort'
			? 'event.optional'
			: 'event.required';
	return {
		type: 'telemetry.batch',
		schemaVersion: 2,
		telemetrySessionId: 'vite-dev-session-1',
		batchSequence,
		samples: [
			{
				producerId: 'main',
				producerSequence: 1,
				sample: {
					type,
					timestampMilliseconds: 1,
					sample,
				},
			},
		],
		lossSummaries: [],
	};
}

function makeTelemetrySample(): BridgeTelemetrySample {
	return {
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
	};
}
