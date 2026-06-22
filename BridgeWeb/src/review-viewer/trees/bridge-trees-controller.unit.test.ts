import type { FileTreeBatchOperation, FileTreeOptions } from '@pierre/trees';
import { describe, expect, expectTypeOf, test, vi } from 'vitest';

import {
	applyDeltaToBridgeReviewItemRegistry,
	createBridgeReviewItemRegistry,
} from '../../foundation/review-package/bridge-review-item-registry.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerBrowserFixture } from '../test-support/bridge-viewer-mocked-backend.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	BridgeTreesController,
	createBridgeTreesSource,
	planBridgeTreesUpdate,
	type BridgeTreesModel,
} from './bridge-trees-controller.js';

describe('Bridge Trees controller', () => {
	test('builds canonical prepared Pierre input and Git status entries from projection metadata', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		const source = createBridgeTreesSource({
			reviewPackage,
			projection,
		});

		expect(source.orderedPaths).toEqual([
			'docs/plans/2026-bridge-plan.md',
			'Sources/App/Core.swift',
			'Sources/App/View.swift',
			'Sources/NewName.swift',
			'Sources/Removed.swift',
			'Tests/App/ViewTests.swift',
		]);
		expect(new Set(source.orderedPaths).size).toBe(source.orderedPaths.length);
		expect(source.initialExpandedPaths).toEqual([
			'docs',
			'docs/plans',
			'Sources',
			'Sources/App',
			'Tests',
			'Tests/App',
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

	test('bounds initial expansion for large review trees so search does not preserve every branch', () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const projection = buildBridgeReviewProjection({
			reviewPackage: fixture.reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		const source = createBridgeTreesSource({
			reviewPackage: fixture.reviewPackage,
			projection,
		});

		expect(source.orderedPaths).toHaveLength(fixture.metadata.pathCount);
		expect(source.initialExpandedPaths.length).toBeLessThanOrEqual(128);
		expect(source.initialExpandedPaths).toContain('Sources');
		expect(source.initialExpandedPaths).not.toContain('Sources/AgentStudio/source/module-199');
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

	test('treats projection identity changes as whole-tree resets', () => {
		const source = makeSource({
			orderedPaths: ['src/a.ts', 'src/b.ts'],
			gitStatusEntries: [{ path: 'src/a.ts', status: 'modified' }],
			projectionId: 'package:338:normal',
		});
		const filteredSource = makeSource({
			orderedPaths: ['docs/plan.md'],
			gitStatusEntries: [{ path: 'docs/plan.md', status: 'modified' }],
			primaryItemIdByTreePath: { 'docs/plan.md': 'docs-plan' },
			projectionId: 'package:338:plans',
		});

		expect(planBridgeTreesUpdate({ previous: source, next: filteredSource })).toEqual({
			kind: 'reset',
		});
	});

	test('plans the medium streaming delta as an append-only tree mutation', () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'medium-agentstudio' });
		const request = { mode: { kind: 'normalReview' }, facets: [] } as const;
		const previousProjection = buildBridgeReviewProjection({
			reviewPackage: fixture.reviewPackage,
			request,
		});
		const previousSource = createBridgeTreesSource({
			reviewPackage: fixture.reviewPackage,
			projection: previousProjection,
		});
		const deltaResult = applyDeltaToBridgeReviewItemRegistry(
			createBridgeReviewItemRegistry({
				reviewPackage: fixture.reviewPackage,
				selectedItemId: null,
			}),
			fixture.streamingAppendDelta,
		);

		expect(deltaResult.accepted).toBe(true);
		if (!deltaResult.accepted) {
			return;
		}
		const nextProjection = buildBridgeReviewProjection({
			reviewPackage: deltaResult.registry.reviewPackage,
			request,
		});
		const nextSource = createBridgeTreesSource({
			reviewPackage: deltaResult.registry.reviewPackage,
			projection: nextProjection,
		});

		expect(previousProjection.projectionId).toBe(nextProjection.projectionId);
		expect(planBridgeTreesUpdate({ previous: previousSource, next: nextSource })).toEqual({
			kind: 'appendOnly',
			addedPaths: ['streaming/append/NewStreamingPanel.ts'],
			shouldUpdateGitStatus: true,
		});
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

	test('expands collapsed ancestors before scrolling a selected tree path', () => {
		const model = new RecordingTreesModel();
		const controller = new BridgeTreesController({ model });
		const source = makeSource({
			orderedPaths: ['src/deep/nested/file.ts'],
			gitStatusEntries: [{ path: 'src/deep/nested/file.ts', status: 'modified' }],
			primaryItemIdByTreePath: {
				'src/deep/nested/file.ts': 'deep-file',
			},
		});
		const rootDirectory = model.addDirectory('src', false);
		const deepDirectory = model.addDirectory('src/deep', false);
		const nestedDirectory = model.addDirectory('src/deep/nested', false);

		controller.applySource(source);

		expect(controller.selectTreePath('src/deep/nested/file.ts')).toBe('deep-file');
		expect(rootDirectory.expand).toHaveBeenCalledTimes(1);
		expect(deepDirectory.expand).toHaveBeenCalledTimes(1);
		expect(nestedDirectory.expand).toHaveBeenCalledTimes(1);
		expect(rootDirectory.expand.mock.invocationCallOrder[0]).toBeLessThan(
			deepDirectory.expand.mock.invocationCallOrder[0] ?? Number.POSITIVE_INFINITY,
		);
		expect(deepDirectory.expand.mock.invocationCallOrder[0]).toBeLessThan(
			nestedDirectory.expand.mock.invocationCallOrder[0] ?? Number.POSITIVE_INFINITY,
		);
		expect(model.focusPathCalls).toEqual([]);
		expect(model.scrollToPathCalls).toEqual([
			{ path: 'src/deep/nested/file.ts', options: { focus: true } },
		]);
	});

	test('reveals a tree path without changing selection focus semantics', () => {
		const model = new RecordingTreesModel();
		const controller = new BridgeTreesController({ model });
		const source = makeSource({
			orderedPaths: ['src/deep/nested/file.ts'],
			gitStatusEntries: [{ path: 'src/deep/nested/file.ts', status: 'modified' }],
			primaryItemIdByTreePath: {
				'src/deep/nested/file.ts': 'deep-file',
			},
		});
		const rootDirectory = model.addDirectory('src', false);
		const deepDirectory = model.addDirectory('src/deep', false);
		const nestedDirectory = model.addDirectory('src/deep/nested', false);

		controller.applySource(source);
		controller.revealTreePath('src/deep/nested/file.ts');

		expect(rootDirectory.expand).toHaveBeenCalledTimes(1);
		expect(deepDirectory.expand).toHaveBeenCalledTimes(1);
		expect(nestedDirectory.expand).toHaveBeenCalledTimes(1);
		expect(model.scrollToPathCalls).toEqual([
			{ path: 'src/deep/nested/file.ts', options: undefined },
		]);
	});

	test('reveals appended paths without expanding the whole large tree', () => {
		const model = new RecordingTreesModel();
		const controller = new BridgeTreesController({ model });
		const source = makeSource({
			orderedPaths: ['src/a.ts'],
			gitStatusEntries: [{ path: 'src/a.ts', status: 'modified' }],
			primaryItemIdByTreePath: {
				'src/a.ts': 'item-a',
			},
		});
		const streamingDirectory = model.addDirectory('streaming', false);
		const appendDirectory = model.addDirectory('streaming/append', false);

		controller.applySource(source);
		controller.applySource(
			makeSource({
				orderedPaths: ['src/a.ts', 'streaming/append/NewStreamingPanel.ts'],
				gitStatusEntries: [
					{ path: 'src/a.ts', status: 'modified' },
					{ path: 'streaming/append/NewStreamingPanel.ts', status: 'added' },
				],
				primaryItemIdByTreePath: {
					...source.primaryItemIdByTreePath,
					'streaming/append/NewStreamingPanel.ts': 'streaming-panel',
				},
			}),
		);

		expect(streamingDirectory.expand).toHaveBeenCalledTimes(1);
		expect(appendDirectory.expand).toHaveBeenCalledTimes(1);
	});
});

function makeSource(
	props: Pick<ReturnType<typeof createBridgeTreesSource>, 'orderedPaths' | 'gitStatusEntries'> &
		Partial<
			Pick<ReturnType<typeof createBridgeTreesSource>, 'primaryItemIdByTreePath' | 'projectionId'>
		>,
): ReturnType<typeof createBridgeTreesSource> {
	const reviewPackage = makeBridgeViewerProjectionFixture();
	const projection = buildBridgeReviewProjection({
		reviewPackage,
		request: { mode: { kind: 'normalReview' }, facets: [] },
	});
	return {
		...createBridgeTreesSource({ reviewPackage, projection }),
		orderedPaths: props.orderedPaths,
		gitStatusEntries: props.gitStatusEntries,
		primaryItemIdByTreePath: props.primaryItemIdByTreePath ?? {},
		projectionId: props.projectionId ?? projection.projectionId,
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
	readonly focusPathCalls: string[] = [];
	readonly scrollToPathCalls: Array<{
		readonly path: string;
		readonly options: Parameters<BridgeTreesModel['scrollToPath']>[1];
	}> = [];
	readonly setGitStatusCalls: Array<NonNullable<FileTreeOptions['gitStatus']>> = [];
	readonly itemByPath = new Map<string, ReturnType<typeof makeDirectoryHandle>>();

	addDirectory(path: string, isExpanded: boolean): ReturnType<typeof makeDirectoryHandle> {
		const directory = makeDirectoryHandle({ isExpanded });
		this.itemByPath.set(path, directory);
		return directory;
	}

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

	getItem(path: string): ReturnType<typeof makeDirectoryHandle> | null {
		return this.itemByPath.get(path) ?? null;
	}

	focusPath(path: string): void {
		this.focusPathCalls.push(path);
	}

	scrollToPath(path: string, options?: Parameters<BridgeTreesModel['scrollToPath']>[1]): void {
		this.scrollToPathCalls.push({ path, options });
	}
}

function makeDirectoryHandle(props: { readonly isExpanded: boolean }): {
	readonly collapse: ReturnType<typeof vi.fn>;
	readonly deselect: ReturnType<typeof vi.fn>;
	readonly expand: ReturnType<typeof vi.fn>;
	readonly focus: ReturnType<typeof vi.fn>;
	readonly getPath: ReturnType<typeof vi.fn>;
	readonly isDirectory: () => true;
	readonly isExpanded: () => boolean;
	readonly isFocused: () => boolean;
	readonly isSelected: () => boolean;
	readonly select: ReturnType<typeof vi.fn>;
	readonly toggle: ReturnType<typeof vi.fn>;
	readonly toggleSelect: ReturnType<typeof vi.fn>;
} {
	let expanded = props.isExpanded;
	return {
		collapse: vi.fn((): void => {
			expanded = false;
		}),
		deselect: vi.fn(),
		expand: vi.fn((): void => {
			expanded = true;
		}),
		focus: vi.fn(),
		getPath: vi.fn((): string => ''),
		isDirectory: (): true => true,
		isExpanded: (): boolean => expanded,
		isFocused: (): boolean => false,
		isSelected: (): boolean => false,
		select: vi.fn(),
		toggle: vi.fn((): void => {
			expanded = !expanded;
		}),
		toggleSelect: vi.fn(),
	};
}
