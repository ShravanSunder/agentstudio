import type { BridgeProductControlMux } from './bridge-product-session-authority.js';
import type { ViewResnapshotAdmissionProps } from './bridge-product-view-control-admission.js';
import type { BridgeProductViewScopeRequest } from './bridge-product-view-control-wire-contracts.js';

type ViewScope = BridgeProductViewScopeRequest['scope'];
type ViewKind = BridgeProductViewScopeRequest['subscriptionKind'];

interface DesiredView {
	consecutiveResnapshots: number;
	readonly handle: string;
	readonly incarnation: string;
	resnapshotInFlight: Promise<void> | null;
	resnapshotRequested: boolean;
	readonly subscriptionId: string;
	readonly subscriptionKind: ViewKind;
	currentAdmission: AbortController | null;
	scopeRevision: number;
	desiredScope: ViewScope;
}

type ViewIdentity = Pick<
	ViewResnapshotAdmissionProps,
	'handle' | 'incarnation' | 'scopeRevision' | 'subscriptionId'
>;

export interface BridgeProductViewRecoveryState {
	readonly consecutiveResnapshots: number;
	readonly status: 'failedRetryable' | 'ready' | 'recovering';
}

export type BridgeProductViewScopeSettlement =
	| { readonly kind: 'accepted'; readonly scopeRevision: number }
	| { readonly kind: 'cancelled' };

/** W2 owns the latest desired scope; W4 owns the separate install barrier. */
export class BridgeProductViewScopeOwner {
	readonly #controlMux: Pick<BridgeProductControlMux, 'resnapshotView' | 'setViewScope'>;
	readonly #createIdentifier: () => string;
	readonly #maximumConsecutiveResnapshots: number;
	readonly #views = new Map<string, DesiredView>();

	constructor(props: {
		readonly controlMux: Pick<BridgeProductControlMux, 'resnapshotView' | 'setViewScope'>;
		readonly createIdentifier: () => string;
		readonly maximumConsecutiveResnapshots: number;
	}) {
		this.#controlMux = props.controlMux;
		this.#createIdentifier = props.createIdentifier;
		if (
			!Number.isSafeInteger(props.maximumConsecutiveResnapshots) ||
			props.maximumConsecutiveResnapshots <= 0
		) {
			throw new Error('View resnapshot budget must be a positive safe integer.');
		}
		this.#maximumConsecutiveResnapshots = props.maximumConsecutiveResnapshots;
	}

