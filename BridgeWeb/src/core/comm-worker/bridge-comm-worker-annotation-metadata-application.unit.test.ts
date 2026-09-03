import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerAnnotationMetadataApplication } from './bridge-comm-worker-annotation-metadata-application.js';
import type { BridgeProductMetadataDataFrame } from './bridge-product-metadata-application-protocol.js';
import { bridgeProductReviewAnnotationMetadataApplicationProtocol } from './bridge-product-metadata-application-registry.js';
import type {
	BridgeProductWorktreeAnnotationCatalogEntry,
	BridgeProductWorktreeAnnotationEvent,
} from './bridge-product-worktree-annotation-contracts.js';

const sessionId = '01890abc-def0-7abc-8def-0123456789ab';
const threadId = '01890abc-def0-7abc-8def-0123456789ac';
const firstWorktreeId = 'worktree-1';
const replacementWorktreeId = 'worktree-2';

type AnnotationMetadataFrame = BridgeProductMetadataDataFrame<BridgeProductWorktreeAnnotationEvent>;

describe('Bridge communication worker annotation metadata application authority', () => {
	test('commits a registered session-scoped thread into the normalized worker catalog', () => {
		const application = new BridgeCommWorkerAnnotationMetadataApplication();
		const catalogActions = commitCatalog(application, {
			catalogRevision: 1,
			subscriptionId: 'annotation-subscription-session-scope',
			worktreeId: firstWorktreeId,
			workerDerivationEpoch: 1,
		});
		const committedCatalogAction = catalogActions.at(-1);

		expect(committedCatalogAction?.kind).toBe('catalog');
		if (committedCatalogAction?.kind !== 'catalog') return;
		expect(committedCatalogAction.catalog.threadsById.get(threadId)).toMatchObject({
			scope: 'session',
			sessionId,
			threadId,
		});
	});

	test('ignores noncatalog events before a lifecycle catalog establishes authority', () => {
		const application = new BridgeCommWorkerAnnotationMetadataApplication();

		expect(
			application.accept(
				frame({
					event: {
						authority: { applicationSourceGeneration: 1, worktreeId: firstWorktreeId },
						kind: 'annotation.controlChanged',
						reason: 'discovery',
					},
				}),
				[],
			),
		).toEqual({ kind: 'none' });
	});

	test('rejects a same-lifecycle worktree replacement and admits a new lifecycle catalog', () => {
		const application = new BridgeCommWorkerAnnotationMetadataApplication();
		const firstCatalogActions = commitCatalog(application, {
			catalogRevision: 20,
			subscriptionId: 'annotation-subscription-1',
			worktreeId: firstWorktreeId,
			workerDerivationEpoch: 1,
		});
		expect(firstCatalogActions.at(-1)?.kind).toBe('catalog');
		expect(
			application.accept(
				frame({
					event: {
						authority: { applicationSourceGeneration: 21, worktreeId: replacementWorktreeId },
						kind: 'annotation.controlChanged',
						reason: 'discovery',
					},
				}),
				[],
			),
		).toEqual({ kind: 'none' });
		expect(
			application.accept(
				frame({
					event: {
						authority: { applicationSourceGeneration: 21, worktreeId: replacementWorktreeId },
						kind: 'annotation.sessionChanged',
						semanticRevision: 4,
						sessionId,
					},
				}),
				[sessionId],
			),
		).toEqual({ kind: 'none' });

		const sameLifecycleReplacementActions = commitCatalog(application, {
			catalogRevision: 21,
			subscriptionId: 'annotation-subscription-1',
			worktreeId: replacementWorktreeId,
			workerDerivationEpoch: 1,
		});
		expect(sameLifecycleReplacementActions).toEqual([
			{ kind: 'none' },
			{ kind: 'none' },
			{ kind: 'none' },
		]);

		const replacementCatalogActions = commitCatalog(application, {
			catalogRevision: 1,
			subscriptionId: 'annotation-subscription-2',
			worktreeId: replacementWorktreeId,
			workerDerivationEpoch: 2,
		});
		expect(replacementCatalogActions.at(-1)).toMatchObject({ kind: 'catalog' });
	});
});

function commitCatalog(
	application: BridgeCommWorkerAnnotationMetadataApplication,
	props: {
		readonly catalogRevision: number;
		readonly subscriptionId: string;
		readonly worktreeId: string;
		readonly workerDerivationEpoch: number;
	},
): readonly ReturnType<BridgeCommWorkerAnnotationMetadataApplication['accept']>[] {
	const transferId = `${props.subscriptionId}-${props.catalogRevision}`;
	const entries = validCatalogEntries();
	const events: readonly BridgeProductWorktreeAnnotationEvent[] = [
		{
			authority: {
				applicationSourceGeneration: props.catalogRevision,
				worktreeId: props.worktreeId,
			},
			kind: 'annotation.catalog',
			transfer: {
				catalogRevision: props.catalogRevision,
				expectedEntryCount: entries.length,
				kind: 'catalog.begin',
				transferId,
			},
		},
		{
			authority: {
				applicationSourceGeneration: props.catalogRevision,
				worktreeId: props.worktreeId,
			},
			kind: 'annotation.catalog',
			transfer: {
				catalogRevision: props.catalogRevision,
				entries,
				kind: 'catalog.window',
				transferId,
				windowOrdinal: 0,
			},
		},
		{
			authority: {
				applicationSourceGeneration: props.catalogRevision,
				worktreeId: props.worktreeId,
			},
			kind: 'annotation.catalog',
			transfer: {
				catalogRevision: props.catalogRevision,
				entryCount: entries.length,
				kind: 'catalog.commit',
				transferId,
				windowCount: 1,
			},
		},
	];

	return events.map((event, index) => {
		const registeredData =
			bridgeProductReviewAnnotationMetadataApplicationProtocol.dataSchema.parse({
				event,
				subscriptionKind: 'review.annotations',
			});
		return application.accept(
			frame({
				event: registeredData.event,
				streamSequence: index + 1,
				subscriptionId: props.subscriptionId,
				subscriptionSequence: index + 1,
				workerDerivationEpoch: props.workerDerivationEpoch,
			}),
			[],
		);
	});
}

function frame(props: {
	readonly event: BridgeProductWorktreeAnnotationEvent;
	readonly streamSequence?: number;
	readonly subscriptionId?: string;
	readonly subscriptionSequence?: number;
	readonly workerDerivationEpoch?: number;
}): AnnotationMetadataFrame {
	return {
		data: props.event,
		metadataStreamId: 'annotation-metadata-stream',
		operationCorrelationId: null,
		sourceGeneration: props.event.authority.applicationSourceGeneration,
		streamSequence: props.streamSequence ?? 1,
		subscriptionId: props.subscriptionId ?? 'annotation-subscription-1',
		subscriptionKind: 'review.annotations',
		subscriptionSequence: props.subscriptionSequence ?? 1,
		workerDerivationEpoch: props.workerDerivationEpoch ?? 1,
	};
}

function validCatalogEntries(): readonly BridgeProductWorktreeAnnotationCatalogEntry[] {
	return [
		{ kind: 'session', semanticRevision: 3, sessionId },
		{ createdOrdinal: 0, kind: 'thread', scope: 'session', sessionId, threadId },
	];
}
