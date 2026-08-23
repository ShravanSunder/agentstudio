import { describe, expect, test } from 'vitest';

import type {
	BridgeMainReviewCandidateRole,
	BridgeMainReviewCandidateStore,
	BridgeMainReviewPublicationIdentity,
	BridgeMainReviewRefreshPresentation,
} from './bridge-main-review-candidate-bank.js';
import {
	createBridgeMainReviewPresentationInstallationGate,
	type BridgeMainReviewInstallAdmissionRequest,
	type BridgeMainReviewInstallAdmissionResult,
	type BridgeMainReviewPresentationInstallationPort,
	type BridgeMainReviewRefreshLifecycleEvent,
	type BridgeMainReviewSemanticAttention,
} from './bridge-main-review-presentation-installation-gate.js';
import type {
	BridgeWorkerReviewCandidateReadyEvent,
	BridgeWorkerReviewCandidateFailedEvent,
	BridgeWorkerReviewCandidateStartDisposition,
} from './bridge-worker-review-publication-contracts.js';

const ACTIVE = identity(1, '11');
const CANDIDATE = identity(2, '12');
const SUCCESSOR = identity(3, '13');

describe('Bridge main Review presentation installation gate', () => {
	test('reports one scrubbed lifecycle sequence for hold, Apply now, and cleanup', async () => {
		// Arrange
		const store = new FakeCandidateStore(
			ACTIVE,
			CANDIDATE,
			sameSourceStart({ kind: 'promoted', reason: 'files' }, ['file-b']),
		);
		const port = new ImmediateInstallationPort(['admitted']);
		const events: BridgeMainReviewRefreshLifecycleEvent[] = [];
		const gate = createBridgeMainReviewPresentationInstallationGate({
			installationPort: port,
			onLifecycleEvent: (event): void => {
				events.push(event);
			},
			store,
		});

		// Act
		await gate.handleCandidateReady(
			candidateReady(CANDIDATE, 'promoted', ['file-b']),
			attention(['file-b']),
		);
		await gate.applyNow();
		gate.close();

		// Assert
		expect(events).toEqual([
			{
				affectedStableFileCount: 1,
				generation: CANDIDATE.generation,
				phase: 'candidateReady',
				presentationClass: { kind: 'promoted', reason: 'files' },
			},
			{
				affectedStableFileCount: 1,
				generation: CANDIDATE.generation,
				phase: 'candidateHeld',
				presentationClass: { kind: 'promoted', reason: 'files' },
			},
			{
				affectedStableFileCount: 1,
				generation: CANDIDATE.generation,
				phase: 'installRequested',
				presentationClass: { kind: 'promoted', reason: 'files' },
				trigger: 'applyNow',
			},
			{
				affectedStableFileCount: 1,
				generation: CANDIDATE.generation,
				phase: 'installTerminal',
				presentationClass: { kind: 'promoted', reason: 'files' },
				result: 'success',
				resultReason: 'none',
				trigger: 'applyNow',
			},
			{
				activeBankCount: 1,
				candidateBankCount: 0,
				phase: 'cleanup',
				reason: 'close',
			},
		]);
	});

	test('auto-installs an ordinary candidate and sends its installed receipt', async () => {
		// Arrange
		const store = new FakeCandidateStore(
			ACTIVE,
			CANDIDATE,
			sameSourceStart({ kind: 'promoted', reason: 'files' }, ['file-b']),
		);
		const port = new ImmediateInstallationPort(['admitted']);
		const gate = createBridgeMainReviewPresentationInstallationGate({
			installationPort: port,
			store,
		});

		// Act
		await gate.handleCandidateReady(
			candidateReady(CANDIDATE, 'ordinary', ['file-b']),
			attention([]),
		);

		// Assert
		expect(port.requests).toEqual([
			{
				candidatePublicationId: CANDIDATE.publicationId,
				expectedDisplayedPublicationId: ACTIVE.publicationId,
			},
		]);
		expect(store.promotions).toEqual([CANDIDATE.publicationId]);
		expect(port.receipts).toEqual([CANDIDATE.publicationId]);
		expect(store.presentation.activeIdentity).toEqual(CANDIDATE);
	});

	test('holds an affected promoted candidate and installs when semantic attention leaves', async () => {
		// Arrange
		const store = new FakeCandidateStore(
			ACTIVE,
			CANDIDATE,
			sameSourceStart({ kind: 'promoted', reason: 'files' }, ['file-b']),
		);
		const port = new ImmediateInstallationPort(['admitted']);
		const gate = createBridgeMainReviewPresentationInstallationGate({
			installationPort: port,
			store,
		});

		// Act
		await gate.handleCandidateReady(
			candidateReady(CANDIDATE, 'promoted', ['file-b']),
			attention(['file-b']),
		);
		await gate.handleCandidateReady(
			candidateReady(CANDIDATE, 'promoted', ['file-b']),
			attention(['file-b']),
		);

		// Assert
		expect(store.roles).toEqual(['updateReady']);
		expect(port.requests).toEqual([]);

		// Act
		await gate.semanticAttentionChanged(attention(['unaffected-file']));

		// Assert
		expect(store.roles).toEqual(['updateReady', 'provisional', 'installing']);
		expect(store.promotions).toEqual([CANDIDATE.publicationId]);
	});

	test('treats promoted unknown as affecting any current Review attention without an identity union', async () => {
		// Arrange
		const store = new FakeCandidateStore(
			ACTIVE,
			CANDIDATE,
			sameSourceStart({ kind: 'promoted', reason: 'unknown' }, []),
		);
		const port = new ImmediateInstallationPort(['admitted']);
		const gate = createBridgeMainReviewPresentationInstallationGate({
			installationPort: port,
			store,
		});
		const unknownCandidate = candidateReady(CANDIDATE, 'promoted', []);

		// Act
		await gate.handleCandidateReady(unknownCandidate, attention(['any-current-review-file']));

		// Assert
		expect(store.roles).toEqual(['updateReady']);
		expect(port.requests).toEqual([]);

		// Act
		await gate.semanticAttentionChanged(attention([]));

		// Assert
		expect(store.promotions).toEqual([CANDIDATE.publicationId]);
	});

	test('Apply now admits the newest complete candidate present at action commit', async () => {
		// Arrange
		const store = new FakeCandidateStore(
			ACTIVE,
			CANDIDATE,
			sameSourceStart({ kind: 'promoted', reason: 'files' }, ['file-b']),
		);
		const port = new ImmediateInstallationPort(['admitted']);
		const gate = createBridgeMainReviewPresentationInstallationGate({
			installationPort: port,
			store,
		});
		await gate.handleCandidateReady(
			candidateReady(CANDIDATE, 'promoted', ['file-b']),
			attention(['file-b']),
		);
		store.replaceCandidate(
			SUCCESSOR,
			sameSourceStart({ kind: 'promoted', reason: 'files' }, ['file-c']),
		);
		await gate.handleCandidateReady(
			candidateReady(SUCCESSOR, 'promoted', ['file-c']),
			attention(['file-c']),
		);

		// Act
		await gate.applyNow();

		// Assert
		expect(port.requests).toHaveLength(1);
		expect(port.requests[0]?.candidatePublicationId).toBe(SUCCESSOR.publicationId);
		expect(store.promotions).toEqual([SUCCESSOR.publicationId]);
	});

	test('is idempotent for duplicate ready events and discards a rejected exact candidate', async () => {
		// Arrange
		const store = new FakeCandidateStore(ACTIVE, CANDIDATE);
		const port = new ImmediateInstallationPort(['rejected']);
		const gate = createBridgeMainReviewPresentationInstallationGate({
			installationPort: port,
			store,
		});
		const event = candidateReady(CANDIDATE, 'ordinary', []);

		// Act
		await gate.handleCandidateReady(event, attention([]));
		await gate.handleCandidateReady(event, attention([]));

		// Assert
		expect(port.requests).toHaveLength(1);
		expect(store.discards).toEqual([CANDIDATE.publicationId]);
		expect(store.presentation.activeIdentity).toEqual(ACTIVE);
		expect(store.presentation.candidate).toBeNull();
	});

	test('pins an admitted identity until it promotes despite successor arrival', async () => {
		// Arrange
		const store = new FakeCandidateStore(ACTIVE, CANDIDATE);
		const port = new DeferredInstallationPort();
		const gate = createBridgeMainReviewPresentationInstallationGate({
			installationPort: port,
			store,
		});
		const firstInstall = gate.handleCandidateReady(
			candidateReady(CANDIDATE, 'ordinary', []),
			attention([]),
		);
		const firstRequest = await port.nextRequest();
		expect(store.replaceCandidate(SUCCESSOR)).toBe(false);
		await gate.handleCandidateReady(candidateReady(SUCCESSOR, 'ordinary', []), attention([]));

		// Act
		firstRequest.resolve('admitted');
		await firstInstall;

		// Assert
		expect(store.promotions).toEqual([CANDIDATE.publicationId]);
		expect(port.receipts).toEqual([CANDIDATE.publicationId]);
	});

	test('invalidates late admission on worker replacement and close', async () => {
		// Arrange
		const store = new FakeCandidateStore(ACTIVE, CANDIDATE);
		const port = new DeferredInstallationPort();
		const gate = createBridgeMainReviewPresentationInstallationGate({
			installationPort: port,
			store,
		});
		const install = gate.handleCandidateReady(
			candidateReady(CANDIDATE, 'ordinary', []),
			attention([]),
		);
		const request = await port.nextRequest();

		// Act
		gate.prepareForWorkerReplacement();
		request.resolve('admitted');
		await install;
		store.replaceCandidate(SUCCESSOR);
		gate.close();
		await gate.handleCandidateReady(candidateReady(SUCCESSOR, 'ordinary', []), attention([]));

		// Assert
		expect(store.promotions).toEqual([]);
		expect(port.receipts).toEqual([]);
		expect(store.presentation.candidate).toBeNull();
	});

	test('stale admission failure cannot discard replacement-worker replay', async () => {
		// Arrange
		const store = new FakeCandidateStore(ACTIVE, CANDIDATE);
		const port = new DeferredInstallationPort();
		const gate = createBridgeMainReviewPresentationInstallationGate({
			installationPort: port,
			store,
		});
		const oldInstall = gate.handleCandidateReady(
			candidateReady(CANDIDATE, 'ordinary', []),
			attention([]),
		);
		const oldRequest = await port.nextRequest();

		// Act
		gate.prepareForWorkerReplacement();
		expect(store.replaceCandidate(CANDIDATE)).toBe(true);
		oldRequest.reject();
		await oldInstall;

		// Assert
		expect(store.presentation.candidate?.identity).toEqual(CANDIDATE);
		expect(store.discards).toEqual([CANDIDATE.publicationId]);
	});

	test('retains an installed active bank and retries only its failed receipt', async () => {
		// Arrange
		const store = new FakeCandidateStore(ACTIVE, CANDIDATE);
		const port = new ImmediateInstallationPort(['admitted'], 1);
		const gate = createBridgeMainReviewPresentationInstallationGate({
			installationPort: port,
			store,
		});

		// Act
		await gate.handleCandidateReady(candidateReady(CANDIDATE, 'ordinary', []), attention([]));
		const retrySucceeded = await gate.retryInstalledReceipt();

		// Assert
		expect(store.presentation.activeIdentity).toEqual(CANDIDATE);
		expect(retrySucceeded).toBe(true);
		expect(port.receiptAttempts).toEqual([CANDIDATE.publicationId, CANDIDATE.publicationId]);
	});

	test('retains only affected promoted failure and ignores stale B failure after C starts', async () => {
		const store = new FakeCandidateStore(
			ACTIVE,
			CANDIDATE,
			sameSourceStart({ kind: 'promoted', reason: 'files' }, ['file-b']),
		);
		const gate = createBridgeMainReviewPresentationInstallationGate({
			installationPort: new ImmediateInstallationPort([]),
			store,
		});
		store.replaceCandidate(SUCCESSOR, sameSourceStart({ kind: 'promoted', reason: 'unknown' }, []));

		gate.handleCandidateFailed(candidateFailed(CANDIDATE, true), attention(['file-b']));
		expect(store.presentation.candidate?.identity).toEqual(SUCCESSOR);
		expect(store.presentation.failure).toBeNull();

		gate.handleCandidateFailed(candidateFailed(SUCCESSOR, true), attention(['any-file']));
		expect(store.presentation.candidate).toBeNull();
		expect(store.presentation.failure).toMatchObject({
			identity: SUCCESSOR,
			presentationClass: { kind: 'promoted', reason: 'unknown' },
			retryable: true,
		});

		await gate.semanticAttentionChanged(attention([]));
		expect(store.presentation.failure).toBeNull();
	});

	test('keeps ordinary and replacement candidate failure off the global presentation', () => {
		for (const startDisposition of [
			sameSourceStart({ kind: 'ordinary' }, ['file-b']),
			{ kind: 'replacement' as const },
		]) {
			const store = new FakeCandidateStore(ACTIVE, CANDIDATE, startDisposition);
			const gate = createBridgeMainReviewPresentationInstallationGate({
				installationPort: new ImmediateInstallationPort([]),
				store,
			});
			gate.handleCandidateFailed(candidateFailed(CANDIDATE, true), attention(['file-b']));
			expect(store.presentation.candidate).toBeNull();
			expect(store.presentation.failure).toBeNull();
		}
	});
});

