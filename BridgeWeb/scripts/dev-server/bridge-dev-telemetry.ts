import { createHash } from 'node:crypto';
import { cwd } from 'node:process';

import { bridgeTelemetryBatchSchema } from '../../src/foundation/telemetry/bridge-telemetry-event.js';
import type {
	BridgeTelemetryBatch,
	BridgeTelemetrySample,
} from '../../src/foundation/telemetry/bridge-telemetry-event.js';

interface BridgeDevTelemetrySinkProps {
	readonly collectorLogsUrl?: string;
	readonly collectorMetricsUrl?: string;
	readonly fetchImpl?: typeof fetch;
	readonly marker?: string;
	readonly nowUnixNano?: () => string;
	readonly serviceVersion?: string;
	readonly worktreeHash?: string;
}

export interface BridgeDevTelemetrySink {
	readonly ingest: (batch: unknown) => Promise<boolean>;
	readonly snapshot: () => BridgeDevTelemetrySnapshot;
}

export interface BridgeDevTelemetrySnapshot {
	readonly acceptedBatchCount: number;
	readonly acceptedSampleCount: number;
	readonly failedBatchCount: number;
	readonly lastError: string | null;
	readonly marker: string;
	readonly recentSamples: readonly BridgeTelemetrySample[];
	readonly serviceVersion: string;
	readonly worktreeHash: string;
}

export interface BridgeDevContentResponseTelemetryBatchProps {
	readonly byteLength: number;
	readonly getProviderMilliseconds: number;
	readonly providerLoadMilliseconds: number;
	readonly responseTotalMilliseconds: number;
	readonly result: 'failed' | 'success';
	readonly resultReason: string;
	readonly scenario: string;
	readonly viewer: 'file' | 'review';
}

interface BuildBridgeDevTelemetryLogRecordProps {
	readonly batch: BridgeTelemetryBatch;
	readonly marker: string;
	readonly receivedAtUnixNano: string;
	readonly sample: BridgeTelemetrySample;
	readonly serviceVersion: string;
	readonly worktreeHash: string;
}

interface OTelAnyValue {
	readonly stringValue?: string;
	readonly intValue?: string;
	readonly doubleValue?: number;
	readonly boolValue?: boolean;
}

interface OTelKeyValue {
	readonly key: string;
	readonly value: OTelAnyValue;
}

interface OTelLogRecord {
	readonly body: OTelAnyValue;
	readonly attributes: readonly OTelKeyValue[];
	readonly severityNumber: number;
	readonly severityText: 'info';
	readonly timeUnixNano: string;
}

const defaultCollectorLogsUrl = 'http://127.0.0.1:4318/v1/logs';
const defaultCollectorMetricsUrl = 'http://127.0.0.1:4318/v1/metrics';
const bridgeDevRuntimeFlavor = 'vite-dev';
const bridgeDevReleaseChannel = 'local';
const elapsedHistogramBounds = [
	0, 5, 10, 25, 50, 75, 100, 150, 200, 250, 350, 500, 650, 750, 900, 1000, 1050, 1100, 1250, 1500,
	2000, 2500, 5000, 7500, 10_000,
] as const satisfies readonly number[];
const recentTelemetrySampleLimit = 1_000;

export function buildBridgeDevContentResponseTelemetryBatch(
	props: BridgeDevContentResponseTelemetryBatchProps,
): BridgeTelemetryBatch {
	const stringAttributes = bridgeDevContentResponseStringAttributes({
		result: props.result,
		resultReason: props.resultReason,
		viewer: props.viewer,
	});
	return {
		schemaVersion: 1,
		scenario: props.scenario,
		samples: [
			bridgeDevContentResponseSample({
				durationMilliseconds: props.getProviderMilliseconds,
				phase: 'dev_content_get_provider',
				stringAttributes,
			}),
			bridgeDevContentResponseSample({
				durationMilliseconds: props.providerLoadMilliseconds,
				phase: 'dev_content_provider_load',
				stringAttributes,
			}),
			bridgeDevContentResponseSample({
				durationMilliseconds: props.responseTotalMilliseconds,
				numericAttributes: {
					'agentstudio.bridge.content.byte_length': props.byteLength,
					'agentstudio.bridge.dev_server.get_provider_ms': props.getProviderMilliseconds,
					'agentstudio.bridge.dev_server.provider_load_ms': props.providerLoadMilliseconds,
					'agentstudio.bridge.dev_server.response_total_ms': props.responseTotalMilliseconds,
				},
				phase: 'dev_content_response_total',
				stringAttributes,
			}),
		],
	};
}

