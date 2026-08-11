import { bridgeProductReviewComparisonTargetsQueryResultSchema } from './bridge-product-call-contracts.js';
import type { BridgeProductReviewComparisonTargetsContentDescriptor } from './bridge-product-content-contracts.js';
import { bridgeProductReviewComparisonTargetCatalogSchema } from './bridge-product-review-comparison-contracts.js';
import type { BridgeProductContentStream } from './bridge-product-transport-contract.js';
import {
	bridgeWorkerReviewComparisonTargetsQueryEventSchema,
	type BridgeWorkerReviewComparisonTargetsQueryEvent,
} from './bridge-worker-review-comparison-target-query-contracts.js';

const bridgeWorkerWireVersion = 1 as const;

type ComparisonTargetsContentOpen = (
	descriptor: BridgeProductReviewComparisonTargetsContentDescriptor,
	abortSignal: AbortSignal,
) => BridgeProductContentStream<'review.comparisonTargets'>;

export interface BridgeWorkerComparisonTargetsQueryRunner {
	readonly abort: () => void;
	readonly run: (requestId: string, result: unknown) => Promise<void>;
}

export function createBridgeWorkerComparisonTargetsQueryRunner(props: {
	readonly openContent: ComparisonTargetsContentOpen | undefined;
	readonly publish: (event: BridgeWorkerReviewComparisonTargetsQueryEvent) => void;
	readonly workSignal: AbortSignal;
}): BridgeWorkerComparisonTargetsQueryRunner {
	let active: { readonly abortController: AbortController; readonly requestId: string } | null =
		null;
	let generation = 0;
	const abort = (): void => {
		generation += 1;
		active?.abortController.abort();
		active = null;
	};
	const postFailure = (requestId: string): void => {
		props.publish(
			bridgeWorkerReviewComparisonTargetsQueryEventSchema.parse({
				catalog: null,
				direction: 'serverWorkerToMain',
				kind: 'reviewComparisonTargetsQuery',
				message: 'Comparison targets are unavailable.',
				requestId,
				status: 'failed',
				transferDescriptors: [],
				wireVersion: bridgeWorkerWireVersion,
			}),
		);
	};
	return {
		abort,
		run: async (requestId, result): Promise<void> => {
			if (props.openContent === undefined) {
				postFailure(requestId);
				return;
			}
			abort();
			const queryGeneration = generation;
			const abortController = new AbortController();
			active = { abortController, requestId };
			const abortForWorkLoss = (): void => abortController.abort();
			props.workSignal.addEventListener('abort', abortForWorkLoss, { once: true });
			try {
				const descriptor =
					bridgeProductReviewComparisonTargetsQueryResultSchema.parse(result).descriptor;
				const contentStream = props.openContent(descriptor, abortController.signal);
				const drain = (async (): Promise<void> => {
					for await (const _frame of contentStream.frames) {
						// The product transport validates and assembles the bounded body.
					}
				})();
				const [, terminal] = await Promise.all([drain, contentStream.terminal]);
				if (
					active?.requestId !== requestId ||
					queryGeneration !== generation ||
					abortController.signal.aborted
				)
					return;
				if (terminal.kind !== 'complete')
					throw new Error('Comparison target content did not complete.');
				const catalog = bridgeProductReviewComparisonTargetCatalogSchema.parse(
					JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(terminal.bytes)),
				);
				props.publish(
					bridgeWorkerReviewComparisonTargetsQueryEventSchema.parse({
						catalog,
						direction: 'serverWorkerToMain',
						kind: 'reviewComparisonTargetsQuery',
						requestId,
						status: catalog.branches.length === 0 ? 'empty' : 'ready',
						...(catalog.branches.length === 0
							? { message: 'No branch choices are available from the last 30 days.' }
							: {}),
						transferDescriptors: [],
						wireVersion: bridgeWorkerWireVersion,
					}),
				);
			} catch {
				if (
					active?.requestId !== requestId ||
					queryGeneration !== generation ||
					abortController.signal.aborted
				)
					return;
				postFailure(requestId);
			} finally {
				props.workSignal.removeEventListener('abort', abortForWorkLoss);
				if (active?.requestId === requestId) active = null;
			}
		},
	};
}
