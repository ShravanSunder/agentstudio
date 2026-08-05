import { expect } from 'vitest';

import type { BridgeMainRenderSnapshotStore } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type {
	BridgeWorkerFileDisplayPatchEvent,
	BridgeWorkerReviewDisplayItem,
	BridgeWorkerReviewDisplayPatchEvent,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type {
	BridgeWorkerCodeViewFileItem,
	BridgeWorkerCodeViewDiffItem,
} from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import { parseBridgeCodeViewDiffForBrowserTest } from '../review-viewer/code-view/bridge-code-view-browser-test-diff.js';
import { reviewWitnessTreeRows } from '../review-viewer/test-support/bridge-viewer-browser-recovery-tree-fixture.js';
import { actWait } from './bridge-app-browser-test-actions.js';

export interface SurfacePositionOwners {
	readonly codeScrollOwner: HTMLElement;
	readonly treeScrollOwner: HTMLElement;
}

export interface SurfacePositionSnapshot {
	readonly codeScrollTop: number;
	readonly treeScrollTop: number;
}

export const bridgePanePositionFileItemId = 'position-file-001';
export const bridgePanePositionFilePath = 'Sources/PositionFile001.swift';
export const bridgePanePositionReviewItemId = 'position-review-001';
export const bridgePaneReplacementFileItemId = 'replacement-file-001';
export const bridgePaneReplacementFilePath = 'Sources/ReplacementOnly.swift';

const fileTreeRowCount = 180;
const fileLineCount = 800;
const reviewFileCount = 80;
const reviewLineCount = 18;
const reviewMetadataWindowIdentity = 'position-review-window-1';

export function installBridgePanePositionFixtures(props: {
	readonly fileRenderStore: BridgeMainRenderSnapshotStore;
	readonly reviewRenderStore: BridgeMainRenderSnapshotStore;
}): void {
	installFilePositionFixture(props.fileRenderStore);
	installReviewPositionFixture(props.reviewRenderStore);
}

export function replaceFilePositionFixtureWithTarget(
	renderStore: BridgeMainRenderSnapshotStore,
): void {
	renderStore.applyFileDisplayPatchEvent({
		direction: 'serverWorkerToMain',
		epoch: 2,
		kind: 'fileDisplayPatch',
		patches: [
			{
				operation: 'reset',
				payload: { sourceGeneration: 2, sourceId: 'replacement-file-source' },
				slice: 'fileTree',
			},
			...replacementFileTargetPatches(0),
		],
		projectionRevision: 2,
		sequence: 2,
		surface: 'fileView',
		transferDescriptors: [],
		wireVersion: 1,
	});
}

export function addReplacementFileTargetToCurrentSource(
	renderStore: BridgeMainRenderSnapshotStore,
): void {
	renderStore.applyFileDisplayPatchEvent({
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'fileDisplayPatch',
		patches: replacementFileTargetPatches(fileTreeRowCount),
		projectionRevision: 2,
		sequence: 2,
		surface: 'fileView',
		transferDescriptors: [],
		wireVersion: 1,
	});
}

export async function exercisePendingFileTargetSupersession(props: {
	readonly fileRenderStore: BridgeMainRenderSnapshotStore;
	readonly hasSelectedReplacementTarget: () => boolean;
	readonly publishTarget: (target: {
		readonly bindingRevision: number;
		readonly commandId: string;
		readonly path: string;
		readonly sourceId: string;
		readonly subscriptionGeneration: number;
	}) => Promise<void>;
	readonly reviewRenderStore: BridgeMainRenderSnapshotStore;
}): Promise<{ readonly afterSupersession: boolean; readonly beforeSupersession: boolean }> {
	await actWait(async (): Promise<void> => {
		installBridgePanePositionFixtures(props);
		await Promise.resolve();
	});
	await props.publishTarget({
		bindingRevision: 1,
		commandId: 'native-file-target-source-a',
		path: bridgePaneReplacementFilePath,
		sourceId: 'position-file-source',
		subscriptionGeneration: 1,
	});
	const beforeSupersession = props.hasSelectedReplacementTarget();
	await props.publishTarget({
		bindingRevision: 2,
		commandId: 'native-file-target-source-b',
		path: bridgePaneReplacementFilePath,
		sourceId: 'replacement-file-source',
		subscriptionGeneration: 2,
	});
	await actWait(async (): Promise<void> => {
		addReplacementFileTargetToCurrentSource(props.fileRenderStore);
		await Promise.resolve();
	});
	await advanceAnimationFrame();
	return {
		afterSupersession: props.hasSelectedReplacementTarget(),
		beforeSupersession,
	};
}

function replacementFileTargetPatches(
	projectionIndex: number,
): BridgeWorkerFileDisplayPatchEvent['patches'] {
	return [
		{
			operation: 'batch',
			payload: {
				operations: [
					{
						operation: 'upsert',
						row: {
							changeStatus: 'modified',
							depth: 1,
							fileClass: 'source',
							fileId: bridgePaneReplacementFileItemId,
							isDirectory: false,
							lineCount: 1,
							name: 'ReplacementOnly.swift',
							parentPath: 'Sources',
							path: bridgePaneReplacementFilePath,
							projectionIndex,
							rowId: 'replacement-file-row-001',
							sizeBytes: 32,
						},
					},
				],
			},
			slice: 'fileTree',
		},
		{
			itemId: bridgePaneReplacementFileItemId,
			operation: 'upsert',
			payload: {
				availability: { kind: 'available' },
				displayPath: bridgePaneReplacementFilePath,
				endsMidLine: false,
				endsWithNewline: true,
				extent: { kind: 'exactLineCount', lineCount: 1 },
				fileExtension: 'swift',
				language: 'swift',
				payloadByteCount: 32,
				payloadLineCount: 1,
				rowId: 'replacement-file-row-001',
				sizeBytes: 32,
				totalLineCount: 1,
				truncationKind: 'none',
			},
			slice: 'fileItem',
		},
	];
}

export async function waitForScrollableSurfaceOwners(props: {
	readonly host: HTMLElement;
	readonly surface: 'file' | 'review';
	readonly remainingFrames?: number;
}): Promise<SurfacePositionOwners> {
	const remainingFrames = props.remainingFrames ?? 180;
	const treeScrollOwner = treeScrollOwnerWithinHost(props.host);
	const codeScrollOwner = props.host.querySelector('.bridge-code-view-scroll-owner');
	if (
		treeScrollOwner instanceof HTMLElement &&
		codeScrollOwner instanceof HTMLElement &&
		treeScrollOwner.scrollHeight > treeScrollOwner.clientHeight &&
		codeScrollOwner.scrollHeight > codeScrollOwner.clientHeight
	) {
		return { codeScrollOwner, treeScrollOwner };
	}
	if (remainingFrames <= 0) {
		throw new Error(
			`Expected scrollable ${props.surface} owners; tree=${treeScrollOwner?.scrollHeight ?? 'missing'}/${treeScrollOwner?.clientHeight ?? 'missing'} code=${codeScrollOwner instanceof HTMLElement ? `${codeScrollOwner.scrollHeight}/${codeScrollOwner.clientHeight}` : 'missing'}.`,
		);
	}
	await advanceAnimationFrame();
	return await waitForScrollableSurfaceOwners({
		...props,
		remainingFrames: remainingFrames - 1,
	});
}

export async function establishSemanticSurfacePosition(
	owners: SurfacePositionOwners,
): Promise<SurfacePositionSnapshot> {
	await actWait(async (): Promise<void> => {
		setUserScrollPosition(owners.treeScrollOwner, 0.37);
		setUserScrollPosition(owners.codeScrollOwner, 0.43);
		await Promise.resolve();
	});
	await waitForStableNonzeroScrollPosition(owners.treeScrollOwner);
	await waitForStableNonzeroScrollPosition(owners.codeScrollOwner);
	return surfacePositionSnapshot(owners);
}

export async function assertSurfacePositionRetained(props: {
	readonly expected: SurfacePositionSnapshot;
	readonly owners: SurfacePositionOwners;
	readonly surface: 'file' | 'review';
}): Promise<void> {
	await waitForStableNonzeroScrollPosition(props.owners.treeScrollOwner);
	await waitForStableNonzeroScrollPosition(props.owners.codeScrollOwner);
	const actual = surfacePositionSnapshot(props.owners);
	expect(actual.treeScrollTop, `${props.surface} tree position`).toBeGreaterThan(0);
	expect(actual.codeScrollTop, `${props.surface} code position`).toBeGreaterThan(0);
	expect(
		Math.abs(actual.codeScrollTop - props.expected.codeScrollTop),
		`${props.surface} code pixel position ${JSON.stringify({ actual, expected: props.expected })}`,
	).toBeLessThanOrEqual(1);
	expect(
		Math.abs(actual.treeScrollTop - props.expected.treeScrollTop),
		`${props.surface} tree pixel position ${JSON.stringify({ actual, expected: props.expected })}`,
	).toBeLessThanOrEqual(1);
}

export function advanceAnimationFrame(): Promise<void> {
	return actWait(
		() =>
			new Promise<void>((resolve): void => {
				requestAnimationFrame((): void => resolve());
			}),
	);
}

function treeScrollOwnerWithinHost(host: HTMLElement): HTMLElement | null {
	const treeContainer = host.querySelector('file-tree-container');
	const scrollOwner = treeContainer?.shadowRoot?.querySelector(
		'[data-file-tree-virtualized-scroll="true"]',
	);
	return scrollOwner instanceof HTMLElement ? scrollOwner : null;
}

function setUserScrollPosition(scrollOwner: HTMLElement, progress: number): void {
	const maximumScrollTop = scrollOwner.scrollHeight - scrollOwner.clientHeight;
	const nextScrollTop = Math.max(1, Math.floor(maximumScrollTop * progress));
	scrollOwner.dispatchEvent(
		new WheelEvent('wheel', { bubbles: true, deltaY: nextScrollTop, view: window }),
	);
	scrollOwner.scrollTop = nextScrollTop;
	scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
}

async function waitForStableNonzeroScrollPosition(
	scrollOwner: HTMLElement,
	remainingFrames = 60,
	previousScrollTop: number | null = null,
): Promise<void> {
	const currentScrollTop = scrollOwner.scrollTop;
	if (currentScrollTop > 0 && previousScrollTop === currentScrollTop) return;
	if (remainingFrames <= 0) {
		throw new Error(`Expected a stable nonzero scroll position; observed ${currentScrollTop}.`);
	}
	await advanceAnimationFrame();
	await waitForStableNonzeroScrollPosition(scrollOwner, remainingFrames - 1, currentScrollTop);
}

function surfacePositionSnapshot(owners: SurfacePositionOwners): SurfacePositionSnapshot {
	return {
		codeScrollTop: owners.codeScrollOwner.scrollTop,
		treeScrollTop: owners.treeScrollOwner.scrollTop,
	};
}

function installFilePositionFixture(renderStore: BridgeMainRenderSnapshotStore): void {
	const fileContents = makeFileContents();
	renderStore.applyFileDisplayPatchEvent(makeFileDisplayEvent(fileContents));
	renderStore.setWorkerCodeViewItem({
		item: makeFileCodeViewItem(fileContents),
		itemId: bridgePanePositionFileItemId,
	});
	renderStore.applyWorkerPatch({
		itemId: bridgePanePositionFileItemId,
		operation: 'upsert',
		payload: { contentCacheKey: 'position-file-cache' },
		slice: 'rowPaint',
	});
	renderStore.applyWorkerPatch({
		itemId: bridgePanePositionFileItemId,
		operation: 'upsert',
		payload: { state: 'ready' },
		slice: 'contentAvailability',
	});
}

function installReviewPositionFixture(renderStore: BridgeMainRenderSnapshotStore): void {
	const reviewFiles = makeReviewFiles();
	renderStore.applyReviewDisplayPatchEvent(makeReviewDisplayEvent(reviewFiles));
	for (const [fileIndex, reviewFile] of reviewFiles.entries()) {
		renderStore.setWorkerCodeViewItem({
			item: makeReviewCodeViewItem(reviewFile, fileIndex),
			itemId: reviewFile.itemId,
		});
		renderStore.applyWorkerPatch({
			itemId: reviewFile.itemId,
			operation: 'upsert',
			payload: { contentCacheKey: `position-review-cache-${reviewFile.itemId}` },
			slice: 'rowPaint',
		});
		renderStore.applyWorkerPatch({
			itemId: reviewFile.itemId,
			operation: 'upsert',
			payload: { state: 'ready' },
			slice: 'contentAvailability',
		});
	}
	renderStore.setLocalSelection({
		selectedItemId: bridgePanePositionReviewItemId,
		source: 'programmatic',
	});
}

function makeFileDisplayEvent(fileContents: string): BridgeWorkerFileDisplayPatchEvent {
	const payloadByteCount = new TextEncoder().encode(fileContents).byteLength;
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'fileDisplayPatch',
		patches: [
			{
				operation: 'reset',
				payload: { sourceGeneration: 1, sourceId: 'position-file-source' },
				slice: 'fileTree',
			},
			{
				operation: 'batch',
				payload: {
					operations: Array.from({ length: fileTreeRowCount }, (_, rowIndex) => {
						const ordinal = String(rowIndex + 1).padStart(3, '0');
						return {
							operation: 'upsert' as const,
							row: {
								changeStatus: rowIndex % 3 === 0 ? ('modified' as const) : null,
								depth: 1,
								fileId: `position-file-${ordinal}`,
								fileClass: 'source' as const,
								isDirectory: false,
								lineCount: rowIndex === 0 ? fileLineCount : 12,
								name: `PositionFile${ordinal}.swift`,
								parentPath: 'Sources',
								path: `Sources/PositionFile${ordinal}.swift`,
								projectionIndex: rowIndex,
								rowId: `position-row-${ordinal}`,
								sizeBytes: rowIndex === 0 ? payloadByteCount : 256,
							},
						};
					}),
				},
				slice: 'fileTree',
			},
			{
				itemId: bridgePanePositionFileItemId,
				operation: 'upsert',
				payload: {
					availability: { kind: 'available' },
					displayPath: bridgePanePositionFilePath,
					endsMidLine: false,
					endsWithNewline: false,
					extent: { kind: 'exactLineCount', lineCount: fileLineCount },
					fileExtension: 'swift',
					language: 'swift',
					payloadByteCount,
					payloadLineCount: fileLineCount,
					rowId: 'position-row-001',
					sizeBytes: payloadByteCount,
					totalLineCount: fileLineCount,
					truncationKind: 'none',
				},
				slice: 'fileItem',
			},
			{
				operation: 'upsert',
				payload: {
					ahead: 0,
					behind: 0,
					branchName: 'position-retention',
					staged: 0,
					state: 'ready',
					unstaged: 1,
					untracked: 0,
				},
				slice: 'fileStatus',
			},
		],
		projectionRevision: 1,
		sequence: 1,
		surface: 'fileView',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function makeFileCodeViewItem(fileContents: string): BridgeWorkerCodeViewFileItem {
	return {
		bridgeMetadata: {
			cacheKey: 'position-file-cache',
			contentRoles: ['file'],
			contentState: 'hydrated',
			displayPath: bridgePanePositionFilePath,
			itemId: bridgePanePositionFileItemId,
			lineCount: fileLineCount,
		},
		file: {
			cacheKey: 'position-file-cache',
			contents: fileContents,
			lang: 'swift',
			name: bridgePanePositionFilePath,
		},
		id: bridgePanePositionFileItemId,
		type: 'file',
		version: 1,
	};
}

interface ReviewPositionFile {
	readonly itemId: string;
	readonly path: string;
}

function makeReviewFiles(): readonly ReviewPositionFile[] {
	return Array.from({ length: reviewFileCount }, (_, fileIndex): ReviewPositionFile => {
		const ordinal = String(fileIndex + 1).padStart(3, '0');
		const groupOrdinal = String(Math.floor(fileIndex / 4) + 1).padStart(2, '0');
		return {
			itemId: `position-review-${ordinal}`,
			path: `Sources/PositionGroup${groupOrdinal}/PositionReview${ordinal}.swift`,
		};
	});
}

function makeReviewDisplayEvent(
	reviewFiles: readonly ReviewPositionFile[],
): BridgeWorkerReviewDisplayPatchEvent {
	const treeRows = reviewWitnessTreeRows(reviewFiles);
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'reviewDisplayPatch',
		patches: [
			{
				operation: 'upsert',
				payload: {
					metadataSourceId: 'position-review-source',
					metadataWindowIdentity: reviewMetadataWindowIdentity,
					packageId: 'position-review-package',
					reviewGeneration: 1,
					status: 'ready',
					summary: {
						additions: reviewFileCount,
						deletions: reviewFileCount,
						filesChanged: reviewFileCount,
						hiddenFileCount: 0,
						visibleFileCount: reviewFileCount,
					},
					totalItemCount: reviewFiles.length,
					totalTreeRowCount: treeRows.length,
				},
				slice: 'reviewSource',
			},
			{
				operation: 'batch',
				payload: {
					items: reviewFiles.map(makeReviewDisplayItem),
					operations: [],
					reset: true,
					startIndex: 0,
				},
				slice: 'reviewItem',
			},
			{
				operation: 'batch',
				payload: { reset: true, windows: [{ rows: treeRows, startIndex: 0 }] },
				slice: 'reviewTree',
			},
		],
		projectionRevision: 1,
		sequence: 1,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function makeReviewDisplayItem(reviewFile: ReviewPositionFile): BridgeWorkerReviewDisplayItem {
	const semanticDocumentRevision = `position-review-semantic:${reviewFile.itemId}`;
	return {
		contentFacts: [
			{
				contentDigest: {
					algorithm: 'position-fixture',
					authority: 'provisional',
					value: `base:${reviewFile.itemId}`,
				},
				role: 'base',
				semanticDocumentRevision,
			},
			{
				contentDigest: {
					algorithm: 'position-fixture',
					authority: 'provisional',
					value: `head:${reviewFile.itemId}`,
				},
				role: 'head',
				semanticDocumentRevision,
			},
		],
		extentFacts: [
			{ contentRole: 'base', itemId: reviewFile.itemId, lineCount: reviewLineCount },
			{ contentRole: 'head', itemId: reviewFile.itemId, lineCount: reviewLineCount },
		],
		metadata: {
			basePath: reviewFile.path,
			changeKind: 'modified',
			contentDescriptorIdsByRole: {},
			contentHashesByRole: {},
			contentRoles: ['base', 'head'],
			extension: 'swift',
			fileClass: 'source',
			headPath: reviewFile.path,
			isHiddenByDefault: false,
			itemId: reviewFile.itemId,
			language: 'swift',
			mimeTypes: ['text/x-swift'],
			provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
			reviewPriority: 'normal',
			reviewState: 'unreviewed',
		},
		metadataWindowIdentity: reviewMetadataWindowIdentity,
	};
}

function makeReviewCodeViewItem(
	reviewFile: ReviewPositionFile,
	fileIndex: number,
): BridgeWorkerCodeViewDiffItem {
	const baseContents = makeReviewContents(reviewFile, fileIndex, 'base');
	const headContents = makeReviewContents(reviewFile, fileIndex, 'head');
	return {
		bridgeMetadata: {
			cacheKey: `position-review-cache-${reviewFile.itemId}`,
			contentRoles: ['base', 'head'],
			contentState: 'hydrated',
			displayPath: reviewFile.path,
			itemId: reviewFile.itemId,
			lineCount: reviewLineCount * 2,
		},
		fileDiff: parseBridgeCodeViewDiffForBrowserTest(
			{ contents: baseContents, name: reviewFile.path },
			{ contents: headContents, name: reviewFile.path },
		),
		id: reviewFile.itemId,
		type: 'diff',
		version: 1,
	};
}

function makeFileContents(): string {
	return Array.from(
		{ length: fileLineCount },
		(_, lineIndex): string =>
			`let retainedFilePosition${String(lineIndex + 1).padStart(3, '0')} = ${lineIndex + 1}`,
	).join('\n');
}

function makeReviewContents(
	reviewFile: ReviewPositionFile,
	fileIndex: number,
	role: 'base' | 'head',
): string {
	return Array.from(
		{ length: reviewLineCount },
		(_, lineIndex): string =>
			`let retainedReviewPosition${String(lineIndex + 1).padStart(2, '0')} = "${role}-${reviewFile.itemId}-${fileIndex}"`,
	).join('\n');
}