class FakeCandidateStore implements BridgeMainReviewCandidateStore {
	presentation: BridgeMainReviewRefreshPresentation;
	readonly discards: string[] = [];
	readonly promotions: string[] = [];
	readonly roles: BridgeMainReviewCandidateRole[] = [];

	constructor(
		activeIdentity: BridgeMainReviewPublicationIdentity,
		candidateIdentity: BridgeMainReviewPublicationIdentity,
		startDisposition: BridgeWorkerReviewCandidateStartDisposition = sameSourceStart(
			{ kind: 'ordinary' },
			[],
		),
	) {
		this.presentation = candidatePresentation(activeIdentity, candidateIdentity, startDisposition);
	}

	getReviewRefreshPresentation = (): BridgeMainReviewRefreshPresentation => this.presentation;
	subscribeReviewRefreshPresentation = (): (() => void) => (): void => {};
	setReviewCandidateCodeViewItem = (): boolean => false;
	startReviewCandidate = (): boolean => false;
	failReviewCandidate = (props: {
		readonly identity: BridgeMainReviewPublicationIdentity;
		readonly retryable: boolean;
	}): boolean => {
		const candidate = this.presentation.candidate;
		if (
			candidate === null ||
			!sameIdentity(candidate.identity, props.identity) ||
			candidate.role === 'installing'
		)
			return false;
		const start = candidate.startDisposition;
		this.presentation = {
			...this.presentation,
			candidate: null,
			failure:
				start?.kind === 'sameSource' && start.presentationClass.kind === 'promoted'
					? {
							affectedStableFileIdentities: start.affectedStableFileIdentities,
							identity: candidate.identity,
							presentationClass: start.presentationClass,
							retryable: props.retryable,
						}
					: null,
		};
		return true;
	};
	clearReviewCandidateFailure = (): boolean => {
		if (this.presentation.failure === null || this.presentation.failure === undefined) return false;
		this.presentation = { ...this.presentation, failure: null };
		return true;
	};
	stageReviewCandidateDisplayEvent = (): boolean => false;
	applyReviewCandidateSnapshotUpdate = (): boolean => false;
	markReviewCandidateReady = (props: {
		readonly identity: BridgeMainReviewPublicationIdentity;
		readonly role: BridgeMainReviewCandidateRole;
	}): boolean => {
		if (!this.candidateIs(props.identity)) return false;
		const startDisposition = this.presentation.candidate?.startDisposition;
		if (startDisposition === undefined) return false;
		this.roles.push(props.role);
		this.presentation = {
			...this.presentation,
			candidate: {
				affectedStableFileIdentities:
					this.presentation.candidate?.affectedStableFileIdentities ?? [],
				identity: props.identity,
				role: props.role,
				startDisposition,
			},
		};
		return true;
	};
	promoteReviewCandidate = (candidateIdentity: BridgeMainReviewPublicationIdentity): boolean => {
		if (!this.candidateIs(candidateIdentity)) return false;
		this.promotions.push(candidateIdentity.publicationId);
		this.presentation = { activeIdentity: candidateIdentity, candidate: null, failure: null };
		return true;
	};
	discardReviewCandidate = (candidateIdentity?: BridgeMainReviewPublicationIdentity): boolean => {
		const candidate = this.presentation.candidate;
		if (
			candidate === null ||
			(candidateIdentity !== undefined && !sameIdentity(candidate.identity, candidateIdentity))
		)
			return false;
		this.discards.push(candidate.identity.publicationId);
		this.presentation = { ...this.presentation, candidate: null };
		return true;
	};

