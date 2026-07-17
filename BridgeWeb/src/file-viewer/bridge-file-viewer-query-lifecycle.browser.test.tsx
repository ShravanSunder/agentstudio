import { act } from 'react';
import { beforeEach, describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode mounts the production File shell.
import '../app/bridge-app.css';
import type { BridgeWorkerMainToServerMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import { BridgeFileViewerBrowserHarnessApp } from './bridge-file-viewer-browser-test-app.js';
import {
	makeFileContent,
	makeFileDescriptorForContent,
	makeFileMetadataEvents,
	makeTreeRowsOnlyMetadataEvents,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	installBridgeFileViewerNoopResizeObserver,
	settleBridgeFileViewerBrowserUpdates,
	waitForMetadataTreeRowCount,
	waitForOpenFileState,
} from './bridge-file-viewer-browser-test-harness.js';

describe('BridgeFileViewerApp query and content lifecycle Browser Mode', () => {
	beforeEach((): void => {
		installBridgeFileViewerNoopResizeObserver();
	});

	test('does not reschedule the unchanged query when content publications update the snapshot', async () => {
		// Arrange
		const content = makeFileContent('export const queryLifecycle = "settled";\n');
		const descriptor = await makeFileDescriptorForContent({
			content,
			contentHandle: 'query-lifecycle-content',
			fileId: 'file-query-lifecycle',
			path: 'src/query-lifecycle.ts',
		});
		const dispatchedMessages: BridgeWorkerMainToServerMessage[] = [];

		// Act
		render(
			<BridgeFileViewerBrowserHarnessApp
				autoOpenInitialFile={true}
				fileProductSession={{
					onWorkerCommand: (message): void => {
						dispatchedMessages.push(message);
					},
					readContent: async (): Promise<string> => content,
				}}
				initialMetadataEvents={makeFileMetadataEvents(descriptor)}
			/>,
		);
		await waitForMetadataTreeRowCount(1);
		await waitForOpenFileState('ready');
		await settleBridgeFileViewerBrowserUpdates();

		// Assert
		const queryUpdates = dispatchedMessages.filter(
			(message): boolean => message.command === 'fileQueryUpdate',
		);
		expect(queryUpdates).toHaveLength(1);
		expect(
			dispatchedMessages.filter((message): boolean => message.command === 'select'),
		).toHaveLength(1);
	});

	test('projects text and regex matches with required ancestors through the visible File search', async () => {
		// Arrange
		const renderResult = render(
			<BridgeFileViewerBrowserHarnessApp
				initialMetadataEvents={makeTreeRowsOnlyMetadataEvents()}
			/>,
		);
		await waitForMetadataTreeRowCount(6);

		// Act: open the product-owned field and enter a text query.
		await act(async (): Promise<void> => {
			await renderResult.getByTestId('worktree-file-search-toggle').click();
			await renderResult.getByTestId('worktree-file-search-input').fill('AppDelegate');
		});
		await settleBridgeFileViewerBrowserUpdates();

		// Assert: only the matching file and required ancestors remain painted.
		await expect
			.poll((): readonly string[] => mountedFileTreePaths())
			.toEqual(['Sources/AgentStudio/App', 'Sources/AgentStudio/App/AppDelegate.swift']);

		// Act: an empty directory whose own path matches must not survive.
		await act(async (): Promise<void> => {
			await renderResult.getByTestId('worktree-file-search-input').fill('Bridge');
		});
		await settleBridgeFileViewerBrowserUpdates();

		// Assert
		await expect.poll((): readonly string[] => mountedFileTreePaths()).toEqual([]);

		// Act: regex is selected from inside the compound search field.
		await act(async (): Promise<void> => {
			await renderResult.getByTestId('worktree-file-regex-toggle').click();
			await renderResult
				.getByTestId('worktree-file-search-input')
				.fill(String.raw`AppDelegate\.swift$`);
		});
		await settleBridgeFileViewerBrowserUpdates();

		// Assert
		await expect
			.poll((): readonly string[] => mountedFileTreePaths())
			.toEqual(['Sources/AgentStudio/App', 'Sources/AgentStudio/App/AppDelegate.swift']);

		// Act: invalid regex fails closed and leaves the input correctable.
		await act(async (): Promise<void> => {
			await renderResult.getByTestId('worktree-file-search-input').fill('[');
		});
		await settleBridgeFileViewerBrowserUpdates();

		// Assert
		await expect.poll((): readonly string[] => mountedFileTreePaths()).toEqual([]);
		await expect
			.element(renderResult.getByTestId('worktree-file-filter-status'))
			.toHaveTextContent('Invalid regex');
		await expect
			.element(renderResult.getByTestId('worktree-file-search-input'))
			.toHaveAttribute('aria-invalid', 'true');
		await expect.element(renderResult.getByTestId('worktree-file-search-input')).toHaveValue('[');
	});
});

function mountedFileTreePaths(): readonly string[] {
	const treeHost = document.querySelector(
		'[data-testid="bridge-file-viewer-pierre-file-tree"] file-tree-container',
	);
	if (!(treeHost instanceof HTMLElement) || treeHost.shadowRoot === null) return [];
	return [...treeHost.shadowRoot.querySelectorAll<HTMLElement>('[data-item-path]')]
		.map((row): string => row.dataset['itemPath']?.replace(/\/$/u, '') ?? '')
		.filter((path): boolean => path.length > 0)
		.filter((path, index, paths): boolean => paths.indexOf(path) === index)
		.toSorted();
}
