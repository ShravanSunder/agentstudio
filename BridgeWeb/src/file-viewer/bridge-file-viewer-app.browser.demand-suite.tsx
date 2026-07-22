import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import type {
	BridgeWorkerMainToServerMessage,
	BridgeWorkerViewportCommand,
} from '../core/comm-worker/bridge-worker-contracts.js';
import {
	findBridgeViewerTreeScrollOwner,
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerTreeItemButton,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { BridgeFileViewerBrowserHarnessApp as BridgeFileViewerApp } from './bridge-file-viewer-browser-test-app.js';
import { makeFileContent } from './bridge-file-viewer-browser-test-fixtures.js';
import {
	makeFileDescriptor,
	makeFileMetadataEvents,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actFrame,
	actUpdate,
	openFilePath,
	openFileState,
	waitForMetadataTreeRowCount,
	waitForTreeScrollHeightAtLeast,
} from './bridge-file-viewer-browser-test-harness.js';

describe('BridgeFileViewerApp Browser Mode', () => {
	test('does not fetch visible file tree demand on the main thread', async () => {
		const firstDescriptor = makeFileDescriptor({
			contentHandle: 'first-visible-content',
			fileId: 'file-first-visible',
			path: 'src/first-visible.ts',
		});
		const secondDescriptor = makeFileDescriptor({
			contentHandle: 'second-visible-content',
			fileId: 'file-second-visible',
			path: 'src/second-visible.ts',
		});
		const openedDescriptorIds: string[] = [];

		render(
			<BridgeFileViewerApp
				initialMetadataEvents={makeFileMetadataEvents(firstDescriptor, secondDescriptor)}
				fileProductSession={{
					readContent: async (props) => {
						openedDescriptorIds.push(props.descriptor.descriptorId);
						return makeFileContent(
							props.descriptor.descriptorId.includes('second-visible-content')
								? 'export const secondVisible = true;\n'
								: 'export const firstVisible = true;\n',
						);
					},
				}}
			/>,
		);

		await waitForMetadataTreeRowCount(2);
		await actFrame();
		await actFrame();
		await actFrame();

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-demand-dispatch-status')).toBeNull();
		expect(shell.getAttribute('data-last-demand-dispatch-first-lane')).toBeNull();
		expect(openFileState()).toBeNull();
		expect(openFilePath()).toBeNull();
		expect(openedDescriptorIds).toEqual([]);
	});

	test('publishes visible viewport facts to the comm worker on File tree scroll', async () => {
		const firstDescriptor = makeFileDescriptor({
			contentHandle: 'first-worker-viewport-content',
			fileId: 'file-first-worker-viewport',
			path: 'src/first-worker-viewport.ts',
		});
		const secondDescriptor = makeFileDescriptor({
			contentHandle: 'second-worker-viewport-content',
			fileId: 'file-second-worker-viewport',
			path: 'src/second-worker-viewport.ts',
		});
		const dispatchedMessages: BridgeWorkerMainToServerMessage[] = [];

		render(
			<div style={{ height: '720px', overflow: 'hidden', width: '1280px' }}>
				<BridgeFileViewerApp
					fileProductSession={{
						onWorkerCommand: (message): void => {
							dispatchedMessages.push(message);
						},
					}}
					initialMetadataEvents={makeFileMetadataEvents(firstDescriptor, secondDescriptor)}
				/>
			</div>,
		);

		await waitForMetadataTreeRowCount(2);
		await waitForBridgeViewerTreeItemButton('src/first-worker-viewport.ts');
		await waitForBridgeViewerTreeItemButton('src/second-worker-viewport.ts');
		const treeScrollOwner = findBridgeViewerTreeScrollOwner();
		if (treeScrollOwner === null) {
			throw new Error('Expected File View tree scroll owner for worker viewport demand.');
		}

		await actUpdate((): void => {
			treeScrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		});
		await actFrame();

		expect(dispatchedMessages.map((message) => message.command)).not.toContain(
			'fileViewSourceUpdate',
		);
		const viewportMessage = dispatchedMessages.find(
			(message): boolean => message.command === 'viewport',
		);
		expect(viewportMessage).toMatchObject({
			command: 'viewport',
			firstVisibleIndex: 0,
			lastVisibleIndex: 1,
			phase: 'settled',
			visibleItemIds: ['file-first-worker-viewport', 'file-second-worker-viewport'],
		});
	});

	test('publishes real scrolled File tree viewport indices to the comm worker', async () => {
		const descriptors = Array.from({ length: 80 }, (_value, index) => {
			const paddedIndex = index.toString().padStart(3, '0');
			return makeFileDescriptor({
				contentHandle: `scrolled-worker-viewport-content-${paddedIndex}`,
				fileId: `file-scrolled-worker-viewport-${paddedIndex}`,
				path: `File-${paddedIndex}.swift`,
			});
		});
		const dispatchedMessages: BridgeWorkerMainToServerMessage[] = [];

		render(
			<div style={{ height: '720px', overflow: 'hidden', width: '1280px' }}>
				<BridgeFileViewerApp
					fileProductSession={{
						onWorkerCommand: (message): void => {
							dispatchedMessages.push(message);
						},
					}}
					initialMetadataEvents={makeFileMetadataEvents(...descriptors)}
				/>
			</div>,
		);

		await waitForMetadataTreeRowCount(80);
		await waitForTreeScrollHeightAtLeast(80 * 24);
		const treeScrollOwner = findBridgeViewerTreeScrollOwner();
		if (treeScrollOwner === null) {
			throw new Error('Expected File View tree scroll owner for scrolled worker viewport demand.');
		}
		await waitForViewportMessageWithFirstVisibleIndex({
			dispatchedMessages,
			minimumFirstVisibleIndex: 0,
		});

		await actUpdate((): void => {
			treeScrollOwner.scrollTop = 24 * 30;
			treeScrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		});

		const viewportMessage = await waitForViewportMessageWithFirstVisibleIndex({
			dispatchedMessages,
			minimumFirstVisibleIndex: 1,
		});
		expect(viewportMessage.firstVisibleIndex).toBeGreaterThan(0);
		expect(viewportMessage.lastVisibleIndex).toBeGreaterThanOrEqual(
			viewportMessage.firstVisibleIndex,
		);
		expect(viewportMessage.visibleItemIds.length).toBeGreaterThan(0);
	});

	test('does not patch global fetch for worker-backed content loading', async () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'global-fetch-isolation-content',
			fileId: 'file-global-fetch-isolation',
			path: 'src/global-fetch-isolation.ts',
		});
		const originalFetch = window.fetch;

		render(
			<BridgeFileViewerApp
				initialMetadataEvents={makeFileMetadataEvents(descriptor)}
				fileProductSession={{
					readContent: async () => makeFileContent('export const globalFetchIsolation = true;\n'),
				}}
			/>,
		);

		await waitForMetadataTreeRowCount(1);
		expect(window.fetch).toBe(originalFetch);
	});

	test('keeps non-text visible demand from falling back to legacy fetch', async () => {
		const textDescriptor = makeFileDescriptor({
			contentHandle: 'text-visible-content',
			fileId: 'file-text-visible',
			path: 'src/text-visible.ts',
		});
		const binaryDescriptor = makeFileDescriptor({
			contentHandle: 'binary-visible-content',
			fileId: 'file-binary-visible',
			isBinary: true,
			path: 'assets/logo.png',
		});
		const unavailableDescriptor = makeFileDescriptor({
			contentHandle: 'unavailable-visible-content',
			fileId: 'file-unavailable-visible',
			path: 'generated/huge.log',
			virtualizedExtentKind: 'unavailable',
		});
		const openedDescriptorIds: string[] = [];

		render(
			<BridgeFileViewerApp
				initialMetadataEvents={makeFileMetadataEvents(
					textDescriptor,
					binaryDescriptor,
					unavailableDescriptor,
				)}
				fileProductSession={{
					readContent: async (props) => {
						openedDescriptorIds.push(props.descriptor.descriptorId);
						return makeFileContent('export const textVisible = true;\n');
					},
				}}
			/>,
		);

		await waitForMetadataTreeRowCount(3);
		await actFrame();
		await actFrame();
		await actFrame();

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-demand-dispatch-status')).toBeNull();
		expect(shell.getAttribute('data-last-demand-dispatch-first-lane')).toBeNull();
		expect(openedDescriptorIds).toEqual([]);
	});

	test('does not start visible demand fetch work before Files becomes inactive', async () => {
		const visibleDescriptor = makeFileDescriptor({
			contentHandle: 'inactive-visible-content',
			fileId: 'file-inactive-visible',
			path: 'src/inactive-visible.ts',
		});
		const openedDescriptorIds: string[] = [];

		render(
			<BridgeFileViewerApp
				initialMetadataEvents={makeFileMetadataEvents(visibleDescriptor)}
				isActive={false}
				fileProductSession={{
					readContent: async (props) => {
						openedDescriptorIds.push(props.descriptor.descriptorId);
						return makeFileContent('export const inactiveVisible = true;\n');
					},
				}}
			/>,
		);

		await waitForMetadataTreeRowCount(1);
		await actFrame();
		await actFrame();

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-file-viewer-active')).toBe('false');
		expect(shell.getAttribute('data-last-demand-dispatch-status')).toBeNull();
		expect(shell.getAttribute('data-last-demand-dispatch-first-lane')).toBeNull();
		expect(openedDescriptorIds).toEqual([]);
	});
});