	replaceCandidate(
		candidateIdentity: BridgeMainReviewPublicationIdentity,
		startDisposition: BridgeWorkerReviewCandidateStartDisposition = sameSourceStart(
			{ kind: 'ordinary' },
			[],
		),
	): boolean {
		if (this.presentation.candidate?.role === 'installing') return false;
		this.presentation = candidatePresentation(
			this.presentation.activeIdentity,
			candidateIdentity,
			startDisposition,
		);
		return true;
	}

	private candidateIs(identityToMatch: BridgeMainReviewPublicationIdentity): boolean {
		const candidate = this.presentation.candidate;
		return candidate !== null && sameIdentity(candidate.identity, identityToMatch);
	}
}

class ImmediateInstallationPort implements BridgeMainReviewPresentationInstallationPort {
	readonly receiptAttempts: string[] = [];
	readonly receipts: string[] = [];
	readonly requests: BridgeMainReviewInstallAdmissionRequest[] = [];
	private readonly admissionStatuses: Array<'admitted' | 'rejected'>;
	private remainingReceiptFailures: number;

	constructor(statuses: readonly ('admitted' | 'rejected')[], receiptFailures = 0) {
		this.admissionStatuses = [...statuses];
		this.remainingReceiptFailures = receiptFailures;
	}

