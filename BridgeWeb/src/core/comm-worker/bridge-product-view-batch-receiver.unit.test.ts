import { describe, expect, it } from 'vitest';

import commentCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-comment-catalog-record-corpus.json' with { type: 'json' };
import fileCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-file-batch-row-corpus.json' with { type: 'json' };
import { BridgeProductBatchFrameRouter } from './bridge-product-batch-frame-router.js';
import {
	bridgeProductBatchFrameSchema,
	type BridgeProductBatchFrame,
} from './bridge-product-batch-wire-contracts.js';
import { parseBridgeProductStrictJSON } from './bridge-product-strict-json.js';
import { BridgeProductViewBatchReceiver } from './bridge-product-view-batch-receiver.js';

const identity = {
	batchId: 'batch-1',
	domain: 'default',
	handle: 'handle-1',
	incarnation: 'incarnation-1',
	metadataStreamId: 'stream-1',
	paneSessionId: 'pane-1',
	scopeRevision: 0,
	streamSequence: 1,
	subscriptionId: 'subscription-1',
	subscriptionKind: 'review.metadata',
	wireVersion: 2,
	workerInstanceId: 'worker-1',
} as const;

let nextFixtureStreamSequence = 0;

function fixtureStreamSequence(): number {
	nextFixtureStreamSequence += 1;
	return nextFixtureStreamSequence;
}

function receiver(
	coversKey?: (scope: Readonly<Record<string, unknown>>, key: string) => boolean,
): BridgeProductViewBatchReceiver {
	return new BridgeProductViewBatchReceiver({
		...(coversKey === undefined ? {} : { coversKey }),
		handle: identity.handle,
		scope: { kind: 'review', interests: [] },
		scopeRevision: 0,
		subscriptionId: identity.subscriptionId,
		subscriptionKind: identity.subscriptionKind,
	});
}

function begin(props: {
	readonly batchId?: string;
	readonly base?: number;
	readonly domain?: string;
	readonly handle?: string;
	readonly incarnation?: string;
	readonly mode?: 'snapshot' | 'change' | 'coverage';
	readonly partCount: number;
	readonly requiresCollection?: number;
	readonly scope?: Readonly<Record<string, unknown>>;
	readonly scopeRevision?: number;
	readonly target: number;
}): BridgeProductBatchFrame {
	return bridgeProductBatchFrameSchema.parse({
		...identity,
		streamSequence: fixtureStreamSequence(),
		batchId: props.batchId ?? identity.batchId,
		baseRevision: props.base ?? 0,
		domain: props.domain ?? identity.domain,
		handle: props.handle ?? identity.handle,
		incarnation: props.incarnation ?? identity.incarnation,
		kind: 'subscription.batchBegin',
		mode: props.mode ?? 'snapshot',
		partCount: props.partCount,
		publicationId: '00000000-0000-7000-8000-000000000011',
		...(props.requiresCollection === undefined
			? {}
			: { requiresCollection: props.requiresCollection }),
		scope: props.scope ?? { kind: 'review', interests: [] },
		scopeRevision: props.scopeRevision ?? 0,
		targetRevision: props.target,
	});
}

function part(props: {
	readonly batchId?: string;
	readonly domain?: string;
	readonly handle?: string;
	readonly incarnation?: string;
	readonly key: string;
	readonly partIndex?: number;
	readonly revision: number;
	readonly scopeRevision?: number;
	readonly value: string;
}): BridgeProductBatchFrame {
	return bridgeProductBatchFrameSchema.parse({
		...identity,
		streamSequence: fixtureStreamSequence(),
		batchId: props.batchId ?? identity.batchId,
		deliverySequence: props.revision,
		domain: props.domain ?? identity.domain,
		handle: props.handle ?? identity.handle,
		incarnation: props.incarnation ?? identity.incarnation,
		kind: 'subscription.batchPart',
		part: { key: props.key, operation: 'put', revision: props.revision, value: props.value },
		partIndex: props.partIndex ?? 0,
		scopeRevision: props.scopeRevision ?? 0,
	});
}

