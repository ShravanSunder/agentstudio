import type { BridgeViewerNavigationCommand } from '../app/bridge-viewer-navigation-models.js';
import type { BridgeProductFileSourceIdentity } from '../core/comm-worker/bridge-product-file-contracts.js';
import {
	bridgeProductFileMetadataEventSchema,
	type BridgeProductSubscriptionEvent,
	type BridgeProductSubscriptionUpdateOptions,
} from '../core/comm-worker/bridge-product-subscription-contracts.js';

export type FileMetadataEvent = BridgeProductSubscriptionEvent<'file.metadata'>;
export type PublishFileMetadataEvents = (events: readonly FileMetadataEvent[]) => void;
export type FileMetadataInterestUpdate = BridgeProductSubscriptionUpdateOptions<'file.metadata'>;
export type FileDescriptorReadyEvent = Extract<
	FileMetadataEvent,
	{ readonly eventKind: 'file.descriptorReady' }
>;
export type FileTreeRow = Extract<
	FileMetadataEvent,
	{ readonly eventKind: 'file.treeWindow' }
>['rows'][number];

const startupWindowMetadataLineage = {
	loadedBy: 'startup_window',
	lane: 'foreground',
} as const;

const idleMetadataLineage = {
	loadedBy: 'idle',
	lane: 'idle',
} as const;

export function makeFileMetadataEvents(
	...descriptors: readonly FileDescriptorReadyEvent[]
): readonly FileMetadataEvent[] {
	const source = descriptors[0]?.source ?? makeSourceIdentity();
	return [
		makeSourceAcceptedMetadataEvent(source),
		parseFileMetadataEvent({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: startupWindowMetadataLineage,
			pathScope: [],
			rows: descriptors.map(makeTreeRowFromDescriptor),
			source,
			startIndex: 0,
			totalRowCount: descriptors.length,
		}),
		...descriptors.map((descriptor): FileMetadataEvent => descriptor),
	];
}

export function makeTreeRowFromDescriptor(descriptor: FileDescriptorReadyEvent): FileTreeRow {
	const pathParts = descriptor.path.split('/');
	const name = pathParts.at(-1) ?? descriptor.path;
	return makeTreeRow({
		changeStatus: null,
		depth: Math.max(pathParts.length - 1, 0),
		fileId: descriptor.fileId,
		isDirectory: false,
		lineCount: descriptor.totalLineCount,
		name,
		parentPath: pathParts.length > 1 ? pathParts.slice(0, -1).join('/') : null,
		path: descriptor.path,
		sizeBytes: descriptor.sizeBytes,
	});
}

export function makeTreeRowsOnlyMetadataEvents(): readonly FileMetadataEvent[] {
	const source = makeSourceIdentity();
	return [
		makeSourceAcceptedMetadataEvent(source),
		parseFileMetadataEvent({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: startupWindowMetadataLineage,
			pathScope: [],
			rows: [
				makeTreeRow({
					depth: 0,
					isDirectory: true,
					name: 'Sources',
					parentPath: null,
					path: 'Sources',
				}),
				makeTreeRow({
					depth: 1,
					isDirectory: true,
					name: 'AgentStudio',
					parentPath: 'Sources',
					path: 'Sources/AgentStudio',
				}),
				makeTreeRow({
					depth: 2,
					isDirectory: true,
					name: 'App',
					parentPath: 'Sources/AgentStudio',
					path: 'Sources/AgentStudio/App',
				}),
				makeTreeRow({
					depth: 3,
					fileId: 'file-app-delegate',
					isDirectory: false,
					lineCount: 42,
					name: 'AppDelegate.swift',
					parentPath: 'Sources/AgentStudio/App',
					path: 'Sources/AgentStudio/App/AppDelegate.swift',
				}),
				makeTreeRow({
					depth: 2,
					isDirectory: true,
					name: 'Features',
					parentPath: 'Sources/AgentStudio',
					path: 'Sources/AgentStudio/Features',
				}),
				makeTreeRow({
					depth: 3,
					isDirectory: true,
					name: 'Bridge',
					parentPath: 'Sources/AgentStudio/Features',
					path: 'Sources/AgentStudio/Features/Bridge',
				}),
			],
			source,
			startIndex: 0,
			totalRowCount: 6,
		}),
	];
}

export function makeTreeWindowedMetadataEvents(props: {
	readonly rowCount: number;
	readonly totalPathCount: number;
}): readonly FileMetadataEvent[] {
	const source = makeSourceIdentity();
	return [
		makeSourceAcceptedMetadataEvent(source),
		makeTreeWindowMetadataEvent({
			rowCount: props.rowCount,
			startIndex: 0,
			totalPathCount: props.totalPathCount,
		}),
	];
}

