import { expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

import { BridgeFileViewerBrowserHarnessApp as BridgeFileViewerApp } from './bridge-file-viewer-browser-test-app.js';
import type { FileMetadataInterestUpdate } from './bridge-file-viewer-browser-test-fixtures.js';
import {
	fileNavigationCommandForPath,
	makeFileContent,
	makeFileDescriptorForContent,
	makeFileMetadataEvents,
	makeSourceIdentity,
	makeSourceResetMetadataEvents,
	makeSourceSnapshotMetadataEvents,
	type PublishFileMetadataEvents,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actFrame,
	actUpdate,
	metadataInterestPathsForLane,
	requireMetadataPublisher,
	waitForOpenFileState,
	waitForVisibleCodeText,
} from './bridge-file-viewer-browser-test-harness.js';

export function registerBridgeFileViewerSourceSnapshotDemandTest(): void {
	test('requests a replacement descriptor after source reset snapshot metadata arrives without descriptors', async () => {
		const initialContent = makeFileContent('export const sourceSnapshotDemandInitial = true;\n');
		const initialDescriptor = await makeFileDescriptorForContent({
			content: initialContent,
			contentHandle: 'source-snapshot-demand-content-1',
			fileId: 'file-source-less-reset-target',
			path: 'src/source-less-reset-target.ts',
		});
		const resetSourceIdentity = makeSourceIdentity({
			subscriptionGeneration: 2,
			sourceCursor: 'cursor-2',
		});
		const metadataInterestUpdates: FileMetadataInterestUpdate[] = [];
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;

		await render(
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeFileMetadataEvents(initialDescriptor)}
				navigationCommand={fileNavigationCommandForPath('src/source-less-reset-target.ts')}
				fileProductSession={{
					readContent: async () => initialContent,
					onMetadataInterestUpdate: (request) => {
						metadataInterestUpdates.push(request);
					},
					onMetadataSubscription: (handler): (() => void) => {
						publishMetadataEvents = handler;
						return (): void => {
							publishMetadataEvents = null;
						};
					},
				}}
			/>,
		);

		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('sourceSnapshotDemandInitial');
		const interestUpdateCountBeforeReset = metadataInterestUpdates.length;
		const publishRequiredMetadataEvents = requireMetadataPublisher(publishMetadataEvents);
		await actUpdate((): void => {
			publishRequiredMetadataEvents(makeSourceResetMetadataEvents());
		});
		await waitForOpenFileState('loading');
		expect(metadataInterestUpdates).toHaveLength(interestUpdateCountBeforeReset);

		await actUpdate((): void => {
			publishRequiredMetadataEvents(
				makeSourceSnapshotMetadataEvents({ sequence: 1, sourceIdentity: resetSourceIdentity }),
			);
		});

		await actFrame();
		await actFrame();
		const finalInterestUpdate = metadataInterestUpdates.at(-1);
		if (finalInterestUpdate === undefined)
			throw new Error('Expected final File metadata interest.');
		expect(metadataInterestPathsForLane(finalInterestUpdate, 'foreground')).toEqual([
			'src/source-less-reset-target.ts',
		]);
		expect(finalInterestUpdate?.pathScope).toEqual([]);
	});
}
