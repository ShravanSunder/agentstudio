import type { FileTreeBatchOperation, FileTreeOptions } from '@pierre/trees';
import { describe, expect, expectTypeOf, test } from 'vitest';

import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	BridgeTreesController,
	createBridgeTreesSource,
	planBridgeTreesUpdate,
	type BridgeTreesModel,
} from './bridge-trees-controller.js';

describe('Bridge Trees controller', () => {
	test('builds presorted public Pierre input and Git status entries from projection metadata', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { base: { kind: 'allFiles' }, refinements: [] },
		});

		const source = createBridgeTreesSource({
			reviewPackage,
			projection,
		});

		expect(source.orderedPaths).toEqual(projection.orderedPaths);
		expect(source.initialExpandedPaths).toEqual([
			'Sources',
			'Sources/App',
			'Tests',
			'Tests/App',
			'docs',
			'docs/plans',
		]);
		expect(source.gitStatusEntries).toEqual([
			{ path: 'Sources/App/Core.swift', status: 'modified' },
			{ path: 'Sources/App/View.swift', status: 'modified' },
			{ path: 'Tests/App/ViewTests.swift', status: 'modified' },
			{ path: 'docs/plans/2026-bridge-plan.md', status: 'modified' },
			{ path: 'Sources/NewName.swift', status: 'renamed' },
			{ path: 'Sources/Removed.swift', status: 'deleted' },
		]);
		expect(source.gitStatusEntries).not.toContainEqual({
			path: 'Sources/App/View.swift',
			status: 'untracked',
		});
		expectTypeOf(source.preparedInput).toMatchTypeOf<FileTreeOptions['preparedInput']>();
	});

	test('plans reset append and status-only mutations without rebuilding for status changes', () => {
		const source = makeSource({
			orderedPaths: ['src/a.ts', 'src/b.ts'],
			gitStatusEntries: [{ path: 'src/a.ts', status: 'modified' }],
		});

		expect(planBridgeTreesUpdate({ previous: null, next: source }).kind).toBe('reset');
		expect(
			planBridgeTreesUpdate({
				previous: source,
				next: makeSource({
					orderedPaths: ['src/a.ts', 'src/b.ts'],
					gitStatusEntries: [{ path: 'src/a.ts', status: 'deleted' }],
				}),
			}).kind,
		).toBe('statusOnly');
		expect(
			planBridgeTreesUpdate({
				previous: source,
				next: makeSource({
					orderedPaths: ['src/a.ts', 'src/b.ts', 'src/c.ts'],
					gitStatusEntries: [{ path: 'src/a.ts', status: 'modified' }],
				}),
			}),
		).toEqual({
			kind: 'appendOnly',
			addedPaths: ['src/c.ts'],
			shouldUpdateGitStatus: false,
		});
		expect(
			planBridgeTreesUpdate({
				previous: source,
				next: makeSource({
					orderedPaths: ['src/b.ts', 'src/a.ts'],
					gitStatusEntries: [{ path: 'src/a.ts', status: 'modified' }],
				}),
			}).kind,
		).toBe('reset');
	});

	test('applies public FileTree mutations and maps selected tree path to primary item id', () => {
		const model = new RecordingTreesModel();
		const controller = new BridgeTreesController({ model });
		const source = makeSource({
			orderedPaths: ['src/a.ts', 'src/b.ts'],
			gitStatusEntries: [{ path: 'src/a.ts', status: 'modified' }],
			primaryItemIdByTreePath: {
				'src/a.ts': 'item-a',
				'src/b.ts': 'item-b',
			},
		});

		controller.applySource(source);
		controller.applySource(
			makeSource({
				orderedPaths: ['src/a.ts', 'src/b.ts'],
				gitStatusEntries: [{ path: 'src/a.ts', status: 'deleted' }],
				primaryItemIdByTreePath: source.primaryItemIdByTreePath,
			}),
		);
		controller.applySource(
			makeSource({
				orderedPaths: ['src/a.ts', 'src/b.ts', 'src/c.ts'],
				gitStatusEntries: [{ path: 'src/a.ts', status: 'deleted' }],
				primaryItemIdByTreePath: {
					...source.primaryItemIdByTreePath,
					'src/c.ts': 'item-c',
				},
			}),
		);

		expect(model.resetCalls).toHaveLength(1);
		expect(model.resetCalls[0]?.paths).toEqual(['src/a.ts', 'src/b.ts']);
		expect(model.setGitStatusCalls).toEqual([
			[{ path: 'src/a.ts', status: 'modified' }],
			[{ path: 'src/a.ts', status: 'deleted' }],
		]);
		expect(model.batchCalls).toEqual([[{ type: 'add', path: 'src/c.ts' }]]);
		expect(controller.selectTreePath('src/b.ts')).toBe('item-b');
		expect(controller.selectTreePath('missing.ts')).toBeNull();
	});
});

function makeSource(
	props: Pick<ReturnType<typeof createBridgeTreesSource>, 'orderedPaths' | 'gitStatusEntries'> &
		Partial<Pick<ReturnType<typeof createBridgeTreesSource>, 'primaryItemIdByTreePath'>>,
): ReturnType<typeof createBridgeTreesSource> {
	const reviewPackage = makeBridgeViewerProjectionFixture();
	const projection = buildBridgeReviewProjection({
		reviewPackage,
		request: { base: { kind: 'allFiles' }, refinements: [] },
	});
	return {
		...createBridgeTreesSource({ reviewPackage, projection }),
		orderedPaths: props.orderedPaths,
		gitStatusEntries: props.gitStatusEntries,
		primaryItemIdByTreePath: props.primaryItemIdByTreePath ?? {},
		gitStatusSignature: props.gitStatusEntries
			.map((entry): string => `${entry.path}\u0000${entry.status}`)
			.join('\n'),
	};
}

class RecordingTreesModel implements BridgeTreesModel {
	readonly resetCalls: Array<{
		readonly paths: readonly string[];
		readonly options: Parameters<BridgeTreesModel['resetPaths']>[1];
	}> = [];
	readonly batchCalls: FileTreeBatchOperation[][] = [];
	readonly setGitStatusCalls: Array<NonNullable<FileTreeOptions['gitStatus']>> = [];

	resetPaths(
		paths: readonly string[],
		options?: Parameters<BridgeTreesModel['resetPaths']>[1],
	): void {
		this.resetCalls.push({ paths, options });
	}

	batch(operations: readonly FileTreeBatchOperation[]): void {
		this.batchCalls.push([...operations]);
	}

	setGitStatus(gitStatus?: FileTreeOptions['gitStatus']): void {
		this.setGitStatusCalls.push([...(gitStatus ?? [])]);
	}

	focusPath(): void {}

	scrollToPath(): void {}
}
