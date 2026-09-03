import { describe, expect, test } from 'vitest';

import {
	activeIdentity,
	candidateIdentity,
	makeApplicatorHarness,
	reviewComparisonOrigin,
	reviewReset,
	reviewSnapshot,
	reviewSourceAccepted,
	reviewWindow,
	workerDerivationEpoch,
} from './bridge-comm-worker-review-metadata-transaction.test-support.js';

describe('Bridge comm worker Review metadata candidate staging', () => {
	test('retains complete A while reset, source acceptance, and partial B remain pending', () => {
		const harness = makeApplicatorHarness();
		harness.applicator.apply(
			reviewSnapshot(activeIdentity, 'item-a', 0, 1, true),
			workerDerivationEpoch,
		);
		harness.applicator.apply(reviewReset(candidateIdentity), workerDerivationEpoch);
		harness.applicator.apply(reviewSourceAccepted(candidateIdentity), workerDerivationEpoch);
		harness.applicator.apply(
			reviewSnapshot(candidateIdentity, 'item-b-1', 0, 2, false),
			workerDerivationEpoch,
		);
		expect(harness.applications).toHaveLength(1);
		expect(harness.applications[0]?.source.contentItems.map(({ itemId }) => itemId)).toEqual([
			'item-a',
		]);
		const pendingPublications = harness.displayPublications.slice(1);
		expect(
			pendingPublications.flatMap(({ patches }) =>
				patches.filter(({ slice }) => slice === 'reviewItem' || slice === 'reviewTree'),
			),
		).toEqual([]);
		expect(JSON.stringify(pendingPublications)).toContain('source-active');
		expect(JSON.stringify(pendingPublications)).not.toContain('source-candidate');
	});

	test('publishes one exact retryable failure only for the current started candidate', () => {
		const harness = makeApplicatorHarness();
		harness.applicator.apply(
			reviewSnapshot(activeIdentity, 'item-a', 0, 1, true),
			workerDerivationEpoch,
		);
		harness.publicationOrder.splice(0);
		harness.candidateFailedPublications.splice(0);
		harness.applicator.apply(
			reviewReset(candidateIdentity, {
				addedLineCount: 0,
				affectedFileCount: 1,
				affectedStableFileIdentities: ['stable-item-b'],
				deletedLineCount: 0,
				newlyImportedCommitCount: 10,
				preDeliveryPresentationClass: { kind: 'promoted', reason: 'commits' },
			}),
			workerDerivationEpoch,
		);
		expect(harness.applicator.handleMetadataFailure(workerDerivationEpoch)).toBe('retainedActive');
		expect(harness.publicationOrder).toEqual(['started', 'failed']);
		expect(harness.candidateFailedPublications).toEqual([
			expect.objectContaining({
				identity: expect.objectContaining({ publicationId: candidateIdentity.publicationId }),
				retryable: true,
			}),
		]);
		expect(harness.applicator.handleMetadataFailure(workerDerivationEpoch)).toBe('retainedActive');
		expect(harness.candidateFailedPublications).toHaveLength(1);
	});

	test('publishes one classified start before reset multi-window candidate geometry and readiness', () => {
		const harness = makeApplicatorHarness();
		harness.applicator.apply(
			reviewSnapshot(activeIdentity, 'item-a', 0, 1, true),
			workerDerivationEpoch,
		);
		harness.publicationOrder.splice(0);
		harness.candidateStartedPublications.splice(0);
		harness.applicator.apply(
			reviewReset(candidateIdentity, {
				addedLineCount: 1_000,
				affectedFileCount: 1,
				affectedStableFileIdentities: ['stable-item-b'],
				deletedLineCount: 0,
				newlyImportedCommitCount: 0,
				preDeliveryPresentationClass: { kind: 'promoted', reason: 'lines' },
			}),
			workerDerivationEpoch,
		);
		expect(harness.publicationOrder).toEqual(['started']);
		harness.applicator.apply(reviewSourceAccepted(candidateIdentity), workerDerivationEpoch);
		harness.applicator.apply(
			reviewSnapshot(candidateIdentity, 'item-b-1', 0, 2, false),
			workerDerivationEpoch,
		);
		harness.applicator.apply(
			reviewWindow(candidateIdentity, 'item-b-2', 1, 2, true),
			workerDerivationEpoch,
		);
		expect(harness.applications).toHaveLength(2);
		expect(harness.applications.map(({ sourceEpoch }) => sourceEpoch)).toEqual([1, 2]);
		expect(harness.applications[1]).toMatchObject({
			completeContentItemIds: ['item-b-1', 'item-b-2'],
			reset: true,
		});
		const candidatePublications = harness.displayPublications.filter((publication) =>
			JSON.stringify(publication).includes('source-candidate'),
		);
		expect(candidatePublications).toHaveLength(1);
		expect(harness.publicationOrder).toEqual(['started', 'display', 'ready']);
		expect(harness.candidateStartedPublications).toEqual([
			expect.objectContaining({
				disposition: {
					affectedStableFileIdentities: ['stable-item-b'],
					kind: 'sameSource',
					presentationClass: { kind: 'promoted', reason: 'lines' },
				},
				identity: expect.objectContaining({ publicationId: candidateIdentity.publicationId }),
			}),
		]);
		expect(candidatePublications[0]?.patches).toEqual([
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
		expect(candidatePublications[0]?.patches[0]).toMatchObject({
			operation: 'upsert',
			payload: {
				comparisonOrigin: reviewComparisonOrigin,
				reviewedSubjectLabel: 'feature/review-comments',
			},
			slice: 'reviewSource',
		});
	});
});
