import type {
	BridgeMainReviewCandidateStore,
	BridgeMainReviewPublicationIdentity,
} from './bridge-main-review-candidate-bank.js';
import type { BridgeWorkerReviewCandidateReadyEvent } from './bridge-worker-review-publication-contracts.js';

export interface BridgeMainReviewSemanticAttention {
	readonly stableFileIdentities: readonly string[];
}

export interface BridgeMainReviewInstallAdmissionRequest {
	readonly candidatePublicationId: string;
	readonly expectedDisplayedPublicationId: string | null;
}

export interface BridgeMainReviewInstallAdmissionResult {
	readonly candidatePublicationId: string;
	readonly status: 'admitted' | 'rejected';
}

export interface BridgeMainReviewPresentationInstallationPort {
	readonly requestInstallAdmission: (
		request: BridgeMainReviewInstallAdmissionRequest,
	) => Promise<BridgeMainReviewInstallAdmissionResult>;
	readonly sendInstalledReceipt: (identity: BridgeMainReviewPublicationIdentity) => Promise<void>;
}

export interface BridgeMainReviewPresentationInstallationGate {
	readonly applyNow: () => Promise<void>;
	readonly close: () => void;
	readonly handleCandidateReady: (
		event: BridgeWorkerReviewCandidateReadyEvent,
		attention: BridgeMainReviewSemanticAttention,
	) => Promise<void>;
	readonly prepareForWorkerReplacement: () => void;
	readonly retryInstalledReceipt: () => Promise<boolean>;
	readonly semanticAttentionChanged: (
		attention: BridgeMainReviewSemanticAttention,
	) => Promise<void>;
}

interface ReadyCandidate {
	readonly affectedStableFileIdentities: readonly string[];
	readonly identity: BridgeMainReviewPublicationIdentity;
	readonly presentationClass: BridgeWorkerReviewCandidateReadyEvent['preDeliveryPresentationClass'];
}