	requestInstallAdmission = async (
		request: BridgeMainReviewInstallAdmissionRequest,
	): Promise<BridgeMainReviewInstallAdmissionResult> => {
		this.requests.push(request);
		return {
			candidatePublicationId: request.candidatePublicationId,
			status: this.admissionStatuses.shift() ?? 'rejected',
		};
	};

	sendInstalledReceipt = async (
		installedIdentity: BridgeMainReviewPublicationIdentity,
	): Promise<void> => {
		const publicationId = installedIdentity.publicationId;
		this.receiptAttempts.push(publicationId);
		if (this.remainingReceiptFailures > 0) {
			this.remainingReceiptFailures -= 1;
			throw new Error('injected receipt failure');
		}
		this.receipts.push(publicationId);
	};
}

class DeferredInstallationPort implements BridgeMainReviewPresentationInstallationPort {
	readonly receipts: string[] = [];
	private readonly pendingRequests: DeferredAdmission[] = [];
	private readonly requestWaiters: Array<(request: DeferredAdmission) => void> = [];

	requestInstallAdmission = (
		request: BridgeMainReviewInstallAdmissionRequest,
	): Promise<BridgeMainReviewInstallAdmissionResult> => {
		const deferred = new DeferredAdmission(request);
		const waiter = this.requestWaiters.shift();
		if (waiter === undefined) this.pendingRequests.push(deferred);
		else waiter(deferred);
		return deferred.promise;
	};

