import { createHash } from 'node:crypto';
import { cwd } from 'node:process';

import {
	bridgeTelemetryWorkerBatchRequestSchema,
	type BridgeTelemetryCompactSample,
	type BridgeTelemetryWorkerBatchRequest,
	type BridgeTelemetryWorkerBatchResponse,
} from '../../src/core/telemetry-worker/bridge-telemetry-worker-contracts.js';
import type { BridgeTelemetrySample } from '../../src/foundation/telemetry/bridge-telemetry-event.js';
import {
	bridgeDevTelemetryObservationIsSafe,
	buildBridgeDevTelemetryOTLPMetricsRequest,
	buildBridgeDevTelemetryOTLPRequest,
	type BridgeDevTelemetryObservation,
} from './bridge-dev-telemetry-otlp.js';

export { buildBridgeDevTelemetryLogRecord } from './bridge-dev-telemetry-otlp.js';

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
	readonly ingestWorkerBatch: (batch: unknown) => Promise<BridgeTelemetryWorkerBatchResponse>;
	readonly recordNativeObservation: (
		observation: BridgeDevNativeTelemetryObservation,
	) => Promise<boolean>;
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

export interface BridgeDevNativeTelemetryObservation extends BridgeDevTelemetryObservation {
	readonly source: 'server';
}

export interface BridgeDevContentResponseTelemetryObservationProps {
	readonly byteLength: number;
	readonly getProviderMilliseconds: number;
	readonly providerLoadMilliseconds: number;
	readonly responseTotalMilliseconds: number;
	readonly result: 'failed' | 'success';
	readonly resultReason: string;
	readonly scenario: string;
	readonly viewer: 'file' | 'review';
}

const defaultCollectorLogsUrl = 'http://127.0.0.1:4318/v1/logs';
const defaultCollectorMetricsUrl = 'http://127.0.0.1:4318/v1/metrics';
const bridgeDevRuntimeFlavor = 'vite-dev';
const recentTelemetrySampleLimit = 1_000;