	register(props: {
		readonly scope: ViewScope;
		readonly subscriptionId: string;
		readonly subscriptionKind: ViewKind;
	}): void {
		if (this.#views.has(props.subscriptionId)) {
			throw new Error('A metadata view is already registered for this subscription.');
		}
		this.#views.set(props.subscriptionId, {
			consecutiveResnapshots: 0,
			currentAdmission: null,
			desiredScope: props.scope,
			handle: this.#createIdentifier(),
			incarnation: this.#createIdentifier(),
			resnapshotInFlight: null,
			resnapshotRequested: false,
			scopeRevision: 0,
			subscriptionId: props.subscriptionId,
			subscriptionKind: props.subscriptionKind,
		});
	}

	async setScope(props: {
		readonly scope: ViewScope;
		readonly signal?: AbortSignal;
		readonly subscriptionId: string;
	}): Promise<BridgeProductViewScopeSettlement> {
		const view = this.#views.get(props.subscriptionId);
		if (view === undefined) throw new Error('Metadata view scope has no registered E3.');
		if (!scopeMatchesKind(view.subscriptionKind, props.scope.kind)) {
			throw new Error('Metadata view scope differs from its registered kind.');
		}
		view.currentAdmission?.abort();
		view.scopeRevision += 1;
		view.desiredScope = props.scope;
		view.resnapshotInFlight = null;
		view.resnapshotRequested = false;
		const scopeRevision = view.scopeRevision;
		const admission = new AbortController();
		view.currentAdmission = admission;
		const abortAdmission = (): void => admission.abort(props.signal?.reason);
		props.signal?.addEventListener('abort', abortAdmission, { once: true });
		if (props.signal?.aborted === true) abortAdmission();
		try {
			await this.#controlMux.setViewScope({
				domain: 'default',
				handle: view.handle,
				incarnation: view.incarnation,
				scope: props.scope,
				scopeRevision,
				signal: admission.signal,
				subscriptionId: view.subscriptionId,
				subscriptionKind: view.subscriptionKind,
			});
			return view.scopeRevision === scopeRevision && !admission.signal.aborted
				? { kind: 'accepted', scopeRevision }
				: { kind: 'cancelled' };
		} catch (error) {
			if (admission.signal.aborted) return { kind: 'cancelled' };
			throw error;
		} finally {
			props.signal?.removeEventListener('abort', abortAdmission);
			if (view.currentAdmission === admission) view.currentAdmission = null;
		}
	}

	async resnapshot(subscriptionId: string, domain = 'default'): Promise<void> {
		const view = this.#views.get(subscriptionId);
		if (view === undefined) return;
		await this.requestResnapshot({
			domain,
			handle: view.handle,
			incarnation: view.incarnation,
			scopeRevision: view.scopeRevision,
			subscriptionId: view.subscriptionId,
			subscriptionKind: view.subscriptionKind,
		});
	}

	requestResnapshot(request: ViewResnapshotAdmissionProps): Promise<void> {
		const view = this.#matchingView(request);
		if (view === undefined || view.consecutiveResnapshots >= this.#maximumConsecutiveResnapshots)
			return Promise.resolve();
		if (view.resnapshotInFlight !== null) return view.resnapshotInFlight;
		if (view.resnapshotRequested) return Promise.resolve();
		view.consecutiveResnapshots += 1;
		view.resnapshotRequested = true;
		try {
			const admission = this.#controlMux.resnapshotView(request);
			const inFlight = admission.then(
				(): void => {
					if (view.resnapshotInFlight === inFlight) view.resnapshotInFlight = null;
				},
				(error: unknown): never => {
					if (view.resnapshotInFlight === inFlight) {
						view.resnapshotInFlight = null;
						view.resnapshotRequested = false;
					}
					throw error;
				},
			);
			view.resnapshotInFlight = inFlight;
			return inFlight;
		} catch (error) {
			view.resnapshotRequested = false;
			return Promise.reject(error);
		}
	}

	observeReplacementSnapshot(identity: ViewIdentity): void {
		const view = this.#matchingView(identity);
		if (view === undefined) return;
		if (view.resnapshotRequested) {
			view.resnapshotRequested = false;
			return;
		}
		view.consecutiveResnapshots = Math.min(
			this.#maximumConsecutiveResnapshots,
			view.consecutiveResnapshots + 1,
		);
	}

	recordCertifiedInstall(identity: ViewIdentity): void {
		const view = this.#matchingView(identity);
		if (view === undefined) return;
		view.consecutiveResnapshots = 0;
		view.resnapshotRequested = false;
	}

	recoveryState(subscriptionId: string): BridgeProductViewRecoveryState | null {
		const view = this.#views.get(subscriptionId);
		if (view === undefined) return null;
		return {
			consecutiveResnapshots: view.consecutiveResnapshots,
			status:
				view.consecutiveResnapshots === 0
					? 'ready'
					: view.consecutiveResnapshots >= this.#maximumConsecutiveResnapshots
						? 'failedRetryable'
						: 'recovering',
		};
	}

	async retryView(subscriptionId: string): Promise<void> {
		const view = this.#views.get(subscriptionId);
		if (view === undefined) return;
		await view.resnapshotInFlight?.catch((): void => {});
		if (this.#views.get(subscriptionId) !== view) return;
		view.consecutiveResnapshots = 0;
		view.resnapshotRequested = false;
		await this.resnapshot(subscriptionId);
	}

	#matchingView(identity: ViewIdentity): DesiredView | undefined {
		const view = this.#views.get(identity.subscriptionId);
		return view?.handle === identity.handle &&
			view.incarnation === identity.incarnation &&
			view.scopeRevision === identity.scopeRevision
			? view
			: undefined;
	}

	retire(subscriptionId: string): void {
		const view = this.#views.get(subscriptionId);
		view?.currentAdmission?.abort();
		this.#views.delete(subscriptionId);
	}
}

function scopeMatchesKind(subscriptionKind: ViewKind, scopeKind: ViewScope['kind']): boolean {
	return (
		(subscriptionKind === 'file.metadata' && scopeKind === 'file') ||
		(subscriptionKind === 'review.metadata' && scopeKind === 'review') ||
		((subscriptionKind === 'file.annotations' || subscriptionKind === 'review.annotations') &&
			scopeKind === 'comment')
	);
}
