import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

describe('Bridge demand membership cutover source structure', () => {
	test('legacy feature-resource owners remain deleted', () => {
		const deletedOwnerPaths = [
			'../../app/bridge-app-review-demand-telemetry-controller.ts',
			'../models/bridge-resource-descriptor.ts',
			'../resources/bridge-resource-registry.ts',
			'../resources/bridge-resource-url.ts',
			'../resources/bridge-integrity.ts',
			'../resources/bridge-resource-stream.ts',
			'./bridge-resource-executor.ts',
			'./bridge-content-demand-reconciler.ts',
			'../../features/review/demand/review-demand-policy.ts',
			'../../features/review/protocol/review-metadata-frame-builder.ts',
			'../../review-viewer/content/review-content-demand-telemetry.ts',
			'../../../scripts/dev-server/bridge-worktree-review-dev-provider.ts',
		];

		expect(
			deletedOwnerPaths.filter((relativePath): boolean =>
				existsSync(fileURLToPath(new URL(relativePath, import.meta.url))),
			),
		).toEqual([]);
	});

	test('main demand reconciler is compile-dead for converted surfaces', () => {
		const violations = convertedSurfaceSources().flatMap((entry): readonly string[] =>
			[
				'reconcileBridgeContentDemand',
				'reviewDemandScheduler',
				'visibleContentHydrationItemLimit',
				'retryAfterVersion',
				'pendingEviction',
				'membershipCap',
				'WorktreeFileDemandStimulus',
			]
				.filter((token): boolean => entry.source.includes(token))
				.map((token): string => `${entry.relativePath}: ${token}`),
		);

		expect(violations).toEqual([]);
	});

	test('main resource executor cannot retain converted demand membership', () => {
		const violations = convertedSurfaceSources().flatMap((entry): readonly string[] =>
			[
				'createBridgeResourceExecutor',
				'useBridgeReviewResourceExecutor',
				'BridgeResourceExecutor<',
				'resourceExecutor,',
				'cancelReviewItemDemand',
				'cancelReviewDescriptorDemandGroups',
				'loadReviewItemContentResourcesThroughDemandResult',
				'loadBridgeTextResourceWithTiming',
				'defaultFetchWorktreeFileResource',
			]
				.filter((token): boolean => entry.source.includes(token))
				.map((token): string => `${entry.relativePath}: ${token}`),
		);

		expect(violations).toEqual([]);
	});
});

interface SourceEntry {
	readonly relativePath: string;
	readonly source: string;
}

function convertedSurfaceSources(): readonly SourceEntry[] {
	return [
		'../../app/bridge-app-review-viewer-mode.tsx',
		'../../app/bridge-app-review-render-snapshot-controller.ts',
		'../../app/bridge-app-review-selection-controller.ts',
		'../../app/bridge-app-review-navigation-controller.ts',
		'../../file-viewer/bridge-file-viewer-app.tsx',
		'../../file-viewer/bridge-file-viewer-render-snapshot-controller.ts',
		'../../file-viewer/use-bridge-file-viewer-visible-demand-controller.ts',
		'../comm-worker/bridge-comm-worker-command-handler.ts',
		'../comm-worker/bridge-comm-worker-file-view-runtime.ts',
		'../comm-worker/bridge-comm-worker-file-view-source-update.ts',
		'../comm-worker/bridge-comm-worker-review-runtime.ts',
		'../comm-worker/bridge-comm-worker-store.ts',
	].map(
		(relativePath): SourceEntry => ({
			relativePath,
			source: readSource(relativePath),
		}),
	);
}

function readSource(relativePath: string): string {
	return readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), 'utf8');
}