export function buildBridgeDevContentResponseTelemetryObservation(
	props: BridgeDevContentResponseTelemetryObservationProps,
): BridgeDevNativeTelemetryObservation {
	const stringAttributes = bridgeDevContentResponseStringAttributes({
		result: props.result,
		resultReason: props.resultReason,
		viewer: props.viewer,
	});
	return {
		source: 'server',
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
	const acceptedWorkerBatchBodies = new Map<string, Map<number, string>>();
	const publishObservation = async (
		observation: BridgeDevTelemetryObservation,
	): Promise<boolean> => {
		if (!bridgeDevTelemetryObservationIsSafe(observation)) {
			failedBatchCount += 1;
			lastError = 'unsafe_attributes';
			return false;
		}
		const receivedAtUnixNano = nowUnixNano();
		const body = buildBridgeDevTelemetryOTLPRequest({
			marker,
			observation,
			receivedAtUnixNano,
			serviceVersion,
			worktreeHash,
		});
		const metricsBody = buildBridgeDevTelemetryOTLPMetricsRequest({
			marker,
			observation,
			receivedAtUnixNano,
			serviceVersion,
			worktreeHash,
		});
		recentSamples = [...recentSamples, ...observation.samples].slice(-recentTelemetrySampleLimit);
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
			acceptedSampleCount += observation.samples.length;
			lastError = null;
			return true;
		} catch (error: unknown) {
			failedBatchCount += 1;
			lastError = error instanceof Error ? error.message : 'collector_failed';
			return false;
		}
	};
	const ingestWorkerBatch = async (batch: unknown): Promise<BridgeTelemetryWorkerBatchResponse> => {
		const parsedBatch = bridgeTelemetryWorkerBatchRequestSchema.safeParse(batch);
		if (!parsedBatch.success) {
			failedBatchCount += 1;
			lastError = 'invalid_batch';
			throw new Error('invalid_telemetry_batch');
		}
		const request = parsedBatch.data;
		const encodedBatch = JSON.stringify(request);
		const acceptedBodiesBySequence =
			acceptedWorkerBatchBodies.get(request.telemetrySessionId) ?? new Map<number, string>();
		acceptedWorkerBatchBodies.set(request.telemetrySessionId, acceptedBodiesBySequence);
		const precedingBody = acceptedBodiesBySequence.get(request.batchSequence);
		if (precedingBody !== undefined) {
			if (precedingBody !== encodedBatch) {
				return rejectedWorkerBatchResponse(request, acceptedBodiesBySequence.size + 1, 'conflict');
			}
			return acceptedWorkerBatchResponse('duplicate', request, acceptedBodiesBySequence.size + 1);
		}
		const expectedBatchSequence = acceptedBodiesBySequence.size + 1;
		if (request.batchSequence !== expectedBatchSequence) {
			return rejectedWorkerBatchResponse(request, expectedBatchSequence, 'sequence_gap');
		}
		const observation = projectBridgeTelemetryWorkerBatch(request);
		if (!bridgeDevTelemetryObservationIsSafe(observation)) {
			failedBatchCount += 1;
			lastError = 'unsafe_attributes';
			return {
				type: 'rejected',
				telemetrySessionId: request.telemetrySessionId,
				batchSequence: request.batchSequence,
				nextExpectedBatchSequence: expectedBatchSequence,
				reason: 'invalid_body',
				retryable: false,
			};
		}
		if (!(await publishObservation(observation))) {
			return rejectedWorkerBatchResponse(request, expectedBatchSequence, 'unavailable', true);
		}
		acceptedBodiesBySequence.set(request.batchSequence, encodedBatch);
		return acceptedWorkerBatchResponse('accepted', request, request.batchSequence + 1);
	};
	return {
		ingestWorkerBatch,
		recordNativeObservation: publishObservation,
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

function acceptedWorkerBatchResponse(
	type: 'accepted' | 'duplicate',
	request: BridgeTelemetryWorkerBatchRequest,
	nextExpectedBatchSequence: number,
): BridgeTelemetryWorkerBatchResponse {
	return {
		type,
		telemetrySessionId: request.telemetrySessionId,
		batchSequence: request.batchSequence,
		nextExpectedBatchSequence,
		acceptedSampleCount: request.samples.length,
		acceptedLossCount: request.lossSummaries.reduce(
			(total, summary) => total + summary.requiredCount + summary.optionalCount,
			0,
		),
	};
}

function rejectedWorkerBatchResponse(
	request: BridgeTelemetryWorkerBatchRequest,
	nextExpectedBatchSequence: number,
	reason: 'conflict' | 'sequence_gap' | 'unavailable',
	retryable = false,
): BridgeTelemetryWorkerBatchResponse {
	return {
		type: 'rejected',
		telemetrySessionId: request.telemetrySessionId,
		batchSequence: request.batchSequence,
		nextExpectedBatchSequence,
		reason,
		retryable,
		...(retryable ? { retryAfterMilliseconds: 50 } : {}),
	};
}

function projectBridgeTelemetryWorkerBatch(
	request: BridgeTelemetryWorkerBatchRequest,
): BridgeDevTelemetryObservation {
	return {
		scenario: 'bridge-worker-v2',
		samples: request.samples.map(({ sample }) => projectBridgeTelemetryWorkerSample(sample)),
	};
}

export function projectBridgeTelemetryWorkerSample(
	sample: BridgeTelemetryCompactSample,
): BridgeTelemetrySample {
	switch (sample.type) {
		case 'event.required':
		case 'event.optional':
			return sample.sample;
		case 'interaction.lifecycle':
			return workerOwnedSample({
				attemptId: sample.attemptId,
				durationMilliseconds: null,
				interactionSequence: sample.interactionSequence,
				name: 'performance.bridge.web.interaction_lifecycle',
				phase: sample.stage,
				priority: 'hot',
				surface: sample.surface,
			});
		case 'duration':
			return workerOwnedSample({
				attemptId: sample.attemptId,
				durationMilliseconds: sample.durationMilliseconds,
				interactionSequence: sample.interactionSequence,
				name: 'performance.bridge.web.interaction_duration',
				phase: sample.metric,
				priority: 'hot',
				surface: sample.surface,
			});
		case 'interaction.failure':
			return workerOwnedSample({
				attemptId: sample.attemptId,
				durationMilliseconds: null,
				interactionSequence: sample.interactionSequence,
				name: 'performance.bridge.web.interaction_failure',
				phase: sample.failure,
				priority: 'hot',
				surface: sample.surface,
			});
		case 'integrity':
			return workerOwnedSample({
				name: 'performance.bridge.web.telemetry_integrity',
				phase: sample.failure,
				priority: 'hot',
			});
		case 'diagnostic':
			return workerOwnedSample({
				name: 'performance.bridge.web.telemetry_diagnostic',
				numericAttributes: { 'agentstudio.bridge.telemetry.value': sample.value },
				phase: sample.code,
				priority: 'best_effort',
			});
	}
}

function workerOwnedSample(props: {
	readonly attemptId?: string;
	readonly durationMilliseconds?: number | null;
	readonly interactionSequence?: number;
	readonly name: string;
	readonly numericAttributes?: Readonly<Record<string, number>>;
	readonly phase: string;
	readonly priority: 'best_effort' | 'hot';
	readonly surface?: 'file' | 'review';
}): BridgeTelemetrySample {
	return {
		scope: 'web',
		name: props.name,
		durationMilliseconds: props.durationMilliseconds ?? null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': props.phase,
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': props.priority,
			...(props.attemptId === undefined
				? {}
				: { 'agentstudio.bridge.interaction.attempt_id': props.attemptId }),
			...(props.surface === undefined ? {} : { 'agentstudio.bridge.surface': props.surface }),
		},
		numericAttributes: {
			...(props.interactionSequence === undefined
				? {}
				: { 'agentstudio.bridge.interaction.sequence': props.interactionSequence }),
			...props.numericAttributes,
		},
		booleanAttributes: {},
	};
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
