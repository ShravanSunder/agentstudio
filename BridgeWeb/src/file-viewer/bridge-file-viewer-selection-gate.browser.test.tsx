import type { ReactElement } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import type { BridgeProductFileSelectionReceipt } from '../core/comm-worker/bridge-product-call-contracts.js';
import { waitForBridgeViewerTreeItemButton } from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { terminateBridgePierreWorkerPoolSingletonForTest } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';
import { useWorktreeAnnotationEditorInstallationPreparation } from '../worktree-annotations/worktree-annotation-surface-provider.js';
import { BridgeFileViewerBrowserHarnessApp } from './bridge-file-viewer-browser-test-app.js';
import {
	fileNavigationCommandForPath,
	makeFileContent,
	makeFileDescriptorForContent,
	makeFileMetadataEvents,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actClick,
	actFrame,
	actUpdate,
	interactAndWaitForBridgeFileViewerQueryCompletion,
	selectedDisplayPath,
	settleBridgeFileViewerBrowserInteraction,
	settleBridgeFileViewerBrowserUpdates,
	waitForOpenFileState,
	waitForSelectedDisplayPath,
	waitForVisibleCodeText,
} from './bridge-file-viewer-browser-test-harness.js';

interface EditorPreparationScript {
	calls: number;
	result: boolean;
	pendingSettle: (() => void) | null;
}

function ActiveEditorPreparation(props: {
	readonly script: EditorPreparationScript;
}): ReactElement | null {
	useWorktreeAnnotationEditorInstallationPreparation(
		'annotation-edit-open-draft',
		(): Promise<boolean> =>
			new Promise<boolean>((resolve): void => {
				props.script.calls += 1;
				props.script.pendingSettle = (): void => resolve(props.script.result);
			}),
	);
	return null;
}

/** Resolves when a receipt matching `predicate` reaches native; no polling. */
function receiptRecorder(): {
	readonly receipts: BridgeProductFileSelectionReceipt[];
	readonly record: (receipt: BridgeProductFileSelectionReceipt) => void;
	readonly next: (
		predicate: (receipt: BridgeProductFileSelectionReceipt) => boolean,
	) => Promise<BridgeProductFileSelectionReceipt>;
} {
	const receipts: BridgeProductFileSelectionReceipt[] = [];
	const waiters: {
		readonly predicate: (receipt: BridgeProductFileSelectionReceipt) => boolean;
		readonly resolve: (receipt: BridgeProductFileSelectionReceipt) => void;
	}[] = [];
	return {
		next: (predicate): Promise<BridgeProductFileSelectionReceipt> => {
			const recorded = receipts.find(predicate);
			if (recorded !== undefined) return Promise.resolve(recorded);
			return new Promise((resolve): void => {
				waiters.push({ predicate, resolve });
			});
		},
		receipts,
		record: (receipt): void => {
			receipts.push(receipt);
			for (const waiter of waiters.filter((candidate) => candidate.predicate(receipt))) {
				waiters.splice(waiters.indexOf(waiter), 1);
				waiter.resolve(receipt);
			}
		},
	};
}

async function settleEditorPreparation(script: EditorPreparationScript): Promise<void> {
	await actUpdate(async (): Promise<void> => {
		const settle = script.pendingSettle;
		if (settle === null) throw new Error('Expected the viewer to prepare the active editor.');
		script.pendingSettle = null;
		settle();
		await Promise.resolve();
	});
	await actFrame();
}

