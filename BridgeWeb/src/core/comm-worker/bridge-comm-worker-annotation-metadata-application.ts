import {
	BridgeCommWorkerAnnotationCatalogApplicator,
	type BridgeCommWorkerAnnotationCatalog,
	type BridgeCommWorkerAnnotationCatalogAuthority,
} from './bridge-comm-worker-annotation-catalog-applicator.js';
import type { BridgeWorkerAnnotationProjectionSnapshot } from './bridge-comm-worker-annotation-projection-decoder.js';
import type { BridgeProductMetadataDataFrame } from './bridge-product-metadata-application-protocol.js';
import type { BridgeProductWorktreeAnnotationEvent } from './bridge-product-worktree-annotation-contracts.js';

export type BridgeCommWorkerAnnotationMetadataAction =
	| { readonly kind: 'none' }
	| { readonly kind: 'control' }
	| { readonly catalog: BridgeCommWorkerAnnotationCatalog; readonly kind: 'catalog' }
	| { readonly kind: 'content' };

type AnnotationMetadataFrame = BridgeProductMetadataDataFrame<BridgeProductWorktreeAnnotationEvent>;

export class BridgeCommWorkerAnnotationMetadataApplication {
	#catalogApplicator: BridgeCommWorkerAnnotationCatalogApplicator | null = null;
	#catalogAuthority: BridgeCommWorkerAnnotationCatalogAuthority | null = null;
	readonly #requiredSemanticRevisionBySessionId = new Map<string, number>();

	accept(
		frame: AnnotationMetadataFrame,
		demandedSessionIds: readonly string[],
	): BridgeCommWorkerAnnotationMetadataAction {
		const event = frame.data;
		this.#admitCatalogAuthority({
			subscriptionId: frame.subscriptionId,
			workerDerivationEpoch: frame.workerDerivationEpoch,
			worktreeId: event.authority.worktreeId,
		});
		switch (event.kind) {
			case 'annotation.catalog': {
				const result = this.#catalogApplicator?.accept(event);
				if (result?.status !== 'completed') return { kind: 'none' };
				this.#reconcileCatalogSessionRevisions(result.catalog);
				return { catalog: result.catalog, kind: 'catalog' };
			}
			case 'annotation.controlChanged':
				return { kind: 'control' };
			case 'annotation.sessionChanged': {
				const requiredRevision = this.#requiredSemanticRevisionBySessionId.get(event.sessionId);
				if (requiredRevision !== undefined && event.semanticRevision <= requiredRevision) {
					return { kind: 'none' };
				}
				this.#requiredSemanticRevisionBySessionId.set(event.sessionId, event.semanticRevision);
				return demandedSessionIds.includes(event.sessionId)
					? { kind: 'content' }
					: { kind: 'none' };
			}
		}
	}

	projectionMeetsCurrentness(
		snapshot: BridgeWorkerAnnotationProjectionSnapshot,
		requestedSessionIds: readonly string[],
	): boolean {
		for (const requestedSessionId of requestedSessionIds) {
			if (!this.#catalogApplicator?.activeCatalog?.sessionsById.has(requestedSessionId)) {
				return false;
			}
			const session = snapshot.sessions.find(
				(candidate) => candidate.sessionId === requestedSessionId,
			);
			const requiredRevision =
				this.#requiredSemanticRevisionBySessionId.get(requestedSessionId) ?? 0;
			if (session === undefined || session.semanticRevision < requiredRevision) return false;
		}
		return true;
	}

	retireAuthority(): void {
		this.#catalogApplicator?.retireExpectedAuthority();
		this.#catalogApplicator = null;
		this.#catalogAuthority = null;
	}

	#admitCatalogAuthority(authority: BridgeCommWorkerAnnotationCatalogAuthority): void {
		if (this.#catalogAuthority === null) {
			this.#catalogAuthority = authority;
			this.#catalogApplicator = new BridgeCommWorkerAnnotationCatalogApplicator(authority);
			return;
		}
		if (
			this.#catalogAuthority.subscriptionId === authority.subscriptionId &&
			this.#catalogAuthority.workerDerivationEpoch === authority.workerDerivationEpoch &&
			this.#catalogAuthority.worktreeId === authority.worktreeId
		) {
			return;
		}
		this.#catalogAuthority = authority;
		this.#catalogApplicator?.replaceExpectedAuthority(authority);
	}

	#reconcileCatalogSessionRevisions(catalog: BridgeCommWorkerAnnotationCatalog): void {
		for (const sessionId of this.#requiredSemanticRevisionBySessionId.keys()) {
			if (!catalog.sessionsById.has(sessionId)) {
				this.#requiredSemanticRevisionBySessionId.delete(sessionId);
			}
		}
		for (const session of catalog.sessionsById.values()) {
			const currentRevision = this.#requiredSemanticRevisionBySessionId.get(session.sessionId) ?? 0;
			this.#requiredSemanticRevisionBySessionId.set(
				session.sessionId,
				Math.max(currentRevision, session.semanticRevision),
			);
		}
	}
}
