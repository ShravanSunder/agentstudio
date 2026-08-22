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
	type BridgeMainReviewSemanticAttention,
} from './bridge-main-review-presentation-installation-gate.js';
import type { BridgeWorkerReviewCandidateReadyEvent } from './bridge-worker-review-publication-contracts.js';

const ACTIVE = identity(1, '11');
const CANDIDATE = identity(2, '12');
const SUCCESSOR = identity(3, '13');

describe('Bridge main Review presentation installation gate', () => {
	test('auto-installs an ordinary candidate and sends its installed receipt', async () => {
		// Arrange
		const store = new FakeCandidateStore(ACTIVE, CANDIDATE);
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
		const store = new FakeCandidateStore(ACTIVE, CANDIDATE);
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
		expect(store.roles).toEqual(['updateReady', 'provisional']);
		expect(store.promotions).toEqual([CANDIDATE.publicationId]);
	});

	test('Apply now admits the newest complete candidate present at action commit', async () => {
		// Arrange
		const store = new FakeCandidateStore(ACTIVE, CANDIDATE);
		const port = new ImmediateInstallationPort(['admitted']);
		const gate = createBridgeMainReviewPresentationInstallationGate({
			installationPort: port,
			store,
		});
		await gate.handleCandidateReady(
			candidateReady(CANDIDATE, 'promoted', ['file-b']),
			attention(['file-b']),
		);
		store.replaceCandidate(SUCCESSOR);
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

	test('does not promote a stale admitted identity after candidate replacement', async () => {
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
		store.replaceCandidate(SUCCESSOR);
		await gate.handleCandidateReady(candidateReady(SUCCESSOR, 'ordinary', []), attention([]));

		// Act
		firstRequest.resolve('admitted');
		const successorRequest = await port.nextRequest();
		successorRequest.resolve('admitted');
		await firstInstall;

		// Assert
		expect(store.promotions).toEqual([SUCCESSOR.publicationId]);
		expect(port.receipts).toEqual([SUCCESSOR.publicationId]);
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
});

class FakeCandidateStore implements BridgeMainReviewCandidateStore {
	presentation: BridgeMainReviewRefreshPresentation;
	readonly discards: string[] = [];
	readonly promotions: string[] = [];
	readonly roles: BridgeMainReviewCandidateRole[] = [];

	constructor(
		activeIdentity: BridgeMainReviewPublicationIdentity,
		candidateIdentity: BridgeMainReviewPublicationIdentity,
	) {
		this.presentation = candidatePresentation(activeIdentity, candidateIdentity);
	}

	getReviewRefreshPresentation = (): BridgeMainReviewRefreshPresentation => this.presentation;
	subscribeReviewRefreshPresentation = (): (() => void) => (): void => {};
	setReviewCandidateCodeViewItem = (): boolean => false;
	stageReviewCandidateDisplayEvent = (): boolean => false;
	applyReviewCandidateSnapshotUpdate = (): boolean => false;
	markReviewCandidateReady = (props: {
		readonly affectedStableFileIdentities: readonly string[];
		readonly identity: BridgeMainReviewPublicationIdentity;
		readonly role: BridgeMainReviewCandidateRole;
	}): boolean => {
		if (!this.candidateIs(props.identity)) return false;
		this.roles.push(props.role);
		this.presentation = {
			...this.presentation,
			candidate: {
				affectedStableFileIdentities: props.affectedStableFileIdentities,
				identity: props.identity,
				role: props.role,
			},
		};
		return true;
	};
	promoteReviewCandidate = (candidateIdentity: BridgeMainReviewPublicationIdentity): boolean => {
		if (!this.candidateIs(candidateIdentity)) return false;
		this.promotions.push(candidateIdentity.publicationId);
		this.presentation = { activeIdentity: candidateIdentity, candidate: null };
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

	replaceCandidate(candidateIdentity: BridgeMainReviewPublicationIdentity): void {
		this.presentation = candidatePresentation(this.presentation.activeIdentity, candidateIdentity);
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
	private resolvePromise!: (result: BridgeMainReviewInstallAdmissionResult) => void;

	constructor(readonly request: BridgeMainReviewInstallAdmissionRequest) {
		this.promise = new Promise((resolve) => {
			this.resolvePromise = resolve;
		});
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
	presentationClass: 'ordinary' | 'promoted',
	affectedStableFileIdentities: readonly string[],
): BridgeWorkerReviewCandidateReadyEvent {
	return {
		affectedStableFileIdentities,
		direction: 'serverWorkerToMain',
		epoch: candidateIdentity.generation,
		kind: 'reviewCandidateReady',
		packageId: candidateIdentity.packageId,
		preDeliveryPresentationClass:
			presentationClass === 'ordinary'
				? { kind: 'ordinary' }
				: { kind: 'promoted', reason: 'files' },
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

function attention(stableFileIdentities: readonly string[]): BridgeMainReviewSemanticAttention {
	return { stableFileIdentities };
}

function candidatePresentation(
	activeIdentity: BridgeMainReviewPublicationIdentity | null,
	candidateIdentity: BridgeMainReviewPublicationIdentity,
): BridgeMainReviewRefreshPresentation {
	return {
		activeIdentity,
		candidate: {
			affectedStableFileIdentities: [],
			identity: candidateIdentity,
			role: 'provisional',
		},
	};
}

function sameIdentity(
	left: BridgeMainReviewPublicationIdentity,
	right: BridgeMainReviewPublicationIdentity,
): boolean {
	return JSON.stringify(left) === JSON.stringify(right);
}
