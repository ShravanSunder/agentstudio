import { describe, expect, test } from 'vitest';

import {
	buildBridgeWorkerReviewCandidateReadyEvent,
	buildBridgeWorkerReviewPublicationInstallAdmissionEvent,
	encodeBridgeWorkerReviewPublicationInstallAdmitCommand,
	encodeBridgeWorkerReviewPublicationInstalledCommand,
} from './bridge-comm-worker-protocol.js';
import {
	BRIDGE_WORKER_REVIEW_AFFECTED_STABLE_FILE_IDENTITY_LIMIT,
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerMainToServerMessageSchema,
	bridgeWorkerReviewCandidateReadyEventSchema,
	bridgeWorkerReviewPublicationInstallAdmissionEventSchema,
	bridgeWorkerServerToMainMessageSchema,
} from './bridge-worker-contracts.js';

const publicationA = '00000000-0000-7000-8000-000000000011';
const publicationB = '00000000-0000-7000-8000-000000000012';

describe('Bridge worker Review publication lifecycle contracts', () => {
	test('encodes strict install admission and installed commands on the existing route', () => {
		const admission = encodeBridgeWorkerReviewPublicationInstallAdmitCommand({
			candidatePublicationId: publicationB,
			epoch: 8,
			expectedDisplayedPublicationId: publicationA,
			requestId: 'review-install-admit-1',
		});
		const installed = encodeBridgeWorkerReviewPublicationInstalledCommand({
			epoch: 8,
			packageId: 'package-b',
			publicationId: publicationB,
			requestId: 'review-installed-1',
			reviewGeneration: 8,
			revision: 12,
			sourceIdentity: 'source-b',
		});

		expect(bridgeWorkerMainToServerMessageSchema.parse(admission)).toEqual(admission);
		expect(bridgeWorkerMainToServerMessageSchema.parse(installed)).toEqual(installed);
		expect(admission).toMatchObject({
			command: 'reviewPublicationInstallAdmit',
			candidatePublicationId: publicationB,
			expectedDisplayedPublicationId: publicationA,
		});
		expect(installed).toMatchObject({
			command: 'reviewPublicationInstalled',
			publicationId: publicationB,
		});
	});

	test('builds strict candidate-ready and correlated admission events', () => {
		const candidateReady = buildBridgeWorkerReviewCandidateReadyEvent({
			affectedStableFileIdentities: ['stable-source-app', 'stable-test-app'],
			epoch: 8,
			packageId: 'review-package-12',
			preDeliveryPresentationClass: { kind: 'promoted', reason: 'files' },
			publicationId: publicationB,
			reviewGeneration: 12,
			revision: 4,
			sequence: 20,
			sourceIdentity: 'review-source-12',
		});
		const admission = buildBridgeWorkerReviewPublicationInstallAdmissionEvent({
			candidatePublicationId: publicationB,
			requestId: 'review-install-admit-1',
			status: 'admitted',
		});

		expect(bridgeWorkerServerToMainMessageSchema.parse(candidateReady)).toEqual(candidateReady);
		expect(bridgeWorkerServerToMainMessageSchema.parse(admission)).toEqual(admission);
		expect(candidateReady).toMatchObject({
			direction: 'serverWorkerToMain',
			kind: 'reviewCandidateReady',
			surface: 'review',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		});
		expect(admission).toMatchObject({
			kind: 'reviewPublicationInstallAdmission',
			requestId: 'review-install-admit-1',
			status: 'admitted',
		});
	});

	test('rejects non-canonical identities, extra keys, duplicate affected identities, and overflow', () => {
		const installAdmit = encodeBridgeWorkerReviewPublicationInstallAdmitCommand({
			candidatePublicationId: publicationB,
			epoch: 8,
			expectedDisplayedPublicationId: null,
			requestId: 'review-install-admit-initial',
		});
		const candidateReady = buildBridgeWorkerReviewCandidateReadyEvent({
			affectedStableFileIdentities: ['stable-source-app'],
			epoch: 8,
			packageId: 'review-package-12',
			preDeliveryPresentationClass: { kind: 'ordinary' },
			publicationId: publicationB,
			reviewGeneration: 12,
			revision: 4,
			sequence: 20,
			sourceIdentity: 'review-source-12',
		});
		const admission = buildBridgeWorkerReviewPublicationInstallAdmissionEvent({
			candidatePublicationId: publicationB,
			requestId: 'review-install-admit-1',
			status: 'rejected',
		});

		expect(bridgeWorkerMainToServerMessageSchema.parse(installAdmit)).toEqual(installAdmit);
		for (const invalidInstallAdmit of [
			{ ...installAdmit, candidatePublicationId: 'not-a-uuidv7' },
			{ ...installAdmit, expectedDisplayedPublicationId: 'not-a-uuidv7' },
			{ ...installAdmit, unexpected: true },
		]) {
			expect(bridgeWorkerMainToServerMessageSchema.safeParse(invalidInstallAdmit).success).toBe(
				false,
			);
		}

		for (const invalidCandidate of [
			{ ...candidateReady, publicationId: 'not-a-uuidv7' },
			{ ...candidateReady, publicationId: 'AAAAAAAA-AAAA-7AAA-8AAA-AAAAAAAAAAAA' },
			{ ...candidateReady, affectedStableFileIdentities: ['file:one', 'file:one'] },
			{
				...candidateReady,
				affectedStableFileIdentities: Array.from(
					{ length: BRIDGE_WORKER_REVIEW_AFFECTED_STABLE_FILE_IDENTITY_LIMIT + 1 },
					(_, index) => `file:${index}`,
				),
			},
			{ ...candidateReady, unexpected: true },
		]) {
			expect(bridgeWorkerReviewCandidateReadyEventSchema.safeParse(invalidCandidate).success).toBe(
				false,
			);
		}
		for (const invalidAdmission of [
			{ ...admission, candidatePublicationId: 'not-a-uuidv7' },
			{ ...admission, status: 'unknown' },
			{ ...admission, unexpected: true },
		]) {
			expect(
				bridgeWorkerReviewPublicationInstallAdmissionEventSchema.safeParse(invalidAdmission)
					.success,
			).toBe(false);
		}
	});
});
