import { readFileSync } from 'node:fs';

import { parseDiffFromFile } from '@pierre/diffs';
import { describe, expect, test } from 'vitest';

import type { BridgeWorkerPierreRenderJobEvent } from './bridge-worker-contracts.js';
import { createBridgeWorkerPierreCourier } from './bridge-worker-pierre-courier.js';
import {
	buildBridgeWorkerPierreRenderJob,
	type BridgeWorkerPierreRenderJob,
} from './bridge-worker-pierre-render-job.js';

describe('Bridge worker Pierre courier', () => {
	test('review courier enqueues BridgeWorkerPierreRenderJob through the injected Pierre seam without main content work', () => {
		const job = buildBridgeWorkerPierreRenderJob({
			itemId: 'item-1',
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:sha256:base|pierre-content:sha256:head',
			contentHash: 'sha256:base+head',
			language: 'typescript',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			window: {
				startLine: 1,
				endLine: 20,
				totalLineCount: 200,
			},
			payload: {
				kind: 'codeViewDiffItem',
				item: {
					id: 'item-1',
					type: 'diff',
					fileDiff: parseDiffFromFile(
						{
							name: 'Sources/App.ts',
							contents: 'export const answer = 41;\n',
							cacheKey: 'pierre-content:sha256:base',
						},
						{
							name: 'Sources/App.ts',
							contents: 'export const answer = 42;\n',
							cacheKey: 'pierre-content:sha256:head',
						},
					),
					version: 2,
					bridgeMetadata: {
						itemId: 'item-1',
						displayPath: 'Sources/App.ts',
						contentState: 'hydrated',
						contentRoles: ['base', 'head'],
						cacheKey: 'pierre-content:sha256:base|pierre-content:sha256:head',
						lineCount: 2,
					},
				},
			},
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
		});
		const event = {
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'pierreRenderJob',
			job,
		} satisfies BridgeWorkerPierreRenderJobEvent;
		const enqueuedJobs: BridgeWorkerPierreRenderJob[] = [];
		const courier = createBridgeWorkerPierreCourier({
			enqueuePierreRenderJob: (receivedJob) => {
				enqueuedJobs.push(receivedJob);
				return {
					status: 'enqueued',
					itemId: receivedJob.itemId,
					payloadByteLength: receivedJob.payloadByteLength,
					budgetClass: receivedJob.budgetClass,
				};
			},
		});

		const receipt = courier.enqueue(event.job);

		expect(receipt).toEqual({
			status: 'enqueued',
			itemId: 'item-1',
			payloadByteLength: job.payloadByteLength,
			budgetClass: 'interactive',
		});
		expect(enqueuedJobs).toEqual([job]);
		expect(enqueuedJobs[0]).toBe(job);
	});

	test('courier seam and review snapshot controller do not import main-thread content processors', () => {
		const courierSource = readFileSync(
			new URL('./bridge-worker-pierre-courier.ts', import.meta.url),
			'utf8',
		);
		const controllerSource = readFileSync(
			new URL('../../app/bridge-app-review-render-snapshot-controller.ts', import.meta.url),
			'utf8',
		);
		const source = `${courierSource}\n${controllerSource}`;
		const forbiddenMainThreadContentProcessors = [
			'loadReviewItemContentResourcesThroughDemandResult',
			'useSelectedReviewContentDemandController',
			'useVisibleReviewContentHydration',
			'requestForegroundItemContent',
			'selectedContentResourcesState',
			'visibleContentResourcesByItemId',
			'materializeBridgeCodeViewItem',
			'bridgeCodeViewMaterializationCacheKeysForItem',
			'selectedBridgeCodeViewContentWindowLineLimitForItem',
			'parseDiffFromFile',
			'bridgePierreOptionalHighlightLanguage',
			'createBridgePierreContentDescriptorFile',
			'windowTextForCodeView',
			'renderDiffWithHighlighter',
			'renderFileWithHighlighter',
			'splitFileContents',
			'TextDecoder',
			'readText()',
			'../review-viewer/code-view/bridge-code-view-materialization.js',
			'../review-viewer/content/review-content-demand-loader.js',
			'./bridge-app-review-selected-content-controller.js',
			'./bridge-app-review-visible-content-controller.js',
		];

		for (const forbiddenProcessor of forbiddenMainThreadContentProcessors) {
			expect(source).not.toContain(forbiddenProcessor);
		}
	});
});