export function createBridgeDevTelemetrySink(
	props: BridgeDevTelemetrySinkProps = {},
): BridgeDevTelemetrySink {
	const collectorLogsUrl =
		props.collectorLogsUrl ??
		process.env['BRIDGE_WEB_DEV_TELEMETRY_OTLP_LOGS_URL'] ??
		defaultCollectorLogsUrl;
	const collectorMetricsUrl =
		props.collectorMetricsUrl ??
		process.env['BRIDGE_WEB_DEV_TELEMETRY_OTLP_METRICS_URL'] ??
		defaultCollectorMetricsUrl;
	const fetchImpl = props.fetchImpl ?? fetch;
	const marker =
		props.marker ??
		process.env['BRIDGE_WEB_DEV_TELEMETRY_MARKER'] ??
		`vite-dev-${Date.now().toString(36)}`;
	const nowUnixNano = props.nowUnixNano ?? currentUnixNano;
	const serviceVersion = props.serviceVersion ?? bridgeDevRuntimeFlavor;
	const worktreeHash = props.worktreeHash ?? hashValue(cwd());
	let acceptedBatchCount = 0;
	let acceptedSampleCount = 0;
	let failedBatchCount = 0;
	let lastError: string | null = null;
	let recentSamples: readonly BridgeTelemetrySample[] = [];
	const ingest = async (batch: unknown): Promise<boolean> => {
		const parsedBatch = bridgeTelemetryBatchSchema.safeParse(batch);
		if (!parsedBatch.success) {
			failedBatchCount += 1;
			lastError = 'invalid_batch';
			return false;
		}
		if (!bridgeDevTelemetryBatchIsSafe(parsedBatch.data)) {
			failedBatchCount += 1;
			lastError = 'unsafe_attributes';
			return false;
		}
		const receivedAtUnixNano = nowUnixNano();
		const body = buildBridgeDevTelemetryOTLPRequest({
			batch: parsedBatch.data,
			marker,
			receivedAtUnixNano,
			serviceVersion,
			worktreeHash,
		});
		const metricsBody = buildBridgeDevTelemetryOTLPMetricsRequest({
			batch: parsedBatch.data,
			marker,
			receivedAtUnixNano,
			serviceVersion,
			worktreeHash,
		});
		recentSamples = [...recentSamples, ...parsedBatch.data.samples].slice(
			-recentTelemetrySampleLimit,
		);
		try {
			const response = await fetchImpl(collectorLogsUrl, {
				body: JSON.stringify(body),
				headers: { 'content-type': 'application/json' },
				method: 'POST',
			});
			if (!response.ok) {
				throw new Error(`collector_logs_http_${response.status}`);
			}
			const metricsResponse = await fetchImpl(collectorMetricsUrl, {
				body: JSON.stringify(metricsBody),
				headers: { 'content-type': 'application/json' },
				method: 'POST',
			});
			if (!metricsResponse.ok) {
				throw new Error(`collector_metrics_http_${metricsResponse.status}`);
			}
			acceptedBatchCount += 1;
			acceptedSampleCount += parsedBatch.data.samples.length;
			lastError = null;
			return true;
		} catch (error: unknown) {
			failedBatchCount += 1;
			lastError = error instanceof Error ? error.message : 'collector_failed';
			return false;
		}
	};
	return {
		ingest,
		snapshot: (): BridgeDevTelemetrySnapshot => ({
			acceptedBatchCount,
			acceptedSampleCount,
			failedBatchCount,
			lastError,
			marker,
			recentSamples,
			serviceVersion,
			worktreeHash,
		}),
	};
}