export function createBridgeMainReviewPresentationInstallationGate(props: {
	readonly installationPort: BridgeMainReviewPresentationInstallationPort;
	readonly store: BridgeMainReviewCandidateStore;
}): BridgeMainReviewPresentationInstallationGate {
	let attentionFileIdentities = new Set<string>();
	let admissionInFlightPublicationId: string | null = null;
	let isClosed = false;
	let lifecycleRevision = 0;
	let pendingInstalledReceiptIdentity: BridgeMainReviewPublicationIdentity | null = null;
	let readyCandidate: ReadyCandidate | null = null;

	const candidateMatchesStore = (candidate: ReadyCandidate): boolean => {
		const storedCandidate = props.store.getReviewRefreshPresentation().candidate;
		return (
			storedCandidate !== null && identitiesAreExact(storedCandidate.identity, candidate.identity)
		);
	};

	const candidateAffectsAttention = (candidate: ReadyCandidate): boolean =>
		candidate.affectedStableFileIdentities.some((fileIdentity): boolean =>
			attentionFileIdentities.has(fileIdentity),
		);

	const installCandidate = async (candidate: ReadyCandidate): Promise<void> => {
		if (isClosed || admissionInFlightPublicationId !== null || !candidateMatchesStore(candidate)) {
			return;
		}
		const activeIdentity = props.store.getReviewRefreshPresentation().activeIdentity;
		const requestLifecycleRevision = lifecycleRevision;
		admissionInFlightPublicationId = candidate.identity.publicationId;
		let result: BridgeMainReviewInstallAdmissionResult;
		try {
			result = await props.installationPort.requestInstallAdmission({
				candidatePublicationId: candidate.identity.publicationId,
				expectedDisplayedPublicationId: activeIdentity?.publicationId ?? null,
			});
		} catch {
			if (
				requestLifecycleRevision === lifecycleRevision &&
				admissionInFlightPublicationId === candidate.identity.publicationId
			) {
				admissionInFlightPublicationId = null;
			}
			return;
		}
		if (
			isClosed ||
			requestLifecycleRevision !== lifecycleRevision ||
			admissionInFlightPublicationId !== candidate.identity.publicationId
		) {
			return;
		}
		admissionInFlightPublicationId = null;
		if (
			result.candidatePublicationId !== candidate.identity.publicationId ||
			result.status === 'rejected'
		) {
			props.store.discardReviewCandidate(candidate.identity);
			await evaluateReadyCandidate();
			return;
		}
		if (!props.store.promoteReviewCandidate(candidate.identity)) {
			await evaluateReadyCandidate();
			return;
		}
		pendingInstalledReceiptIdentity = candidate.identity;
		await sendPendingInstalledReceipt();
	};

	const evaluateReadyCandidate = async (): Promise<void> => {
		const candidate = readyCandidate;
		if (candidate === null || !candidateMatchesStore(candidate)) return;
		if (candidate.presentationClass.kind === 'promoted' && candidateAffectsAttention(candidate)) {
			props.store.markReviewCandidateReady({
				affectedStableFileIdentities: candidate.affectedStableFileIdentities,
				identity: candidate.identity,
				role: 'updateReady',
			});
			return;
		}
		if (
			!props.store.markReviewCandidateReady({
				affectedStableFileIdentities: candidate.affectedStableFileIdentities,
				identity: candidate.identity,
				role: 'provisional',
			})
		) {
			return;
		}
		await installCandidate(candidate);
	};

	const sendPendingInstalledReceipt = async (): Promise<boolean> => {
		const identity = pendingInstalledReceiptIdentity;
		if (identity === null || isClosed) return false;
		try {
			await props.installationPort.sendInstalledReceipt(identity);
			if (pendingInstalledReceiptIdentity?.publicationId === identity.publicationId) {
				pendingInstalledReceiptIdentity = null;
			}
			return true;
		} catch {
			return false;
		}
	};

	return {
		applyNow: async (): Promise<void> => {
			const candidate = readyCandidate;
			if (candidate === null || !candidateMatchesStore(candidate)) return;
			await installCandidate(candidate);
		},
		close: (): void => {
			if (isClosed) return;
			isClosed = true;
			lifecycleRevision += 1;
			admissionInFlightPublicationId = null;
			pendingInstalledReceiptIdentity = null;
			readyCandidate = null;
			props.store.discardReviewCandidate();
		},
		handleCandidateReady: async (event, attention): Promise<void> => {
			if (isClosed) return;
			const nextAttentionFileIdentities = new Set(attention.stableFileIdentities);
			const attentionChanged = !setsAreEqual(attentionFileIdentities, nextAttentionFileIdentities);
			attentionFileIdentities = nextAttentionFileIdentities;
			const candidate = readyCandidateFromEvent(event);
			if (!candidateMatchesStore(candidate)) return;
			if (
				readyCandidate !== null &&
				readyCandidatesAreEquivalent(readyCandidate, candidate) &&
				!attentionChanged
			) {
				return;
			}
			readyCandidate = candidate;
			await evaluateReadyCandidate();
		},
		prepareForWorkerReplacement: (): void => {
			if (isClosed) return;
			lifecycleRevision += 1;
			admissionInFlightPublicationId = null;
			readyCandidate = null;
			props.store.discardReviewCandidate();
		},
		retryInstalledReceipt: sendPendingInstalledReceipt,
		semanticAttentionChanged: async (attention): Promise<void> => {
			if (isClosed) return;
			const nextAttentionFileIdentities = new Set(attention.stableFileIdentities);
			if (setsAreEqual(attentionFileIdentities, nextAttentionFileIdentities)) return;
			attentionFileIdentities = nextAttentionFileIdentities;
			await evaluateReadyCandidate();
		},
	};
}

function readyCandidateFromEvent(event: BridgeWorkerReviewCandidateReadyEvent): ReadyCandidate {
	return {
		affectedStableFileIdentities: event.affectedStableFileIdentities,
		identity: {
			generation: event.reviewGeneration,
			packageId: event.packageId,
			publicationId: event.publicationId,
			revision: event.revision,
			sourceIdentity: event.sourceIdentity,
		},
		presentationClass: event.preDeliveryPresentationClass,
	};
}

function identitiesAreExact(
	left: BridgeMainReviewPublicationIdentity,
	right: BridgeMainReviewPublicationIdentity,
): boolean {
	return (
		left.generation === right.generation &&
		left.packageId === right.packageId &&
		left.publicationId === right.publicationId &&
		left.revision === right.revision &&
		left.sourceIdentity === right.sourceIdentity
	);
}

function readyCandidatesAreEquivalent(left: ReadyCandidate, right: ReadyCandidate): boolean {
	return (
		identitiesAreExact(left.identity, right.identity) &&
		left.presentationClass.kind === right.presentationClass.kind &&
		(left.presentationClass.kind === 'ordinary' ||
			(right.presentationClass.kind === 'promoted' &&
				left.presentationClass.reason === right.presentationClass.reason)) &&
		arraysAreEqual(left.affectedStableFileIdentities, right.affectedStableFileIdentities)
	);
}

function setsAreEqual(left: ReadonlySet<string>, right: ReadonlySet<string>): boolean {
	return left.size === right.size && [...left].every((value): boolean => right.has(value));
}

function arraysAreEqual(left: readonly string[], right: readonly string[]): boolean {
	return (
		left.length === right.length && left.every((value, index): boolean => value === right[index])
	);
}