describe('Bridge File selection editor gate', () => {
	afterEach(async () => {
		await actUpdate(async (): Promise<void> => {
			await cleanup();
		});
		await settleBridgeFileViewerBrowserUpdates();
		await actFrame();
		document.body.replaceChildren();
		terminateBridgePierreWorkerPoolSingletonForTest();
	});

	test('keeps the displayed file while an active editor cannot be flushed, then follows once it can', async () => {
		// Arrange
		const displayedContent = makeFileContent('export const displayedWithDraft = true;\n');
		const nextContent = makeFileContent('export const nextSelection = true;\n');
		const displayedDescriptor = await makeFileDescriptorForContent({
			content: displayedContent,
			contentHandle: 'displayed-content',
			fileId: 'file-000',
			path: 'File-000.swift',
		});
		const nextDescriptor = await makeFileDescriptorForContent({
			content: nextContent,
			contentHandle: 'next-content',
			fileId: 'file-001',
			path: 'File-001.swift',
		});
		const script: EditorPreparationScript = { calls: 0, pendingSettle: null, result: false };
		const receipts: BridgeProductFileSelectionReceipt[] = [];
		await render(
			<BridgeFileViewerBrowserHarnessApp
				annotationSurfaceChildren={<ActiveEditorPreparation script={script} />}
				autoOpenInitialFile
				codeViewWorkerPoolEnabled={false}
				fileProductSession={{
					onFileSelectionReceipt: (receipt): void => {
						receipts.push(receipt);
					},
					readContent: async (props) =>
						props.descriptor.descriptorId.includes('next-content') ? nextContent : displayedContent,
				}}
				initialMetadataEvents={makeFileMetadataEvents(displayedDescriptor, nextDescriptor)}
			/>,
		);
		await waitForOpenFileState('ready');
		await waitForVisibleCodeText('displayedWithDraft');
		await settleBridgeFileViewerBrowserInteraction();
		expect(receipts.map((receipt) => [receipt.displayPath, receipt.outcome])).toEqual([
			['File-000.swift', 'displayed'],
		]);

		// Act: the draft flush is refused.
		await actClick(await waitForBridgeViewerTreeItemButton('File-001.swift'));
		await settleEditorPreparation(script);

		// Assert
		expect(script.calls).toBe(1);
		expect(selectedDisplayPath()).toBe('File-000.swift');
		await waitForVisibleCodeText('displayedWithDraft');
		await settleBridgeFileViewerBrowserInteraction();
		expect(receipts).toHaveLength(1);

		// Act: the draft flush is acknowledged.
		script.result = true;
		await actClick(await waitForBridgeViewerTreeItemButton('File-001.swift'));
		await settleEditorPreparation(script);

		// Assert
		expect(script.calls).toBe(2);
		await waitForSelectedDisplayPath('File-001.swift');
		await waitForVisibleCodeText('nextSelection');
		await settleBridgeFileViewerBrowserInteraction();
		expect(receipts.at(-1)).toMatchObject({
			displayPath: 'File-001.swift',
			nativeNavigationCommandId: null,
			outcome: 'displayed',
		});
	});

	test('a native navigation hidden by the search reveals every row and ends displayed', async () => {
		// Arrange
		const firstContent = makeFileContent('export const first = true;\n');
		const targetContent = makeFileContent('export const deepTarget = true;\n');
		const firstDescriptor = await makeFileDescriptorForContent({
			content: firstContent,
			contentHandle: 'first-content',
			fileId: 'file-first',
			path: 'src/first.ts',
		});
		const targetDescriptor = await makeFileDescriptorForContent({
			content: targetContent,
			contentHandle: 'target-content',
			fileId: 'file-target',
			path: 'packages/core/src/deep/target.ts',
		});
		const recorder = receiptRecorder();
		const session = {
			onFileSelectionReceipt: recorder.record,
			readContent: async (props: {
				readonly descriptor: { readonly descriptorId: string };
			}): Promise<string> =>
				props.descriptor.descriptorId.includes('target-content') ? targetContent : firstContent,
		};
		const rendered = await render(
			<BridgeFileViewerBrowserHarnessApp
				autoOpenInitialFile
				codeViewWorkerPoolEnabled={false}
				fileProductSession={session}
				initialMetadataEvents={makeFileMetadataEvents(firstDescriptor, targetDescriptor)}
			/>,
		);
		await waitForOpenFileState('ready');
		await interactAndWaitForBridgeFileViewerQueryCompletion((): void => {
			window.dispatchEvent(
				new CustomEvent('__bridge_review_control', {
					detail: {
						method: 'bridge.fileTree.search',
						searchMode: { kind: 'text' },
						searchText: 'first',
					},
				}),
			);
		});
		const command = fileNavigationCommandForPath('packages/core/src/deep/target.ts');
		const nativeReceipt = recorder.next(
			(candidate) => candidate.nativeNavigationCommandId === command.commandId,
		);

		// Act: the reveal clears the search, which settles as one more query.
		await interactAndWaitForBridgeFileViewerQueryCompletion(async (): Promise<void> => {
			await rendered.rerender(
				<BridgeFileViewerBrowserHarnessApp
					autoOpenInitialFile
					codeViewWorkerPoolEnabled={false}
					fileProductSession={session}
					initialMetadataEvents={makeFileMetadataEvents(firstDescriptor, targetDescriptor)}
					navigationCommand={command}
				/>,
			);
		});
		const receipt = await nativeReceipt;

		// Assert
		expect(receipt).toMatchObject({
			displayPath: 'packages/core/src/deep/target.ts',
			outcome: 'displayed',
		});
		await waitForVisibleCodeText('deepTarget');
	});

	test('a native navigation to a path the tree does not list settles as not listed', async () => {
		// Arrange
		const content = makeFileContent('export const listed = true;\n');
		const descriptor = await makeFileDescriptorForContent({
			content,
			contentHandle: 'listed-content',
			fileId: 'file-listed',
			path: 'src/listed.ts',
		});
		const recorder = receiptRecorder();
		const command = fileNavigationCommandForPath('src/excluded-by-policy.ts');

		// Act
		await render(
			<BridgeFileViewerBrowserHarnessApp
				codeViewWorkerPoolEnabled={false}
				fileProductSession={{
					onFileSelectionReceipt: recorder.record,
					readContent: async (): Promise<string> => content,
				}}
				initialMetadataEvents={makeFileMetadataEvents(descriptor)}
				navigationCommand={command}
			/>,
		);
		let receipt: BridgeProductFileSelectionReceipt | null = null;
		await actUpdate(async (): Promise<void> => {
			receipt = await recorder.next(
				(candidate) => candidate.nativeNavigationCommandId === command.commandId,
			);
		});
		await settleBridgeFileViewerBrowserInteraction();

		// Assert
		expect(receipt).toMatchObject({
			displayPath: 'src/excluded-by-policy.ts',
			outcome: 'notListed',
		});
		expect(selectedDisplayPath()).toBeNull();
	});
});