export function buildBridgeDevTelemetryLogRecord(
	props: BuildBridgeDevTelemetryLogRecordProps,
): OTelLogRecord {
	return {
		body: { stringValue: props.sample.name },
		attributes: [
			stringAttribute('agent.proof.marker', props.marker),
			stringAttribute('agentstudio.bridge.test.scenario', props.batch.scenario),
			stringAttribute('dev.release.channel', bridgeDevReleaseChannel),
			stringAttribute('dev.runtime.flavor', bridgeDevRuntimeFlavor),
			stringAttribute('dev.worktree.hash', props.worktreeHash),
			stringAttribute('service.name', 'AgentStudioBridgeWebDevServer'),
			stringAttribute('service.version', props.serviceVersion),
			...Object.entries(props.sample.stringAttributes)
				.filter(([key, value]): boolean => bridgeDevStringAttributeIsSafe(key, value))
				.map(([key, value]): OTelKeyValue => stringAttribute(key, value)),
			...Object.entries(props.sample.numericAttributes)
				.filter(([key]): boolean => bridgeDevNumericAttributeKeys.has(key))
				.map(([key, value]): OTelKeyValue => numberAttribute(key, value)),
			...Object.entries(props.sample.booleanAttributes)
				.filter(([key]): boolean => bridgeDevBooleanAttributeKeys.has(key))
				.map(([key, value]): OTelKeyValue => booleanAttribute(key, value)),
			...(props.sample.durationMilliseconds === null
				? []
				: [
						numberAttribute(
							'agentstudio.performance.elapsed_ms',
							props.sample.durationMilliseconds,
						),
					]),
		],
		severityNumber: 9,
		severityText: 'info',
		timeUnixNano: props.receivedAtUnixNano,
	};
}

function bridgeDevTelemetryBatchIsSafe(batch: BridgeTelemetryBatch): boolean {
	if (!bridgeDevTelemetryStringValueIsSafe(batch.scenario)) {
		return false;
	}
	for (const sample of batch.samples) {
		if (!bridgeDevTelemetryStringValueIsSafe(sample.name)) {
			return false;
		}
		for (const [key, value] of Object.entries(sample.stringAttributes)) {
			if (!bridgeDevStringAttributeIsSafe(key, value)) {
				return false;
			}
		}
		for (const key of Object.keys(sample.numericAttributes)) {
			if (!bridgeDevNumericAttributeKeys.has(key)) {
				return false;
			}
		}
		for (const key of Object.keys(sample.booleanAttributes)) {
			if (!bridgeDevBooleanAttributeKeys.has(key)) {
				return false;
			}
		}
	}
	return true;
}

function bridgeDevStringAttributeIsSafe(key: string, value: string): boolean {
	return bridgeDevStringAttributeKeys.has(key) && bridgeDevTelemetryStringValueIsSafe(value);
}

function bridgeDevTelemetryStringValueIsSafe(value: string): boolean {
	return !bridgeDevTelemetryUnsafeValuePatterns.some((pattern): boolean => pattern.test(value));
}

const bridgeDevStringAttributeKeys = new Set<string>([
	'agentstudio.bridge.content.correlation_mode',
	'agentstudio.bridge.content.interest',
	'agentstudio.bridge.content.priority',
	'agentstudio.bridge.content.role',
	'agentstudio.bridge.content_bytes_bucket',
	'agentstudio.bridge.demand.lane',
	'agentstudio.bridge.file_size_bucket',
	'agentstudio.bridge.fixture_class',
	'agentstudio.bridge.generation_relation',
	'agentstudio.bridge.header_missing',
	'agentstudio.bridge.header_supported',
	'agentstudio.bridge.item_count_bucket',
	'agentstudio.bridge.item_update.kind',
	'agentstudio.bridge.language_class',
	'agentstudio.bridge.markdown.fallback_reason',
	'agentstudio.bridge.phase',
	'agentstudio.bridge.plane',
	'agentstudio.bridge.priority',
	'agentstudio.bridge.protocol',
	'agentstudio.bridge.projection.kind',
	'agentstudio.bridge.queue.depth_bucket',
	'agentstudio.bridge.result',
	'agentstudio.bridge.result_reason',
	'agentstudio.bridge.rpc.method_class',
	'agentstudio.bridge.slice',
	'agentstudio.bridge.telemetry.drop_reason',
	'agentstudio.bridge.transport',
	'agentstudio.bridge.viewer',
	'agentstudio.bridge.worker.lane',
	'agentstudio.bridge.worker.task_kind',
]);

const bridgeDevNumericAttributeKeys = new Set<string>([
	'agentstudio.bridge.content.byte_length',
	'agentstudio.bridge.content.byte_count',
	'agentstudio.bridge.content.chunk_byte_count',
	'agentstudio.bridge.content.chunk_count',
	'agentstudio.bridge.content.estimated_bytes',
	'agentstudio.bridge.content.first_chunk_wait_ms',
	'agentstudio.bridge.content.response_wait_ms',
	'agentstudio.bridge.content.stream_read_ms',
	'agentstudio.bridge.content.resource_count',
	'agentstudio.bridge.content.total_bytes_read',
	'agentstudio.bridge.dev_server.get_provider_ms',
	'agentstudio.bridge.dev_server.provider_load_ms',
	'agentstudio.bridge.dev_server.response_total_ms',
	'agentstudio.bridge.markdown.input_bytes',
	'agentstudio.bridge.markdown.output_bytes',
	'agentstudio.bridge.review.item_count',
	'agentstudio.bridge.telemetry.dropped_count',
	'agentstudio.bridge.worktree.content_height_delta_px',
	'agentstudio.bridge.worktree.content_total_size_px',
	'agentstudio.bridge.worktree.descriptor_count',
	'agentstudio.bridge.worktree.frame_count',
	'agentstudio.bridge.worktree.tree_height_delta_px',
	'agentstudio.bridge.worktree.tree_total_size_px',
]);

