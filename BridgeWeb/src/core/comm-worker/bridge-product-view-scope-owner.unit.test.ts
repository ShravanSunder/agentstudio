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
	test('emits per-view recovery status only when it changes', async () => {
		const statuses: Array<{
			readonly view: { readonly kind: string; readonly subscriptionId: string };
			readonly status: 'failedRetryable' | 'ready' | 'recovering';
		}> = [];
		const owner = new BridgeProductViewScopeOwner({
			controlMux: {
				setViewScope: async (props) => acceptedScope(props),
				resnapshotView: async (props) => acceptedResnapshot(props),
			},
			createIdentifier: (): string => 'view-identity',
			maximumConsecutiveResnapshots: 2,
			onViewRecoveryStatus: (status): void => {
				statuses.push(status);
			},
		});
		owner.register({
			scope: emptyFileScope,
			subscriptionId: 'file-subscription-1',
			subscriptionKind: 'file.metadata',
		});
		owner.register({
			scope: { kind: 'comment', sessionIds: ['session-1'], worktreeId: 'worktree-1' },
			subscriptionId: 'comment-subscription-1',
			subscriptionKind: 'file.annotations',
		});

		await owner.resnapshot('file-subscription-1');
		owner.observeReplacementSnapshot({
			handle: 'view-identity',
			incarnation: 'view-identity',
			scopeRevision: 0,
			subscriptionId: 'file-subscription-1',
		});
		await owner.resnapshot('file-subscription-1');
		await owner.resnapshot('file-subscription-1');
		owner.recordCertifiedInstall({
			handle: 'view-identity',
			incarnation: 'view-identity',
			scopeRevision: 0,
			subscriptionId: 'file-subscription-1',
		});
		await owner.retryView('file-subscription-1');

		const fileStatuses = statuses.filter(
			(status): boolean => status.view.subscriptionId === 'file-subscription-1',
		);
		expect(fileStatuses).toEqual([
			{ view: { kind: 'file.metadata', subscriptionId: 'file-subscription-1' }, status: 'ready' },
			{
				view: { kind: 'file.metadata', subscriptionId: 'file-subscription-1' },
				status: 'recovering',
			},
			{
				view: { kind: 'file.metadata', subscriptionId: 'file-subscription-1' },
				status: 'failedRetryable',
			},
			{ view: { kind: 'file.metadata', subscriptionId: 'file-subscription-1' }, status: 'ready' },
			{
				view: { kind: 'file.metadata', subscriptionId: 'file-subscription-1' },
				status: 'recovering',
			},
		]);
		expect(owner.recoveryState('comment-subscription-1')).toEqual({
			consecutiveResnapshots: 0,
			status: 'ready',
		});
		expect(
			statuses.filter((status) => status.view.subscriptionId === 'comment-subscription-1'),
		).toEqual([
			{
				view: { kind: 'file.annotations', subscriptionId: 'comment-subscription-1' },
				status: 'ready',
			},
		]);
	});

	test('counts unsuccessful page resnapshots per view, stops at the budget, and rearms on Retry', async () => {
		const resnapshots: ViewResnapshotAdmissionProps[] = [];
		const owner = new BridgeProductViewScopeOwner({
			controlMux: {
				setViewScope: async (props) => acceptedScope(props),
				resnapshotView: async (props) => {
					resnapshots.push(props);
					return acceptedResnapshot(props);
				},
			},
			createIdentifier: (): string => 'view-identity',
			maximumConsecutiveResnapshots: 2,
		});
		owner.register({
			scope: emptyFileScope,
			subscriptionId: 'file-subscription-1',
			subscriptionKind: 'file.metadata',
		});
		await owner.resnapshot('file-subscription-1');
		expect(owner.recoveryState('file-subscription-1')).toEqual({
			consecutiveResnapshots: 1,
			status: 'recovering',
		});
		owner.observeReplacementSnapshot({
			handle: 'view-identity',
			incarnation: 'view-identity',
			scopeRevision: 0,
			subscriptionId: 'file-subscription-1',
		});
		await owner.resnapshot('file-subscription-1');
		expect(owner.recoveryState('file-subscription-1')).toEqual({
			consecutiveResnapshots: 2,
			status: 'failedRetryable',
		});
		await owner.resnapshot('file-subscription-1');
		expect(resnapshots).toHaveLength(2);
		await owner.retryView('file-subscription-1');
		expect(resnapshots).toHaveLength(3);
		expect(owner.recoveryState('file-subscription-1')).toEqual({
			consecutiveResnapshots: 1,
			status: 'recovering',
		});
	});

	test('coalesces overlapping admissions and fences their late settlement after retirement', async () => {
		let resolveAdmission: (() => void) | undefined;
		let requestCount = 0;
		const owner = new BridgeProductViewScopeOwner({
			controlMux: {
				setViewScope: async (props) => acceptedScope(props),
				resnapshotView: async (props) => {
					requestCount += 1;
					await new Promise<void>((resolve) => {
						resolveAdmission = resolve;
					});
					return acceptedResnapshot(props);
				},
			},
			createIdentifier: (() => {
				let nextIdentifier = 0;
				return (): string => `view-${++nextIdentifier}`;
			})(),
			maximumConsecutiveResnapshots: 2,
		});
		owner.register({
			scope: emptyFileScope,
			subscriptionId: 'file-subscription-1',
			subscriptionKind: 'file.metadata',
		});
		const first = owner.resnapshot('file-subscription-1');
		const second = owner.resnapshot('file-subscription-1');
		expect(requestCount).toBe(1);
		expect(owner.recoveryState('file-subscription-1')?.consecutiveResnapshots).toBe(1);
		owner.retire('file-subscription-1');
		owner.register({
			scope: emptyFileScope,
			subscriptionId: 'file-subscription-1',
			subscriptionKind: 'file.metadata',
		});
		resolveAdmission?.();
		await Promise.all([first, second]);
		expect(owner.recoveryState('file-subscription-1')).toEqual({
			consecutiveResnapshots: 0,
			status: 'ready',
		});
	});

	test('a new scope can resnapshot while the old scope admission remains unsettled', async () => {
		const admissions: ViewResnapshotAdmissionProps[] = [];
		const settleByRevision = new Map<
			number,
			{ resolve: () => void; reject: (error: Error) => void }
		>();
		const owner = new BridgeProductViewScopeOwner({
			controlMux: {
				setViewScope: async (props) => acceptedScope(props),
				resnapshotView: async (props) => {
					admissions.push(props);
					await new Promise<void>((resolve, reject) => {
						settleByRevision.set(props.scopeRevision, { resolve, reject });
					});
					return acceptedResnapshot(props);
				},
			},
			createIdentifier: (): string => 'view-identity',
			maximumConsecutiveResnapshots: 3,
		});
		owner.register({
			scope: emptyFileScope,
			subscriptionId: 'file-subscription-1',
			subscriptionKind: 'file.metadata',
		});
		const oldScopeRecovery = owner.resnapshot('file-subscription-1');
		await owner.setScope({ scope: emptyFileScope, subscriptionId: 'file-subscription-1' });
		const currentRecovery = owner.resnapshot('file-subscription-1');
		expect(admissions.map((admission) => admission.scopeRevision)).toEqual([0, 1]);
		settleByRevision.get(0)?.reject(new Error('Superseded scope rejected.'));
		await expect(oldScopeRecovery).rejects.toThrow('Superseded scope rejected.');
		const duplicateCurrentRecovery = owner.resnapshot('file-subscription-1');
		expect(admissions).toHaveLength(2);
		settleByRevision.get(1)?.resolve();
		await Promise.all([currentRecovery, duplicateCurrentRecovery]);
		expect(owner.recoveryState('file-subscription-1')?.consecutiveResnapshots).toBe(2);
	});

	test('counts native replacement once and resets only after a certified install', async () => {
		const owner = new BridgeProductViewScopeOwner({
			controlMux: {
				setViewScope: async (props) => acceptedScope(props),
				resnapshotView: async (props) => acceptedResnapshot(props),
			},
			createIdentifier: (): string => 'view-identity',
			maximumConsecutiveResnapshots: 2,
		});
		owner.register({
			scope: emptyFileScope,
			subscriptionId: 'file-subscription-1',
			subscriptionKind: 'file.metadata',
		});
		owner.observeReplacementSnapshot({
			handle: 'view-identity',
			incarnation: 'view-identity',
			scopeRevision: 0,
			subscriptionId: 'file-subscription-1',
		});
		expect(owner.recoveryState('file-subscription-1')?.consecutiveResnapshots).toBe(1);
		owner.recordCertifiedInstall({
			handle: 'stale-handle',
			incarnation: 'view-identity',
			scopeRevision: 0,
			subscriptionId: 'file-subscription-1',
		});
		expect(owner.recoveryState('file-subscription-1')?.consecutiveResnapshots).toBe(1);
		owner.recordCertifiedInstall({
			handle: 'view-identity',
			incarnation: 'view-identity',
			scopeRevision: 0,
			subscriptionId: 'file-subscription-1',
		});
		expect(owner.recoveryState('file-subscription-1')).toEqual({
			consecutiveResnapshots: 0,
			status: 'ready',
		});
	});
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
			maximumConsecutiveResnapshots: 3,
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
			maximumConsecutiveResnapshots: 3,
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
