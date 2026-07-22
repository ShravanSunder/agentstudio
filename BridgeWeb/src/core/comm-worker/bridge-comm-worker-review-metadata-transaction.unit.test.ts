import { describe, expect, test } from 'vitest';

import {
	activeIdentity,
	candidateIdentity,
	makeApplicatorHarness,
	reviewDelta,
	reviewIdentity,
	reviewInvalidated,
	reviewMetadataTransport,
	reviewPublicationId,
	reviewReset,
	reviewSnapshot,
	reviewSourceAccepted,
	reviewWindow,
	workerDerivationEpoch,
} from './bridge-comm-worker-review-metadata-transaction.test-support.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';

describe('Bridge comm worker Review metadata transaction staging', () => {
	test('retains complete A while reset, source acceptance, and partial B remain pending', () => {
		// Arrange
		const harness = makeApplicatorHarness();
		harness.applicator.apply(
			reviewSnapshot(activeIdentity, 'item-a', 0, 1, true),
			workerDerivationEpoch,
		);

		// Act
		harness.applicator.apply(reviewReset(candidateIdentity), workerDerivationEpoch);
		harness.applicator.apply(reviewSourceAccepted(candidateIdentity), workerDerivationEpoch);
		harness.applicator.apply(
			reviewSnapshot(candidateIdentity, 'item-b-1', 0, 2, false),
			workerDerivationEpoch,
		);

		// Assert
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

	test('swaps complete B once with one reset application and one complete display replacement', () => {
		// Arrange
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

		// Act
		harness.applicator.apply(
			reviewWindow(candidateIdentity, 'item-b-2', 1, 2, true),
			workerDerivationEpoch,
		);

		// Assert
		expect(harness.applications).toHaveLength(2);
		expect(harness.applications.map(({ sourceEpoch }) => sourceEpoch)).toEqual([1, 2]);
		expect(harness.applications[1]).toMatchObject({
			completeContentItemIds: ['item-b-1', 'item-b-2'],
			reset: true,
		});
		expect(harness.applications[1]?.source.contentItems.map(({ itemId }) => itemId)).toEqual([
			'item-b-1',
			'item-b-2',
		]);
		const candidatePublications = harness.displayPublications.filter((publication) =>
			JSON.stringify(publication).includes('source-candidate'),
		);
		expect(candidatePublications).toHaveLength(1);
		expect(candidatePublications[0]?.patches).toEqual([
			expect.objectContaining({ operation: 'upsert', slice: 'reviewSource' }),
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
	});

	test('ignores delayed older accepted snapshots after a newer generation commits', () => {
		// Arrange
		const harness = makeApplicatorHarness();
		harness.applicator.apply(
			reviewSnapshot(candidateIdentity, 'item-b', 0, 1, true),
			workerDerivationEpoch,
		);

		// Act
		harness.applicator.apply(reviewSourceAccepted(activeIdentity), workerDerivationEpoch);
		harness.applicator.apply(
			reviewSnapshot(activeIdentity, 'item-a-delayed', 0, 1, true),
			workerDerivationEpoch,
		);

		// Assert
		expect(harness.applications).toHaveLength(1);
		expect(harness.applications[0]).toMatchObject({ reset: true, sourceEpoch: 1 });
		expect(harness.applications[0]?.source.contentItems.map(({ itemId }) => itemId)).toEqual([
			'item-b',
		]);
	});

	test('retains a newer pending candidate across delayed traffic from the active generation', () => {
		// Arrange
		const harness = makeApplicatorHarness();
		const newerCandidateIdentity = reviewIdentity('newer-candidate', 9, 31);
		harness.applicator.apply(
			reviewSnapshot(candidateIdentity, 'item-b', 0, 1, true),
			workerDerivationEpoch,
		);
		harness.applicator.apply(reviewReset(newerCandidateIdentity), workerDerivationEpoch);
		harness.applicator.apply(reviewSourceAccepted(newerCandidateIdentity), workerDerivationEpoch);
		harness.applicator.apply(
			reviewSnapshot(newerCandidateIdentity, 'item-c-1', 0, 2, false),
			workerDerivationEpoch,
		);

		// Act
		harness.applicator.apply(reviewSourceAccepted(candidateIdentity), workerDerivationEpoch);
		harness.applicator.apply(
			reviewSnapshot(candidateIdentity, 'item-b-delayed', 0, 1, true),
			workerDerivationEpoch,
		);
		harness.applicator.apply(
			reviewWindow(newerCandidateIdentity, 'item-c-2', 1, 2, true),
			workerDerivationEpoch,
		);

		// Assert
		expect(
			harness.applications.map(({ source }) => source.contentItems.map(({ itemId }) => itemId)),
		).toEqual([['item-b'], ['item-c-1', 'item-c-2']]);
		expect(harness.applications.map(({ sourceEpoch }) => sourceEpoch)).toEqual([1, 2]);
	});

	test('ignores delayed revision 21 after the same source commits revision 22', () => {
		// Arrange
		const harness = makeApplicatorHarness();
		const committedIdentity = reviewIdentity('revision-floor', 8, 22);
		const delayedIdentity = reviewIdentity('revision-floor', 8, 21);
		harness.applicator.apply(
			reviewSnapshot(committedIdentity, 'item-revision-22', 0, 1, true),
			workerDerivationEpoch,
		);

		// Act
		harness.applicator.apply(reviewSourceAccepted(delayedIdentity), workerDerivationEpoch);
		harness.applicator.apply(
			reviewSnapshot(delayedIdentity, 'item-revision-21-delayed', 0, 1, true),
			workerDerivationEpoch,
		);

		// Assert
		expect(harness.applications).toHaveLength(1);
		expect(harness.applications[0]?.source.contentItems.map(({ itemId }) => itemId)).toEqual([
			'item-revision-22',
		]);
	});

	test('retains pending revision 23 across delayed revision 22 from the same source', () => {
		// Arrange
		const harness = makeApplicatorHarness();
		const activeRevisionIdentity = reviewIdentity('revision-pending', 8, 22);
		const pendingRevisionIdentity = reviewIdentity('revision-pending', 8, 23);
		harness.applicator.apply(
			reviewSnapshot(activeRevisionIdentity, 'item-revision-22', 0, 1, true),
			workerDerivationEpoch,
		);
		harness.applicator.apply(reviewReset(pendingRevisionIdentity), workerDerivationEpoch);
		harness.applicator.apply(reviewSourceAccepted(pendingRevisionIdentity), workerDerivationEpoch);
		harness.applicator.apply(
			reviewSnapshot(pendingRevisionIdentity, 'item-revision-23-1', 0, 2, false),
			workerDerivationEpoch,
		);

		// Act
		harness.applicator.apply(reviewSourceAccepted(activeRevisionIdentity), workerDerivationEpoch);
		harness.applicator.apply(
			reviewSnapshot(activeRevisionIdentity, 'item-revision-22-delayed', 0, 1, true),
			workerDerivationEpoch,
		);
		harness.applicator.apply(
			reviewWindow(pendingRevisionIdentity, 'item-revision-23-2', 1, 2, true),
			workerDerivationEpoch,
		);

		// Assert
		expect(
			harness.applications.map(({ source }) => source.contentItems.map(({ itemId }) => itemId)),
		).toEqual([['item-revision-22'], ['item-revision-23-1', 'item-revision-23-2']]);
		expect(harness.applications.map(({ sourceEpoch }) => sourceEpoch)).toEqual([1, 2]);
	});

	test('advances the accepted revision floor after a successful active delta', () => {
		// Arrange
		const harness = makeApplicatorHarness();
		const initialIdentity = reviewIdentity('revision-delta', 8, 21);
		harness.applicator.apply(
			reviewSnapshot(initialIdentity, 'item-revision-delta-current', 0, 1, true),
			workerDerivationEpoch,
		);

		// Act
		const delta = reviewDelta(initialIdentity, 22);
		const deltaReceipt = harness.applicator.apply(delta, workerDerivationEpoch);
		const replayReceipt = harness.applicator.apply(delta, workerDerivationEpoch);
		expect(() =>
			harness.applicator.apply(
				{
					...delta,
					operations: [{ itemIds: ['item-revision-delta-current'], operationKind: 'removeItems' }],
				},
				workerDerivationEpoch,
			),
		).toThrow(/changed payload/iu);
		harness.applicator.apply(reviewSourceAccepted(initialIdentity), workerDerivationEpoch);
		harness.applicator.apply(
			reviewSnapshot(initialIdentity, 'item-revision-delta-delayed', 0, 1, true),
			workerDerivationEpoch,
		);

		// Assert
		expect(deltaReceipt).toEqual({ publicationId: delta.publicationId });
		expect(replayReceipt).toEqual({ publicationId: delta.publicationId });
		expect(harness.applications).toHaveLength(2);
		expect(harness.applications.map(({ reset }) => reset)).toEqual([true, false]);
		expect(harness.applications.map(({ sourceEpoch }) => sourceEpoch)).toEqual([1, 1]);
		expect(harness.applications.at(-1)?.source.contentItems.map(({ itemId }) => itemId)).toEqual([
			'item-revision-delta-current',
		]);
	});

	test('lets a newer successor delta supersede an older pending candidate', () => {
		// Arrange
		const harness = makeApplicatorHarness();
		const activeRevisionIdentity = reviewIdentity('pending-floor', 8, 22);
		const pendingRevisionIdentity = reviewIdentity('pending-floor', 8, 23);
		harness.applicator.apply(
			reviewSnapshot(activeRevisionIdentity, 'item-active-22', 0, 1, true),
			workerDerivationEpoch,
		);
		harness.applicator.apply(reviewReset(pendingRevisionIdentity), workerDerivationEpoch);
		harness.applicator.apply(reviewSourceAccepted(pendingRevisionIdentity), workerDerivationEpoch);
		harness.applicator.apply(
			reviewSnapshot(pendingRevisionIdentity, 'item-pending-23-1', 0, 2, false),
			workerDerivationEpoch,
		);

		// Act
		harness.applicator.apply(reviewDelta(activeRevisionIdentity, 24), workerDerivationEpoch);
		harness.applicator.apply(
			reviewWindow(pendingRevisionIdentity, 'item-pending-23-2', 1, 2, true),
			workerDerivationEpoch,
		);
		const publicationCountBeforeSameRevisionReplay = harness.displayPublications.length;
		harness.applicator.apply(reviewSourceAccepted(pendingRevisionIdentity), workerDerivationEpoch);

		// Assert
		expect(
			harness.applications.map(({ source }) => source.contentItems.map(({ itemId }) => itemId)),
		).toEqual([['item-active-22'], ['item-active-22']]);
		expect(harness.applications.map(({ reset }) => reset)).toEqual([true, false]);
		expect(harness.applications.map(({ sourceEpoch }) => sourceEpoch)).toEqual([1, 1]);
		expect(harness.displayPublications).toHaveLength(publicationCountBeforeSameRevisionReplay);
	});

	test('preserves a pending candidate while a valid duplicate active window arrives', () => {
		// Arrange
		const harness = makeApplicatorHarness();
		harness.applicator.apply(
			reviewSnapshot(activeIdentity, 'item-a-1', 0, 2, false),
			workerDerivationEpoch,
		);
		harness.applicator.apply(
			reviewWindow(activeIdentity, 'item-a-2', 1, 2, true),
			workerDerivationEpoch,
		);
		harness.applicator.apply(reviewReset(candidateIdentity), workerDerivationEpoch);
		harness.applicator.apply(reviewSourceAccepted(candidateIdentity), workerDerivationEpoch);
		harness.applicator.apply(
			reviewSnapshot(candidateIdentity, 'item-b-1', 0, 2, false),
			workerDerivationEpoch,
		);

		// Act
		harness.applicator.apply(
			reviewWindow(activeIdentity, 'item-a-2', 1, 2, true),
			workerDerivationEpoch,
		);
		const activePublicationAfterDuplicateWindow = harness.displayPublications.at(-1);
		harness.applicator.apply(
			reviewWindow(candidateIdentity, 'item-b-2', 1, 2, true),
			workerDerivationEpoch,
		);

		// Assert
		expect(harness.applications.map(({ reset }) => reset)).toEqual([true, true]);
		expect(harness.applications.map(({ sourceEpoch }) => sourceEpoch)).toEqual([1, 2]);
		expect(activePublicationAfterDuplicateWindow?.patches).toContainEqual(
			expect.objectContaining({
				operation: 'upsert',
				payload: expect.objectContaining({ status: 'stale' }),
				slice: 'reviewSource',
			}),
		);
		expect(harness.applications.at(-1)?.source.contentItems.map(({ itemId }) => itemId)).toEqual([
			'item-b-1',
			'item-b-2',
		]);
	});

	test('preserves a pending candidate while the active source advances through a delta', () => {
		// Arrange
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

		// Act
		harness.applicator.apply(reviewDelta(activeIdentity, 12), workerDerivationEpoch);
		harness.applicator.apply(
			reviewWindow(candidateIdentity, 'item-b-2', 1, 2, true),
			workerDerivationEpoch,
		);

		// Assert
		expect(harness.applications.map(({ reset }) => reset)).toEqual([true, true]);
		expect(harness.applications.map(({ sourceEpoch }) => sourceEpoch)).toEqual([1, 2]);
		expect(harness.applications.at(-1)?.source.contentItems.map(({ itemId }) => itemId)).toEqual([
			'item-b-1',
			'item-b-2',
		]);
	});

	test('preserves a pending candidate while the active source is invalidated', () => {
		// Arrange
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

		// Act
		harness.applicator.apply(reviewInvalidated(activeIdentity), workerDerivationEpoch);
		harness.applicator.apply(
			reviewWindow(candidateIdentity, 'item-b-2', 1, 2, true),
			workerDerivationEpoch,
		);

		// Assert
		expect(harness.applications.map(({ reset }) => reset)).toEqual([true, false, true]);
		expect(harness.applications.map(({ sourceEpoch }) => sourceEpoch)).toEqual([1, 1, 2]);
		expect(harness.applications.at(-1)?.source.contentItems.map(({ itemId }) => itemId)).toEqual([
			'item-b-1',
			'item-b-2',
		]);
	});

	test('validates an exact same-publication replay and receipts it without another swap', () => {
		// Arrange
		const harness = makeApplicatorHarness();
		harness.applicator.apply(
			reviewSnapshot(candidateIdentity, 'item-b', 0, 1, true),
			workerDerivationEpoch,
		);

		// Act
		harness.applicator.apply(reviewSourceAccepted(candidateIdentity), workerDerivationEpoch);
		const replayReceipt = harness.applicator.apply(
			reviewSnapshot(candidateIdentity, 'item-b', 0, 1, true),
			workerDerivationEpoch,
		);

		// Assert
		expect(replayReceipt).toEqual({ publicationId: candidateIdentity.publicationId });
		expect(harness.applications).toHaveLength(1);
		expect(harness.applications[0]).toMatchObject({ reset: true, sourceEpoch: 1 });
		expect(harness.applications[0]?.source.contentItems.map(({ itemId }) => itemId)).toEqual([
			'item-b',
		]);
	});

	test('rejects changed payload under an exact active publication identity', () => {
		const harness = makeApplicatorHarness();
		harness.applicator.apply(
			reviewSnapshot(candidateIdentity, 'item-b', 0, 1, true),
			workerDerivationEpoch,
		);
		harness.applicator.apply(reviewSourceAccepted(candidateIdentity), workerDerivationEpoch);

		expect(() =>
			harness.applicator.apply(
				reviewSnapshot(candidateIdentity, 'item-b-changed', 0, 1, true),
				workerDerivationEpoch,
			),
		).toThrow(/changed payload/iu);
		expect(harness.applications).toHaveLength(1);
		expect(harness.applications[0]?.source.contentItems.map(({ itemId }) => itemId)).toEqual([
			'item-b',
		]);
	});

	test('rejects a distinct publication identity at the same lineage revision', () => {
		// Arrange
		const harness = makeApplicatorHarness();
		harness.applicator.apply(
			reviewSnapshot(activeIdentity, 'item-a', 0, 1, true),
			workerDerivationEpoch,
		);
		const unorderedIdentity = {
			...activeIdentity,
			publicationId: reviewPublicationId(999),
		};

		// Act / Assert
		expect(() =>
			harness.applicator.apply(reviewReset(unorderedIdentity), workerDerivationEpoch),
		).toThrow(/cannot order distinct sources/iu);
		expect(harness.applications).toHaveLength(1);
		expect(harness.applications[0]?.source.contentItems.map(({ itemId }) => itemId)).toEqual([
			'item-a',
		]);
	});

	test('rejects a gapped final B before mutating or publishing over active A', () => {
		// Arrange
		const harness = makeApplicatorHarness();
		harness.applicator.apply(
			reviewSnapshot(activeIdentity, 'item-a', 0, 1, true),
			workerDerivationEpoch,
		);
		harness.applicator.apply(reviewReset(candidateIdentity), workerDerivationEpoch);
		harness.applicator.apply(reviewSourceAccepted(candidateIdentity), workerDerivationEpoch);
		harness.applicator.apply(
			reviewSnapshot(candidateIdentity, 'item-b-1', 0, 3, false),
			workerDerivationEpoch,
		);
		const publicationCountBeforeFinalBarrier = harness.displayPublications.length;

		// Act / Assert
		expect(() =>
			harness.applicator.apply(
				reviewWindow(candidateIdentity, 'item-b-3', 2, 3, true),
				workerDerivationEpoch,
			),
		).toThrow(/incomplete|hole/iu);
		expect(harness.applications).toHaveLength(1);
		expect(harness.applications[0]?.source.contentItems.map(({ itemId }) => itemId)).toEqual([
			'item-a',
		]);
		expect(harness.displayPublications).toHaveLength(publicationCountBeforeFinalBarrier);
	});

	test('discards failed pending B and republishes readable A as stale', () => {
		// Arrange
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
		harness.displayPublications.splice(0);

		// Act
		const disposition = harness.applicator.handleMetadataFailure(workerDerivationEpoch);

		// Assert
		expect(disposition).toBe('retainedActive');
		expect(harness.applications).toHaveLength(1);
		expect(harness.applications[0]?.source.contentItems.map(({ itemId }) => itemId)).toEqual([
			'item-a',
		]);
		expect(harness.displayPublications).toHaveLength(1);
		expect(harness.displayPublications[0]?.patches).toEqual([
			expect.objectContaining({
				operation: 'upsert',
				payload: expect.objectContaining({ status: 'stale' }),
				slice: 'reviewSource',
			}),
		]);
		expect(JSON.stringify(harness.displayPublications)).toContain('source-active');
		expect(JSON.stringify(harness.displayPublications)).not.toContain('source-candidate');
	});

	test('rolls back complete B when runtime application throws before publication', () => {
		// Arrange
		let rejectCandidateApplication = false;
		const harness = makeApplicatorHarness({
			beforeApplyRuntimeSource: (application): void => {
				if (
					rejectCandidateApplication &&
					application.source.contentItems.some(({ itemId }) => itemId.startsWith('item-b'))
				) {
					throw new Error('injected runtime application failure');
				}
			},
		});
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
		rejectCandidateApplication = true;

		// Act
		expect(() =>
			harness.applicator.apply(
				reviewWindow(candidateIdentity, 'item-b-2', 1, 2, true),
				workerDerivationEpoch,
			),
		).toThrow(/injected runtime application failure/iu);
		rejectCandidateApplication = false;
		const disposition = harness.applicator.handleMetadataFailure(workerDerivationEpoch);

		// Assert
		expect(disposition).toBe('retainedActive');
		expect(JSON.stringify(harness.displayPublications.at(-1))).toContain('source-active');
		expect(JSON.stringify(harness.displayPublications.at(-1))).not.toContain('source-candidate');
		harness.applicator.apply(reviewSourceAccepted(candidateIdentity), workerDerivationEpoch);
		const replayReceipt = harness.applicator.apply(
			reviewSnapshot(candidateIdentity, 'item-b-replay', 0, 1, true),
			workerDerivationEpoch,
		);
		expect(replayReceipt).toEqual({ publicationId: candidateIdentity.publicationId });
		expect(
			harness.applications.filter(({ source }) =>
				source.contentItems.some(({ itemId }) => itemId.startsWith('item-b')),
			),
		).toHaveLength(1);
	});

	test('rolls back complete B when display publication throws after runtime application', () => {
		// Arrange
		let rejectCandidateDisplay = false;
		const harness = makeApplicatorHarness({
			beforePublishDisplayPatches: (publication): void => {
				if (rejectCandidateDisplay && JSON.stringify(publication).includes('source-candidate')) {
					throw new Error('injected display publication failure');
				}
			},
		});
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
		rejectCandidateDisplay = true;

		// Act
		expect(() =>
			harness.applicator.apply(
				reviewWindow(candidateIdentity, 'item-b-2', 1, 2, true),
				workerDerivationEpoch,
			),
		).toThrow(/injected display publication failure/iu);
		rejectCandidateDisplay = false;
		const disposition = harness.applicator.handleMetadataFailure(workerDerivationEpoch);

		// Assert
		expect(disposition).toBe('retainedActive');
		expect(JSON.stringify(harness.displayPublications.at(-1))).toContain('source-active');
		expect(JSON.stringify(harness.displayPublications.at(-1))).not.toContain('source-candidate');
	});

	test('rolls back a successor delta until its replay applies successfully', () => {
		// Arrange
		let rejectDeltaApplication = false;
		const harness = makeApplicatorHarness({
			beforeApplyRuntimeSource: (application): void => {
				if (rejectDeltaApplication && !application.reset) {
					throw new Error('injected successor delta application failure');
				}
			},
		});
		harness.applicator.apply(
			reviewSnapshot(activeIdentity, 'item-a', 0, 1, true),
			workerDerivationEpoch,
		);
		const delta = reviewDelta(activeIdentity, 12);
		rejectDeltaApplication = true;

		// Act
		expect(() => harness.applicator.apply(delta, workerDerivationEpoch)).toThrow(
			/injected successor delta application failure/iu,
		);
		rejectDeltaApplication = false;
		const disposition = harness.applicator.handleMetadataFailure(workerDerivationEpoch);
		const replayReceipt = harness.applicator.apply(delta, workerDerivationEpoch);
		const exactReplayReceipt = harness.applicator.apply(delta, workerDerivationEpoch);

		// Assert
		expect(disposition).toBe('retainedActive');
		expect(replayReceipt).toEqual({ publicationId: delta.publicationId });
		expect(exactReplayReceipt).toEqual({ publicationId: delta.publicationId });
		expect(harness.applications.map(({ reset }) => reset)).toEqual([true, false]);
	});

	test('reopens Review after a final B application failure and commits replayed B once', async () => {
		const firstEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const replayEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		let firstCancelCount = 0;
		let openedSubscriptionCount = 0;
		const subscriptions: readonly BridgeProductSubscription<'review.metadata'>[] = [
			{
				cancel: async (): Promise<void> => {
					firstCancelCount += 1;
				},
				events: firstEvents,
				subscriptionId: 'review-transaction-application-failure',
				subscriptionKind: 'review.metadata',
				update: async (): Promise<void> => {},
			},
			{
				cancel: async (): Promise<void> => {},
				events: replayEvents,
				subscriptionId: 'review-transaction-replay',
				subscriptionKind: 'review.metadata',
				update: async (): Promise<void> => {},
			},
		];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: reviewMetadataTransport(subscriptions, (): void => {
				openedSubscriptionCount += 1;
			}),
		});
		await flushBridgeWorkerRuntimeContinuations();
		firstEvents.push(reviewSnapshot(activeIdentity, 'item-a', 0, 1, true));
		await flushBridgeWorkerRuntimeContinuations();
		firstEvents.push(reviewReset(candidateIdentity));
		firstEvents.push(reviewSourceAccepted(candidateIdentity));
		firstEvents.push(reviewSnapshot(candidateIdentity, 'item-b-1', 0, 3, false));
		firstEvents.push(reviewWindow(candidateIdentity, 'item-b-3', 2, 3, true));

		await flushBridgeWorkerRuntimeContinuations();

		expect(firstCancelCount).toBe(1);
		expect(openedSubscriptionCount).toBe(2);
		const failureDisplayMessages = postedMessages
			.map(({ message }) => message)
			.filter((message) => message.kind === 'reviewDisplayPatch');
		expect(JSON.stringify(failureDisplayMessages.at(-1))).toContain('source-active');
		expect(JSON.stringify(failureDisplayMessages.at(-1))).not.toContain('source-candidate');

		replayEvents.push(reviewSourceAccepted(candidateIdentity));
		replayEvents.push(reviewSnapshot(candidateIdentity, 'item-b-replay', 0, 1, true));
		await flushBridgeWorkerRuntimeContinuations();

		const replayPublications = postedMessages
			.map(({ message }) => message)
			.filter(
				(message) =>
					message.kind === 'reviewDisplayPatch' &&
					JSON.stringify(message).includes('source-candidate'),
			);
		expect(replayPublications).toHaveLength(1);
		expect(JSON.stringify(replayPublications[0])).toContain('item-b-replay');
	});

	test('rolls back the real worker store when the critical B display post fails', async () => {
		// Arrange
		const firstEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const replayEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		let firstCancelCount = 0;
		let openedSubscriptionCount = 0;
		let appliedReceiptCount = 0;
		let rejectCandidateDisplay = false;
		const subscriptions: readonly BridgeProductSubscription<'review.metadata'>[] = [
			{
				cancel: async (): Promise<void> => {
					firstCancelCount += 1;
				},
				events: firstEvents,
				subscriptionId: 'review-transaction-display-failure',
				subscriptionKind: 'review.metadata',
				update: async (): Promise<void> => {},
			},
			{
				cancel: async (): Promise<void> => {},
				events: replayEvents,
				subscriptionId: 'review-transaction-display-replay',
				subscriptionKind: 'review.metadata',
				update: async (): Promise<void> => {},
			},
		];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort({
			beforePostMessage: (message): void => {
				if (
					rejectCandidateDisplay &&
					message.kind === 'reviewDisplayPatch' &&
					JSON.stringify(message).includes('source-candidate')
				) {
					throw new Error('injected critical B display failure');
				}
			},
		});
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: reviewMetadataTransport(
				subscriptions,
				(): void => {
					openedSubscriptionCount += 1;
				},
				(): void => {
					appliedReceiptCount += 1;
				},
			),
		});
		await flushBridgeWorkerRuntimeContinuations();
		firstEvents.push(reviewSnapshot(activeIdentity, 'item-a', 0, 1, true));
		await flushBridgeWorkerRuntimeContinuations();
		const activeSlicePatchCount = postedMessages.filter(
			({ message }) => message.kind === 'slicePatch',
		).length;
		rejectCandidateDisplay = true;

		// Act
		firstEvents.push(reviewReset(candidateIdentity));
		firstEvents.push(reviewSourceAccepted(candidateIdentity));
		firstEvents.push(reviewSnapshot(candidateIdentity, 'item-b', 0, 1, true));
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(firstCancelCount).toBe(1);
		expect(openedSubscriptionCount).toBe(2);
		expect(appliedReceiptCount).toBe(1);
		expect(postedMessages.filter(({ message }) => message.kind === 'slicePatch')).toHaveLength(
			activeSlicePatchCount,
		);
		const failureDisplayMessages = postedMessages
			.map(({ message }) => message)
			.filter((message) => message.kind === 'reviewDisplayPatch');
		expect(JSON.stringify(failureDisplayMessages.at(-1))).toContain('source-active');
		expect(JSON.stringify(failureDisplayMessages)).not.toContain('source-candidate');

		rejectCandidateDisplay = false;
		replayEvents.push(reviewSourceAccepted(candidateIdentity));
		replayEvents.push(reviewSnapshot(candidateIdentity, 'item-b', 0, 1, true));
		await flushBridgeWorkerRuntimeContinuations();
		const candidateDisplayMessages = postedMessages
			.map(({ message }) => message)
			.filter(
				(message) =>
					message.kind === 'reviewDisplayPatch' &&
					JSON.stringify(message).includes('source-candidate'),
			);
		expect(candidateDisplayMessages).toHaveLength(1);
		expect(appliedReceiptCount).toBe(2);
	});

	test('keeps applied B when post-commit drain scheduling fails', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		let cancelCount = 0;
		let openedSubscriptionCount = 0;
		let appliedReceiptCount = 0;
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {
				cancelCount += 1;
			},
			events,
			subscriptionId: 'review-transaction-post-commit-drain-failure',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: reviewMetadataTransport(
				reviewSubscription,
				(): void => {
					openedSubscriptionCount += 1;
				},
				(): void => {
					appliedReceiptCount += 1;
				},
			),
			schedulePreparationDrain: (): never => {
				throw new Error('injected post-commit drain scheduling failure');
			},
		});
		await flushBridgeWorkerRuntimeContinuations();

		// Act
		events.push(reviewSnapshot(activeIdentity, 'item-a', 0, 1, true));
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(appliedReceiptCount).toBe(1);
		expect(cancelCount).toBe(0);
		expect(openedSubscriptionCount).toBe(1);
		expect(
			postedMessages.filter(
				({ message }) =>
					message.kind === 'reviewDisplayPatch' &&
					JSON.stringify(message).includes('source-active'),
			),
		).toHaveLength(1);
		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({ kind: 'health', status: 'degraded' }),
		);
	});

	test('routes a pending subscription failure without replacing the active runtime source', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'review-transaction-failure',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: reviewMetadataTransport(reviewSubscription),
		});
		await flushBridgeWorkerRuntimeContinuations();
		events.push(reviewSnapshot(activeIdentity, 'item-a', 0, 1, true));
		await flushBridgeWorkerRuntimeContinuations();
		const activeSlicePatchCount = postedMessages.filter(
			({ message }) => message.kind === 'slicePatch',
		).length;
		events.push(reviewReset(candidateIdentity));
		events.push(reviewSourceAccepted(candidateIdentity));
		events.push(reviewSnapshot(candidateIdentity, 'item-b-1', 0, 2, false));
		await flushBridgeWorkerRuntimeContinuations();

		// Act
		events.fail(new Error('private pending B failure'), true);
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(postedMessages.filter(({ message }) => message.kind === 'slicePatch')).toHaveLength(
			activeSlicePatchCount,
		);
		const reviewDisplayMessages = postedMessages
			.map(({ message }) => message)
			.filter((message) => message.kind === 'reviewDisplayPatch');
		expect(reviewDisplayMessages.at(-1)).toMatchObject({
			patches: [
				{
					operation: 'upsert',
					payload: { status: 'stale' },
					slice: 'reviewSource',
				},
			],
		});
		expect(JSON.stringify(reviewDisplayMessages.at(-1))).toContain('source-active');
		expect(JSON.stringify(reviewDisplayMessages.at(-1))).not.toMatch(
			/source-candidate|metadataUnavailable|private pending B failure/iu,
		);
	});
});
