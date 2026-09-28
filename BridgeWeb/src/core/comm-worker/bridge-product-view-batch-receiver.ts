import type { BridgeProductBatchFrame } from './bridge-product-batch-wire-contracts.js';

type BatchBegin = Extract<BridgeProductBatchFrame, { readonly kind: 'subscription.batchBegin' }>;
type BatchPart = Extract<BridgeProductBatchFrame, { readonly kind: 'subscription.batchPart' }>;
type BatchComplete = Extract<
	BridgeProductBatchFrame,
	{ readonly kind: 'subscription.batchComplete' }
>;

interface InstalledRecord {
	readonly key: string;
	readonly revision: number;
	readonly value: unknown;
}

export interface BridgeProductViewInstallation {
	readonly begin: BatchBegin;
	readonly domain: string;
	readonly records: readonly InstalledRecord[];
}

interface StagedBatch {
	readonly begin: BatchBegin;
	readonly partsByIndex: Map<number, BatchPart>;
	complete: BatchComplete | null;
}

interface DomainState {
	readonly incarnation: string;
	cursor: number;
	readonly receivedPartSequences: Set<number>;
	receivedThroughDeliverySequence: number;
	receiptBaselinePending: boolean;
	hasCertifiedSnapshot: boolean;
	lastInstalledBatchId: string | null;
	lastInstalledCompleteStreamSequence: number;
	readonly recordsByKey: Map<string, InstalledRecord>;
	readonly tombstoneRevisionByKey: Map<string, number>;
	readonly certifiedAbsenceFloorsByScope: Map<
		string,
		{
			readonly coveredScope: BatchComplete['coveredScope'];
			readonly revision: number;
		}
	>;
	stage: StagedBatch | null;
}

export type BridgeProductBatchAcceptance =
	| { readonly kind: 'ignored' }
	| {
			readonly kind: 'staged';
			readonly receivedThroughDeliverySequence?: number;
			readonly replacedIncompleteStage?: boolean;
	  }
	| { readonly kind: 'installed'; readonly domain: string; readonly targetRevision: number }
	| { readonly kind: 'resnapshot'; readonly domain: string };

/** W4's side bank. The live transport calls this owner only after the N3 cutover. */
export class BridgeProductViewBatchReceiver {
	#handle: string;
	#scope: BatchBegin['scope'];
	#scopeRevision: number;
	readonly #subscriptionId: string;
	readonly #subscriptionKind: BatchBegin['subscriptionKind'];
	readonly #coversKey: (coveredScope: BatchComplete['coveredScope'], key: string) => boolean;
	readonly #domains = new Map<string, DomainState>();
	readonly #staleRecordsByDomain = new Map<string, Map<string, InstalledRecord>>();
	readonly #completedInstallations: BridgeProductViewInstallation[] = [];

	constructor(props: {
		readonly handle: string;
		readonly scope: BatchBegin['scope'];
		readonly scopeRevision: number;
		readonly subscriptionId: string;
		readonly subscriptionKind: BatchBegin['subscriptionKind'];
		readonly coversKey?: (coveredScope: BatchComplete['coveredScope'], key: string) => boolean;
	}) {
		this.#handle = props.handle;
		this.#scope = props.scope;
		this.#scopeRevision = props.scopeRevision;
		this.#subscriptionId = props.subscriptionId;
		this.#subscriptionKind = props.subscriptionKind;
		this.#coversKey = props.coversKey ?? (() => true);
	}

