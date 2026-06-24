import { describe, expect, test } from 'vitest';

import { bridgeReviewProjectionWorkloadIdSchema } from '../models/review-projection-models.js';
import {
	makeBridgeViewerBenchmarkWorkload,
	type BridgeViewerBenchmarkWorkload,
} from './bridge-viewer-benchmark-workloads.js';

describe('bridge viewer benchmark workloads', () => {
	test('medium review workload is deterministic metadata with mixed review cases', () => {
		const workload = makeBridgeViewerBenchmarkWorkload('bridge_viewer_medium_review_v1');

		expectWorkloadId(workload.workloadId);
		expect(workload.reviewPackage.orderedItemIds).toHaveLength(1_000);
		expect(
			new Set(Object.values(workload.reviewPackage.itemsById).map((item) => item.fileClass)),
		).toEqual(new Set(['source', 'test', 'docs', 'generated', 'binary', 'large', 'config']));
		expect(
			new Set(Object.values(workload.reviewPackage.itemsById).map((item) => item.changeKind)),
		).toEqual(new Set(['added', 'modified', 'deleted', 'renamed', 'copied']));
		expect(JSON.stringify(workload.reviewPackage)).not.toContain('function mediumBody');
		expect(workload.metadata.expectedItemCount).toBe(1_000);
	});

	test('large tree workload owns a repo-scale sorted path set', () => {
		const workload = makeBridgeViewerBenchmarkWorkload('bridge_viewer_large_tree_v1');

		expect(workload.treePaths).toHaveLength(90_000);
		expect(workload.reviewPackage.orderedItemIds).toHaveLength(90_000);
		expect(workload.treePaths[0]).toBe('apps/app-000/src/module-000/file-00000.ts');
		expect(workload.treePaths.at(-1)).toBe('vendor/generated/pkg-089/file-89999.ts');
		expect(workload.metadata.expectedPathCount).toBe(90_000);
	});

	test('large diff scroll workload has fixed line volume and checksum', () => {
		const workload = makeBridgeViewerBenchmarkWorkload('bridge_viewer_large_diff_scroll_v1');

		expect(workload.reviewPackage.orderedItemIds).toHaveLength(25);
		expect(workload.largeDiff?.lineCount).toBe(100_000);
		expect(workload.largeDiff?.baseText.split('\n')).toHaveLength(100_000);
		expect(workload.largeDiff?.headText.split('\n')).toHaveLength(100_000);
		expect(workload.largeDiff?.contentChecksum).toMatch(/^[a-f0-9]{64}$/u);
		expect(workload.metadata.expectedDiffRows).toBe(100_000);
	});
});

function expectWorkloadId(workloadId: BridgeViewerBenchmarkWorkload['workloadId']): void {
	const parsed = bridgeReviewProjectionWorkloadIdSchema.safeParse(workloadId);
	expect(parsed.success).toBe(true);
}
