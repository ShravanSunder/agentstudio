import type { Page } from 'playwright';
import { expect } from 'vitest';

export interface BackpressureTelemetryObservation {
	readonly currentCount: number;
	readonly failureCount: number;
	readonly highWaterMark: number;
	readonly maximumPublicationAgeMilliseconds: number;
	readonly maximumReceiptPendingAgeMilliseconds: number;
	readonly maximumWorkerQueueWaitMilliseconds: number;
	readonly receiptHighWaterMark: number;
	readonly receiptPendingCount: number;
	readonly receiptProducedCount: number;
	readonly responseBeforeOwnerEffectObserved: boolean;
}

interface BackpressureTelemetryRecorder {
	readonly recordTelemetry: (status: unknown, viewer: 'file' | 'review') => void;
}

interface TelemetryStatusSample {
	readonly name: string;
	readonly numericAttributes: Readonly<Record<string, number>>;
	readonly stringAttributes: Readonly<Record<string, string>>;
}

export async function waitForBackpressureTelemetry(props: {
	readonly expectedReceiptProducedCount: number | null;
	readonly milestones: BackpressureTelemetryRecorder;
	readonly page: Page;
	readonly timeoutMilliseconds: number;
	readonly viewer: 'file' | 'review';
}): Promise<BackpressureTelemetryObservation> {
	const statusUrl = new URL('/__bridge-dev-telemetry/status', props.page.url()).toString();
	let latestStatus: unknown = null;
	let observation: BackpressureTelemetryObservation | null = null;
	let telemetryProofFailure: string | null = null;
	try {
		await expect
			.poll(
				async (): Promise<boolean> => {
					const response = await fetch(statusUrl);
					if (!response.ok) return false;
					latestStatus = await response.json();
					props.milestones.recordTelemetry(latestStatus, props.viewer);
					telemetryProofFailure = telemetryBatchHealthFailure(latestStatus);
					if (telemetryProofFailure !== null) return true;
					telemetryProofFailure = telemetryRuntimeFailure(latestStatus, props.viewer);
					if (telemetryProofFailure !== null) return true;
					observation = backpressureTelemetryObservation({ ...props, status: latestStatus });
					return observation !== null;
				},
				{ timeout: props.timeoutMilliseconds },
			)
			.toBe(true);
	} catch (error: unknown) {
		throw new Error(
			`Backpressure telemetry did not quiesce: ${JSON.stringify(compactTelemetryDiagnostic(latestStatus, props.viewer))}.`,
			{ cause: error },
		);
	}
	if (telemetryProofFailure !== null) {
		throw new Error(`Backpressure telemetry proof is invalid: ${telemetryProofFailure}.`);
	}
	if (observation === null) {
		throw new Error(`Backpressure telemetry did not quiesce: ${JSON.stringify(latestStatus)}.`);
	}
	return observation;
}

function telemetryBatchHealthFailure(status: unknown): string | null {
	if (!isRecord(status)) return null;
	const failedBatchCount = status['failedBatchCount'];
	const lastError = status['lastError'];
	if (typeof failedBatchCount !== 'number' || failedBatchCount === 0) return null;
	return JSON.stringify({ failedBatchCount, lastError });
}

function telemetryRuntimeFailure(status: unknown, viewer: 'file' | 'review'): string | null {
	if (!isRecord(status) || !Array.isArray(status['recentSamples'])) return null;
	const failures = status['recentSamples']
		.filter(isTelemetryStatusSample)
		.filter(
			(sample) =>
				sample.stringAttributes['agentstudio.bridge.viewer'] === viewer &&
				(sample.stringAttributes['agentstudio.bridge.render_disposition.outcome'] === 'timed_out' ||
					sample.stringAttributes['agentstudio.bridge.phase'] ===
						'render_disposition_admission_overloaded' ||
					sample.stringAttributes['agentstudio.bridge.worker.session_state'] ===
						'replacement_requested'),
		)
		.slice(-4)
		.map((sample) => ({
			name: sample.name,
			outcome: sample.stringAttributes['agentstudio.bridge.render_disposition.outcome'],
			phase: sample.stringAttributes['agentstudio.bridge.phase'],
			sessionState: sample.stringAttributes['agentstudio.bridge.worker.session_state'],
		}));
	return failures.length === 0 ? null : JSON.stringify({ runtimeFailures: failures });
}

