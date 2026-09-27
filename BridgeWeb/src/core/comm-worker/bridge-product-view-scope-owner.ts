import type { BridgeProductControlMux } from './bridge-product-session-authority.js';
import type { BridgeProductViewScopeRequest } from './bridge-product-view-control-wire-contracts.js';

type ViewScope = BridgeProductViewScopeRequest['scope'];
type ViewKind = BridgeProductViewScopeRequest['subscriptionKind'];

interface DesiredView {
	readonly handle: string;
	readonly incarnation: string;
	readonly subscriptionId: string;
	readonly subscriptionKind: ViewKind;
	currentAdmission: AbortController | null;
	scopeRevision: number;
	desiredScope: ViewScope;
}

export type BridgeProductViewScopeSettlement =
	| { readonly kind: 'accepted'; readonly scopeRevision: number }
	| { readonly kind: 'cancelled' };

/** W2 owns the latest desired scope; W4 owns the separate install barrier. */
export class BridgeProductViewScopeOwner {
	readonly #controlMux: Pick<BridgeProductControlMux, 'resnapshotView' | 'setViewScope'>;
	readonly #createIdentifier: () => string;
	readonly #views = new Map<string, DesiredView>();

	constructor(props: {
		readonly controlMux: Pick<BridgeProductControlMux, 'resnapshotView' | 'setViewScope'>;
		readonly createIdentifier: () => string;
	}) {
		this.#controlMux = props.controlMux;
		this.#createIdentifier = props.createIdentifier;
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
			currentAdmission: null,
			desiredScope: props.scope,
			handle: this.#createIdentifier(),
			incarnation: this.#createIdentifier(),
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

	async resnapshot(subscriptionId: string): Promise<void> {
		const view = this.#views.get(subscriptionId);
		if (view === undefined) return;
		await this.#controlMux.resnapshotView({
			domain: 'default',
			handle: view.handle,
			incarnation: view.incarnation,
			scopeRevision: view.scopeRevision,
			subscriptionId: view.subscriptionId,
			subscriptionKind: view.subscriptionKind,
		});
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