const bridgeDevBooleanAttributeKeys = new Set<string>([
	'agentstudio.bridge.header_missing',
	'agentstudio.bridge.header_supported',
]);

const bridgeDevTelemetryUnsafeValuePatterns = [
	/(^|[ "'=])\/Users\//,
	/agentstudio:\/\/resource\//i,
	/prompt-canary/i,
	/(^|[._-])prompt([._-]|$)/i,
	/(^|[._-])comment([._-]|$)/i,
	/(^|[._-])comms?([._-]|$)/i,
] as const satisfies readonly RegExp[];

function buildBridgeDevTelemetryOTLPRequest(props: {
	readonly batch: BridgeTelemetryBatch;
	readonly marker: string;
	readonly receivedAtUnixNano: string;
	readonly serviceVersion: string;
	readonly worktreeHash: string;
}): {
	readonly resourceLogs: readonly [
		{
			readonly resource: { readonly attributes: readonly OTelKeyValue[] };
			readonly scopeLogs: readonly [
				{
					readonly scope: { readonly name: 'bridge-web-vite-dev'; readonly version: string };
					readonly logRecords: readonly OTelLogRecord[];
				},
			];
		},
	];
} {
	return {
		resourceLogs: [
			{
				resource: {
					attributes: [
						stringAttribute('service.name', 'AgentStudioBridgeWebDevServer'),
						stringAttribute('service.version', props.serviceVersion),
						stringAttribute('dev.release.channel', bridgeDevReleaseChannel),
						stringAttribute('dev.runtime.flavor', bridgeDevRuntimeFlavor),
						stringAttribute('dev.worktree.hash', props.worktreeHash),
					],
				},
				scopeLogs: [
					{
						scope: { name: 'bridge-web-vite-dev', version: props.serviceVersion },
						logRecords: props.batch.samples.map(
							(sample: BridgeTelemetrySample): OTelLogRecord =>
								buildBridgeDevTelemetryLogRecord({ ...props, sample }),
						),
					},
				],
			},
		],
	};
}

function buildBridgeDevTelemetryOTLPMetricsRequest(props: {
	readonly batch: BridgeTelemetryBatch;
	readonly marker: string;
	readonly receivedAtUnixNano: string;
	readonly serviceVersion: string;
	readonly worktreeHash: string;
}): {
	readonly resourceMetrics: readonly [
		{
			readonly resource: { readonly attributes: readonly OTelKeyValue[] };
			readonly scopeMetrics: readonly [
				{
					readonly scope: { readonly name: 'bridge-web-vite-dev'; readonly version: string };
					readonly metrics: readonly OTelMetric[];
				},
			];
		},
	];
} {
	return {
		resourceMetrics: [
			{
				resource: {
					attributes: resourceAttributesForBridgeDevTelemetry(props),
				},
				scopeMetrics: [
					{
						scope: { name: 'bridge-web-vite-dev', version: props.serviceVersion },
						metrics: metricsForBridgeTelemetryBatch(props),
					},
				],
			},
		],
	};
}

type OTelMetric =
	| {
			readonly name: string;
			readonly sum: {
				readonly aggregationTemporality: 2;
				readonly isMonotonic: boolean;
				readonly dataPoints: readonly OTelMetricDataPoint[];
			};
	  }
	| {
			readonly name: string;
			readonly gauge: {
				readonly dataPoints: readonly OTelMetricDataPoint[];
			};
	  }
	| {
			readonly name: string;
			readonly histogram: {
				readonly aggregationTemporality: 2;
				readonly dataPoints: readonly OTelHistogramDataPoint[];
			};
	  };

interface OTelMetricDataPoint {
	readonly timeUnixNano: string;
	readonly attributes: readonly OTelKeyValue[];
	readonly asInt?: string;
	readonly asDouble?: number;
}

interface OTelHistogramDataPoint {
	readonly timeUnixNano: string;
	readonly attributes: readonly OTelKeyValue[];
	readonly count: string;
	readonly sum: number;
	readonly bucketCounts: readonly string[];
	readonly explicitBounds: readonly number[];
	readonly min: number;
	readonly max: number;
}

function metricsForBridgeTelemetryBatch(props: {
	readonly batch: BridgeTelemetryBatch;
	readonly receivedAtUnixNano: string;
}): readonly OTelMetric[] {
	const counterPoints: OTelMetricDataPoint[] = [];
	const elapsedHistogramPoints: OTelHistogramDataPoint[] = [];
	const elapsedMaxPoints: OTelMetricDataPoint[] = [];
	const numericGaugePointsByMetricName = new Map<string, OTelMetricDataPoint[]>();

	for (const sample of props.batch.samples) {
		const dimensions = dimensionsForBridgeTelemetrySample(sample);
		if (dimensions === null) {
			continue;
		}
		counterPoints.push({
			timeUnixNano: props.receivedAtUnixNano,
			attributes: dimensions,
			asInt: '1',
		});
		if (sample.durationMilliseconds !== null) {
			elapsedHistogramPoints.push(
				histogramPointForDuration({
					attributes: dimensions,
					durationMilliseconds: sample.durationMilliseconds,
					timeUnixNano: props.receivedAtUnixNano,
				}),
			);
			elapsedMaxPoints.push({
				timeUnixNano: props.receivedAtUnixNano,
				attributes: dimensions,
				asDouble: sample.durationMilliseconds,
			});
		}
		for (const [key, value] of Object.entries(sample.numericAttributes)) {
			const metricName = metricNameForBridgeTelemetryNumericAttribute(key);
			if (metricName === null) {
				continue;
			}
			const points = numericGaugePointsByMetricName.get(metricName) ?? [];
			points.push({
				timeUnixNano: props.receivedAtUnixNano,
				attributes: dimensions,
				asDouble: value,
			});
			numericGaugePointsByMetricName.set(metricName, points);
		}
	}

	const metrics: OTelMetric[] = [
		{
			name: 'agentstudio_performance_events_total',
			sum: {
				aggregationTemporality: 2,
				isMonotonic: true,
				dataPoints: counterPoints,
			},
		},
		{
			name: 'agentstudio_performance_event_elapsed_ms',
			histogram: {
				aggregationTemporality: 2,
				dataPoints: elapsedHistogramPoints,
			},
		},
		{
			name: 'agentstudio_performance_event_elapsed_ms_max',
			gauge: {
				dataPoints: elapsedMaxPoints,
			},
		},
	];
	for (const [metricName, dataPoints] of [...numericGaugePointsByMetricName.entries()].sort(
		([leftName], [rightName]): number => leftName.localeCompare(rightName),
	)) {
		metrics.push({
			name: metricName,
			gauge: { dataPoints },
		});
	}
	return metrics;
}

function dimensionsForBridgeTelemetrySample(
	sample: BridgeTelemetrySample,
): readonly OTelKeyValue[] | null {
	if (!sample.name.startsWith('performance.')) {
		return null;
	}
	if (sample.name.startsWith('performance.bridge.')) {
		const phase = sample.stringAttributes['agentstudio.bridge.phase'];
		const plane = sample.stringAttributes['agentstudio.bridge.plane'];
		const priority = sample.stringAttributes['agentstudio.bridge.priority'];
		const slice = sample.stringAttributes['agentstudio.bridge.slice'];
		if (
			phase === undefined ||
			plane === undefined ||
			priority === undefined ||
			slice === undefined
		) {
			return null;
		}
		return [
			stringAttribute('event', sample.name),
			stringAttribute('phase', phase),
			stringAttribute('plane', plane),
			stringAttribute('priority', priority),
			stringAttribute('slice', slice),
			...(sample.stringAttributes['agentstudio.bridge.transport'] === undefined
				? []
				: [stringAttribute('transport', sample.stringAttributes['agentstudio.bridge.transport'])]),
		];
	}
	return [stringAttribute('event', sample.name)];
}

function histogramPointForDuration(props: {
	readonly attributes: readonly OTelKeyValue[];
	readonly durationMilliseconds: number;
	readonly timeUnixNano: string;
}): OTelHistogramDataPoint {
	const bucketCounts = Array.from({ length: elapsedHistogramBounds.length + 1 }, (): string => '0');
	const bucketIndex = elapsedHistogramBounds.findIndex(
		(bound): boolean => props.durationMilliseconds <= bound,
	);
	bucketCounts[bucketIndex === -1 ? elapsedHistogramBounds.length : bucketIndex] = '1';
	return {
		timeUnixNano: props.timeUnixNano,
		attributes: props.attributes,
		count: '1',
		sum: props.durationMilliseconds,
		bucketCounts,
		explicitBounds: [...elapsedHistogramBounds],
		min: props.durationMilliseconds,
		max: props.durationMilliseconds,
	};
}

function metricNameForBridgeTelemetryNumericAttribute(key: string): string | null {
	if (key === 'agentstudio.performance.elapsed_ms') {
		return null;
	}
	if (key.startsWith('agentstudio.performance.')) {
		return metricNameFromAttributeSuffix(
			'agentstudio_performance',
			key.slice('agentstudio.performance.'.length),
		);
	}
	if (!key.startsWith('agentstudio.bridge.')) {
		return null;
	}
	return metricNameFromAttributeSuffix(
		'agentstudio_bridge',
		key.slice('agentstudio.bridge.'.length),
	);
}

function metricNameFromAttributeSuffix(prefix: string, suffix: string): string | null {
	const sanitized = suffix
		.replace(/[^A-Za-z0-9]+/gu, '_')
		.replace(/_+/gu, '_')
		.replace(/^_|_$/gu, '');
	return sanitized.length === 0 ? null : `${prefix}_${sanitized}`;
}

function resourceAttributesForBridgeDevTelemetry(props: {
	readonly marker: string;
	readonly serviceVersion: string;
	readonly worktreeHash: string;
}): readonly OTelKeyValue[] {
	return [
		stringAttribute('service.name', 'AgentStudioBridgeWebDevServer'),
		stringAttribute('service.version', props.serviceVersion),
		stringAttribute('dev.release.channel', bridgeDevReleaseChannel),
		stringAttribute('dev.runtime.flavor', bridgeDevRuntimeFlavor),
		stringAttribute('dev.worktree.hash', props.worktreeHash),
		stringAttribute('agent.proof.marker', props.marker),
	];
}

function stringAttribute(key: string, value: string): OTelKeyValue {
	return { key, value: { stringValue: value } };
}

function numberAttribute(key: string, value: number): OTelKeyValue {
	return Number.isInteger(value)
		? { key, value: { intValue: String(value) } }
		: { key, value: { doubleValue: value } };
}

function booleanAttribute(key: string, value: boolean): OTelKeyValue {
	return { key, value: { boolValue: value } };
}

function currentUnixNano(): string {
	return `${BigInt(Date.now()) * 1_000_000n}`;
}

function hashValue(value: string): string {
	return createHash('sha256').update(value).digest('hex').slice(0, 16);
}

function bridgeDevContentResponseStringAttributes(props: {
	readonly result: 'failed' | 'success';
	readonly resultReason: string;
	readonly viewer: 'file' | 'review';
}): Readonly<Record<string, string>> {
	return {
		'agentstudio.bridge.content.correlation_mode': 'summary',
		'agentstudio.bridge.content.role': props.viewer === 'file' ? 'file' : 'unknown',
		'agentstudio.bridge.phase': 'dev_content_response_total',
		'agentstudio.bridge.plane': 'data',
		'agentstudio.bridge.priority': 'hot',
		'agentstudio.bridge.protocol': props.viewer === 'file' ? 'worktree-file' : 'review',
		'agentstudio.bridge.result': props.result,
		'agentstudio.bridge.result_reason': props.resultReason,
		'agentstudio.bridge.slice': 'content_fetch',
		'agentstudio.bridge.transport': 'content',
		'agentstudio.bridge.viewer': props.viewer,
	};
}

function bridgeDevContentResponseSample(props: {
	readonly durationMilliseconds: number;
	readonly numericAttributes?: Readonly<Record<string, number>>;
	readonly phase: string;
	readonly stringAttributes: Readonly<Record<string, string>>;
}): BridgeTelemetrySample {
	return {
		scope: 'web',
		name: 'performance.bridge.web.dev_content_response',
		durationMilliseconds: Math.max(0, props.durationMilliseconds),
		traceContext: null,
		stringAttributes: {
			...props.stringAttributes,
			'agentstudio.bridge.phase': props.phase,
		},
		numericAttributes: props.numericAttributes ?? {},
		booleanAttributes: {},
	};
}