async function waitForViewportMessageWithFirstVisibleIndex(props: {
	readonly attempt?: number;
	readonly dispatchedMessages: readonly BridgeWorkerMainToServerMessage[];
	readonly minimumFirstVisibleIndex: number;
}): Promise<BridgeWorkerViewportCommand> {
	const viewportMessage = latestViewportMessage(props.dispatchedMessages);
	if (
		viewportMessage !== null &&
		viewportMessage.firstVisibleIndex >= props.minimumFirstVisibleIndex
	) {
		return viewportMessage;
	}
	const attempt = props.attempt ?? 0;
	if (attempt >= 30) {
		throw new Error(
			`Expected viewport firstVisibleIndex >= ${props.minimumFirstVisibleIndex}; actual=${viewportMessage?.firstVisibleIndex ?? 'missing'}`,
		);
	}
	await actFrame();
	return waitForViewportMessageWithFirstVisibleIndex({
		attempt: attempt + 1,
		dispatchedMessages: props.dispatchedMessages,
		minimumFirstVisibleIndex: props.minimumFirstVisibleIndex,
	});
}

function latestViewportMessage(
	messages: readonly BridgeWorkerMainToServerMessage[],
): BridgeWorkerViewportCommand | null {
	for (const message of messages.toReversed()) {
		if (message.command === 'viewport') {
			return message;
		}
	}
	return null;
}
