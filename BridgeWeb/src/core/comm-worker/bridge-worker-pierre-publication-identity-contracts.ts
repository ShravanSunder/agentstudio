import { z } from 'zod';

import type { BridgeProductSurface } from './bridge-product-contract-primitives.js';
import type { BridgeWorkerReviewPublicationIdentity } from './bridge-worker-review-publication-contracts.js';

export function assertBridgeWorkerReviewPublicationIdentityMatches(
	expected: BridgeWorkerReviewPublicationIdentity,
	actual: BridgeWorkerReviewPublicationIdentity,
): void {
	if (
		expected.packageId !== actual.packageId ||
		expected.publicationId !== actual.publicationId ||
		expected.reviewGeneration !== actual.reviewGeneration ||
		expected.revision !== actual.revision ||
		expected.sourceIdentity !== actual.sourceIdentity
	) {
		throw new Error('Bridge worker Review publication does not match its preparation ticket.');
	}
}

export function validateBridgeWorkerPierreRenderPublicationIdentity(
	event: {
		readonly job: { readonly itemId: string };
		readonly publicationSequence: number;
		readonly renderReceiptIdentity: {
			readonly itemId: string;
			readonly publicationSequence: number;
			readonly surface: BridgeProductSurface;
			readonly workerDerivationEpoch: number;
		};
		readonly surface: BridgeProductSurface;
		readonly workerDerivationEpoch: number;
	},
	context: z.RefinementCtx,
): void {
	for (const [field, matches] of [
		['itemId', event.renderReceiptIdentity.itemId === event.job.itemId],
		[
			'publicationSequence',
			event.renderReceiptIdentity.publicationSequence === event.publicationSequence,
		],
		['surface', event.renderReceiptIdentity.surface === event.surface],
		[
			'workerDerivationEpoch',
			event.renderReceiptIdentity.workerDerivationEpoch === event.workerDerivationEpoch,
		],
	] as const) {
		if (matches) continue;
		context.addIssue({
			code: 'custom',
			message: `Bridge Pierre publication ${field} does not match its receipt identity.`,
			path: ['renderReceiptIdentity', field],
		});
	}
}
