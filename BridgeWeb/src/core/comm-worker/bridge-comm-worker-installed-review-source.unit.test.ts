import { describe, expect, test } from 'vitest';

import {
	createBridgeCommWorkerInstalledReviewSource,
	type BridgeWorkerInstalledReviewIdentity,
} from './bridge-comm-worker-installed-review-source.js';

describe('Bridge comm worker installed Review source', () => {
	test('advances exact annotation identity only at main installation and retains it across metadata failure', () => {
		const unavailableErrors: unknown[] = [];
		const installedIdentities: BridgeWorkerInstalledReviewIdentity[] = [];
		const installedSource = createBridgeCommWorkerInstalledReviewSource(() => ({
			setAnnotationProjectionSourceUnavailable: (_surface, error): void => {
				unavailableErrors.push(error);
			},
			setReviewAnnotationProjectionIdentity: (identity): void => {
				if (identity !== null) installedIdentities.push(identity);
			},
		}));

		installedSource.handleMetadataFailure('before-install');
		installedSource.recordInstallation(installedCommand(7));
		installedSource.handleMetadataFailure('candidate-failed');

		expect(unavailableErrors).toEqual(['before-install']);
		expect(installedIdentities).toEqual([installedCommand(7)]);
		expect(installedSource.hasInstalledSource).toBe(true);
	});
});

function installedCommand(reviewGeneration: number): BridgeWorkerInstalledReviewIdentity {
	return {
		packageId: 'package-installed',
		publicationId: '00000000-0000-7000-8000-000000000001',
		reviewGeneration,
		revision: 1,
		sourceIdentity: 'source-installed',
	};
}
