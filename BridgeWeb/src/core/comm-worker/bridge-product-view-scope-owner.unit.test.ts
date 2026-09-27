import { describe, expect, test } from 'vitest';

import type { BridgeProductControlMux } from './bridge-product-session-authority.js';
import type {
	ViewResnapshotAdmissionProps,
	ViewScopeAdmissionProps,
} from './bridge-product-view-control-admission.js';
import { BridgeProductViewScopeOwner } from './bridge-product-view-scope-owner.js';

const emptyFileScope = {
	changeFilter: { kind: 'none' },
	interests: [],
	kind: 'file',
	pathScope: [],
} as const;

describe('W2 desired view scope owner', () => {
	test('a newer File scope cancels the unsettled operation and resnapshot uses the latest revision', async () => {
		const scopes: ViewScopeAdmissionProps[] = [];
		const resnapshots: ViewResnapshotAdmissionProps[] = [];
		const controlMux = {
			setViewScope: async (props: ViewScopeAdmissionProps) => {
				scopes.push(props);
				if (props.scopeRevision === 1) {
					await new Promise<void>((_, reject): void => {
						props.signal?.addEventListener('abort', (): void => reject(new Error('superseded')), {
							once: true,
						});
					});
				}
				return acceptedScope(props);
			},
			resnapshotView: async (props: ViewResnapshotAdmissionProps) => {
				resnapshots.push(props);
				return acceptedResnapshot(props);
			},
		} satisfies Pick<BridgeProductControlMux, 'resnapshotView' | 'setViewScope'>;
		let nextIdentifier = 0;
		const owner = new BridgeProductViewScopeOwner({
			controlMux,
			createIdentifier: (): string => `view-identity-${++nextIdentifier}`,
		});
		owner.register({
			scope: emptyFileScope,
			subscriptionId: 'file-subscription-1',
			subscriptionKind: 'file.metadata',
		});
		const older = owner.setScope({ scope: emptyFileScope, subscriptionId: 'file-subscription-1' });
		const newerScope = {
			...emptyFileScope,
			interests: [{ lane: 'foreground', paths: ['src/current.ts'] }],
		} as const;
		const newer = owner.setScope({ scope: newerScope, subscriptionId: 'file-subscription-1' });

		await expect(older).resolves.toEqual({ kind: 'cancelled' });
		await expect(newer).resolves.toEqual({ kind: 'accepted', scopeRevision: 2 });
		expect(scopes.map((scope) => scope.scopeRevision)).toEqual([1, 2]);
		expect(scopes[0]?.signal?.aborted).toBe(true);
		await owner.resnapshot('file-subscription-1');
		expect(resnapshots).toMatchObject([
			{
				handle: 'view-identity-1',
				incarnation: 'view-identity-2',
				scopeRevision: 2,
				subscriptionId: 'file-subscription-1',
			},
		]);
	});

	test('retirement cancels the pending view operation and removes resnapshot authority', async () => {
		let started = false;
		const controlMux = {
			setViewScope: async (props: ViewScopeAdmissionProps) => {
				started = true;
				await new Promise<void>((_, reject): void => {
					props.signal?.addEventListener('abort', (): void => reject(new Error('retired')), {
						once: true,
					});
				});
				return acceptedScope(props);
			},
			resnapshotView: async (props: ViewResnapshotAdmissionProps) => acceptedResnapshot(props),
		} satisfies Pick<BridgeProductControlMux, 'resnapshotView' | 'setViewScope'>;
		const owner = new BridgeProductViewScopeOwner({
			controlMux,
			createIdentifier: (): string => 'view-identity',
		});
		owner.register({
			scope: emptyFileScope,
			subscriptionId: 'file-subscription-1',
			subscriptionKind: 'file.metadata',
		});
		const pending = owner.setScope({
			scope: emptyFileScope,
			subscriptionId: 'file-subscription-1',
		});
		expect(started).toBe(true);
		owner.retire('file-subscription-1');
		await expect(pending).resolves.toEqual({ kind: 'cancelled' });
		await expect(owner.resnapshot('file-subscription-1')).resolves.toBeUndefined();
	});
});

function acceptedScope(
	props: ViewScopeAdmissionProps,
): Awaited<ReturnType<BridgeProductControlMux['setViewScope']>> {
	return {
		...props,
		kind: 'subscription.scopeAccepted' as const,
		paneSessionId: 'pane-session-1',
		requestId: 'request-1',
		requestSequence: 1,
		wireVersion: 2 as const,
		workerInstanceId: 'worker-instance-1',
	};
}

function acceptedResnapshot(
	props: ViewResnapshotAdmissionProps,
): Awaited<ReturnType<BridgeProductControlMux['resnapshotView']>> {
	return {
		...props,
		kind: 'subscription.resnapshotAccepted' as const,
		paneSessionId: 'pane-session-1',
		requestId: 'request-2',
		requestSequence: 2,
		wireVersion: 2 as const,
		workerInstanceId: 'worker-instance-1',
	};
}
