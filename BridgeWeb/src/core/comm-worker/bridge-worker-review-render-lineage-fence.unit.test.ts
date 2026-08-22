import { describe, expect, test } from 'vitest';

import { makeFetchedReviewContentResource } from './bridge-comm-worker-entry.test-support.js';
import { makeRenderSemantics } from './bridge-comm-worker-runtime-protocol.test-support.js';
import {
	bridgeWorkerReviewPierreRenderJobEventSchema,
	bridgeWorkerReviewRenderPatchEventSchema,
	type BridgeWorkerReviewPierreRenderJobEvent,
	type BridgeWorkerReviewPublicationIdentity,
	type BridgeWorkerReviewRenderPatchEvent,
} from './bridge-worker-contracts.js';
import { assertBridgeWorkerReviewPublicationIdentityMatches } from './bridge-worker-pierre-publication-identity-contracts.js';
import { makeBridgeWorkerRenderReceiptIdentity } from './bridge-worker-render-fulfillment.test-support.js';
import { prepareBridgeWorkerReviewRenderPatchEvent } from './bridge-worker-review-content-ready.js';
import {
	createBridgeWorkerReviewPierreRenderJobPlanningSession,
	prepareBridgeWorkerReviewPierreRenderJobEventFromJob,
	type BridgeWorkerReviewPierreRenderJobPlanningSession,
} from './bridge-worker-review-pierre-job-planner.js';

const publicationB = reviewPublicationIdentity(11);
const publicationC = reviewPublicationIdentity(12);

describe('Bridge worker Review render lineage fence', () => {
	test('preserves B and C identity when B preparation completes after C in one worker epoch', () => {
		const preparationB = createPlanningSession('B');
		const preparationC = createPlanningSession('C');
		expect(preparationB.runNextStage()).toEqual({ status: 'pending' });

		const jobC = completePlanning(preparationC);
		const pierreC = preparePierrePublication(jobC, publicationC, 22);
		const renderC = prepareRenderPublication(publicationC, 22);
		const jobB = completePlanning(preparationB);
		const pierreB = preparePierrePublication(jobB, publicationB, 21);
		const renderB = prepareRenderPublication(publicationB, 21);

		expect(pierreC.reviewPublicationIdentity).toEqual(publicationC);
		expect(renderC.reviewPublicationIdentity).toEqual(publicationC);
		expect(pierreB.reviewPublicationIdentity).toEqual(publicationB);
		expect(renderB.reviewPublicationIdentity).toEqual(publicationB);
		expect(pierreB.workerDerivationEpoch).toBe(pierreC.workerDerivationEpoch);
		expect(renderB.workerDerivationEpoch).toBe(renderC.workerDerivationEpoch);
		expect(() =>
			assertBridgeWorkerReviewPublicationIdentityMatches(
				publicationC,
				pierreB.reviewPublicationIdentity,
			),
		).toThrow(/preparation ticket/iu);
	});

	test('requires one strict full Review identity on render and Pierre publications', () => {
		const validPierre = preparePierrePublication(
			completePlanning(createPlanningSession('strict')),
			publicationB,
			21,
		);
		const validRender = prepareRenderPublication(publicationB, 21);

		for (const [schema, publication] of [
			[bridgeWorkerReviewPierreRenderJobEventSchema, validPierre],
			[bridgeWorkerReviewRenderPatchEventSchema, validRender],
		] as const) {
			const { reviewPublicationIdentity: _omitted, ...withoutIdentity } = publication;
			expect(schema.safeParse(withoutIdentity).success).toBe(false);
			expect(
				schema.safeParse({
					...publication,
					reviewPublicationIdentity: { publicationId: publicationB.publicationId },
				}).success,
			).toBe(false);
			expect(
				schema.safeParse({
					...publication,
					reviewPublicationIdentity: {
						...publicationB,
						currentPublicationId: publicationC.publicationId,
					},
				}).success,
			).toBe(false);
		}
	});
});

function createPlanningSession(label: string): BridgeWorkerReviewPierreRenderJobPlanningSession {
	return createBridgeWorkerReviewPierreRenderJobPlanningSession({
		bridgeDemandRank: { lane: 'selected', priority: 0 },
		budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
		resources: [
			makeFetchedReviewContentResource({
				contentHash: `sha256:item-1:base:${label}`,
				role: 'base',
				text: `base ${label}\n`,
			}),
			makeFetchedReviewContentResource({
				contentHash: `sha256:item-1:head:${label}`,
				role: 'head',
				text: `head ${label}\n`,
			}),
		],
		semantics: makeRenderSemantics({ itemId: 'item-1' }),
	});
}

function completePlanning(
	preparation: BridgeWorkerReviewPierreRenderJobPlanningSession,
): NonNullable<
	Extract<ReturnType<typeof preparation.runNextStage>, { status: 'complete' }>['job']
> {
	while (true) {
		const result = preparation.runNextStage();
		if (result.status === 'pending') continue;
		if (result.job === null) throw new Error('Expected a complete Review render job.');
		return result.job;
	}
}

function preparePierrePublication(
	job: ReturnType<typeof completePlanning>,
	identity: BridgeWorkerReviewPublicationIdentity,
	publicationSequence: number,
): BridgeWorkerReviewPierreRenderJobEvent {
	return prepareBridgeWorkerReviewPierreRenderJobEventFromJob({
		job,
		renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
			itemId: job.itemId,
			publicationSequence,
			surface: 'review',
			workerDerivationEpoch: 7,
		}),
		reviewPublicationIdentity: identity,
	}).message;
}

function prepareRenderPublication(
	identity: BridgeWorkerReviewPublicationIdentity,
	publicationSequence: number,
): BridgeWorkerReviewRenderPatchEvent {
	return prepareBridgeWorkerReviewRenderPatchEvent({
		patches: [{ operation: 'reset', slice: 'panelChrome' }],
		publicationSequence,
		reviewPublicationIdentity: identity,
		workerDerivationEpoch: 7,
	}).message;
}

function reviewPublicationIdentity(revision: number): BridgeWorkerReviewPublicationIdentity {
	return {
		packageId: `review-package-${revision}`,
		publicationId: `00000000-0000-7000-8000-${revision.toString().padStart(12, '0')}`,
		reviewGeneration: revision,
		revision,
		sourceIdentity: `review-source-${revision}`,
	};
}
