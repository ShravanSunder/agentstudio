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

export const bridgePanePositionFileItemId = 'position-file-001';
export const bridgePanePositionFilePath = 'Sources/PositionFile001.swift';
export const bridgePanePositionReviewItemId = 'position-review-001';

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
					metadataWindowIdentity: reviewMetadataWindowIdentity,
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
