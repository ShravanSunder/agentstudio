import { describe, expect, test } from 'vitest';

import { answerBridgeWorkerFileCollectionSearch } from './bridge-comm-worker-file-collection-search-command.js';
import { BridgeCommWorkerFileQueryProjection } from './bridge-comm-worker-file-query-projection.js';
import type {
	BridgeWorkerFileDisplayPatch,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type {
	BridgeFileCollectionSearchOutcome,
	BridgeFileCollectionSearchWireCriteria,
	BridgeWorkerFileCollectionSearchCommand,
} from './bridge-worker-file-collection-search-contracts.js';

const frontendWorktreeId = '0198f3a2-0000-7000-8000-00000000000a';
const backendWorktreeId = '0198f3a2-0000-7000-8000-00000000000b';
const collectionSource = { sourceGeneration: 4, sourceId: 'collection-source-4' };

describe('Bridge comm worker File collection search', () => {
	test('searches every member and opened document without changing the published query', () => {
		// Arrange
		const projection = makeProjection();
		projection.applyDisplayPatches(collectionDisplayPatches({ committed: true }));
		projection.updateQuery({
			publish: (): void => {},
			publishOutcome: (): void => {},
			query: { filterMode: 'all', searchMode: 'text', searchText: 'backend' },
			requestId: 'viewer-query',
		});
		const publishedBefore = projection.snapshotDisplayPatches();

		// Act
		const outcome = searchOutcome(projection, criteria({ searchText: 'app.ts' }));

		// Assert
		expect(outcome).toEqual({
			complete: true,
			kind: 'matches',
			matches: [
				{
					displayPath: 'frontend/src/app.ts',
					documentLocation: null,
					fileId: 'file-frontend-app',
					memberWorktreeId: frontendWorktreeId,
				},
				{
					displayPath: 'backend/src/app.ts',
					documentLocation: null,
					fileId: 'file-backend-app',
					memberWorktreeId: backendWorktreeId,
				},
			],
			membershipRevision: 2,
			source: collectionSource,
			totalMatchCount: 2,
			truncated: false,
		});
		expect(projection.snapshotDisplayPatches()).toEqual(publishedBefore);
	});

	test('names an opened loose document by its real location', () => {
		// Arrange
		const projection = makeProjection();
		projection.applyDisplayPatches(collectionDisplayPatches({ committed: true }));

		// Act
		const outcome = searchOutcome(
			projection,
			criteria({ scope: { kind: 'openedDocuments' }, searchText: '' }),
		);

		// Assert
		expect(outcome).toMatchObject({
			kind: 'matches',
			matches: [
				{
					displayPath: 'Open Files/notes.md',
					documentLocation: '/private/tmp/notes.md',
					memberWorktreeId: null,
				},
			],
		});
	});

	test('an uncommitted source answers incomplete so an empty result is not proof of absence', () => {
		// Arrange
		const projection = makeProjection();
		projection.applyDisplayPatches(collectionDisplayPatches({ committed: false }));

		// Act
		const outcome = searchOutcome(projection, criteria({ searchText: 'missing.ts' }));

		// Assert
		expect(outcome).toMatchObject({ complete: false, kind: 'matches', totalMatchCount: 0 });
	});

	test('without a File source the worker answers noSource', () => {
		// Act
		const outcome = searchOutcome(makeProjection(), criteria({ searchText: 'app' }));

		// Assert
		expect(outcome).toEqual({ kind: 'noSource' });
	});

	test('answers the request id and acknowledges the command', () => {
		// Arrange
		const projection = makeProjection();
		projection.applyDisplayPatches(collectionDisplayPatches({ committed: true }));

		// Act
		const messages = answerBridgeWorkerFileCollectionSearch({
			command: searchCommand(criteria({ searchMode: 'regex', searchText: '(' })),
			projection,
		});

		// Assert
		expect(messages).toEqual([
			expect.objectContaining({
				kind: 'fileCollectionSearch',
				outcome: { kind: 'invalidPattern', searchError: 'Invalid regex' },
				requestId: 'native-search-1',
			}),
			expect.objectContaining({ kind: 'health', requestId: 'native-search-1', status: 'ready' }),
		]);
	});
});

function makeProjection(): BridgeCommWorkerFileQueryProjection {
	return new BridgeCommWorkerFileQueryProjection({
		maximumRowsPerQueryChunk: 128,
		recordEvaluatedQueryChunk: (): void => {},
		scheduleQueryChunk: (runChunk): void => {
			runChunk();
		},
	});
}

function criteria(
	overrides: Partial<BridgeFileCollectionSearchWireCriteria> = {},
): BridgeFileCollectionSearchWireCriteria {
	return { limit: 50, scope: { kind: 'all' }, searchMode: 'text', searchText: '', ...overrides };
}

function searchCommand(
	searchCriteria: BridgeFileCollectionSearchWireCriteria,
): BridgeWorkerFileCollectionSearchCommand {
	return {
		command: 'fileCollectionSearch',
		criteria: searchCriteria,
		direction: 'mainToServerWorker',
		epoch: 0,
		kind: 'command',
		requestId: 'native-search-1',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function searchOutcome(
	projection: BridgeCommWorkerFileQueryProjection,
	searchCriteria: BridgeFileCollectionSearchWireCriteria,
): BridgeFileCollectionSearchOutcome {
	const answer = answerBridgeWorkerFileCollectionSearch({
		command: searchCommand(searchCriteria),
		projection,
	}).find(
		(
			message,
		): message is Extract<BridgeWorkerServerToMainMessage, { kind: 'fileCollectionSearch' }> =>
			message.kind === 'fileCollectionSearch',
	);
	if (answer === undefined) throw new Error('Expected a File collection search answer.');
	return answer.outcome;
}

type FileTreeOperation = Extract<
	BridgeWorkerFileDisplayPatch,
	{ readonly operation: 'batch'; readonly slice: 'fileTree' }
>['payload']['operations'][number];

function fileRow(
	rowId: string,
	fileId: string | null,
	path: string,
	projectionIndex: number,
	documentLocation: string | null = null,
): FileTreeOperation {
	const pathSegments = path.split('/');
	const isDirectory = fileId === null;
	return {
		operation: 'upsert',
		row: {
			changeStatus: null,
			depth: pathSegments.length - 1,
			documentLocation,
			fileClass: isDirectory ? null : 'source',
			fileId,
			isDirectory,
			lineCount: null,
			name: pathSegments.at(-1) ?? path,
			parentPath: pathSegments.length === 1 ? null : pathSegments.slice(0, -1).join('/'),
			path,
			projectionIndex,
			rowId,
			sizeBytes: isDirectory ? null : 10,
		},
	};
}

function collectionDisplayPatches(props: {
	readonly committed: boolean;
}): readonly BridgeWorkerFileDisplayPatch[] {
	return [
		{ operation: 'reset', payload: collectionSource, slice: 'fileTree' },
		{
			operation: 'upsert',
			payload: {
				groups: [
					{
						groupPath: 'frontend',
						identityPrefix: 'm0000000000aa.',
						nestedMemberRelativeRoots: [],
						worktreeId: frontendWorktreeId,
					},
					{
						groupPath: 'backend',
						identityPrefix: 'm0000000000bb.',
						nestedMemberRelativeRoots: [],
						worktreeId: backendWorktreeId,
					},
				],
				membershipRevision: 2,
			},
			slice: 'fileMemberGroups',
		},
		{
			operation: 'batch',
			payload: {
				operations: [
					fileRow('row-frontend', null, 'frontend', 0),
					fileRow('row-frontend-src', null, 'frontend/src', 1),
					fileRow('row-frontend-app', 'file-frontend-app', 'frontend/src/app.ts', 2),
					fileRow('row-backend', null, 'backend', 3),
					fileRow('row-backend-src', null, 'backend/src', 4),
					fileRow('row-backend-app', 'file-backend-app', 'backend/src/app.ts', 5),
					fileRow('row-opened', null, 'Open Files', 6),
					fileRow(
						'row-opened-notes',
						'file-opened-notes',
						'Open Files/notes.md',
						7,
						'/private/tmp/notes.md',
					),
				],
			},
			slice: 'fileTree',
		},
		...(props.committed
			? [
					{
						operation: 'replacementCommit',
						payload: collectionSource,
						slice: 'fileTree',
					} satisfies BridgeWorkerFileDisplayPatch,
				]
			: []),
	];
}