	sendInstalledReceipt = async (
		installedIdentity: BridgeMainReviewPublicationIdentity,
	): Promise<void> => {
		this.receipts.push(installedIdentity.publicationId);
	};

	nextRequest(): Promise<DeferredAdmission> {
		const pending = this.pendingRequests.shift();
		if (pending !== undefined) return Promise.resolve(pending);
		return new Promise((resolve) => this.requestWaiters.push(resolve));
	}
}

class DeferredAdmission {
	readonly promise: Promise<BridgeMainReviewInstallAdmissionResult>;
	private rejectPromise!: (error: Error) => void;
	private resolvePromise!: (result: BridgeMainReviewInstallAdmissionResult) => void;

	constructor(readonly request: BridgeMainReviewInstallAdmissionRequest) {
		this.promise = new Promise((resolve, reject) => {
			this.rejectPromise = reject;
			this.resolvePromise = resolve;
		});
	}

	reject(): void {
		this.rejectPromise(new Error('injected admission failure'));
	}

	resolve(status: 'admitted' | 'rejected'): void {
		this.resolvePromise({ candidatePublicationId: this.request.candidatePublicationId, status });
	}
}

function identity(generation: number, suffix: string): BridgeMainReviewPublicationIdentity {
	return {
		generation,
		packageId: `package-${generation}`,
		publicationId: `00000000-0000-7000-8000-${suffix.padStart(12, '0')}`,
		revision: 1,
		sourceIdentity: 'same-source',
	};
}