export function makeTreeWindowMetadataEvent(props: {
	readonly rowCount: number;
	readonly sequence?: number;
	readonly startIndex: number;
	readonly totalPathCount: number;
	readonly sourceIdentity?: BridgeProductFileSourceIdentity;
}): FileMetadataEvent {
	return parseFileMetadataEvent({
		eventKind: 'file.treeWindow',
		finalWindow: props.startIndex + props.rowCount >= props.totalPathCount,
		lineage: props.startIndex === 0 ? startupWindowMetadataLineage : idleMetadataLineage,
		pathScope: [],
		rows: makeFlatFileTreeRows({ count: props.rowCount, startIndex: props.startIndex }),
		source: props.sourceIdentity ?? makeSourceIdentity(),
		startIndex: props.startIndex,
		totalRowCount: props.totalPathCount,
	});
}

export function makeFlatFileTreeRows(props: {
	readonly count: number;
	readonly startIndex: number;
}): readonly FileTreeRow[] {
	return Array.from({ length: props.count }, (_value, index): FileTreeRow => {
		const fileIndex = props.startIndex + index;
		const fileName = `File-${fileIndex.toString().padStart(3, '0')}.swift`;
		return makeTreeRow({
			depth: 0,
			fileId: `file-${fileIndex.toString().padStart(3, '0')}`,
			isDirectory: false,
			name: fileName,
			parentPath: null,
			path: fileName,
			sizeBytes: 24,
		});
	});
}

export function makeDescriptorReadyMetadataEvents(
	descriptor: FileDescriptorReadyEvent,
	_props?: { readonly generation?: number; readonly sequence?: number },
): readonly FileMetadataEvent[] {
	return [descriptor];
}

export function makeSourceAcceptedMetadataEvent(
	sourceIdentity: BridgeProductFileSourceIdentity,
): FileMetadataEvent {
	return parseFileMetadataEvent({ eventKind: 'file.sourceAccepted', source: sourceIdentity });
}

export function makeSourceSnapshotMetadataEvents(props: {
	readonly sequence?: number;
	readonly sourceIdentity: BridgeProductFileSourceIdentity;
}): readonly FileMetadataEvent[] {
	return [
		makeSourceAcceptedMetadataEvent(props.sourceIdentity),
		parseFileMetadataEvent({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'foreground', loadedBy: 'replacement' },
			pathScope: [],
			rows: [
				makeTreeRow({
					depth: 0,
					fileId: 'file-source-less-reset-target',
					isDirectory: false,
					name: 'source-less-reset-target.ts',
					parentPath: 'src',
					path: 'src/source-less-reset-target.ts',
					sizeBytes: 64,
				}),
			],
			source: props.sourceIdentity,
			startIndex: 0,
			totalRowCount: 1,
		}),
	];
}

export function makeSourceResetMetadataEvents(): readonly FileMetadataEvent[] {
	return makeFileInvalidatedMetadataEvents({
		fileId: 'file-source-less-reset-target',
		path: 'src/source-less-reset-target.ts',
	});
}

export function makeSourceReplacementMetadataEvents(
	...replacementDescriptors: readonly FileDescriptorReadyEvent[]
): readonly FileMetadataEvent[] {
	const source =
		replacementDescriptors[0]?.source ??
		makeSourceIdentity({
			sourceCursor: 'cursor-2',
			subscriptionGeneration: 2,
		});
	return [
		makeSourceAcceptedMetadataEvent(source),
		parseFileMetadataEvent({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'foreground', loadedBy: 'replacement' },
			pathScope: [],
			rows: replacementDescriptors.map(makeTreeRowFromDescriptor),
			source,
			startIndex: 0,
			totalRowCount: replacementDescriptors.length,
		}),
		...replacementDescriptors,
	];
}

export function makeFileInvalidatedMetadataEvents(props: {
	readonly fileId: string;
	readonly path: string;
	readonly sequence?: number;
	readonly sourceIdentity?: BridgeProductFileSourceIdentity;
}): readonly FileMetadataEvent[] {
	return [
		parseFileMetadataEvent({
			eventKind: 'file.invalidated',
			fileId: props.fileId,
			path: props.path,
			reason: 'contentChanged',
			replacementDescriptor: null,
			source: props.sourceIdentity ?? makeSourceIdentity(),
		}),
	];
}

export function makeTreeRow(props: {
	readonly changeStatus?: FileTreeRow['changeStatus'];
	readonly depth: number;
	readonly fileId?: string;
	readonly isDirectory: boolean;
	readonly lineCount?: number | null;
	readonly name: string;
	readonly parentPath: string | null;
	readonly path: string;
	readonly sizeBytes?: number | null;
}): FileTreeRow {
	return {
		changeStatus: props.changeStatus ?? null,
		depth: props.depth,
		fileId: props.fileId ?? null,
		isDirectory: props.isDirectory,
		lineCount: props.lineCount ?? null,
		name: props.name,
		parentPath: props.parentPath,
		path: props.path,
		rowId: fileTreeRowId(props.path),
		sizeBytes: props.sizeBytes ?? null,
	};
}

