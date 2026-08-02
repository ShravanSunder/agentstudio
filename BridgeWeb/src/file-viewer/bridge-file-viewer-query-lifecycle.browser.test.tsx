import { act } from 'react';
import { beforeEach, describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';
import { userEvent } from 'vitest/browser';

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
	makeMixedFileClassTreeMetadataEvents,
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
		await render(
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
		const renderResult = await render(
			<BridgeFileViewerBrowserHarnessApp
				initialMetadataEvents={makeTreeRowsOnlyMetadataEvents()}
			/>,
		);
		await waitForMetadataTreeRowCount(6);
		expect(document.querySelector('[data-testid="worktree-file-search-toggle"]')).not.toBeNull();

		// Act: Command-Shift-F opens the active Files Search control.
		await dispatchFileViewerShortcut({ shiftKey: true });

		// Assert: the toggle remains available to cancel an empty search and the field owns focus.
		const searchToggle = renderResult.getByTestId('worktree-file-search-toggle');
		await expect.element(searchToggle).toHaveAttribute('aria-pressed', 'true');
		await expect.element(searchToggle).toHaveAttribute('aria-label', 'Search files');
		let searchInput = renderResult.getByTestId('worktree-file-search-input').element();
		if (!(searchInput instanceof HTMLInputElement)) {
			throw new Error('Expected the visible File search input.');
		}
		expect(document.activeElement).toBe(searchInput);

		// Act: the active toolbar toggle cancels an empty search and can reopen it.
		await act(async (): Promise<void> => {
			await searchToggle.click();
		});
		expect(document.querySelector('[data-testid="worktree-file-search-input"]')).toBeNull();
		await expect.element(searchToggle).toHaveAttribute('aria-pressed', 'false');
		await expect.element(searchToggle).toHaveAttribute('aria-label', 'Search files');
		await act(async (): Promise<void> => {
			await searchToggle.click();
		});
		searchInput = renderResult.getByTestId('worktree-file-search-input').element();
		if (!(searchInput instanceof HTMLInputElement)) {
			throw new Error('Expected the reopened File search input.');
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

		// Act: close a populated search through the persistent toggle.
		await act(async (): Promise<void> => {
			await renderResult.getByTestId('worktree-file-search-input').fill('AppDelegate');
			await searchToggle.click();
		});
		await settleBridgeFileViewerBrowserUpdates();

		// Assert: closing clears the query, and reopening starts empty.
		expect(document.querySelector('[data-testid="worktree-file-search-input"]')).toBeNull();
		await expect.element(searchToggle).toHaveAttribute('aria-pressed', 'false');
		await expect.element(searchToggle).toHaveAttribute('aria-label', 'Search files');
		await act(async (): Promise<void> => {
			await searchToggle.click();
		});
		await expect.element(renderResult.getByTestId('worktree-file-search-input')).toHaveValue('');
	});

	test('routes active Files toolbar shortcuts through its scoped control target', async () => {
		// Arrange
		const controlTarget = new EventTarget();
		await render(
			<BridgeFileViewerBrowserHarnessApp
				controlTarget={controlTarget}
				initialMetadataEvents={makeTreeRowsOnlyMetadataEvents()}
			/>,
		);
		await waitForMetadataTreeRowCount(6);

		// Act: the document is outside this viewer's command scope.
		await dispatchFileViewerShortcut({ shiftKey: true });

		// Assert
		expect(document.querySelector('[data-testid="worktree-file-search-input"]')).toBeNull();

		// Act: the scoped target owns both toolbar shortcuts.
		await dispatchFileViewerShortcut({ shiftKey: true }, controlTarget);

		// Assert
		expect(document.querySelector('[data-testid="worktree-file-search-input"]')).not.toBeNull();

		// Act
		await dispatchFileViewerShortcut({ altKey: true }, controlTarget);

		// Assert
		expect(
			document.querySelector('[data-testid="worktree-file-filter-menu-popover"][data-open]'),
		).not.toBeNull();
	});

	test('File Type filters use real native classes, preserve ancestors, and Clear restores the tree', async () => {
		// Arrange
		const renderResult = await render(
			<BridgeFileViewerBrowserHarnessApp
				initialMetadataEvents={makeMixedFileClassTreeMetadataEvents()}
			/>,
		);
		await waitForMetadataTreeRowCount(19);
		await expect
			.poll((): readonly string[] => mountedFileTreePaths())
			.toEqual(allClassifiedFileTreePaths);

		// Act: Command-Option-F opens the production Base UI menu.
		await dispatchFileViewerShortcut({ altKey: true });
		const filterPopover = requireHTMLElement(
			renderResult.getByTestId('worktree-file-filter-menu-popover').element(),
		);

		// Assert: Files exposes exactly the native path-and-size-backed taxonomy.
		expect(filterPopover.textContent).toContain('File type');
		expect(filterPopover.textContent).not.toContain('Git status');
		expect(filterPopover.textContent).not.toContain('Binary');
		for (const fileClassLabel of [
			'Source',
			'Test',
			'Docs',
			'Config',
			'Generated',
			'Vendor',
			'Large',
			'Fixture',
			'Unknown',
		]) {
			expect(filterPopover.textContent).toContain(fileClassLabel);
		}

		// Act: repeating the shortcut closes and reopens the same menu.
		await dispatchFileViewerShortcut({ altKey: true });
		expect(
			document.querySelector('[data-testid="worktree-file-filter-menu-popover"][data-open]'),
		).toBeNull();
		await dispatchFileViewerShortcut({ altKey: true });

		// Act: Base UI Escape dismissal closes the menu and preserves its filter state.
		await dispatchFileViewerMenuKey('Escape');
		expect(
			document.querySelector('[data-testid="worktree-file-filter-menu-popover"][data-open]'),
		).toBeNull();
		await dispatchFileViewerShortcut({ altKey: true });

		// Act: Base UI owns menu focus, highlighted-option navigation, and Return selection.
		await waitForFileViewerMenuFocus();
		await dispatchFileViewerMenuKey('ArrowDown');
		await expect.poll(highlightedFileViewerMenuOptionLabel).toBe('Source');
		await navigateFileViewerMenuTo('Vendor');
		const focusedVendorOption = highlightedFileViewerMenuOption();
		expect(focusedVendorOption.textContent).toContain('Vendor');
		expect(document.activeElement).toBe(focusedVendorOption);
		await dispatchFileViewerMenuKey('Enter');
		await expect.poll(() => focusedVendorOption.getAttribute('aria-checked')).toBe('true');
		await settleBridgeFileViewerBrowserUpdates();

		// Assert: the matching file and only its required ancestor remain.
		await expect
			.poll((): readonly string[] => mountedFileTreePaths())
			.toEqual(['Vendor', 'Vendor/Library.js']);

		// Act / Assert: every exposed category selects real metadata-backed rows.
		// oxlint-disable no-await-in-loop -- Each selection mutates one shared Base UI menu and must settle before the next.
		for (const fileClassCase of fileClassFilterCases) {
			await actClickAndSettleFileViewerMenu(
				await waitForFileViewerMenuOptionContaining({ text: fileClassCase.label }),
			);
			await settleBridgeFileViewerBrowserUpdates();
			await expect
				.poll((): readonly string[] => mountedFileTreePaths())
				.toEqual(fileClassCase.expectedPaths);
		}
		// oxlint-enable no-await-in-loop

		// Act: Clear is the product reset path, not a test-only state mutation.
		await actClickAndSettleFileViewerMenu(
			requireHTMLElement(renderResult.getByTestId('worktree-file-filter-menu-clear').element()),
		);
		await settleBridgeFileViewerBrowserUpdates();

		// Assert
		await expect
			.poll((): readonly string[] => mountedFileTreePaths())
			.toEqual(allClassifiedFileTreePaths);
	});
});

