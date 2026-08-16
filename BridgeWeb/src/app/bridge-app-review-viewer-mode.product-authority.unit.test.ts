import { readFileSync } from 'node:fs';

import { describe, expect, test } from 'vitest';

const reviewViewerModeSource = readFileSync(
	new URL('./bridge-app-review-viewer-mode.tsx', import.meta.url),
	'utf8',
);
const renderSnapshotControllerSource = readFileSync(
	new URL('./bridge-app-review-render-snapshot-controller.ts', import.meta.url),
	'utf8',
);
const directReviewBrowserSource = readFileSync(
	new URL('./bridge-app-review-render-snapshot-controller.browser.test.tsx', import.meta.url),
	'utf8',
);

describe('BridgeReviewViewerMode product authority', () => {
	test('keeps legacy writers and package adapters out of production composition and proof', () => {
		// Arrange
		const forbiddenModeAuthorityTokens = [
			'useBridgeReviewViewerStore',
			'useBridgeReviewViewerStoreSelector',
			'useBridgeReviewIntakeController',
			'useBridgeReviewProjectionCoordinator',
			'createBridgeReviewProjectionWebWorkerClient',
			'useBridgeReviewMarkdownPreviewController',
			'createBridgeMarkdownRenderWebWorkerClient',
			'useState<BridgeReviewPackage',
			'useState<readonly ReviewTreeRowMetadata',
		] as const;
		const forbiddenPackageAdapterTokens = [
			'bridgeReviewPackageFromProductDisplay',
			'productReviewPackage',
			'productReviewTreeRows',
		] as const;

		// Act
		const retainedModeTokens = forbiddenModeAuthorityTokens.filter((token): boolean =>
			reviewViewerModeSource.includes(token),
		);
		const productionAndProofSources = [
			reviewViewerModeSource,
			renderSnapshotControllerSource,
			directReviewBrowserSource,
		];
		const retainedAdapterTokens = forbiddenPackageAdapterTokens.filter((token): boolean =>
			productionAndProofSources.some((source): boolean => source.includes(token)),
		);

		// Assert
		expect({ retainedAdapterTokens, retainedModeTokens }).toEqual({
			retainedAdapterTokens: [],
			retainedModeTokens: [],
		});
	});

	test('composes source, item, tree, selected, and visible reads from direct keyed product facts', () => {
		// Arrange
		const requiredModeCompositionFacts = [
			'controller.reviewSourceSlice',
			'controller.displayStore',
			'controller.selectedReviewItem',
			'controller.selectedCodeViewItem',
		] as const;
		const requiredControllerKeyedReads = [
			'displayStore.getReviewCatalogSnapshot',
			'displayStore.getReviewSourceSnapshot',
			'displayStore.getReviewItemSnapshot',
			'displayStore.getReviewCodeViewItemSnapshot',
			'displayStore.getReviewAvailabilitySnapshot',
		] as const;

		// Act
		const missingModeFacts = requiredModeCompositionFacts.filter(
			(fragment): boolean => !reviewViewerModeSource.includes(fragment),
		);
		const missingControllerReads = requiredControllerKeyedReads.filter(
			(fragment): boolean => !renderSnapshotControllerSource.includes(fragment),
		);

		// Assert
		expect(missingModeFacts).toEqual([]);
		expect(missingControllerReads).toEqual([]);
	});
});
