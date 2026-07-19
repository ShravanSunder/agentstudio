import { act } from 'react';
import { beforeEach, describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode mounts the production File shell.
import '../app/bridge-app.css';
import type { BridgeWorkerMainToServerMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import {
	actClickAndSettleFileViewerMenu,
	waitForFileViewerMenuOptionContaining,
} from './bridge-file-viewer-app-startup.browser.test-support.js';
import { BridgeFileViewerBrowserHarnessApp } from './bridge-file-viewer-browser-test-app.js';
import {
	makeFileContent,
	makeFileDescriptorForContent,
	makeFileMetadataEvents,
	makeMixedAvailabilityTreeMetadataEvents,
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
		expect(document.querySelector('[data-testid="worktree-file-search-toggle"]')).not.toBeNull();

		// Act: open the product-owned field and enter a text query.
		await act(async (): Promise<void> => {
			await renderResult.getByTestId('worktree-file-search-toggle').click();
		});

		// Assert: the field replaces the trigger and owns focus while search is open.
		expect(document.querySelector('[data-testid="worktree-file-search-toggle"]')).toBeNull();
		const searchInput = renderResult.getByTestId('worktree-file-search-input').element();
		if (!(searchInput instanceof HTMLInputElement)) {
			throw new Error('Expected the visible File search input.');
		}
		expect(document.activeElement).toBe(searchInput);

		// Act: enter a text query.
		await act(async (): Promise<void> => {
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

		// Act: the far-right Clear action resets the visible query.
		await act(async (): Promise<void> => {
			await renderResult.getByTestId('worktree-file-search-clear').click();
		});
		await settleBridgeFileViewerBrowserUpdates();

		// Assert
		await expect.element(renderResult.getByTestId('worktree-file-search-input')).toHaveValue('');
		await expect
			.poll((): readonly string[] => mountedFileTreePaths())
			.toContain('Sources/AgentStudio/App/AppDelegate.swift');
		await expect
			.poll((): readonly string[] => mountedFileTreePaths())
			.toContain('Sources/AgentStudio/Features/Bridge');
	});

	test('availability filters replace the visible File tree and Clear restores every branch', async () => {
		// Arrange
		const renderResult = render(
			<BridgeFileViewerBrowserHarnessApp
				initialMetadataEvents={makeMixedAvailabilityTreeMetadataEvents()}
			/>,
		);
		await waitForMetadataTreeRowCount(5);
		await expect
			.poll((): readonly string[] => mountedFileTreePaths())
			.toEqual(['Sources/App', 'Sources/App/TextFile.ts', 'Vendor', 'Vendor/BinaryFile.bin']);

		// Act: choose the unavailable-file availability filter through the real menu.
		await actClickAndSettleFileViewerMenu(
			requireHTMLElement(renderResult.getByTestId('worktree-file-filter-menu').element()),
		);
		const unavailableOption = await waitForFileViewerMenuOptionContaining({
			text: 'Unavailable files',
		});
		await actClickAndSettleFileViewerMenu(unavailableOption);
		await settleBridgeFileViewerBrowserUpdates();

		// Assert: the matching file and only its required ancestor remain.
		await expect
			.poll((): readonly string[] => mountedFileTreePaths())
			.toEqual(['Vendor', 'Vendor/BinaryFile.bin']);

		// Act: Clear is the product reset path, not a test-only state mutation.
		await actClickAndSettleFileViewerMenu(
			requireHTMLElement(renderResult.getByTestId('worktree-file-filter-menu').element()),
		);
		await actClickAndSettleFileViewerMenu(
			requireHTMLElement(renderResult.getByTestId('worktree-file-filter-menu-clear').element()),
		);
		await settleBridgeFileViewerBrowserUpdates();

		// Assert
		await expect
			.poll((): readonly string[] => mountedFileTreePaths())
			.toEqual(['Sources/App', 'Sources/App/TextFile.ts', 'Vendor', 'Vendor/BinaryFile.bin']);
	});
});

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) throw new Error('Expected a real Browser Mode element.');
	return element;
}

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