const fileClassFilterCases = [
	{ expectedPaths: ['Sources/App', 'Sources/App/TextFile.ts'], label: 'Source' },
	{ expectedPaths: ['Tests', 'Tests/TextFile.test.ts'], label: 'Test' },
	{ expectedPaths: ['Docs', 'Docs/Guide.md'], label: 'Docs' },
	{ expectedPaths: ['Config', 'Config/package.json'], label: 'Config' },
	{ expectedPaths: ['Generated', 'Generated/API.generated.swift'], label: 'Generated' },
	{ expectedPaths: ['Vendor', 'Vendor/Library.js'], label: 'Vendor' },
	{ expectedPaths: ['Large', 'Large/blob.txt'], label: 'Large' },
	{ expectedPaths: ['Fixtures', 'Fixtures/sample.txt'], label: 'Fixture' },
	{ expectedPaths: ['Assets', 'Assets/logo.png'], label: 'Unknown' },
] as const;

const allClassifiedFileTreePaths = fileClassFilterCases
	.flatMap((fileClassCase): readonly string[] => fileClassCase.expectedPaths)
	.toSorted();

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) throw new Error('Expected a real Browser Mode element.');
	return element;
}

async function dispatchFileViewerShortcut(
	modifiers: Readonly<{ altKey?: boolean; shiftKey?: boolean }>,
	target: EventTarget = document,
): Promise<void> {
	await act(async (): Promise<void> => {
		target.dispatchEvent(
			new KeyboardEvent('keydown', {
				altKey: modifiers.altKey ?? false,
				bubbles: true,
				cancelable: true,
				key: 'f',
				metaKey: true,
				shiftKey: modifiers.shiftKey ?? false,
			}),
		);
	});
}

async function dispatchFileViewerMenuKey(key: 'ArrowDown' | 'Enter' | 'Escape'): Promise<void> {
	await act(async (): Promise<void> => {
		await userEvent.keyboard(`{${key}}`);
	});
}

async function waitForFileViewerMenuFocus(): Promise<void> {
	await expect
		.poll((): boolean => {
			const openFilterMenu = document.querySelector(
				'[data-testid="worktree-file-filter-menu-popover"][data-open]',
			);
			return (
				document.activeElement !== null && openFilterMenu?.contains(document.activeElement) === true
			);
		})
		.toBe(true);
}

async function navigateFileViewerMenuTo(label: string): Promise<void> {
	for (let optionIndex = 0; optionIndex < 9; optionIndex += 1) {
		if (highlightedFileViewerMenuOptionLabel() === label) {
			return;
		}
		await dispatchFileViewerMenuKey('ArrowDown');
	}
	throw new Error(`Expected Base UI arrow navigation to focus ${label}.`);
}

function highlightedFileViewerMenuOption(): HTMLElement {
	return requireHTMLElement(
		document.querySelector('[data-testid="worktree-file-filter-menu-option"][data-highlighted]'),
	);
}

function highlightedFileViewerMenuOptionLabel(): string {
	const highlightedOption = document.querySelector(
		'[data-testid="worktree-file-filter-menu-option"][data-highlighted]',
	);
	return (
		highlightedOption
			?.querySelector('[data-testid="worktree-file-filter-menu-option-label"]')
			?.textContent?.trim() ?? ''
	);
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
