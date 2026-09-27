import { describe, expect, test } from 'vitest';

import commentCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-comment-catalog-record-corpus.json' with { type: 'json' };
import fileCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-file-batch-row-corpus.json' with { type: 'json' };
import reviewCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-review-batch-record-corpus.json' with { type: 'json' };
import sessionCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-session-corpus.json' with { type: 'json' };
import { BridgeCommWorkerProductBatchApplication } from './bridge-comm-worker-product-batch-application.js';
import {
	bridgeProductBatchFrameSchema,
	type BridgeProductBatchFrame,
} from './bridge-product-batch-wire-contracts.js';
import type { BridgeProductViewInstallation } from './bridge-product-view-batch-receiver.js';

function batchBegin(
	subscriptionKind: 'file.metadata' | 'review.metadata' | 'file.annotations',
): Extract<BridgeProductBatchFrame, { readonly kind: 'subscription.batchBegin' }> {
	const source = sessionCorpus.transportV2.batchFrames.find(
		(frame) => frame.kind === 'subscription.batchBegin',
	);
	const publication = reviewCorpus.records[1]?.record;
	const frame = bridgeProductBatchFrameSchema.parse({
		...source,
		publicationId:
			subscriptionKind === 'review.metadata' && publication?.recordKind === 'publication'
				? publication.publicationId
				: undefined,
		scope:
			subscriptionKind === 'file.metadata'
				? { kind: 'file', changeFilter: { kind: 'none' }, interests: [], pathScope: [] }
				: subscriptionKind === 'review.metadata'
					? { kind: 'review', interests: [] }
					: { kind: 'comment', sessionIds: [], worktreeId: 'worktree-1' },
		subscriptionKind,
		targetRevision: subscriptionKind === 'review.metadata' ? 1 : 4,
	});
	if (frame.kind !== 'subscription.batchBegin') throw new Error('Batch begin fixture missing.');
	return frame;
}

describe('Bridge comm worker product batch application owner', () => {
	test('routes certified File, Review and Comment banks to their typed owners', async () => {
		const installedKinds: string[] = [];
		const application = new BridgeCommWorkerProductBatchApplication({
			applyComment: (catalog, surface): void => {
				expect(catalog.orderedSessionIds).toHaveLength(1);
				expect(surface).toBe('file');
				installedKinds.push('comment');
			},
			applyFile: (view): void => {
				expect(view.memberStatus.kind).toBe('memberStatus');
				installedKinds.push('file');
			},
			applyReview: (presentation): void => {
				expect(presentation.publication.displayed).toBeNull();
				installedKinds.push('review');
			},
			createSequence: (): number => 1,
			publishMessage: (): void => {},
			publishReviewDisplay: (): void => {},
			requestResnapshot: (): void => {},
			workerDerivationEpoch: (): number => 2,
		});
		const fileInstallation: BridgeProductViewInstallation = {
			begin: batchBegin('file.metadata'),
			domain: 'default',
			records: [
				...fileCorpus.rows.map(({ recordKey, row }) => ({
					key: recordKey,
					revision: 1,
					value: row,
				})),
				{ key: 'member-status', revision: 1, value: fileCorpus.memberStatuses[0]?.record },
			],
		};
		const emptyPublication = reviewCorpus.records[1];
		if (emptyPublication?.record.recordKind !== 'publication')
			throw new Error('Review publication fixture missing.');
		if (emptyPublication.record.revision === undefined)
			throw new Error('Review publication fixture has no revision.');
		const reviewInstallation: BridgeProductViewInstallation = {
			begin: batchBegin('review.metadata'),
			domain: 'default',
			records: [
				{
					key: emptyPublication.recordKey,
					revision: emptyPublication.record.revision,
					value: emptyPublication.record,
				},
			],
		};
		const commentInstallation: BridgeProductViewInstallation = {
			begin: batchBegin('file.annotations'),
			domain: 'default',
			records: [
				...new Map(
					commentCorpus.records.map(({ recordKey, record }) => [
						recordKey,
						{ key: recordKey, revision: record.revision, value: record },
					]),
				).values(),
			],
		};
		await application.sinks().install(fileInstallation);
		await application.sinks().install(reviewInstallation);
		await application.sinks().install(commentInstallation);
		expect(installedKinds).toEqual(['file', 'review', 'comment']);
	});
});
