import { createHash } from 'node:crypto';
import { cwd } from 'node:process';

import { bridgeTelemetryBatchSchema } from '../../src/foundation/telemetry/bridge-telemetry-event.js';
import type {
	BridgeTelemetryBatch,
	BridgeTelemetrySample,
} from '../../src/foundation/telemetry/bridge-telemetry-event.js';

interface BridgeDevTelemetrySinkProps {
	readonly collectorLogsUrl?: string;
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
	readonly serviceVersion: string;
	readonly worktreeHash: string;
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
const bridgeDevRuntimeFlavor = 'vite-dev';
const bridgeDevReleaseChannel = 'local';

export function createBridgeDevTelemetrySink(
	props: BridgeDevTelemetrySinkProps = {},
): BridgeDevTelemetrySink {
	const collectorLogsUrl =
		props.collectorLogsUrl ??
		process.env['BRIDGE_WEB_DEV_TELEMETRY_OTLP_LOGS_URL'] ??
		defaultCollectorLogsUrl;
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
		try {
			const response = await fetchImpl(collectorLogsUrl, {
				body: JSON.stringify(body),
				headers: { 'content-type': 'application/json' },
				method: 'POST',
			});
			if (!response.ok) {
				throw new Error(`collector_http_${response.status}`);
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
	'agentstudio.bridge.fixture_class',
	'agentstudio.bridge.header_missing',
	'agentstudio.bridge.header_supported',
	'agentstudio.bridge.item_count_bucket',
	'agentstudio.bridge.item_update.kind',
	'agentstudio.bridge.language_class',
	'agentstudio.bridge.markdown.fallback_reason',
	'agentstudio.bridge.phase',
	'agentstudio.bridge.plane',
	'agentstudio.bridge.priority',
	'agentstudio.bridge.projection.kind',
	'agentstudio.bridge.queue.depth_bucket',
	'agentstudio.bridge.result',
	'agentstudio.bridge.result_reason',
	'agentstudio.bridge.rpc.method_class',
	'agentstudio.bridge.slice',
	'agentstudio.bridge.telemetry.drop_reason',
	'agentstudio.bridge.transport',
	'agentstudio.bridge.worker.lane',
	'agentstudio.bridge.worker.task_kind',
]);

const bridgeDevNumericAttributeKeys = new Set<string>([
	'agentstudio.bridge.content.byte_count',
	'agentstudio.bridge.content.chunk_byte_count',
	'agentstudio.bridge.content.chunk_count',
	'agentstudio.bridge.content.resource_count',
	'agentstudio.bridge.content.total_bytes_read',
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
