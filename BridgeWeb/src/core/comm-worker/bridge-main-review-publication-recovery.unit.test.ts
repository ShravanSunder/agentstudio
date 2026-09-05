import { describe, expect, test, vi } from 'vitest';

import {
	ACTIVE,
	CANDIDATE,
	SUCCESSOR,
	candidateReady,
	createHarness,
	installPublication,
	mainIdentity,
	reviewDisplayEvent,
} from './bridge-main-review-publication-integration.test-support.js';

describe('Bridge Review installed receipt recovery', () => {
	test('retries the exact installed publication without repeating promotion or admission', async () => {
		// Arrange
		const harness = createHarness();
		try {
			await installPublication(harness, ACTIVE, 'item-a');
			harness.receive(reviewDisplayEvent(CANDIDATE, 'item-b'));
			harness.receive(candidateReady(CANDIDATE, 'ordinary', []));
			const admission = await harness.nextCommand('reviewPublicationInstallAdmit');
			harness.admit(admission, CANDIDATE, 'admitted');
			const installed = await harness.nextCommand('reviewPublicationInstalled');

			// Act
			harness.fail(installed);
			await vi.waitFor(() =>
				expect(harness.pendingCommandCount('reviewPublicationInstalled')).toBe(1),
			);
			const retry = await harness.nextCommand('reviewPublicationInstalled');
			expect(retry).toMatchObject({ publicationId: CANDIDATE.publicationId });
			expect(retry.requestId).not.toBe(installed.requestId);
			harness.ack(retry);
			await harness.integration.whenSettled();

			// Assert
			expect(harness.store.getReviewRefreshPresentation().activeIdentity).toEqual(
				mainIdentity(CANDIDATE),
			);
			expect(
				harness.commandKinds.filter((kind) => kind === 'reviewPublicationInstallAdmit'),
			).toHaveLength(2);
			expect(harness.requestWorkerReplacement).not.toHaveBeenCalled();
		} finally {
			harness.dispose();
		}
	});

	test('delegates persistent receipt failure to the existing worker lifecycle', async () => {
		// Arrange
		const harness = createHarness();
		try {
			await installPublication(harness, ACTIVE, 'item-a');
			harness.receive(reviewDisplayEvent(CANDIDATE, 'item-b'));
			harness.receive(candidateReady(CANDIDATE, 'ordinary', []));
			const admission = await harness.nextCommand('reviewPublicationInstallAdmit');
			harness.admit(admission, CANDIDATE, 'admitted');
			const installed = await harness.nextCommand('reviewPublicationInstalled');

			// Act
			harness.fail(installed);
			await vi.waitFor(() =>
				expect(harness.pendingCommandCount('reviewPublicationInstalled')).toBe(1),
			);
			const retry = await harness.nextCommand('reviewPublicationInstalled');
			harness.fail(retry);
			await harness.integration.whenSettled();

			// Assert
			expect(harness.requestWorkerReplacement).toHaveBeenCalledOnce();
			expect(harness.pendingCommandCount('reviewPublicationInstalled')).toBe(0);
			expect(harness.store.getReviewRefreshPresentation().activeIdentity).toEqual(
				mainIdentity(CANDIDATE),
			);
		} finally {
			harness.dispose();
		}
	});

	test('does not request successor admission until the installed predecessor receipt settles', async () => {
		// Arrange
		const harness = createHarness();
		try {
			await installPublication(harness, ACTIVE, 'item-a');
			harness.receive(reviewDisplayEvent(CANDIDATE, 'item-b'));
			harness.receive(candidateReady(CANDIDATE, 'ordinary', []));
			const admission = await harness.nextCommand('reviewPublicationInstallAdmit');
			harness.admit(admission, CANDIDATE, 'admitted');
			const installed = await harness.nextCommand('reviewPublicationInstalled');

			// Act / Assert — C may be ready, but native has not yet confirmed displayed B.
			harness.receive(reviewDisplayEvent(SUCCESSOR, 'item-c'));
			harness.receive(candidateReady(SUCCESSOR, 'ordinary', []));
			expect(harness.pendingCommandCount('reviewPublicationInstallAdmit')).toBe(0);
			harness.ack(installed);
			await vi.waitFor(() =>
				expect(harness.pendingCommandCount('reviewPublicationInstallAdmit')).toBe(1),
			);
			const successorAdmission = await harness.nextCommand('reviewPublicationInstallAdmit');
			expect(successorAdmission).toMatchObject({
				expectedDisplayedPublicationId: CANDIDATE.publicationId,
			});
			harness.admit(successorAdmission, SUCCESSOR, 'admitted');
			const successorInstalled = await harness.nextCommand('reviewPublicationInstalled');
			harness.ack(successorInstalled);
			await harness.integration.whenSettled();
			expect(harness.store.getReviewRefreshPresentation().activeIdentity).toEqual(
				mainIdentity(SUCCESSOR),
			);
		} finally {
			harness.dispose();
		}
	});
});
