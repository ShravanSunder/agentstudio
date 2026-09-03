import type { Page } from 'playwright';
import { expect } from 'vitest';

const annotationLifecycleTelemetryTimeoutMilliseconds = 30_000;
const requiredAnnotationLifecycleStages = [
	'annotation_invalidation_received',
	'annotation_paint_started',
	'annotation_paint_terminal',
	'content_transfer_started',
	'content_transfer_terminal',
	'main_thread_install_started',
	'main_thread_install_terminal',
	'projection_convergence_started',
	'projection_query_started',
	'projection_store_started',
	'projection_store_terminal',
	'projection_validation_started',
	'projection_validation_terminal',
	'projection_query_terminal',
	'projection_convergence_terminal',
	'worker_application_started',
	'worker_application_terminal',
] as const;

export const requiredAnnotationLifecycleStageCount = requiredAnnotationLifecycleStages.length;

export async function drainAnnotationLifecycleTelemetry(page: Page): Promise<unknown> {
	const report: unknown = await page.evaluate(async (): Promise<unknown> => {
		const control: unknown = Reflect.get(globalThis, '__bridgeTelemetrySidecarControl');
		if (typeof control !== 'object' || control === null) return { kind: 'unavailable' };
		const drain: unknown = Reflect.get(control, 'drain');
		if (typeof drain !== 'function') return { kind: 'unavailable' };
		return await Reflect.apply(drain, control, []);
	});
	if (!isUnknownRecord(report) || report['kind'] !== 'report') {
		throw new Error(
			`Annotation lifecycle telemetry sidecar could not drain: ${JSON.stringify(report)}.`,
		);
	}
	return report;
}

export async function waitForCompleteAnnotationLifecycleTelemetry(props: {
	readonly operationCorrelationId: string;
	readonly page: Page;
	readonly sidecarDrainReport: unknown;
}): Promise<number> {
	const statusUrl = new URL('/__bridge-dev-telemetry/status', props.page.url()).toString();
	let completedStageCount: number | null = null;
	let latestDiagnostic: Readonly<Record<string, unknown>> = {
		kind: 'status-unavailable',
		operationCorrelationId: props.operationCorrelationId,
	};
	try {
		await expect
			.poll(
				async (): Promise<boolean> => {
					const response = await fetch(statusUrl, { cache: 'no-store' });
					if (!response.ok) {
						latestDiagnostic = {
							kind: 'status-http-error',
							operationCorrelationId: props.operationCorrelationId,
							status: response.status,
						};
						return false;
					}
					const body: unknown = await response.json();
					if (typeof body !== 'object' || body === null || !('recentSamples' in body)) {
						latestDiagnostic = {
							kind: 'status-malformed',
							operationCorrelationId: props.operationCorrelationId,
						};
						return false;
					}
					const recentSamples = body.recentSamples;
					const operationLifecycle = Reflect.get(body, 'operationLifecycle');
					if (!Array.isArray(recentSamples)) return false;
					const observedStages = new Set<string>();
					for (const sample of recentSamples) {
						if (typeof sample !== 'object' || sample === null || !('stringAttributes' in sample)) {
							continue;
						}
						const attributes = sample.stringAttributes;
						if (typeof attributes !== 'object' || attributes === null) continue;
						const operationId = Reflect.get(attributes, 'agentstudio.bridge.operation.id');
						const phase = Reflect.get(attributes, 'agentstudio.bridge.phase');
						if (operationId !== props.operationCorrelationId || typeof phase !== 'string') continue;
						observedStages.add(phase);
					}
					const completedOperationIds =
						typeof operationLifecycle === 'object' && operationLifecycle !== null
							? Reflect.get(operationLifecycle, 'completedOperationIds')
							: null;
					const malformed =
						typeof operationLifecycle === 'object' && operationLifecycle !== null
							? Reflect.get(operationLifecycle, 'malformed')
							: null;
					const missingTerminals =
						typeof operationLifecycle === 'object' && operationLifecycle !== null
							? Reflect.get(operationLifecycle, 'missingTerminals')
							: null;
					const matchingMalformed = matchingLifecycleEntries(
						malformed,
						props.operationCorrelationId,
					);
					const matchingMissingTerminals = matchingLifecycleEntries(
						missingTerminals,
						props.operationCorrelationId,
					);
					const missingStages = requiredAnnotationLifecycleStages.filter(
						(stage) => !observedStages.has(stage),
					);
					latestDiagnostic = {
						completed: Array.isArray(completedOperationIds)
							? completedOperationIds.includes(props.operationCorrelationId)
							: false,
						matchingMalformed,
						matchingMissingTerminals,
						missingStages,
						observedStages: [...observedStages],
						operationCorrelationId: props.operationCorrelationId,
					};
					if (
						missingStages.length === 0 &&
						Array.isArray(completedOperationIds) &&
						completedOperationIds.includes(props.operationCorrelationId) &&
						matchingMalformed?.length === 0 &&
						matchingMissingTerminals?.length === 0
					) {
						completedStageCount = requiredAnnotationLifecycleStageCount;
						return true;
					}
					return false;
				},
				{ timeout: annotationLifecycleTelemetryTimeoutMilliseconds },
			)
			.toBe(true);
	} catch (error: unknown) {
		throw new Error(
			`Annotation lifecycle telemetry did not complete for the saved projection: lifecycle=${JSON.stringify(
				latestDiagnostic,
			)} sidecarDrain=${JSON.stringify(props.sidecarDrainReport)}.`,
			{ cause: error },
		);
	}
	if (completedStageCount === null) {
		throw new Error('Annotation lifecycle telemetry completed without a stage count');
	}
	return completedStageCount;
}

function matchingLifecycleEntries(
	entries: unknown,
	operationCorrelationId: string,
): readonly unknown[] | null {
	return Array.isArray(entries)
		? entries.filter(
				(entry): boolean =>
					typeof entry === 'object' &&
					entry !== null &&
					Reflect.get(entry, 'operationCorrelationId') === operationCorrelationId,
			)
		: null;
}

function isUnknownRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