export function compactTelemetryDiagnostic(
	status: unknown,
	viewer: 'file' | 'review',
): readonly Readonly<Record<string, unknown>>[] {
	if (!isRecord(status) || !Array.isArray(status['recentSamples'])) return [];
	const relevantSamples = status['recentSamples']
		.filter(isTelemetryStatusSample)
		.filter(
			(sample) =>
				sample.stringAttributes['agentstudio.bridge.viewer'] === viewer &&
				(sample.name === 'performance.bridge.web.render_disposition_admission' ||
					sample.name === 'performance.bridge.worker.render_disposition_batch' ||
					sample.name === 'performance.bridge.worker.render_publication_outstanding'),
		);
	return [
		...relevantSamples
			.filter((sample) => sample.name === 'performance.bridge.web.render_disposition_admission')
			.slice(-4),
		...relevantSamples
			.filter((sample) => sample.name === 'performance.bridge.worker.render_disposition_batch')
			.slice(-4),
		...relevantSamples
			.filter(
				(sample) => sample.name === 'performance.bridge.worker.render_publication_outstanding',
			)
			.slice(-4),
	].map((sample) => ({
		accepted: sample.numericAttributes['agentstudio.bridge.render_disposition.accepted_count'],
		current: sample.numericAttributes['agentstudio.bridge.render_publication.current_count'],
		event: sample.name,
		highWater:
			sample.numericAttributes['agentstudio.bridge.render_publication.high_water_mark'] ??
			sample.numericAttributes['agentstudio.bridge.render_disposition.pending_high_water_mark'],
		oldest:
			sample.numericAttributes['agentstudio.bridge.render_publication.oldest_age_ms'] ??
			sample.numericAttributes['agentstudio.bridge.render_disposition.oldest_pending_age_ms'],
		outcome:
			sample.stringAttributes['agentstudio.bridge.render_publication.outcome'] ??
			sample.stringAttributes['agentstudio.bridge.render_disposition.outcome'],
		pending: sample.numericAttributes['agentstudio.bridge.render_disposition.pending_count'],
		phase: sample.stringAttributes['agentstudio.bridge.phase'],
		produced: sample.numericAttributes['agentstudio.bridge.render_disposition.produced_count'],
		receipts: sample.numericAttributes['agentstudio.bridge.render_disposition.batch_receipt_count'],
		rejected: sample.numericAttributes['agentstudio.bridge.render_disposition.rejected_count'],
		viewer,
	}));
}

function backpressureTelemetryObservation(props: {
	readonly expectedReceiptProducedCount: number | null;
	readonly status: unknown;
	readonly viewer: 'file' | 'review';
}): BackpressureTelemetryObservation | null {
	if (!isRecord(props.status) || !Array.isArray(props.status['recentSamples'])) return null;
	const samples = props.status['recentSamples'].filter(isTelemetryStatusSample);
	const admissions = samples.filter(
		(sample) =>
			sample.name === 'performance.bridge.web.render_disposition_admission' &&
			sample.stringAttributes['agentstudio.bridge.viewer'] === props.viewer,
	);
	const publications = samples.filter(
		(sample) =>
			sample.name === 'performance.bridge.worker.render_publication_outstanding' &&
			sample.stringAttributes['agentstudio.bridge.viewer'] === props.viewer,
	);
	const latestAdmission = admissions.at(-1);
	const latestPublication = publications.at(-1);
	if (latestAdmission === undefined || latestPublication === undefined) return null;
	const receiptPendingCount = numberAttribute(
		latestAdmission,
		'agentstudio.bridge.render_disposition.pending_count',
	);
	const receiptProducedCount = numberAttribute(
		latestAdmission,
		'agentstudio.bridge.render_disposition.produced_count',
	);
	const receiptRetainedCount = numberAttribute(
		latestAdmission,
		'agentstudio.bridge.render_disposition.retained_count',
	);
	const currentCount = numberAttribute(
		latestPublication,
		'agentstudio.bridge.render_publication.current_count',
	);
	if (
		receiptRetainedCount !== 0 ||
		(props.expectedReceiptProducedCount === null
			? receiptProducedCount === 0
			: receiptProducedCount !== props.expectedReceiptProducedCount) ||
		currentCount !== 0
	)
		return null;
	const failureCount = samples.filter(
		(sample) =>
			sample.stringAttributes['agentstudio.bridge.render_disposition.outcome'] === 'timed_out' ||
			sample.stringAttributes['agentstudio.bridge.phase'] ===
				'render_disposition_admission_overloaded' ||
			sample.stringAttributes['agentstudio.bridge.worker.session_state'] ===
				'replacement_requested',
	).length;
	return {
		currentCount,
		failureCount,
		highWaterMark: maximumAttribute(
			publications,
			'agentstudio.bridge.render_publication.high_water_mark',
		),
		maximumPublicationAgeMilliseconds: maximumAttribute(
			publications,
			'agentstudio.bridge.render_publication.oldest_age_ms',
		),
		maximumReceiptPendingAgeMilliseconds: maximumAttribute(
			admissions,
			'agentstudio.bridge.render_disposition.oldest_pending_age_ms',
		),
		maximumWorkerQueueWaitMilliseconds: maximumAttribute(
			samples.filter((sample) => sample.name === 'performance.bridge.worker.task'),
			'agentstudio.bridge.worker.queue_wait_ms',
		),
		receiptHighWaterMark: maximumAttribute(
			admissions,
			'agentstudio.bridge.render_disposition.pending_high_water_mark',
		),
		receiptPendingCount,
		receiptProducedCount,
		responseBeforeOwnerEffectObserved: publications.some(
			(sample) =>
				sample.stringAttributes['agentstudio.bridge.phase'] ===
				'render_disposition_response_posted_before_owner_effect',
		),
	};
}

function isTelemetryStatusSample(value: unknown): value is TelemetryStatusSample {
	return (
		isRecord(value) &&
		typeof value['name'] === 'string' &&
		isRecord(value['numericAttributes']) &&
		isRecord(value['stringAttributes'])
	);
}

function numberAttribute(sample: TelemetryStatusSample, key: string): number {
	return sample.numericAttributes[key] ?? 0;
}

function maximumAttribute(samples: readonly TelemetryStatusSample[], key: string): number {
	return samples.reduce((maximum, sample) => Math.max(maximum, numberAttribute(sample, key)), 0);
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
