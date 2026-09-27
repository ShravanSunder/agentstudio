import { describe, expect, test } from 'vitest';

import type { ViewScopeAdmissionProps } from './bridge-product-view-control-admission.js';
import { bridgeProductInitialViewOpening } from './bridge-product-view-opening.js';
import { BridgeProductViewScopeOwner } from './bridge-product-view-scope-owner.js';

describe('initial E4 view scope admission', () => {
	test('admits File scope after subscription open with one stable handle and typed acceptance', async () => {
		const requests: ViewScopeAdmissionProps[] = [];
		let nextId = 0;
		const owner = new BridgeProductViewScopeOwner({
			controlMux: {
				setViewScope: async (props) => {
					requests.push(props);
					return {
						...props,
						kind: 'subscription.scopeAccepted',
						paneSessionId: 'pane-session-1',
						requestId: 'request-1',
						requestSequence: 1,
						wireVersion: 2,
						workerInstanceId: 'worker-instance-1',
					};
				},
				resnapshotView: async (): Promise<never> => {
					throw new Error('Unexpected resnapshot.');
				},
			},
			createIdentifier: (): string => `view-${++nextId}`,
		});
		const openView = bridgeProductInitialViewOpening(owner, 'file.metadata');
		if (openView === undefined) throw new Error('File view opening missing.');
		const signal = new AbortController().signal;
		await openView('file-subscription-1', signal, null);
		expect(requests).toEqual([
			{
				domain: 'default',
				handle: 'view-1',
				incarnation: 'view-2',
				scope: { kind: 'file', changeFilter: { kind: 'none' }, interests: [], pathScope: [] },
				scopeRevision: 1,
				signal: expect.any(AbortSignal),
				subscriptionId: 'file-subscription-1',
				subscriptionKind: 'file.metadata',
			},
		]);
	});

	test('Review metadata and native-authorized Comments receive their initial scopes', async () => {
		const requests: ViewScopeAdmissionProps[] = [];
		const controlMux = {
			setViewScope: async (props: ViewScopeAdmissionProps) => {
				requests.push(props);
				return {
					...props,
					kind: 'subscription.scopeAccepted' as const,
					paneSessionId: 'pane-session-1',
					requestId: 'request-1',
					requestSequence: 1,
					wireVersion: 2 as const,
					workerInstanceId: 'worker-instance-1',
				};
			},
		};
		const owner = new BridgeProductViewScopeOwner({
			controlMux: {
				...controlMux,
				resnapshotView: async (): Promise<never> => {
					throw new Error('Unexpected resnapshot.');
				},
			},
			createIdentifier: (() => {
				let nextId = 0;
				return (): string => `review-view-${++nextId}`;
			})(),
		});
		const review = bridgeProductInitialViewOpening(owner, 'review.metadata');
		const comment = bridgeProductInitialViewOpening(owner, 'review.annotations');
		if (review === undefined) throw new Error('Review view opening missing.');
		if (comment === undefined) throw new Error('Comment view opening missing.');
		await review('review-subscription-1', new AbortController().signal, null);
		await comment('comment-subscription-1', new AbortController().signal, 'native-worktree-1');
		expect(requests[0]).toMatchObject({
			scope: { kind: 'review', interests: [] },
			subscriptionKind: 'review.metadata',
		});
		expect(requests[1]).toMatchObject({
			scope: { kind: 'comment', sessionIds: [], worktreeId: 'native-worktree-1' },
			subscriptionId: 'comment-subscription-1',
			subscriptionKind: 'review.annotations',
		});
		expect(requests).toHaveLength(2);
	});
});
