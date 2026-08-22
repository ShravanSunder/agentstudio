import { describe, expect, test } from 'vitest';

import {
	activeIdentity,
	candidateIdentity,
	makeApplicatorHarness,
	reviewIdentity,
	reviewSnapshot,
	workerDerivationEpoch,
} from './bridge-comm-worker-review-metadata-transaction.test-support.js';
import type { BridgeWorkerReviewPublicationIdentity } from './bridge-worker-contracts.js';

describe('Bridge comm worker Review successor re-exposure', () => {
	test('re-exposes one newer active projection after an installed predecessor is acknowledged', () => {
		// Arrange
		const harness = makeApplicatorHarness();
		harness.applicator.apply(
			{
				...reviewSnapshot(activeIdentity, 'item-a', 0, 1, true),
				affectedStableFileIdentities: ['stable-a'],
				preDeliveryPresentationClass: { kind: 'ordinary' },
			},
			workerDerivationEpoch,
		);
		harness.applicator.apply(
			{
				...reviewSnapshot(candidateIdentity, 'item-c', 0, 1, true),
				affectedStableFileIdentities: ['stable-c'],
				preDeliveryPresentationClass: { kind: 'promoted', reason: 'files' },
			},
			workerDerivationEpoch,
		);
		const applicationCount = harness.applications.length;

		// Act
		const reExposed = applyPublicationApplied(harness, activeIdentity);
		const duplicate = applyPublicationApplied(harness, activeIdentity);
		const samePublication = applyPublicationApplied(harness, candidateIdentity);

		// Assert
		expect(reExposed).toBe(true);
		expect(duplicate).toBe(false);
		expect(samePublication).toBe(false);
		expect(harness.applications).toHaveLength(applicationCount);
		expect(harness.displayPublications).toHaveLength(3);
		expect(harness.displayPublications.at(-1)?.patches).toEqual([
			expect.objectContaining({ operation: 'upsert', slice: 'reviewSource' }),
			expect.objectContaining({ operation: 'replace', slice: 'reviewComparison' }),
			expect.objectContaining({
				operation: 'batch',
				payload: expect.objectContaining({ reset: true, startIndex: 0 }),
				slice: 'reviewItem',
			}),
			expect.objectContaining({
				operation: 'batch',
				payload: expect.objectContaining({ reset: true }),
				slice: 'reviewTree',
			}),
		]);
		expect(harness.candidateReadyPublications.at(-1)).toMatchObject({
			affectedStableFileIdentities: ['stable-c'],
			identity: {
				generation: candidateIdentity.generation,
				packageId: candidateIdentity.packageId,
				publicationId: candidateIdentity.publicationId,
				revision: candidateIdentity.revision,
				sourceIdentity: candidateIdentity.sourceIdentity,
			},
			preDeliveryPresentationClass: { kind: 'promoted', reason: 'files' },
		});
	});

	test('allows the same active successor to re-expose after its admission transport fails', () => {
		// Arrange
		const harness = makeApplicatorHarness();
		applyReadyPublication(harness, activeIdentity, 'item-a');
		applyReadyPublication(harness, candidateIdentity, 'item-c');
		applyPublicationApplied(harness, activeIdentity);

		// Act
		const firstRetry = harness.applicator.handleSuccessorReExposureSettlement(
			{ candidatePublicationId: candidateIdentity.publicationId, kind: 'admissionFailed' },
			workerDerivationEpoch - 1,
		);
		const secondRetry = harness.applicator.handleSuccessorReExposureSettlement(
			{ candidatePublicationId: candidateIdentity.publicationId, kind: 'admissionFailed' },
			workerDerivationEpoch,
		);
		const duplicateApplied = applyPublicationApplied(harness, activeIdentity);

		// Assert
		expect(firstRetry).toBe(true);
		expect(secondRetry).toBe(false);
		expect(duplicateApplied).toBe(false);
		expect(harness.displayPublications).toHaveLength(4);
	});

	test('re-exposes current-epoch D after an older-epoch C admission is rejected', () => {
		// Arrange
		const harness = makeApplicatorHarness();
		const newestIdentity = reviewIdentity('newest', 9, 31);
		applyReadyPublication(harness, activeIdentity, 'item-a');
		applyReadyPublication(harness, candidateIdentity, 'item-c');
		applyPublicationApplied(harness, activeIdentity);
		applyReadyPublication(harness, newestIdentity, 'item-d');
		const displayCountBeforeRejection = harness.displayPublications.length;

		// Act
		const reExposed = harness.applicator.handleSuccessorReExposureSettlement(
			{ candidatePublicationId: candidateIdentity.publicationId, kind: 'admissionRejected' },
			workerDerivationEpoch - 1,
		);

		// Assert
		expect(reExposed).toBe(true);
		expect(harness.displayPublications).toHaveLength(displayCountBeforeRejection + 1);
		expect(harness.candidateReadyPublications.at(-1)?.identity).toMatchObject({
			generation: newestIdentity.generation,
			publicationId: newestIdentity.publicationId,
			revision: newestIdentity.revision,
		});
	});
});

function applyReadyPublication(
	harness: ReturnType<typeof makeApplicatorHarness>,
	identity: typeof activeIdentity,
	itemId: string,
): void {
	harness.applicator.apply(
		{
			...reviewSnapshot(identity, itemId, 0, 1, true),
			affectedStableFileIdentities: [`stable-${itemId}`],
			preDeliveryPresentationClass: { kind: 'ordinary' },
		},
		workerDerivationEpoch,
	);
}

function applyPublicationApplied(
	harness: ReturnType<typeof makeApplicatorHarness>,
	identity: typeof activeIdentity,
): boolean {
	return harness.applicator.handleSuccessorReExposureSettlement(
		{ identity: workerIdentity(identity), kind: 'publicationApplied' },
		workerDerivationEpoch,
	);
}

function workerIdentity(identity: typeof activeIdentity): BridgeWorkerReviewPublicationIdentity {
	return {
		packageId: identity.packageId,
		publicationId: identity.publicationId,
		reviewGeneration: identity.generation,
		revision: identity.revision,
		sourceIdentity: identity.sourceIdentity,
	};
}
