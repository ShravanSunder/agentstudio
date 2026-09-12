import type { Page, Response } from 'playwright';

import {
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import type { BridgeWorkerHealthEvent } from '../../src/core/comm-worker/bridge-worker-contracts.js';
import { annotationProjectionQueryResultDiagnostic } from './bridge-viewer-vite-annotation-projection-test-support.ts';

type MetadataHealthDiagnostic = NonNullable<BridgeWorkerHealthEvent['diagnostic']>;

declare global {
	interface Window {
		bridgeInteractionMetadataHealthHistory?: MetadataHealthDiagnostic[];
	}
}

interface ControlRejectionObservation {
	readonly code: string;
	readonly nextExpectedRequestSequence: number | null;
	readonly requestKind: string;
	readonly requestMethod: string | null;
	readonly requestSequence: number;
	readonly retryable: boolean;
	readonly safeMessage: string | null;
}

interface AnnotationQueryObservation {
	readonly method: string;
	readonly operationCorrelationId: string;
	readonly requestSequence: number;
	readonly sourceGeneration: number;
	readonly workerDerivationEpoch: number | null;
	readonly result: unknown;
}

export async function observeInteractionProfileFailures(page: Page): Promise<{
	readonly read: () => Promise<{
		readonly annotationQueries: readonly AnnotationQueryObservation[];
		readonly controlRejections: readonly ControlRejectionObservation[];
		readonly metadataHealthHistory: readonly MetadataHealthDiagnostic[];
		readonly pendingControlResponseCount: number;
		readonly unreadableControlResponseCount: number;
	}>;
}> {
	const annotationQueries: AnnotationQueryObservation[] = [];
	const controlRejections: ControlRejectionObservation[] = [];
	const pendingReads = new Set<Promise<void>>();
	let unreadableControlResponseCount = 0;
	await page.addInitScript((): void => {
		let latest: MetadataHealthDiagnostic | undefined;
		const history: MetadataHealthDiagnostic[] = [];
		window.bridgeInteractionMetadataHealthHistory = history;
		// Observe the existing diagnostic publication without changing its value or owner.
		Object.defineProperty(window, '__bridgeProductMetadataStreamDiagnostic', {
			configurable: true,
			get: (): MetadataHealthDiagnostic | undefined => latest,
			set: (diagnostic: MetadataHealthDiagnostic): void => {
				latest = diagnostic;
				history.push(diagnostic);
				if (history.length > 32) history.shift();
			},
		});
	});
	const inspectResponse = async (response: Response): Promise<void> => {
		try {
			const parsed = bridgeProductControlResponseSchema.safeParse(await response.json());
			if (!parsed.success) return;
			const request = bridgeProductControlRequestSchema.parse(response.request().postDataJSON());
			if (
				request.kind === 'product.call' &&
				(request.call.method === 'file.annotations.projection.query' ||
					request.call.method === 'review.annotations.projection.query')
			) {
				annotationQueries.push({
					method: request.call.method,
					operationCorrelationId: request.call.request.operationCorrelationId,
					requestSequence: request.requestSequence,
					sourceGeneration: request.call.request.sourceGeneration,
					workerDerivationEpoch: request.workerDerivationEpoch ?? null,
					result: annotationProjectionQueryResultDiagnostic(parsed.data, request.call.request),
				});
				if (annotationQueries.length > 64) annotationQueries.shift();
			}
			if (parsed.data.kind !== 'request.error') return;
			if (controlRejections.length >= 32) return;
			controlRejections.push({
				code: parsed.data.code,
				nextExpectedRequestSequence: parsed.data.nextExpectedRequestSequence ?? null,
				requestKind: request.kind,
				requestMethod: request.kind === 'product.call' ? request.call.method : null,
				requestSequence: request.requestSequence,
				retryable: parsed.data.retryable,
				safeMessage: parsed.data.safeMessage ?? null,
			});
		} catch {
			unreadableControlResponseCount += 1;
		}
	};
	page.on('response', (response): void => {
		if (
			response.status() !== 200 ||
			new URL(response.url()).pathname !== '/__bridge-product/command'
		)
			return;
		const pending = inspectResponse(response);
		pendingReads.add(pending);
		void pending.finally((): void => {
			pendingReads.delete(pending);
		});
	});
	return {
		read: async () => {
			return {
				annotationQueries: [...annotationQueries],
				controlRejections: [...controlRejections],
				metadataHealthHistory: await page.evaluate(
					() => window.bridgeInteractionMetadataHealthHistory ?? [],
				),
				unreadableControlResponseCount,
				pendingControlResponseCount: pendingReads.size,
			};
		},
	};
}
