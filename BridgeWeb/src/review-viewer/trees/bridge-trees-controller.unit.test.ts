import type { FileTreeBatchOperation, FileTreeItemHandle, FileTreeOptions } from '@pierre/trees';
import { describe, expect, expectTypeOf, test, vi } from 'vitest';

import {
	applyDeltaToBridgeReviewItemRegistry,
	createBridgeReviewItemRegistry,
} from '../../foundation/review-package/bridge-review-item-registry.js';
import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import type {
	BridgeTelemetryMeasureProps,
	BridgeTelemetryRecorder,
} from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerBrowserFixture } from '../test-support/bridge-viewer-mocked-backend-fixture.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	BridgeTreesController,
	createBridgeTreesSource,
	expandedDirectoryPathsForBridgeTreePaths,
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
			{ path: 'docs/plans/2026-bridge-plan.md', status: 'modified' },
			{ path: 'Sources/App/Core.swift', status: 'modified' },
			{ path: 'Sources/App/View.swift', status: 'modified' },
			{ path: 'Sources/NewName.swift', status: 'renamed' },
			{ path: 'Sources/Removed.swift', status: 'deleted' },
			{ path: 'Tests/App/ViewTests.swift', status: 'modified' },
		]);
		expect(source.gitStatusEntries).not.toContainEqual({
			path: 'Sources/App/View.swift',
			status: 'untracked',
		});
		expectTypeOf(source.preparedInput).toMatchTypeOf<FileTreeOptions['preparedInput']>();
	});

	test('prefers streamed review tree rows over synthesized projection paths', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const itemId = projection.orderedItemIds[0] ?? 'missing-item';
		expect(projection.orderedItemIds[0]).toBeDefined();

		const source = createBridgeTreesSource({
			reviewPackage,
			projection,
			reviewTreeRows: [
				{
					rowId: 'stream-row-1',
					itemId,
					path: 'authoritative/streamed/path.swift',
					depth: 2,
					isDirectory: false,
				},
			],
		});

		expect(source.orderedPaths).toEqual(['authoritative/streamed/path.swift']);
		expect(source.primaryItemIdByTreePath).toEqual({
			'authoritative/streamed/path.swift': itemId,
		});
		expect(source.gitStatusEntries).toEqual([
			{ path: 'authoritative/streamed/path.swift', status: 'modified' },
		]);
		expect(source.orderedPaths).not.toContain(projection.orderedPaths[0]);
	});

	test('normalizes streamed directory rows for Pierre tree input', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const itemId = projection.orderedItemIds[0] ?? 'missing-item';
		expect(projection.orderedItemIds[0]).toBeDefined();

		const source = createBridgeTreesSource({
			reviewPackage,
			projection,
			reviewTreeRows: [
				{
					rowId: 'review-directory:review-viewer',
					path: 'review-viewer',
					depth: 0,
					isDirectory: true,
				},
				{
					rowId: 'review-row:review-viewer-file',
					itemId,
					path: 'review-viewer/file.ts',
					depth: 1,
					isDirectory: false,
				},
			],
		});

		expect(source.orderedPaths).toEqual(['review-viewer/', 'review-viewer/file.ts']);
		expect(source.primaryItemIdByTreePath).toEqual({
			'review-viewer/file.ts': itemId,
		});
	});

	test('starts large Review trees with every directory expanded', () => {
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
		expect(source.initialExpandedPaths.length).toBeGreaterThan(0);
		expect(source.initialExpandedPaths).toContain('Sources');
	});

	test('starts a fresh Review tree with every directory expanded', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		const source = createBridgeTreesSource({
			reviewPackage,
			projection,
		});

		expect(source.initialExpandedPaths).toEqual([
			'docs',
			'docs/plans',
			'Sources',
			'Sources/App',
			'Tests',
			'Tests/App',
		]);
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

	test('resets retained disclosure when the worker starts a new Review generation', () => {
		// Arrange
		const previousSource = makeSource({
			gitStatusEntries: [],
			orderedPaths: ['Sources/Feature/File.swift'],
			reviewGeneration: 7,
		});
		const nextSource = makeSource({
			gitStatusEntries: [],
			orderedPaths: ['Sources/Feature/File.swift'],
			reviewGeneration: 8,
		});

		// Act / Assert
		expect(planBridgeTreesUpdate({ previous: previousSource, next: nextSource })).toEqual({
			kind: 'reset',
		});
		expect(nextSource.initialExpandedPaths).toEqual(['Sources', 'Sources/Feature']);
	});

	test('resets retained Pierre disclosure when the initial disclosure policy changes', () => {
		// Arrange
		const previousSource = {
			...makeSource({
				orderedPaths: ['Sources/Feature/File.swift'],
				gitStatusEntries: [],
			}),
			disclosurePolicyIdentity: 'expand-first-window-v1',
		};
		const nextSource = makeSource({
			orderedPaths: ['Sources/Feature/File.swift'],
			gitStatusEntries: [],
		});

		// Act
		const updatePlan = planBridgeTreesUpdate({ previous: previousSource, next: nextSource });

		// Assert
		expect(updatePlan).toEqual({ kind: 'reset' });
		expect(nextSource.initialExpandedPaths).toEqual(['Sources', 'Sources/Feature']);
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

	test('canonicalizes streamed review tree rows before planning tree updates', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const itemIds = projection.orderedItemIds.slice(0, 3);
		expect(itemIds).toHaveLength(3);
		const previousSource = createBridgeTreesSource({
			reviewPackage,
			projection,
			reviewTreeRows: [
				{
					rowId: 'review-row:middle',
					itemId: itemIds[0],
					path: 'middle/File.swift',
					depth: 1,
					isDirectory: false,
				},
				{
					rowId: 'review-row:z-last',
					itemId: itemIds[1],
					path: 'z-last/File.swift',
					depth: 1,
					isDirectory: false,
				},
			],
		});
		const nextSource = createBridgeTreesSource({
			reviewPackage,
			projection,
			reviewTreeRows: [
				{
					rowId: 'review-row:middle',
					itemId: itemIds[0],
					path: 'middle/File.swift',
					depth: 1,
					isDirectory: false,
				},
				{
					rowId: 'review-row:z-last',
					itemId: itemIds[1],
					path: 'z-last/File.swift',
					depth: 1,
					isDirectory: false,
				},
				{
					rowId: 'review-row:a-late',
					itemId: itemIds[2],
					path: 'a-late/File.swift',
					depth: 1,
					isDirectory: false,
				},
			],
		});

		expect(previousSource.orderedPaths).toEqual(['middle/File.swift', 'z-last/File.swift']);
		expect(nextSource.orderedPaths).toEqual([
			'a-late/File.swift',
			'middle/File.swift',
			'z-last/File.swift',
		]);
		expect(planBridgeTreesUpdate({ previous: previousSource, next: nextSource })).toEqual({
			kind: 'reset',
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

	test('does not rescan and scroll the tree when selecting the already-selected path', () => {
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
		expect(controller.selectTreePath('src/deep/nested/file.ts')).toBe('deep-file');

		expect(rootDirectory.expand).toHaveBeenCalledTimes(1);
		expect(deepDirectory.expand).toHaveBeenCalledTimes(1);
		expect(nestedDirectory.expand).toHaveBeenCalledTimes(1);
		expect(model.scrollToPathCalls).toEqual([
			{ path: 'src/deep/nested/file.ts', options: { focus: true } },
		]);
	});

	test('guards selected-path scrollToPath while user tree scroll is active', () => {
		const model = new RecordingTreesModel();
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const controller = new BridgeTreesController({
			model,
			isProgrammaticScrollActive: () => true,
			telemetryRecorder: makeCapturingRecorder(telemetrySamples),
		});
		const source = makeSource({
			orderedPaths: ['src/deep/nested/file.ts'],
			gitStatusEntries: [{ path: 'src/deep/nested/file.ts', status: 'modified' }],
			primaryItemIdByTreePath: {
				'src/deep/nested/file.ts': 'deep-file',
			},
		});

		controller.applySource(source);

		expect(controller.selectTreePath('src/deep/nested/file.ts')).toBe('deep-file');
		expect(model.scrollToPathCalls).toEqual([]);
		expect(telemetrySamples[0]).toMatchObject({
			name: 'performance.bridge.trees.scroll_to_path',
			stringAttributes: expect.objectContaining({
				'agentstudio.bridge.result': 'dropped',
				'agentstudio.bridge.scroll.offset': 'none',
				'agentstudio.bridge.scroll.reason': 'selected_path_effect',
			}),
			booleanAttributes: {
				'agentstudio.bridge.focus': true,
			},
		});
	});

	test('selects a clicked tree item through the public tree handle without scrolling', () => {
		const model = new RecordingTreesModel();
		const controller = new BridgeTreesController({ model });
		const source = makeSource({
			orderedPaths: ['src/clicked.ts'],
			gitStatusEntries: [{ path: 'src/clicked.ts', status: 'modified' }],
			primaryItemIdByTreePath: {
				'src/clicked.ts': 'clicked-file',
			},
		});
		const clickedFile = model.addFile('src/clicked.ts');

		controller.applySource(source);

		expect(controller.selectClickedTreePath('src/clicked.ts')).toBe('clicked-file');
		expect(clickedFile.select).toHaveBeenCalledTimes(1);
		expect(model.scrollToPathCalls).toEqual([]);
	});

	test('keeps clicked tree selection active while user tree scroll is active', () => {
		const model = new RecordingTreesModel();
		const controller = new BridgeTreesController({
			model,
			isProgrammaticScrollActive: () => true,
		});
		const source = makeSource({
			orderedPaths: ['src/clicked.ts'],
			gitStatusEntries: [{ path: 'src/clicked.ts', status: 'modified' }],
			primaryItemIdByTreePath: {
				'src/clicked.ts': 'clicked-file',
			},
		});
		const clickedFile = model.addFile('src/clicked.ts');

		controller.applySource(source);

		expect(controller.selectClickedTreePath('src/clicked.ts')).toBe('clicked-file');
		expect(clickedFile.select).toHaveBeenCalledTimes(1);
		expect(model.scrollToPathCalls).toEqual([]);
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

	test('guards search-match scrollToPath while user tree scroll is active', () => {
		const model = new RecordingTreesModel();
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const controller = new BridgeTreesController({
			model,
			isProgrammaticScrollActive: () => true,
			telemetryRecorder: makeCapturingRecorder(telemetrySamples),
		});
		const source = makeSource({
			orderedPaths: ['src/deep/nested/TargetFile.ts'],
			gitStatusEntries: [{ path: 'src/deep/nested/TargetFile.ts', status: 'modified' }],
			primaryItemIdByTreePath: {
				'src/deep/nested/TargetFile.ts': 'target-file',
			},
		});

		controller.applySource(source);

		expect(controller.revealFirstSearchMatch('targetfile')).toBe('src/deep/nested/TargetFile.ts');
		expect(model.scrollToPathCalls).toEqual([]);
		expect(telemetrySamples[0]).toMatchObject({
			name: 'performance.bridge.trees.scroll_to_path',
			stringAttributes: expect.objectContaining({
				'agentstudio.bridge.result': 'dropped',
				'agentstudio.bridge.scroll.offset': 'none',
				'agentstudio.bridge.scroll.reason': 'search_match',
			}),
			booleanAttributes: {
				'agentstudio.bridge.focus': false,
			},
		});
	});

	test('reveals a tree path without throwing on stale ancestor expansion handles', () => {
		const model = new RecordingTreesModel();
		const controller = new BridgeTreesController({ model });
		const source = makeSource({
			orderedPaths: ['src/stale/file.ts'],
			gitStatusEntries: [{ path: 'src/stale/file.ts', status: 'modified' }],
			primaryItemIdByTreePath: {
				'src/stale/file.ts': 'stale-file',
			},
		});
		model.addDirectory('src', false);
		model.itemByPath.set(
			'src/stale',
			makeDirectoryHandle({
				expand: (): void => {
					throw new Error('stale directory handle');
				},
				isExpanded: false,
			}),
		);

		controller.applySource(source);

		expect((): void => {
			controller.revealTreePath('src/stale/file.ts');
		}).not.toThrow();
		expect(model.scrollToPathCalls).toEqual([{ path: 'src/stale/file.ts', options: undefined }]);
	});

	test('appends paths without mutating directory disclosure', () => {
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

		expect(model.batchCalls.at(-1)).toEqual([
			{ type: 'add', path: 'streaming/append/NewStreamingPanel.ts' },
		]);
		expect(streamingDirectory.expand).not.toHaveBeenCalled();
		expect(appendDirectory.expand).not.toHaveBeenCalled();
	});

	test('preserves directory disclosure when metadata appends new paths', () => {
		const model = new RecordingTreesModel();
		const controller = new BridgeTreesController({ model });
		controller.applySource(
			makeSource({
				gitStatusEntries: [],
				orderedPaths: ['src/a.ts'],
			}),
		);
		const streamingDirectory = model.addDirectory('streaming', false);
		const appendDirectory = model.addDirectory('streaming/append', false);

		controller.applySource(
			makeSource({
				gitStatusEntries: [],
				orderedPaths: ['src/a.ts', 'streaming/append/NewStreamingPanel.ts'],
			}),
		);

		expect(streamingDirectory.expand).not.toHaveBeenCalled();
		expect(appendDirectory.expand).not.toHaveBeenCalled();
	});

	test('reveals explicitly requested appended review paths', () => {
		const model = new RecordingTreesModel();
		const controller = new BridgeTreesController({ model });
		controller.applySource(
			makeSource({
				orderedPaths: ['src/a.ts'],
				gitStatusEntries: [{ path: 'src/a.ts', status: 'modified' }],
				primaryItemIdByTreePath: {
					'src/a.ts': 'item-a',
				},
			}),
		);
		const appendedPaths = Array.from(
			{ length: 20 },
			(_, index): string => `streamed/module-${index}/File.swift`,
		);
		const lastModuleDirectory = model.addDirectory('streamed/module-19', false);
		model.addDirectory('streamed', false);

		controller.applySource(
			makeSource({
				orderedPaths: ['src/a.ts', ...appendedPaths],
				gitStatusEntries: [
					{ path: 'src/a.ts', status: 'modified' },
					...appendedPaths.map((path): { readonly path: string; readonly status: 'added' } => ({
						path,
						status: 'added',
					})),
				],
				primaryItemIdByTreePath: {
					'src/a.ts': 'item-a',
					...Object.fromEntries(
						appendedPaths.map((path, index): readonly [string, string] => [path, `item-${index}`]),
					),
				},
			}),
		);
		controller.revealTreePath(appendedPaths.at(-1) ?? '');

		expect(lastModuleDirectory.expand).toHaveBeenCalledTimes(1);
	});

	test('reveals the first active search match after streamed source updates', () => {
		const model = new RecordingTreesModel();
		const controller = new BridgeTreesController({ model });
		controller.applySource(
			makeSource({
				orderedPaths: ['src/visible.ts'],
				gitStatusEntries: [{ path: 'src/visible.ts', status: 'modified' }],
				primaryItemIdByTreePath: {
					'src/visible.ts': 'visible',
				},
			}),
		);
		expect(controller.revealFirstSearchMatch('targetfile')).toBeNull();
		const laterDirectory = model.addDirectory('src/later', false);
		const nestedDirectory = model.addDirectory('src/later/nested', false);

		controller.applySource(
			makeSource({
				orderedPaths: ['src/visible.ts', 'src/later/nested/TargetFile.ts'],
				gitStatusEntries: [
					{ path: 'src/visible.ts', status: 'modified' },
					{ path: 'src/later/nested/TargetFile.ts', status: 'added' },
				],
				primaryItemIdByTreePath: {
					'src/visible.ts': 'visible',
					'src/later/nested/TargetFile.ts': 'target',
				},
			}),
		);

		expect(controller.revealFirstSearchMatch('targetfile')).toBe('src/later/nested/TargetFile.ts');
		expect(laterDirectory.expand).toHaveBeenCalledTimes(1);
		expect(nestedDirectory.expand).toHaveBeenCalledTimes(1);
		expect(model.scrollToPathCalls.at(-1)).toEqual({
			path: 'src/later/nested/TargetFile.ts',
			options: undefined,
		});
	});

	test('maps full path search intent to a Pierre-friendly leaf query', () => {
		const model = new RecordingTreesModel();
		const controller = new BridgeTreesController({ model });
		controller.applySource(
			makeSource({
				orderedPaths: ['BridgeWeb/src/review-viewer/test-support/review-viewer-fixtures.ts'],
				gitStatusEntries: [
					{
						path: 'BridgeWeb/src/review-viewer/test-support/review-viewer-fixtures.ts',
						status: 'modified',
					},
				],
			}),
		);

		expect(
			controller.modelSearchTextForFirstSearchMatch(
				'BridgeWeb/src/review-viewer/test-support/review-viewer-fixtures.ts',
			),
		).toBe('review-viewer-fixtures');
		expect(controller.modelSearchTextForFirstSearchMatch('review-viewer')).toBe('review-viewer');
	});
});

function makeSource(
	props: Pick<ReturnType<typeof createBridgeTreesSource>, 'orderedPaths' | 'gitStatusEntries'> &
		Partial<
			Pick<
				ReturnType<typeof createBridgeTreesSource>,
				'primaryItemIdByTreePath' | 'projectionId' | 'reviewGeneration'
			>
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
		initialExpandedPaths: expandedDirectoryPathsForBridgeTreePaths(props.orderedPaths),
		gitStatusEntries: props.gitStatusEntries,
		primaryItemIdByTreePath: props.primaryItemIdByTreePath ?? {},
		projectionId: props.projectionId ?? projection.projectionId,
		reviewGeneration: props.reviewGeneration ?? reviewPackage.reviewGeneration,
		gitStatusSignature: props.gitStatusEntries
			.map((entry): string => `${entry.path}\u0000${entry.status}`)
			.join('\n'),
	};
}

function makeCapturingRecorder(samples: BridgeTelemetrySample[]): BridgeTelemetryRecorder {
	return {
		flush: (): boolean => true,
		isEnabled: (): boolean => true,
		measure: <TResult>(props: BridgeTelemetryMeasureProps<TResult>): TResult => props.operation(),
		record: (sample: BridgeTelemetrySample): void => {
			samples.push(sample);
		},
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
	readonly itemByPath = new Map<string, FileTreeItemHandle>();

	addDirectory(path: string, isExpanded: boolean): ReturnType<typeof makeDirectoryHandle> {
		const directory = makeDirectoryHandle({ isExpanded });
		this.itemByPath.set(path, directory);
		return directory;
	}

	addFile(path: string): ReturnType<typeof makeFileHandle> {
		const file = makeFileHandle();
		this.itemByPath.set(path, file);
		return file;
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

	getItem(path: string): FileTreeItemHandle | null {
		return this.itemByPath.get(path) ?? null;
	}

	focusPath(path: string): void {
		this.focusPathCalls.push(path);
	}

	scrollToPath(path: string, options?: Parameters<BridgeTreesModel['scrollToPath']>[1]): void {
		this.scrollToPathCalls.push({ path, options });
	}
}

function makeDirectoryHandle(props: {
	readonly expand?: () => void;
	readonly isExpanded: boolean;
}): {
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
		expand: vi.fn(
			props.expand ??
				((): void => {
					expanded = true;
				}),
		),
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

function makeFileHandle(): {
	readonly deselect: ReturnType<typeof vi.fn>;
	readonly focus: ReturnType<typeof vi.fn>;
	readonly getPath: ReturnType<typeof vi.fn>;
	readonly isDirectory: () => false;
	readonly isFocused: () => boolean;
	readonly isSelected: () => boolean;
	readonly select: ReturnType<typeof vi.fn>;
	readonly toggleSelect: ReturnType<typeof vi.fn>;
} {
	return {
		deselect: vi.fn(),
		focus: vi.fn(),
		getPath: vi.fn((): string => ''),
		isDirectory: (): false => false,
		isFocused: (): boolean => false,
		isSelected: (): boolean => false,
		select: vi.fn(),
		toggleSelect: vi.fn(),
	};
}