function deletion(props: {
	readonly batchId: string;
	readonly key: string;
	readonly revision: number;
}): BridgeProductBatchFrame {
	return bridgeProductBatchFrameSchema.parse({
		...identity,
		streamSequence: fixtureStreamSequence(),
		batchId: props.batchId,
		deliverySequence: props.revision,
		kind: 'subscription.batchPart',
		part: { key: props.key, operation: 'delete', revision: props.revision },
		partIndex: 0,
	});
}

function eviction(props: {
	readonly batchId: string;
	readonly scopeRevision: number;
}): BridgeProductBatchFrame {
	return bridgeProductBatchFrameSchema.parse({
		...identity,
		streamSequence: fixtureStreamSequence(),
		batchId: props.batchId,
		deliverySequence: 2,
		kind: 'subscription.batchPart',
		part: { key: 'a', operation: 'evict' },
		partIndex: 0,
		scopeRevision: props.scopeRevision,
	});
}

function complete(props: {
	readonly batchId?: string;
	readonly coveredScope?: Readonly<Record<string, unknown>>;
	readonly domain?: string;
	readonly handle?: string;
	readonly incarnation?: string;
	readonly scopeRevision?: number;
}): BridgeProductBatchFrame {
	return bridgeProductBatchFrameSchema.parse({
		...identity,
		streamSequence: fixtureStreamSequence(),
		batchId: props.batchId ?? identity.batchId,
		coveredScope: props.coveredScope ?? { kind: 'review', interests: [] },
		domain: props.domain ?? identity.domain,
		handle: props.handle ?? identity.handle,
		incarnation: props.incarnation ?? identity.incarnation,
		kind: 'subscription.batchComplete',
		scopeRevision: props.scopeRevision ?? 0,
	});
}

