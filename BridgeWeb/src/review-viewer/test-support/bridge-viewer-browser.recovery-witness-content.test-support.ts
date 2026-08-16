import type { BridgeWorkerServerToMainMessage } from '../../core/comm-worker/bridge-worker-contracts.js';
import { buildBridgeWorkerPierreRenderJob } from '../../core/comm-worker/bridge-worker-pierre-render-job.js';
import { makeBridgeWorkerRenderReceiptIdentity } from '../../core/comm-worker/bridge-worker-render-fulfillment.test-support.js';
import { parseBridgeCodeViewDiffForBrowserTest } from '../code-view/bridge-code-view-browser-test-diff.js';
import type { BridgeReviewRecoveryWitnessFile } from './bridge-viewer-browser.recovery-witness.test-support.js';

export function completeReviewContentMessages(
	file: BridgeReviewRecoveryWitnessFile,
	publicationSequence: number,
): readonly BridgeWorkerServerToMainMessage[] {
	const baseContents = reviewWitnessFileContents(file, 'BASE');
	const headContents = reviewWitnessFileContents(file, file.contentMarker);
	const baseCacheKey = `review-recovery-base-${file.itemId}`;
	const headCacheKey = `review-recovery-head-${file.itemId}`;
	const contentCacheKey = `${baseCacheKey}|${headCacheKey}`;
	const job = buildBridgeWorkerPierreRenderJob({
		bridgeDemandRank: { lane: 'visible', priority: publicationSequence },
		budget: { className: 'visible', maxBytes: 512 * 1024, maxWindowLines: 400 },
		contentCacheKey,
		contentHash: `review-recovery-content-${file.itemId}`,
		itemId: file.itemId,
		language: 'swift',
		payload: {
			item: {
				bridgeMetadata: {
					cacheKey: contentCacheKey,
					contentRoles: ['base', 'head'],
					contentState: 'hydrated',
					displayPath: file.path,
					itemId: file.itemId,
					lineCount: file.lineCount * 2,
				},
				fileDiff: parseBridgeCodeViewDiffForBrowserTest(
					{ cacheKey: baseCacheKey, contents: baseContents, name: file.path },
					{ cacheKey: headCacheKey, contents: headContents, name: file.path },
				),
				id: file.itemId,
				type: 'diff',
				version: 1,
			},
			kind: 'codeViewDiffItem',
		},
		renderKind: 'reviewDiff',
		...(file.sourceCorrelation === undefined
			? {}
			: { sourceCorrelations: [file.sourceCorrelation] }),
		window: { endLine: file.lineCount, startLine: 1, totalLineCount: file.lineCount },
	});
	return [
		{
			direction: 'serverWorkerToMain',
			job,
			kind: 'reviewPierreRenderJob',
			publicationSequence,
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
				itemId: job.itemId,
				publicationSequence,
				surface: 'review',
				workerDerivationEpoch: 1,
			}),
			surface: 'review',
			transferDescriptors: [
				{
					byteLength: job.payloadByteLength,
					fieldPath: ['job', 'payload'],
					messageKind: 'reviewPierreRenderJob',
					mode: 'clone',
				},
			],
			wireVersion: 1,
			workerDerivationEpoch: 1,
		},
		{
			direction: 'serverWorkerToMain',
			kind: 'reviewRenderPatch',
			patches: [
				{
					itemId: file.itemId,
					operation: 'upsert',
					payload: { contentCacheKey },
					slice: 'rowPaint',
				},
				{
					itemId: file.itemId,
					operation: 'upsert',
					payload: { state: 'ready' },
					slice: 'contentAvailability',
				},
			],
			publicationSequence,
			surface: 'review',
			transferDescriptors: [],
			wireVersion: 1,
			workerDerivationEpoch: 1,
		},
	];
}

export function completeReviewFileContentMessages(
	file: BridgeReviewRecoveryWitnessFile,
	publicationSequence: number,
): readonly BridgeWorkerServerToMainMessage[] {
	const contents = reviewWitnessFileContents(file, file.contentMarker);
	const contentCacheKey = `review-recovery-file-${file.itemId}`;
	const job = buildBridgeWorkerPierreRenderJob({
		bridgeDemandRank: { lane: 'selected', priority: publicationSequence },
		budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
		contentCacheKey,
		contentHash: `review-recovery-file-content-${file.itemId}`,
		itemId: file.itemId,
		language: 'swift',
		payload: {
			item: {
				bridgeMetadata: {
					cacheKey: contentCacheKey,
					contentRoles: ['head'],
					contentState: 'hydrated',
					displayPath: file.path,
					itemId: file.itemId,
					lineCount: file.lineCount,
				},
				file: { cacheKey: contentCacheKey, contents, lang: 'swift', name: file.path },
				id: file.itemId,
				type: 'file',
				version: 1,
			},
			kind: 'codeViewFileItem',
		},
		renderKind: 'fileText',
		window: { endLine: file.lineCount, startLine: 1, totalLineCount: file.lineCount },
	});
	return [
		{
			direction: 'serverWorkerToMain',
			job,
			kind: 'reviewPierreRenderJob',
			publicationSequence,
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
				itemId: job.itemId,
				publicationSequence,
				surface: 'review',
				workerDerivationEpoch: 1,
			}),
			surface: 'review',
			transferDescriptors: [
				{
					byteLength: job.payloadByteLength,
					fieldPath: ['job', 'payload'],
					messageKind: 'reviewPierreRenderJob',
					mode: 'clone',
				},
			],
			wireVersion: 1,
			workerDerivationEpoch: 1,
		},
		{
			direction: 'serverWorkerToMain',
			kind: 'reviewRenderPatch',
			patches: [
				{
					itemId: file.itemId,
					operation: 'upsert',
					payload: { contentCacheKey },
					slice: 'rowPaint',
				},
				{
					itemId: file.itemId,
					operation: 'upsert',
					payload: { state: 'ready' },
					slice: 'contentAvailability',
				},
			],
			publicationSequence,
			surface: 'review',
			transferDescriptors: [],
			wireVersion: 1,
			workerDerivationEpoch: 1,
		},
	];
}

function reviewWitnessFileContents(file: BridgeReviewRecoveryWitnessFile, marker: string): string {
	return Array.from({ length: file.lineCount }, (_, lineIndex): string => {
		const lineNumber = String(lineIndex + 1).padStart(3, '0');
		return `let recoveryWitness${lineNumber} = "${marker}_LINE_${lineNumber}"`;
	}).join('\n');
}