export interface MakeFileDescriptorProps {
	readonly contentExpectedBytes?: number;
	readonly contentHandle?: string;
	readonly contentMaxBytes?: number;
	readonly fileId?: string;
	readonly generation?: number;
	readonly isBinary?: boolean;
	readonly lineCount?: number;
	readonly path: string;
	readonly sourceIdentity?: BridgeProductFileSourceIdentity;
	readonly virtualizedExtentKind?: FileDescriptorReadyEvent['virtualizedExtentKind'];
}

export function makeFileDescriptor(props: MakeFileDescriptorProps): FileDescriptorReadyEvent {
	const descriptorId = props.contentHandle ?? 'file-content-1';
	const source =
		props.sourceIdentity ??
		makeSourceIdentity(
			props.generation === undefined ? {} : { subscriptionGeneration: props.generation },
		);
	const fileId = props.fileId ?? 'file-1';
	const maximumBytes = props.contentMaxBytes ?? DEFAULT_FILE_TEST_CONTENT_MAX_BYTES;
	const payloadLineCount = props.lineCount ?? 2;
	const isUnavailable = props.isBinary === true || props.virtualizedExtentKind === 'unavailable';
	const virtualizedExtentKind = isUnavailable
		? 'unavailable'
		: (props.virtualizedExtentKind ?? 'exactLineCount');
	const payloadByteCount = isUnavailable
		? 0
		: Math.min(props.contentExpectedBytes ?? 64, maximumBytes);
	const emittedPayloadLineCount = isUnavailable ? 0 : payloadLineCount;
	const contentDescriptor = {
		contentKind: 'file.content',
		declaredByteLength: props.contentExpectedBytes ?? 64,
		descriptorId,
		encoding: 'utf-8',
		expectedSha256: testSha256ForDescriptor(descriptorId),
		fileId,
		maximumBytes,
		source,
		window: {
			kind: 'prefix',
			maximumBytes,
			maximumLines: 10_000,
			startByte: 0,
		},
	} as const;
	const parsedDescriptor = parseFileMetadataEvent({
		availability: props.isBinary
			? { availabilityKind: 'binary' }
			: virtualizedExtentKind === 'unavailable'
				? { availabilityKind: 'unavailable', reason: 'outside_scope' }
				: { availabilityKind: 'available', contentDescriptor },
		encoding: isUnavailable ? null : 'utf-8',
		endsMidLine: false,
		endsWithNewline: !isUnavailable,
		estimatedContentHeightPixels: null,
		eventKind: 'file.descriptorReady',
		fileExtension: 'ts',
		fileId,
		language: 'typescript',
		modifiedAtUnixMilliseconds: null,
		path: props.path,
		payloadByteCount,
		payloadLineCount: emittedPayloadLineCount,
		rowId: fileTreeRowId(props.path),
		sizeBytes: Math.max(props.contentExpectedBytes ?? 64, 64),
		source,
		totalLineCount: virtualizedExtentKind === 'exactLineCount' ? payloadLineCount : null,
		truncationKind: 'none',
		virtualizedExtentKind,
	});
	if (parsedDescriptor.eventKind !== 'file.descriptorReady') {
		throw new Error('Browser File descriptor fixture parsed to the wrong event kind.');
	}
	return parsedDescriptor;
}

export function makeSourceIdentity(
	props: {
		readonly sourceCursor?: string;
		readonly subscriptionGeneration?: number;
	} = {},
): BridgeProductFileSourceIdentity {
	return {
		repoId: '00000000-0000-4000-8000-000000000001',
		rootRevisionToken: 'root-revision-1',
		sourceCursor: props.sourceCursor ?? 'cursor-1',
		sourceId: 'dev-worktree-source',
		subscriptionGeneration: props.subscriptionGeneration ?? 1,
		worktreeId: '00000000-0000-4000-8000-000000000002',
	};
}

export function parseFileMetadataEvent(event: unknown): FileMetadataEvent {
	return bridgeProductFileMetadataEventSchema.parse(event);
}

export function makeFileContent(content: string): string {
	return content;
}

export function fileTreeRowId(path: string): string {
	return `row:${path.replaceAll('/', ':').replaceAll(' ', '_')}`;
}

export function fileNavigationCommandForPath(path: string): BridgeViewerNavigationCommand {
	return {
		commandId: `test:file:${path}`,
		commandKind: 'initialize',
		context: 'files',
		restoreMemory: true,
		source: { sourceKind: 'worktree', sourceId: 'source-1' },
		target: {
			targetKind: 'file',
			fileRef: { sourceId: 'source-1', path },
			version: 'current',
		},
	};
}

function testSha256ForDescriptor(descriptorId: string): string {
	return Array.from(new TextEncoder().encode(descriptorId)).reduce((hash, byte, index): string => {
		const offset = (index * 2) % 64;
		return `${hash.slice(0, offset)}${byte.toString(16).padStart(2, '0')}${hash.slice(offset + 2)}`;
	}, '0'.repeat(64));
}

const DEFAULT_FILE_TEST_CONTENT_MAX_BYTES = 2 * 1024 * 1024;