describe('Bridge product W4 per-domain batch receiver', () => {
	it('reports an accepted replacement snapshot once and ignores late parts from its abandoned stage', () => {
		const router = new BridgeProductBatchFrameRouter();
		const replacements: string[] = [];
		const resnapshots: string[] = [];
		const installations: string[] = [];
		router.setSinks({
			install: (installation): void => {
				installations.push(installation.begin.batchId);
			},
			receipt: (): void => {},
			replacementSnapshot: (frame): void => {
				replacements.push(frame.batchId);
			},
			resnapshot: (frame): void => {
				resnapshots.push(frame.batchId);
			},
		});
		router.accept(begin({ batchId: 'abandoned', partCount: 2, target: 2 }));
		router.accept(part({ batchId: 'abandoned', key: 'a', revision: 1, value: 'old' }));
		const latePart = part({
			batchId: 'abandoned',
			key: 'b',
			partIndex: 1,
			revision: 2,
			value: 'late',
		});
		const lateComplete = complete({ batchId: 'abandoned' });
		for (let index = 0; index < 12; index += 1) {
			router.accept(begin({ batchId: `replacement-${index}`, partCount: 1, target: 3 + index }));
		}
		router.accept(latePart);
		router.accept(lateComplete);
		router.accept(part({ batchId: 'replacement-11', key: 'a', revision: 14, value: 'current' }));
		router.accept(complete({ batchId: 'replacement-11' }));
		expect(replacements).toEqual(Array.from({ length: 12 }, (_, index) => `replacement-${index}`));
		expect(resnapshots).toEqual([]);
		expect(installations).toEqual(['replacement-11']);
	});
	it('routes a received part credit before the certified bank install', () => {
		const router = new BridgeProductBatchFrameRouter();
		const events: string[] = [];
		router.setSinks({
			install: (installation): void => {
				events.push(`installed:${installation.domain}:${installation.records.length}`);
			},
			receipt: (_, through): void => {
				events.push(`received:${through}`);
			},
			resnapshot: (): void => {
				events.push('resnapshot');
			},
		});
		router.accept(begin({ partCount: 1, target: 1 }));
		router.accept(part({ key: 'a', revision: 1, value: 'A' }));
		expect(events).toEqual(['received:1']);
		router.accept(complete({}));
		expect(events).toEqual(['received:1', 'installed:default:1']);
	});

	it('an application rejection resnapshots only its subscription while a sibling installs', () => {
		const router = new BridgeProductBatchFrameRouter();
		const resnapshots: string[] = [];
		const installed: string[] = [];
		router.setSinks({
			install: (installation): void => {
				if (installation.begin.subscriptionId === identity.subscriptionId) {
					throw new Error('The typed application rejected this bank.');
				}
				installed.push(installation.begin.subscriptionId);
			},
			receipt: (): void => {},
			resnapshot: (frame): void => {
				resnapshots.push(frame.subscriptionId);
			},
		});
		router.accept(begin({ partCount: 1, target: 1 }));
		router.accept(part({ key: 'a', revision: 1, value: 'A' }));
		router.accept(complete({}));
		const siblingSubscriptionId = 'sibling-subscription';
		router.accept(
			bridgeProductBatchFrameSchema.parse({
				...begin({ batchId: 'sibling-batch', partCount: 1, target: 1 }),
				subscriptionId: siblingSubscriptionId,
			}),
		);
		router.accept(
			bridgeProductBatchFrameSchema.parse({
				...part({ batchId: 'sibling-batch', key: 'b', revision: 1, value: 'B' }),
				subscriptionId: siblingSubscriptionId,
			}),
		);
		router.accept(
			bridgeProductBatchFrameSchema.parse({
				...complete({ batchId: 'sibling-batch' }),
				subscriptionId: siblingSubscriptionId,
			}),
		);
		expect(resnapshots).toEqual([identity.subscriptionId]);
		expect(installed).toEqual([siblingSubscriptionId]);
	});

	it('an asynchronous typed install rejection resnapshots after receipt credit', async () => {
		const router = new BridgeProductBatchFrameRouter();
		const events: string[] = [];
		let rejectInstallation: ((error: Error) => void) | undefined;
		const installation = new Promise<void>((_resolve, reject): void => {
			rejectInstallation = reject;
		});
		router.setSinks({
			install: (): Promise<void> => installation,
			receipt: (): void => {
				events.push('receipt');
			},
			resnapshot: (): void => {
				events.push('resnapshot');
			},
		});
		router.accept(begin({ partCount: 1, target: 1 }));
		router.accept(part({ key: 'a', revision: 1, value: 'A' }));
		router.accept(complete({}));
		expect(events).toEqual(['receipt']);
		rejectInstallation?.(new Error('The Review installer rejected its certified bank.'));
		await Promise.resolve();
		expect(events).toEqual(['receipt', 'resnapshot']);
	});

	it('installs all four kinds through strict JSON and the batch wire contract', () => {
		const cases = [
			{
				key: fileCorpus.rows[0]?.recordKey,
				kind: 'file.metadata',
				scope: { kind: 'file', changeFilter: { kind: 'none' }, interests: [], pathScope: [] },
				value: fileCorpus.rows[0]?.row,
			},
			{
				key: 'review:item-a',
				kind: 'review.metadata',
				scope: { kind: 'review', interests: [] },
				value: { itemId: 'item-a' },
			},
			{
				key: commentCorpus.records[0]?.recordKey,
				kind: 'file.annotations',
				scope: { kind: 'comment', sessionIds: [], worktreeId: 'worktree-1' },
				value: commentCorpus.records[0]?.record,
			},
			{
				key: commentCorpus.records[0]?.recordKey,
				kind: 'review.annotations',
				scope: { kind: 'comment', sessionIds: [], worktreeId: 'worktree-1' },
				value: commentCorpus.records[0]?.record,
			},
		] as const;
		for (const entry of cases) {
			expect(entry.key).toBeDefined();
			const state = new BridgeProductViewBatchReceiver({
				handle: identity.handle,
				scope: entry.scope,
				scopeRevision: 0,
				subscriptionId: identity.subscriptionId,
				subscriptionKind: entry.kind,
			});
			state.admitDomain('default', 'incarnation-1');
			const frames = [
				{
					...identity,
					kind: 'subscription.batchBegin',
					subscriptionKind: entry.kind,
					scope: entry.scope,
					baseRevision: 0,
					mode: 'snapshot',
					partCount: 1,
					...(entry.kind === 'review.metadata'
						? { publicationId: '00000000-0000-7000-8000-000000000011' }
						: {}),
					targetRevision: 1,
					streamSequence: 1,
				},
				{
					...identity,
					kind: 'subscription.batchPart',
					subscriptionKind: entry.kind,
					deliverySequence: 1,
					part: { operation: 'put', key: entry.key, revision: 1, value: entry.value },
					partIndex: 0,
					streamSequence: 2,
				},
				{
					...identity,
					kind: 'subscription.batchComplete',
					subscriptionKind: entry.kind,
					coveredScope: entry.scope,
					streamSequence: 3,
				},
			];
			for (const frame of frames) {
				const validated = bridgeProductBatchFrameSchema.parse(frame);
				const rawBytes = new TextEncoder().encode(JSON.stringify(validated));
				state.accept(bridgeProductBatchFrameSchema.parse(parseBridgeProductStrictJSON(rawBytes)));
			}
			expect(state.records('default')).toEqual([
				{ key: entry.key, revision: 1, value: entry.value },
			]);
		}
	});

	it('keeps installed rows until every declared part completes, then swaps atomically', () => {
		const state = receiver();
		state.admitDomain('default', 'incarnation-1');
		expect(state.accept(begin({ partCount: 2, target: 2 })).kind).toBe('staged');
		expect(state.accept(part({ key: 'a', revision: 1, value: 'A' })).kind).toBe('staged');
		expect(state.records('default')).toEqual([]);
		expect(state.accept(complete({})).kind).toBe('resnapshot');
		expect(state.records('default')).toEqual([]);

		state.accept(begin({ batchId: 'batch-2', partCount: 1, target: 3 }));
		state.accept(part({ batchId: 'batch-2', key: 'a', revision: 3, value: 'new' }));
		expect(state.accept(complete({ batchId: 'batch-2' })).kind).toBe('installed');
		expect(state.records('default')).toEqual([{ key: 'a', revision: 3, value: 'new' }]);
	});

	it('a zero-part coverage batch changes the cursor without pruning existing rows', () => {
		const state = receiver();
		state.admitDomain('default', 'incarnation-1');
		state.accept(begin({ partCount: 1, target: 1 }));
		state.accept(part({ key: 'a', revision: 1, value: 'A' }));
		state.accept(complete({}));
		state.accept(
			begin({ batchId: 'coverage-2', base: 1, mode: 'coverage', partCount: 0, target: 2 }),
		);
		expect(state.accept(complete({ batchId: 'coverage-2' })).kind).toBe('installed');
		expect(state.records('default')).toEqual([{ key: 'a', revision: 1, value: 'A' }]);
		expect(state.cursor('default')).toBe(2);
	});

	it('member completion waits for its collection dependency without blocking another domain', () => {
		const state = receiver();
		state.admitDomain('collection', 'collection-1');
		state.admitDomain('member-a', 'member-1');
		state.accept(
			begin({
				domain: 'member-a',
				incarnation: 'member-1',
				partCount: 1,
				requiresCollection: 2,
				target: 1,
			}),
		);
		state.accept(
			part({ domain: 'member-a', incarnation: 'member-1', key: 'a', revision: 1, value: 'A' }),
		);
		expect(state.accept(complete({ domain: 'member-a', incarnation: 'member-1' })).kind).toBe(
			'staged',
		);
		expect(state.records('member-a')).toEqual([]);
		state.accept(
			begin({
				batchId: 'collection-2',
				domain: 'collection',
				incarnation: 'collection-1',
				partCount: 0,
				target: 2,
			}),
		);
		expect(
			state.accept(
				complete({ batchId: 'collection-2', domain: 'collection', incarnation: 'collection-1' }),
			).kind,
		).toBe('installed');
		expect(state.records('member-a')).toEqual([{ key: 'a', revision: 1, value: 'A' }]);
		expect(state.takeInstallations().map((installation) => installation.domain)).toEqual([
			'collection',
			'member-a',
		]);
		expect(state.takeInstallations()).toEqual([]);
	});

	it('a deletion tombstone rejects a delayed write and an old incarnation', () => {
		const state = receiver();
		state.admitDomain('default', 'incarnation-1');
		state.accept(begin({ partCount: 1, target: 1 }));
		state.accept(part({ key: 'a', revision: 1, value: 'A' }));
		state.accept(complete({}));
		state.accept(begin({ batchId: 'delete-2', base: 1, mode: 'change', partCount: 1, target: 2 }));
		state.accept(deletion({ batchId: 'delete-2', key: 'a', revision: 2 }));
		expect(state.accept(complete({ batchId: 'delete-2' })).kind).toBe('installed');
		state.accept(begin({ batchId: 'stale-3', base: 2, mode: 'change', partCount: 1, target: 3 }));
		state.accept(part({ batchId: 'stale-3', key: 'a', revision: 1, value: 'stale' }));
		state.accept(complete({ batchId: 'stale-3' }));
		expect(state.records('default')).toEqual([]);
		expect(state.accept(begin({ incarnation: 'retired', partCount: 1, target: 4 })).kind).toBe(
			'ignored',
		);
	});

	it('a conflicting duplicate invalidates staging without installing its earlier part', () => {
		const state = receiver();
		state.admitDomain('default', 'incarnation-1');
		state.accept(begin({ partCount: 1, target: 1 }));
		state.accept(part({ key: 'a', revision: 1, value: 'A' }));
		expect(state.accept(part({ key: 'a', revision: 1, value: 'different' })).kind).toBe(
			'resnapshot',
		);
		expect(state.accept(complete({})).kind).toBe('resnapshot');
		expect(state.records('default')).toEqual([]);
	});

	it('a windowed empty snapshot prunes only its range and leaves an absence floor', () => {
		const state = receiver((scope, key) =>
			typeof scope['prefix'] === 'string' ? key.startsWith(scope['prefix']) : true,
		);
		state.admitDomain('default', 'incarnation-1');
		state.accept(begin({ partCount: 2, target: 2 }));
		state.accept(part({ key: 'src/a', revision: 1, value: 'A' }));
		state.accept(part({ key: 'docs/b', partIndex: 1, revision: 2, value: 'B' }));
		state.accept(complete({}));
		state.accept(begin({ batchId: 'src-empty-3', mode: 'snapshot', partCount: 0, target: 3 }));
		expect(
			state.accept(
				complete({
					batchId: 'src-empty-3',
					coveredScope: { kind: 'review', interests: [], prefix: 'src/' },
				}),
			).kind,
		).toBe('installed');
		state.accept(begin({ batchId: 'late-4', base: 3, mode: 'change', partCount: 1, target: 4 }));
		state.accept(part({ batchId: 'late-4', key: 'src/new', revision: 2, value: 'stale' }));
		state.accept(complete({ batchId: 'late-4' }));
		expect(state.records('default')).toEqual([{ key: 'docs/b', revision: 2, value: 'B' }]);
	});

	it('ignores a late change against the cursor replaced by a complete snapshot', () => {
		const state = receiver();
		state.admitDomain('default', 'incarnation-1');
		state.accept(begin({ batchId: 'initial', partCount: 1, target: 1 }));
		state.accept(part({ batchId: 'initial', key: 'a', revision: 1, value: 'old' }));
		state.accept(complete({ batchId: 'initial' }));
		state.accept(begin({ batchId: 'recovered', base: 1, partCount: 1, target: 3 }));
		state.accept(part({ batchId: 'recovered', key: 'a', revision: 3, value: 'current' }));
		expect(state.accept(complete({ batchId: 'recovered' })).kind).toBe('installed');

		expect(
			state.accept(
				begin({ batchId: 'late-change', base: 1, mode: 'change', partCount: 1, target: 4 }),
			).kind,
		).toBe('ignored');
		expect(state.cursor('default')).toBe(3);
		expect(state.records('default')).toEqual([{ key: 'a', revision: 3, value: 'current' }]);
	});

	it('scope comparison is independent of JSON member order', () => {
		const state = new BridgeProductViewBatchReceiver({
			handle: identity.handle,
			scope: { kind: 'review', interests: [{ lane: 'active', itemIds: ['first', 'second'] }] },
			scopeRevision: 0,
			subscriptionId: identity.subscriptionId,
			subscriptionKind: identity.subscriptionKind,
		});
		state.admitDomain('default', 'incarnation-1');
		expect(
			state.accept(
				begin({
					partCount: 0,
					scope: { interests: [{ itemIds: ['first', 'second'], lane: 'active' }], kind: 'review' },
					target: 1,
				}),
			).kind,
		).toBe('staged');
		expect(state.accept(complete({})).kind).toBe('installed');
	});

	it('credits advance on received contiguous parts before installation', () => {
		const state = receiver();
		state.admitDomain('default', 'incarnation-1');
		state.accept(begin({ partCount: 3, target: 3 }));
		expect(state.accept(part({ key: 'c', partIndex: 2, revision: 3, value: 'C' }))).toEqual({
			kind: 'staged',
		});
		expect(state.accept(part({ key: 'a', partIndex: 0, revision: 1, value: 'A' }))).toEqual({
			kind: 'staged',
			receivedThroughDeliverySequence: 1,
		});
		expect(state.records('default')).toEqual([]);
		expect(state.accept(part({ key: 'b', partIndex: 1, revision: 2, value: 'B' }))).toEqual({
			kind: 'staged',
			receivedThroughDeliverySequence: 3,
		});
		expect(state.accept(complete({})).kind).toBe('installed');
	});

	it('credits are contiguous within each domain when delivery sequences overlap', () => {
		const state = receiver();
		state.admitDomain('member-a', 'incarnation-a');
		state.admitDomain('member-b', 'incarnation-b');
		state.accept(
			begin({
				batchId: 'batch-a',
				domain: 'member-a',
				incarnation: 'incarnation-a',
				partCount: 2,
				target: 2,
			}),
		);
		state.accept(
			begin({
				batchId: 'batch-b',
				domain: 'member-b',
				incarnation: 'incarnation-b',
				partCount: 2,
				target: 2,
			}),
		);
		expect(
			state.accept(
				part({
					batchId: 'batch-a',
					domain: 'member-a',
					incarnation: 'incarnation-a',
					key: 'a-1',
					partIndex: 0,
					revision: 1,
					value: 'A1',
				}),
			),
		).toEqual({ kind: 'staged', receivedThroughDeliverySequence: 1 });
		expect(
			state.accept(
				part({
					batchId: 'batch-a',
					domain: 'member-a',
					incarnation: 'incarnation-a',
					key: 'a-2',
					partIndex: 1,
					revision: 2,
					value: 'A2',
				}),
			),
		).toEqual({ kind: 'staged', receivedThroughDeliverySequence: 2 });
		expect(
			state.accept(
				part({
					batchId: 'batch-b',
					domain: 'member-b',
					incarnation: 'incarnation-b',
					key: 'b-2',
					partIndex: 1,
					revision: 2,
					value: 'B2',
				}),
			),
		).toEqual({ kind: 'staged' });
		expect(
			state.accept(
				part({
					batchId: 'batch-b',
					domain: 'member-b',
					incarnation: 'incarnation-b',
					key: 'b-1',
					partIndex: 0,
					revision: 1,
					value: 'B1',
				}),
			),
		).toEqual({ kind: 'staged', receivedThroughDeliverySequence: 2 });
	});

	it('a resnapshot establishes a new receipt base without acknowledging its missing first part', () => {
		const state = receiver();
		state.admitDomain('default', 'incarnation-1');
		state.accept(begin({ batchId: 'old', partCount: 2, target: 2 }));
		expect(
			state.accept(part({ batchId: 'old', key: 'old-2', partIndex: 1, revision: 2, value: 'O2' })),
		).toEqual({ kind: 'staged' });
		expect(state.accept(complete({ batchId: 'old' })).kind).toBe('resnapshot');
		state.accept(begin({ batchId: 'replacement', partCount: 2, target: 4 }));
		expect(
			state.accept(
				part({ batchId: 'replacement', key: 'new-4', partIndex: 1, revision: 4, value: 'N4' }),
			),
		).toEqual({ kind: 'staged' });
		expect(
			state.accept(
				part({ batchId: 'replacement', key: 'new-3', partIndex: 0, revision: 3, value: 'N3' }),
			),
		).toEqual({ kind: 'staged', receivedThroughDeliverySequence: 4 });
	});

	it('keeps the installed view readable and ignores an old change after a replacement snapshot', () => {
		const state = receiver();
		state.admitDomain('default', identity.incarnation);
		state.accept(begin({ batchId: 'initial', partCount: 1, target: 1 }));
		state.accept(part({ batchId: 'initial', key: 'item/a', revision: 1, value: 'A' }));
		expect(state.accept(complete({ batchId: 'initial' })).kind).toBe('installed');

		state.accept(begin({ batchId: 'replacement', partCount: 1, target: 3 }));
		expect(state.records('default')).toEqual([{ key: 'item/a', revision: 1, value: 'A' }]);
		state.accept(part({ batchId: 'replacement', key: 'item/a', revision: 3, value: 'C' }));
		expect(state.accept(complete({ batchId: 'replacement' })).kind).toBe('installed');
		expect(state.cursor('default')).toBe(3);

		expect(
			state.accept(
				begin({ batchId: 'old-change', base: 1, mode: 'change', partCount: 1, target: 2 }),
			),
		).toEqual({ kind: 'ignored' });
		expect(state.records('default')).toEqual([{ key: 'item/a', revision: 3, value: 'C' }]);
	});

	it('a new handle retains stale rows until its range is certified', () => {
		const state = receiver();
		state.admitDomain('default', 'incarnation-1');
		state.accept(begin({ partCount: 1, target: 1 }));
		state.accept(part({ key: 'a', revision: 1, value: 'A' }));
		state.accept(complete({}));
		state.replaceHandle('handle-2', { kind: 'review', interests: [] }, 0);
		expect(state.records('default')).toEqual([]);
		expect(state.staleRecords('default')).toEqual([{ key: 'a', revision: 1, value: 'A' }]);
		state.admitDomain('default', 'incarnation-2');
		state.accept(
			begin({ handle: 'handle-2', incarnation: 'incarnation-2', partCount: 1, target: 1 }),
		);
		expect(state.accept(complete({ handle: 'handle-2', incarnation: 'incarnation-2' })).kind).toBe(
			'resnapshot',
		);
		expect(state.staleRecords('default')).toHaveLength(1);
		state.accept(
			begin({
				batchId: 'replacement',
				handle: 'handle-2',
				incarnation: 'incarnation-2',
				partCount: 0,
				target: 1,
			}),
		);
		expect(
			state.accept(
				complete({ batchId: 'replacement', handle: 'handle-2', incarnation: 'incarnation-2' }),
			).kind,
		).toBe('installed');
		expect(state.staleRecords('default')).toEqual([]);
	});

	it('A to B to A coverage resends a key at its current revision after eviction', () => {
		const state = receiver();
		state.admitDomain('default', 'incarnation-1');
		state.accept(begin({ partCount: 1, target: 1 }));
		state.accept(part({ key: 'a', revision: 1, value: 'A' }));
		state.accept(complete({}));
		state.setScope({ kind: 'review', interests: [{ lane: 'active', itemIds: ['B'] }] }, 1);
		state.accept(
			begin({
				batchId: 'scope-b',
				base: 1,
				mode: 'coverage',
				partCount: 1,
				scope: { kind: 'review', interests: [{ lane: 'active', itemIds: ['B'] }] },
				scopeRevision: 1,
				target: 2,
			}),
		);
		state.accept(eviction({ batchId: 'scope-b', scopeRevision: 1 }));
		expect(state.accept(complete({ batchId: 'scope-b', scopeRevision: 1 })).kind).toBe('installed');
		expect(state.records('default')).toEqual([]);
		state.setScope({ kind: 'review', interests: [] }, 2);
		state.accept(
			begin({
				batchId: 'scope-a',
				base: 2,
				mode: 'coverage',
				partCount: 1,
				scopeRevision: 2,
				target: 3,
			}),
		);
		state.accept(part({ batchId: 'scope-a', key: 'a', revision: 1, scopeRevision: 2, value: 'A' }));
		expect(state.accept(complete({ batchId: 'scope-a', scopeRevision: 2 })).kind).toBe('installed');
		expect(state.records('default')).toEqual([{ key: 'a', revision: 1, value: 'A' }]);
	});

	it('a delayed complete or lower-target snapshot cannot replace a newer row', () => {
		const state = receiver();
		state.admitDomain('default', 'incarnation-1');
		state.accept(begin({ partCount: 1, target: 1 }));
		state.accept(part({ key: 'a', revision: 1, value: 'A' }));
		state.accept(complete({}));
		state.accept(begin({ batchId: 'change-2', base: 1, mode: 'change', partCount: 1, target: 2 }));
		state.accept(part({ batchId: 'change-2', key: 'a', revision: 2, value: 'new' }));
		state.accept(complete({ batchId: 'change-2' }));
		expect(state.accept(complete({ batchId: 'change-2' })).kind).toBe('ignored');
		expect(state.accept(begin({ batchId: 'delayed', partCount: 0, target: 1 })).kind).toBe(
			'ignored',
		);
		expect(state.records('default')).toEqual([{ key: 'a', revision: 2, value: 'new' }]);
	});

	it('a failed replacement incarnation keeps its last good rows stale until certification', () => {
		const state = receiver();
		state.admitDomain('default', 'incarnation-1');
		state.accept(begin({ partCount: 1, target: 1 }));
		state.accept(part({ key: 'a', revision: 1, value: 'A' }));
		state.accept(complete({}));
		state.admitDomain('default', 'incarnation-2');
		expect(state.records('default')).toEqual([]);
		expect(state.staleRecords('default')).toEqual([{ key: 'a', revision: 1, value: 'A' }]);
		expect(
			state.accept(
				begin({
					batchId: 'new-change',
					incarnation: 'incarnation-2',
					mode: 'change',
					partCount: 0,
					target: 2,
				}),
			).kind,
		).toBe('resnapshot');
		expect(state.staleRecords('default')).toHaveLength(1);
		state.accept(
			begin({ batchId: 'new-snapshot', incarnation: 'incarnation-2', partCount: 0, target: 2 }),
		);
		expect(
			state.accept(complete({ batchId: 'new-snapshot', incarnation: 'incarnation-2' })).kind,
		).toBe('installed');
		expect(state.staleRecords('default')).toEqual([]);
	});
});
