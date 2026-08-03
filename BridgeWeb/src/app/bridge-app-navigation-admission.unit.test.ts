import { describe, expect, test } from 'vitest';

import type { BridgeProductNavigationCommand } from '../core/comm-worker/bridge-product-session-contracts.js';
import {
	applyBridgeAppNavigationCommand,
	bridgeAppReviewNavigationSourceForDisplaySlice,
	clearBridgeAppAcceptedNavigationSource,
	createBridgeAppNavigationAdmissionState,
	reportBridgeAppAcceptedNavigationSource,
} from './bridge-app-navigation-admission.js';

const fileSource = {
	sourceId: 'file-source-1',
	sourceKind: 'file',
	subscriptionGeneration: 3,
} as const;
const reviewSource = {
	generation: 7,
	metadataSourceId: 'review-source-1',
	packageId: 'review-package-1',
	sourceKind: 'review',
} as const;

describe('BridgeApp navigation admission', () => {
	test('admits the accepted Review tuple while its child projection is still loading', () => {
		expect(
			bridgeAppReviewNavigationSourceForDisplaySlice({
				metadataSourceId: reviewSource.metadataSourceId,
				metadataWindowIdentity: 'review-window-loading',
				packageId: reviewSource.packageId,
				reviewGeneration: reviewSource.generation,
				status: 'loading',
				summary: null,
				totalItemCount: null,
				totalTreeRowCount: null,
			}),
		).toEqual(reviewSource);
		expect(
			bridgeAppReviewNavigationSourceForDisplaySlice({
				error: 'metadataUnavailable',
				status: 'failed',
			}),
		).toBeNull();
	});

	test('holds an exact target pending until its complete accepted source exists', () => {
		const command = reviewCommand({ bindingRevision: 1, commandId: 'review-pending' });
		const pending = applyBridgeAppNavigationCommand(
			createBridgeAppNavigationAdmissionState('file'),
			command,
		);

		expect(pending.activeSurface).toBe('file');
		expect(pending.pendingCommand).toEqual(command);
		expect(pending.targetCommands.review).toBeUndefined();

		const admitted = reportBridgeAppAcceptedNavigationSource(pending, reviewSource);
		expect(admitted.activeSurface).toBe('review');
		expect(admitted.pendingCommand).toBeNull();
		expect(admitted.targetCommands.review).toEqual(command);
	});

	test('rejects mismatch and stale revision without changing surface or target', () => {
		const initialCommand = fileCommand({ bindingRevision: 4, commandId: 'file-current' });
		const withSource = reportBridgeAppAcceptedNavigationSource(
			createBridgeAppNavigationAdmissionState('file'),
			fileSource,
		);
		const admitted = applyBridgeAppNavigationCommand(withSource, initialCommand);
		const mismatched = applyBridgeAppNavigationCommand(admitted, {
			...reviewCommand({ bindingRevision: 5, commandId: 'review-mismatch' }),
			source: { ...reviewSource, packageId: 'other-package' },
		});
		const stale = applyBridgeAppNavigationCommand(
			mismatched,
			reviewCommand({ bindingRevision: 3, commandId: 'review-stale' }),
		);

		expect(mismatched.activeSurface).toBe('file');
		expect(mismatched.targetCommands.file).toEqual(initialCommand);
		expect(mismatched.targetCommands.review).toBeUndefined();
		expect(stale).toEqual(mismatched);
	});

	test('keeps a successor-bound command pending across the old accepted source', () => {
		const oldSource = { ...reviewSource, generation: 6, packageId: 'review-package-old' };
		const successorCommand = reviewCommand({
			bindingRevision: 8,
			commandId: 'review-successor-target',
		});
		const withOldSource = reportBridgeAppAcceptedNavigationSource(
			createBridgeAppNavigationAdmissionState('file'),
			oldSource,
		);

		const pending = applyBridgeAppNavigationCommand(withOldSource, successorCommand);
		expect(pending.activeSurface).toBe('file');
		expect(pending.targetCommands.review).toBeUndefined();
		expect(pending.pendingCommand).toEqual(successorCommand);

		const admitted = reportBridgeAppAcceptedNavigationSource(pending, reviewSource);
		expect(admitted.activeSurface).toBe('review');
		expect(admitted.pendingCommand).toBeNull();
		expect(admitted.targetCommands.review).toEqual(successorCommand);
	});

	test('keeps a successor-bound command pending across old-source cleanup', () => {
		const oldSource = { ...reviewSource, generation: 6, packageId: 'review-package-old' };
		const successorCommand = reviewCommand({
			bindingRevision: 8,
			commandId: 'review-successor-after-cleanup',
		});
		const oldTarget = {
			...reviewCommand({ bindingRevision: 7, commandId: 'review-old-target' }),
			source: oldSource,
		};
		const withOldTarget = applyBridgeAppNavigationCommand(
			reportBridgeAppAcceptedNavigationSource(
				createBridgeAppNavigationAdmissionState('review'),
				oldSource,
			),
			oldTarget,
		);
		const pending = applyBridgeAppNavigationCommand(withOldTarget, successorCommand);

		const afterOldCleanup = clearBridgeAppAcceptedNavigationSource(pending, 'review');
		const admitted = reportBridgeAppAcceptedNavigationSource(afterOldCleanup, reviewSource);

		expect(afterOldCleanup.targetCommands.review).toBeUndefined();
		expect(afterOldCleanup.pendingCommand).toEqual(successorCommand);
		expect(admitted.activeSurface).toBe('review');
		expect(admitted.pendingCommand).toBeNull();
		expect(admitted.targetCommands.review).toEqual(successorCommand);
	});

	test('revokes File targets on either source field rotation', () => {
		for (const rotatedSource of [
			{ ...fileSource, sourceId: 'file-source-2' },
			{ ...fileSource, subscriptionGeneration: 4 },
		]) {
			const admitted = applyBridgeAppNavigationCommand(
				reportBridgeAppAcceptedNavigationSource(
					createBridgeAppNavigationAdmissionState('file'),
					fileSource,
				),
				fileCommand({ bindingRevision: 1, commandId: 'file-target' }),
			);

			const rotated = reportBridgeAppAcceptedNavigationSource(admitted, rotatedSource);
			expect(rotated.targetCommands.file).toBeUndefined();
			expect(rotated.pendingCommand).toBeNull();

			const pending = applyBridgeAppNavigationCommand(
				createBridgeAppNavigationAdmissionState('review'),
				fileCommand({ bindingRevision: 1, commandId: 'file-pending' }),
			);
			const pendingRevoked = reportBridgeAppAcceptedNavigationSource(pending, rotatedSource);
			expect(pendingRevoked.pendingCommand).toBeNull();
			expect(pendingRevoked.targetCommands.file).toBeUndefined();
		}
	});

	test('revokes Review targets on source tuple rotation but not publication-only updates', () => {
		const admitted = applyBridgeAppNavigationCommand(
			reportBridgeAppAcceptedNavigationSource(
				createBridgeAppNavigationAdmissionState('review'),
				reviewSource,
			),
			reviewCommand({ bindingRevision: 1, commandId: 'review-target' }),
		);
		for (const rotatedSource of [
			{ ...reviewSource, metadataSourceId: 'review-source-2' },
			{ ...reviewSource, generation: 8 },
			{ ...reviewSource, packageId: 'review-package-2' },
		]) {
			const rotated = reportBridgeAppAcceptedNavigationSource(admitted, rotatedSource);
			expect(rotated.targetCommands.review).toBeUndefined();
			expect(rotated.pendingCommand).toBeNull();

			const pending = applyBridgeAppNavigationCommand(
				createBridgeAppNavigationAdmissionState('file'),
				reviewCommand({ bindingRevision: 1, commandId: 'review-pending' }),
			);
			const pendingRevoked = reportBridgeAppAcceptedNavigationSource(pending, rotatedSource);
			expect(pendingRevoked.pendingCommand).toBeNull();
			expect(pendingRevoked.targetCommands.review).toBeUndefined();
		}

		const publicationOnly = reportBridgeAppAcceptedNavigationSource(admitted, reviewSource);
		expect(publicationOnly).toBe(admitted);
	});

	test('activateContext restores only a remembered target still bound to the accepted source', () => {
		const admittedTarget = applyBridgeAppNavigationCommand(
			reportBridgeAppAcceptedNavigationSource(
				createBridgeAppNavigationAdmissionState('review'),
				fileSource,
			),
			fileCommand({ bindingRevision: 1, commandId: 'remembered-file-target' }),
		);
		const reviewContext = applyBridgeAppNavigationCommand(admittedTarget, {
			bindingRevision: 2,
			commandId: 'activate-review',
			commandKind: 'activateContext',
			surface: 'review',
		});
		const restoredFile = applyBridgeAppNavigationCommand(reviewContext, {
			bindingRevision: 3,
			commandId: 'restore-file',
			commandKind: 'activateContext',
			surface: 'file',
		});
		expect(restoredFile.activeSurface).toBe('file');
		expect(restoredFile.targetCommands.file?.commandId).toBe('remembered-file-target');

		const rotated = reportBridgeAppAcceptedNavigationSource(restoredFile, {
			...fileSource,
			subscriptionGeneration: 4,
		});
		const afterRotationContext = applyBridgeAppNavigationCommand(rotated, {
			bindingRevision: 4,
			commandId: 'restore-file-after-rotation',
			commandKind: 'activateContext',
			surface: 'file',
		});
		expect(afterRotationContext.activeSurface).toBe('file');
		expect(afterRotationContext.targetCommands.file).toBeUndefined();
	});

	test('applies one binding once and permits one truthful newer rebind', () => {
		const firstCommand = fileCommand({ bindingRevision: 2, commandId: 'logical-file-target' });
		const withFirstSource = reportBridgeAppAcceptedNavigationSource(
			createBridgeAppNavigationAdmissionState('review'),
			fileSource,
		);
		const first = applyBridgeAppNavigationCommand(withFirstSource, firstCommand);
		expect(applyBridgeAppNavigationCommand(first, firstCommand)).toBe(first);

		const reboundSource = { ...fileSource, subscriptionGeneration: 4 };
		const rebound = applyBridgeAppNavigationCommand(
			reportBridgeAppAcceptedNavigationSource(first, reboundSource),
			{
				...firstCommand,
				bindingRevision: 3,
				source: reboundSource,
			},
		);
		expect(rebound.targetCommands.file?.bindingRevision).toBe(3);
		expect(
			applyBridgeAppNavigationCommand(rebound, {
				...firstCommand,
				bindingRevision: 2,
				source: fileSource,
			}),
		).toBe(rebound);
	});
});

function fileCommand(props: {
	readonly bindingRevision: number;
	readonly commandId: string;
}): Extract<BridgeProductNavigationCommand, { readonly surface: 'file' }> {
	return {
		...props,
		commandKind: 'activateTarget',
		source: fileSource,
		surface: 'file',
		target: { path: 'README.md', targetKind: 'file', version: 'current' },
	};
}

function reviewCommand(props: {
	readonly bindingRevision: number;
	readonly commandId: string;
}): Extract<BridgeProductNavigationCommand, { readonly surface: 'review' }> {
	return {
		...props,
		commandKind: 'activateTarget',
		source: reviewSource,
		surface: 'review',
		target: { reviewItemId: 'review-item-1', targetKind: 'review' },
	};
}