function candidateReady(
	candidateIdentity: BridgeMainReviewPublicationIdentity,
	_presentationClass: 'ordinary' | 'promoted',
	_affectedStableFileIdentities: readonly string[],
): BridgeWorkerReviewCandidateReadyEvent {
	return {
		direction: 'serverWorkerToMain',
		epoch: candidateIdentity.generation,
		kind: 'reviewCandidateReady',
		packageId: candidateIdentity.packageId,
		publicationId: candidateIdentity.publicationId,
		reviewGeneration: candidateIdentity.generation,
		revision: candidateIdentity.revision,
		sequence: candidateIdentity.generation,
		sourceIdentity: candidateIdentity.sourceIdentity,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function candidateFailed(
	candidateIdentity: BridgeMainReviewPublicationIdentity,
	retryable: boolean,
): BridgeWorkerReviewCandidateFailedEvent {
	return {
		direction: 'serverWorkerToMain',
		epoch: candidateIdentity.generation,
		kind: 'reviewCandidateFailed',
		packageId: candidateIdentity.packageId,
		publicationId: candidateIdentity.publicationId,
		retryable,
		reviewGeneration: candidateIdentity.generation,
		revision: candidateIdentity.revision,
		sequence: candidateIdentity.generation,
		sourceIdentity: candidateIdentity.sourceIdentity,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function attention(stableFileIdentities: readonly string[]): BridgeMainReviewSemanticAttention {
	return { stableFileIdentities };
}

function candidatePresentation(
	activeIdentity: BridgeMainReviewPublicationIdentity | null,
	candidateIdentity: BridgeMainReviewPublicationIdentity,
	startDisposition: BridgeWorkerReviewCandidateStartDisposition,
): BridgeMainReviewRefreshPresentation {
	return {
		activeIdentity,
		candidate: {
			affectedStableFileIdentities:
				startDisposition.kind === 'sameSource' ? startDisposition.affectedStableFileIdentities : [],
			identity: candidateIdentity,
			role: 'provisional',
			startDisposition,
		},
		failure: null,
	};
}

function sameSourceStart(
	presentationClass:
		| { readonly kind: 'ordinary' }
		| {
				readonly kind: 'promoted';
				readonly reason: 'commits' | 'files' | 'lines' | 'unknown';
		  },
	affectedStableFileIdentities: readonly string[],
): BridgeWorkerReviewCandidateStartDisposition {
	return { affectedStableFileIdentities, kind: 'sameSource', presentationClass };
}

function sameIdentity(
	left: BridgeMainReviewPublicationIdentity,
	right: BridgeMainReviewPublicationIdentity,
): boolean {
	return JSON.stringify(left) === JSON.stringify(right);
}
