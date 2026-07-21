import type { BridgeTelemetrySample } from '../../src/foundation/telemetry/bridge-telemetry-event.js';

export interface BridgeDevTelemetryObservation {
	readonly scenario: string;
	readonly samples: readonly BridgeTelemetrySample[];
}

interface BuildBridgeDevTelemetryLogRecordProps {
	readonly marker: string;
	readonly observation: BridgeDevTelemetryObservation;
	readonly receivedAtUnixNano: string;
	readonly sample: BridgeTelemetrySample;
	readonly serviceVersion: string;
	readonly worktreeHash: string;
}

interface BuildBridgeDevTelemetryOTLPRequestProps {
	readonly marker: string;
	readonly observation: BridgeDevTelemetryObservation;
	readonly receivedAtUnixNano: string;
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

const bridgeDevRuntimeFlavor = 'vite-dev';
const bridgeDevReleaseChannel = 'local';
const elapsedHistogramBounds = [
	0, 5, 10, 25, 50, 75, 100, 150, 200, 250, 350, 500, 650, 750, 900, 1000, 1050, 1100, 1250, 1500,
	2000, 2500, 5000, 7500, 10_000,
] as const satisfies readonly number[];

const bridgeDevStringAttributeKeys = new Set<string>([
	'agentstudio.bridge.content.correlation_mode',
	'agentstudio.bridge.content.interest',
	'agentstudio.bridge.content.priority',
	'agentstudio.bridge.content.role',
	'agentstudio.bridge.content_bytes_bucket',
	'agentstudio.bridge.demand.lane',
	'agentstudio.bridge.drop_reason',
	'agentstudio.bridge.file_size_bucket',
	'agentstudio.bridge.fixture_class',
	'agentstudio.bridge.generation_relation',
	'agentstudio.bridge.header_missing',
	'agentstudio.bridge.header_supported',
	'agentstudio.bridge.item_count_bucket',
	'agentstudio.bridge.item_update.kind',
	'agentstudio.bridge.interaction.attempt_id',
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
	'agentstudio.bridge.surface',
	'agentstudio.bridge.telemetry.drop_reason',
	'agentstudio.bridge.transport',
	'agentstudio.bridge.viewer',
	'agentstudio.bridge.worker.action',
	'agentstudio.bridge.worker.command',
	'agentstudio.bridge.worker.lane',
	'agentstudio.bridge.worker.payload_class',
	'agentstudio.bridge.worker.task_kind',
	'agentstudio.bridge.worker.work_kind',
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
	'agentstudio.bridge.interaction.sequence',
	'agentstudio.bridge.review.item_count',
	'agentstudio.bridge.telemetry.dropped_count',
	'agentstudio.bridge.telemetry.value',
	'agentstudio.bridge.worker.handler_duration_ms',
	'agentstudio.bridge.worker.patch_count',
	'agentstudio.bridge.worker.queue_wait_ms',
	'agentstudio.bridge.worker.source_epoch',
	'agentstudio.bridge.worker.touched_key_count',
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
	'agentstudio.bridge.worker.file_metadata_selected_path_resolved',
]);

const bridgeDevTelemetryUnsafeValuePatterns = [
	/(^|[ "'=])\/Users\//,
	/agentstudio:\/\/resource\//i,
	/prompt-canary/i,
	/(^|[._-])prompt([._-]|$)/i,
	/(^|[._-])comment([._-]|$)/i,
	/(^|[._-])comms?([._-]|$)/i,
] as const satisfies readonly RegExp[];

export function bridgeDevTelemetryObservationIsSafe(
	observation: BridgeDevTelemetryObservation,
): boolean {
	if (!bridgeDevTelemetryStringValueIsSafe(observation.scenario)) {
		return false;
	}
	for (const sample of observation.samples) {
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

export function buildBridgeDevTelemetryLogRecord(
	props: BuildBridgeDevTelemetryLogRecordProps,
): OTelLogRecord {
	return {
		body: { stringValue: props.sample.name },
		attributes: [
			stringAttribute('agent.proof.marker', props.marker),
			stringAttribute('agentstudio.bridge.test.scenario', props.observation.scenario),
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

export function buildBridgeDevTelemetryOTLPRequest(
	props: BuildBridgeDevTelemetryOTLPRequestProps,
): {
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
						logRecords: props.observation.samples.map(
							(sample: BridgeTelemetrySample): OTelLogRecord =>
								buildBridgeDevTelemetryLogRecord({ ...props, sample }),
						),
					},
				],
			},
		],
	};
}

export function buildBridgeDevTelemetryOTLPMetricsRequest(
	props: BuildBridgeDevTelemetryOTLPRequestProps,
): {
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
						metrics: metricsForBridgeTelemetryObservation(props),
					},
				],
			},
		],
	};
}

function metricsForBridgeTelemetryObservation(props: {
	readonly observation: BridgeDevTelemetryObservation;
	readonly receivedAtUnixNano: string;
}): readonly OTelMetric[] {
	const counterPoints: OTelMetricDataPoint[] = [];
	const elapsedHistogramPoints: OTelHistogramDataPoint[] = [];
	const elapsedMaxPoints: OTelMetricDataPoint[] = [];
	const numericGaugePointsByMetricName = new Map<string, OTelMetricDataPoint[]>();

	for (const sample of props.observation.samples) {
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
	for (const [metricName, dataPoints] of [...numericGaugePointsByMetricName.entries()].toSorted(
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

function bridgeDevStringAttributeIsSafe(key: string, value: string): boolean {
	return bridgeDevStringAttributeKeys.has(key) && bridgeDevTelemetryStringValueIsSafe(value);
}

function bridgeDevTelemetryStringValueIsSafe(value: string): boolean {
	return !bridgeDevTelemetryUnsafeValuePatterns.some((pattern): boolean => pattern.test(value));
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