	admitDomain(domain: string, incarnation: string): void {
		const existing = this.#domains.get(domain);
		if (existing?.incarnation === incarnation) return;
		this.#completedInstallations.splice(
			0,
			this.#completedInstallations.length,
			...this.#completedInstallations.filter((installation) => installation.domain !== domain),
		);
		if (existing !== undefined && existing.recordsByKey.size > 0) {
			this.#staleRecordsByDomain.set(domain, new Map(existing.recordsByKey));
		}
		this.#domains.set(domain, {
			cursor: 0,
			receivedPartSequences: new Set(),
			receivedThroughDeliverySequence: 0,
			receiptBaselinePending: true,
			hasCertifiedSnapshot: false,
			lastInstalledBatchId: null,
			lastInstalledCompleteStreamSequence: 0,
			certifiedAbsenceFloorsByScope: new Map(),
			incarnation,
			recordsByKey: new Map(),
			stage: null,
			tombstoneRevisionByKey: new Map(),
		});
	}

	setScope(scope: BatchBegin['scope'], scopeRevision: number): void {
		if (scopeRevision <= this.#scopeRevision) return;
		this.#completedInstallations.length = 0;
		this.#scope = scope;
		this.#scopeRevision = scopeRevision;
		for (const domain of this.#domains.values()) {
			domain.stage = null;
			domain.receivedPartSequences.clear();
			domain.receivedThroughDeliverySequence = 0;
			domain.receiptBaselinePending = true;
		}
	}

	replaceHandle(handle: string, scope: BatchBegin['scope'], scopeRevision: number): void {
		if (handle === this.#handle) {
			this.setScope(scope, scopeRevision);
			return;
		}
		this.#staleRecordsByDomain.clear();
		this.#completedInstallations.length = 0;
		for (const [domain, state] of this.#domains) {
			this.#staleRecordsByDomain.set(domain, new Map(state.recordsByKey));
		}
		this.#domains.clear();
		this.#handle = handle;
		this.#scope = scope;
		this.#scopeRevision = scopeRevision;
	}

	accept(frame: BridgeProductBatchFrame): BridgeProductBatchAcceptance {
		const domainState = this.#domains.get(frame.domain);
		if (
			domainState === undefined ||
			frame.incarnation !== domainState.incarnation ||
			frame.handle !== this.#handle ||
			frame.scopeRevision !== this.#scopeRevision ||
			frame.subscriptionId !== this.#subscriptionId ||
			frame.subscriptionKind !== this.#subscriptionKind
		)
			return { kind: 'ignored' };
		switch (frame.kind) {
			case 'subscription.batchBegin':
				return this.#begin(domainState, frame);
			case 'subscription.batchPart':
				return this.#part(domainState, frame);
			case 'subscription.batchComplete':
				return this.#complete(domainState, frame);
		}
	}

	cursor(domain: string): number {
		return this.#domains.get(domain)?.cursor ?? 0;
	}

	records(domain: string): readonly InstalledRecord[] {
		return [...(this.#domains.get(domain)?.recordsByKey.values() ?? [])].sort((left, right) =>
			left.key.localeCompare(right.key),
		);
	}

	staleRecords(domain: string): readonly InstalledRecord[] {
		return [...(this.#staleRecordsByDomain.get(domain)?.values() ?? [])].sort((left, right) =>
			left.key.localeCompare(right.key),
		);
	}

	/** Includes members whose collection dependency became ready in this turn. */
	takeInstallations(): readonly BridgeProductViewInstallation[] {
		return this.#completedInstallations.splice(0);
	}

	#begin(domainState: DomainState, frame: BatchBegin): BridgeProductBatchAcceptance {
		if (domainState.lastInstalledBatchId === frame.batchId) return { kind: 'ignored' };
		if (frame.streamSequence <= domainState.lastInstalledCompleteStreamSequence)
			return { kind: 'ignored' };
		if (!domainState.hasCertifiedSnapshot && frame.mode !== 'snapshot')
			return { kind: 'resnapshot', domain: frame.domain };
		if (frame.targetRevision < domainState.cursor) return { kind: 'ignored' };
		if (frame.mode !== 'snapshot' && frame.baseRevision < domainState.cursor)
			return { kind: 'ignored' };
		if (frame.mode !== 'snapshot' && frame.baseRevision > domainState.cursor) {
			domainState.stage = null;
			return { kind: 'resnapshot', domain: frame.domain };
		}
		if (!sameJSON(frame.scope, this.#scope)) {
			domainState.stage = null;
			return { kind: 'resnapshot', domain: frame.domain };
		}
		const priorStage = domainState.stage;
		if (priorStage?.begin.batchId === frame.batchId) {
			if (sameJSON(priorStage.begin, frame)) return { kind: 'staged' };
			domainState.stage = null;
			return { kind: 'resnapshot', domain: frame.domain };
		}
		if (priorStage !== null && frame.mode !== 'snapshot') {
			domainState.stage = null;
			return { kind: 'resnapshot', domain: frame.domain };
		}
		domainState.stage = { begin: frame, complete: null, partsByIndex: new Map() };
		if (frame.mode === 'snapshot') domainState.receiptBaselinePending = true;
		return {
			kind: 'staged',
			...(priorStage === null ? {} : { replacedIncompleteStage: true }),
		};
	}

	#part(domainState: DomainState, frame: BatchPart): BridgeProductBatchAcceptance {
		const stage = domainState.stage;
		if (
			stage !== null &&
			stage.begin.batchId !== frame.batchId &&
			frame.streamSequence < stage.begin.streamSequence
		)
			return { kind: 'ignored' };
		if (
			stage === null &&
			(frame.batchId === domainState.lastInstalledBatchId ||
				frame.streamSequence <= domainState.lastInstalledCompleteStreamSequence)
		)
			return { kind: 'ignored' };
		if (stage === null || stage.begin.batchId !== frame.batchId)
			return { kind: 'resnapshot', domain: frame.domain };
		if (frame.part.operation !== 'evict' && frame.part.revision > stage.begin.targetRevision) {
			domainState.stage = null;
			return { kind: 'resnapshot', domain: frame.domain };
		}
		if (frame.partIndex >= stage.begin.partCount) {
			domainState.stage = null;
			return { kind: 'resnapshot', domain: frame.domain };
		}
		const existing = stage.partsByIndex.get(frame.partIndex);
		if (existing !== undefined && !sameJSON(existing.part, frame.part)) {
			domainState.stage = null;
			return { kind: 'resnapshot', domain: frame.domain };
		}
		stage.partsByIndex.set(frame.partIndex, frame);
		if (domainState.receiptBaselinePending) {
			// A resnapshot abandons native's older in-transit credits. The first
			// received part establishes its sealed batch's sequence base even if
			// an earlier part in this same batch was delayed or lost.
			const baseline = frame.deliverySequence - frame.partIndex - 1;
			if (baseline < domainState.receivedThroughDeliverySequence) {
				domainState.stage = null;
				return { kind: 'resnapshot', domain: frame.domain };
			}
			domainState.receivedPartSequences.clear();
			domainState.receivedThroughDeliverySequence = baseline;
			domainState.receiptBaselinePending = false;
		}
		const priorReceivedThrough = domainState.receivedThroughDeliverySequence;
		domainState.receivedPartSequences.add(frame.deliverySequence);
		while (
			domainState.receivedPartSequences.delete(domainState.receivedThroughDeliverySequence + 1)
		) {
			domainState.receivedThroughDeliverySequence += 1;
		}
		return {
			kind: 'staged',
			...(domainState.receivedThroughDeliverySequence === priorReceivedThrough
				? {}
				: { receivedThroughDeliverySequence: domainState.receivedThroughDeliverySequence }),
		};
	}

	#complete(domainState: DomainState, frame: BatchComplete): BridgeProductBatchAcceptance {
		const stage = domainState.stage;
		if (
			stage !== null &&
			stage.begin.batchId !== frame.batchId &&
			frame.streamSequence < stage.begin.streamSequence
		)
			return { kind: 'ignored' };
		if (
			stage === null &&
			(frame.batchId === domainState.lastInstalledBatchId ||
				frame.streamSequence <= domainState.lastInstalledCompleteStreamSequence)
		)
			return { kind: 'ignored' };
		if (stage === null || stage.begin.batchId !== frame.batchId)
			return { kind: 'resnapshot', domain: frame.domain };
		if (stage.begin.scope.kind !== frame.coveredScope.kind) {
			domainState.stage = null;
			return { kind: 'resnapshot', domain: frame.domain };
		}
		if (stage.partsByIndex.size !== stage.begin.partCount) {
			domainState.stage = null;
			return { kind: 'resnapshot', domain: frame.domain };
		}
		stage.complete = frame;
		if (
			stage.begin.requiresCollection !== undefined &&
			this.cursor('collection') < stage.begin.requiresCollection
		)
			return { kind: 'staged' };
		const installed = this.#install(frame.domain, domainState, stage);
		if (frame.domain === 'collection') this.#installReadyMembers();
		return installed;
	}

	#installReadyMembers(): void {
		for (const [domain, state] of this.#domains) {
			const stage = state.stage;
			if (
				domain === 'collection' ||
				stage?.complete === null ||
				stage === null ||
				(stage.begin.requiresCollection ?? 0) > this.cursor('collection')
			)
				continue;
			this.#install(domain, state, stage);
		}
	}

	#install(domain: string, state: DomainState, stage: StagedBatch): BridgeProductBatchAcceptance {
		const nextRecords = new Map(state.recordsByKey);
		const nextTombstones = new Map(state.tombstoneRevisionByKey);
		const includedKeys = new Set<string>();
		for (let index = 0; index < stage.begin.partCount; index += 1) {
			const part = stage.partsByIndex.get(index)?.part;
			if (part === undefined) return { kind: 'resnapshot', domain };
			includedKeys.add(part.key);
			if (part.operation === 'evict') {
				nextRecords.delete(part.key);
				continue;
			}
			let priorRevision = Math.max(
				nextRecords.get(part.key)?.revision ?? 0,
				nextTombstones.get(part.key) ?? 0,
			);
			if (stage.begin.mode !== 'coverage') {
				for (const floor of state.certifiedAbsenceFloorsByScope.values()) {
					if (this.#coversKey(floor.coveredScope, part.key))
						priorRevision = Math.max(priorRevision, floor.revision);
				}
			}
			if (part.revision <= priorRevision) continue;
			if (part.operation === 'delete') {
				nextRecords.delete(part.key);
				nextTombstones.set(part.key, part.revision);
			} else {
				nextRecords.set(part.key, {
					key: part.key,
					revision: part.revision,
					value: part.value,
				});
				nextTombstones.delete(part.key);
			}
		}
		if (stage.begin.mode === 'snapshot') {
			for (const [key, record] of nextRecords) {
				if (
					!includedKeys.has(key) &&
					record.revision <= stage.begin.targetRevision &&
					this.#coversKey(stage.complete?.coveredScope ?? stage.begin.scope, key)
				)
					nextRecords.delete(key);
			}
			const coveredScope = stage.complete?.coveredScope ?? stage.begin.scope;
			state.certifiedAbsenceFloorsByScope.set(canonicalJSON(coveredScope), {
				coveredScope,
				revision: stage.begin.targetRevision,
			});
		}
		const staleRecords = this.#staleRecordsByDomain.get(domain);
		if (staleRecords !== undefined && stage.begin.mode === 'snapshot') {
			const coveredScope = stage.complete?.coveredScope ?? stage.begin.scope;
			for (const key of staleRecords.keys()) {
				if (this.#coversKey(coveredScope, key)) staleRecords.delete(key);
			}
			if (staleRecords.size === 0) this.#staleRecordsByDomain.delete(domain);
		}
		state.recordsByKey.clear();
		for (const [key, record] of nextRecords) state.recordsByKey.set(key, record);
		state.tombstoneRevisionByKey.clear();
		for (const [key, revision] of nextTombstones) state.tombstoneRevisionByKey.set(key, revision);
		state.cursor = stage.begin.targetRevision;
		if (stage.begin.mode === 'snapshot') state.hasCertifiedSnapshot = true;
		state.lastInstalledBatchId = stage.begin.batchId;
		state.lastInstalledCompleteStreamSequence = stage.complete?.streamSequence ?? 0;
		state.stage = null;
		this.#completedInstallations.push({
			begin: stage.begin,
			domain,
			records: [...nextRecords.values()],
		});
		return { kind: 'installed', domain, targetRevision: state.cursor };
	}
}

function sameJSON(left: unknown, right: unknown): boolean {
	return canonicalJSON(left) === canonicalJSON(right);
}

function canonicalJSON(value: unknown): string {
	if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(',')}]`;
	if (isJSONRecord(value)) {
		return `{${Object.keys(value)
			.sort()
			.map((key) => `${JSON.stringify(key)}:${canonicalJSON(value[key])}`)
			.join(',')}}`;
	}
	return JSON.stringify(value) ?? 'undefined';
}

function isJSONRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return value !== null && typeof value === 'object' && !Array.isArray(value);
}
