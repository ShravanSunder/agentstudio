import { act } from 'react';
import { beforeEach, describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';
import { userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode mounts the production File shell.
import '../app/bridge-app.css';
import { bridgeAppControlProbeSchema } from '../app/bridge-app-control.js';
import type { BridgeWorkerMainToServerMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import {
	actClickAndSettleFileViewerMenu,
	waitForFileViewerMenuOptionContaining,
} from './bridge-file-viewer-app-startup.browser.test-support.js';
import { BridgeFileViewerBrowserHarnessApp } from './bridge-file-viewer-browser-test-app.js';
import {
	fileNavigationCommandForPath,
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
	selectedDisplayPath,
	waitForSelectedDisplayPath,
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

	test('clears an excluded File selection without auto-selecting a filtered replacement', async () => {
		// Arrange
		await render(
			<BridgeFileViewerBrowserHarnessApp
				initialMetadataEvents={makeMixedFileClassTreeMetadataEvents()}
				navigationCommand={fileNavigationCommandForPath('Sources/App/TextFile.ts')}
			/>,
		);
		await waitForMetadataTreeRowCount(19);
		await waitForSelectedDisplayPath('Sources/App/TextFile.ts');

		// Act
		await act(async (): Promise<void> => {
			window.dispatchEvent(
				new CustomEvent('__bridge_review_control', {
					detail: {
						filter: { categoryFilter: 'docs', surface: 'files' },
						method: 'bridge.fileTree.setFilter',
					},
				}),
			);
			await Promise.resolve();
		});
		await waitForMetadataTreeRowCount(1);

		// Assert
		await expect.poll(selectedDisplayPath, { timeout: 1_000 }).toBeNull();
		await expect
			.poll((): readonly string[] => mountedFileTreePaths())
			.toEqual(['Docs', 'Docs/Guide.md']);
		const probe = bridgeAppControlProbeSchema.safeParse(window.bridgeReviewControlProbe);
		expect(probe.success).toBe(true);
		if (!probe.success) return;
		expect(probe.data).toMatchObject({
			categoryFilter: 'docs',
			filterSurface: 'files',
			status: 'accepted',
		});
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
		const fileTree = renderResult.getByTestId('bridge-file-viewer-pierre-file-tree').element();
		if (!(fileTree instanceof HTMLElement)) throw new Error('Expected the Files tree focus owner.');
		fileTree.focus();

		// Act: Command-Shift-F opens the active Files Search control.
		await dispatchFileViewerShortcut({ shiftKey: true });

		// Assert: the toggle remains available to cancel an empty search and the field owns focus.
		const searchToggle = renderResult.getByTestId('worktree-file-search-toggle');
		await expect.element(searchToggle).toHaveAttribute('aria-pressed', 'true');
		await expect.element(searchToggle).toHaveAttribute('aria-label', 'Search files');
		await expect.element(searchToggle).toHaveAttribute('title', 'Close file search (⌘⇧F)');
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
		expect(document.activeElement).toBe(fileTree);
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

		// Act: foreground Escape closes Search without relying on a surface-global handler.
		await act(async (): Promise<void> => {
			searchInput.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Escape' }));
		});

		// Assert: focus returns to the still-eligible Files tree and Search can reopen normally.
		expect(document.querySelector('[data-testid="worktree-file-search-input"]')).toBeNull();
		expect(document.activeElement).toBe(fileTree);
		await act(async (): Promise<void> => {
			await searchToggle.click();
		});

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

		// Act: invalid regex leaves the last accepted projection visible and the input correctable.
		await act(async (): Promise<void> => {
			await renderResult.getByTestId('worktree-file-search-input').fill('[');
		});
		await settleBridgeFileViewerBrowserUpdates();

		// Assert
		await expect
			.poll((): readonly string[] => mountedFileTreePaths())
			.toEqual(['Sources/AgentStudio/App', 'Sources/AgentStudio/App/AppDelegate.swift']);
		await expect
			.element(renderResult.getByTestId('worktree-file-filter-status'))
			.toHaveTextContent('Invalid regex');
		await expect
			.element(renderResult.getByTestId('worktree-file-search-input'))
			.toHaveAttribute('aria-invalid', 'true');
		await expect.element(renderResult.getByTestId('worktree-file-search-input')).toHaveValue('[');

		// Act: oversized visible input is rejected without replacing entered or accepted state.
		await act(async (): Promise<void> => {
			await renderResult.getByTestId('worktree-file-search-input').fill('a'.repeat(4_097));
		});
		await settleBridgeFileViewerBrowserUpdates();

		// Assert
		await expect.element(renderResult.getByTestId('worktree-file-search-input')).toHaveValue('[');
		await expect
			.element(renderResult.getByTestId('worktree-file-filter-status'))
			.toHaveTextContent('Search query is too long');
		await expect
			.poll((): readonly string[] => mountedFileTreePaths())
			.toEqual(['Sources/AgentStudio/App', 'Sources/AgentStudio/App/AppDelegate.swift']);

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

	test('announces closed semantic rejection and clears it on the next admitted Search', async () => {
		// Arrange
		const renderResult = await render(
			<BridgeFileViewerBrowserHarnessApp
				initialMetadataEvents={makeTreeRowsOnlyMetadataEvents()}
			/>,
		);
		await waitForMetadataTreeRowCount(6);
		const fileTree = requireHTMLElement(
			renderResult.getByTestId('bridge-file-viewer-pierre-file-tree').element(),
		);
		fileTree.focus();

		// Act: reject a complete semantic candidate while Search is closed.
		await dispatchFileViewerSearchCommand({ mode: 'text', query: 'a'.repeat(4_097) });

		// Assert: Search and focus stay put while the persistent live region announces rejection.
		expect(document.querySelector('[data-testid="worktree-file-search-input"]')).toBeNull();
		expect(document.activeElement).toBe(fileTree);
		await expect
			.element(renderResult.getByTestId('worktree-file-filter-status'))
			.toHaveTextContent('Search query is too long');

		// Act: an admitted semantic Search clears the stale rejection.
		await dispatchFileViewerSearchCommand({ mode: 'regex', query: 'AppDelegate' });

		// Assert
		await expect
			.element(renderResult.getByTestId('worktree-file-search-input'))
			.toHaveValue('AppDelegate');
		await expect
			.element(renderResult.getByTestId('worktree-file-filter-status'))
			.toHaveTextContent('');

		// Act: a later invalid regex must replace, not be masked by, the oversized status.
		await dispatchFileViewerSearchCommand({ mode: 'regex', query: '[' });

		// Assert
		await expect.element(renderResult.getByTestId('worktree-file-search-input')).toHaveValue('[');
		await expect
			.element(renderResult.getByTestId('worktree-file-filter-status'))
			.toHaveTextContent('Invalid regex');
	});

	test('returns focus to the Search trigger when no earlier semantic owner was recorded', async () => {
		// Arrange
		const renderResult = await render(
			<BridgeFileViewerBrowserHarnessApp
				initialMetadataEvents={makeTreeRowsOnlyMetadataEvents()}
			/>,
		);
		await waitForMetadataTreeRowCount(6);
		const searchToggle = renderResult.getByTestId('worktree-file-search-toggle');

		// Act: open directly from the trigger, then close from the focused field.
		await act(async (): Promise<void> => {
			await searchToggle.click();
		});
		const searchInput = requireHTMLElement(
			renderResult.getByTestId('worktree-file-search-input').element(),
		);
		await act(async (): Promise<void> => {
			searchInput.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Escape' }));
		});

		// Assert
		expect(document.querySelector('[data-testid="worktree-file-search-input"]')).toBeNull();
		expect(document.activeElement).toBe(searchToggle.element());
	});

	test('restores Files focus by eligible path and falls back when the path is excluded', async () => {
		// Arrange
		const renderResult = await render(
			<BridgeFileViewerBrowserHarnessApp
				initialMetadataEvents={makeTreeRowsOnlyMetadataEvents()}
			/>,
		);
		await waitForMetadataTreeRowCount(6);
		const focusedPath = 'Sources/AgentStudio/App/AppDelegate.swift';
		await expect.poll(() => mountedFileTreeRow(focusedPath)).not.toBeNull();
		const originalRow = requireHTMLElement(mountedFileTreeRow(focusedPath));
		originalRow.focus();
		expect(deepActiveElement()).toBe(originalRow);

		// Act: Search keeps the focused semantic path eligible.
		await dispatchFileViewerShortcut({ shiftKey: true });
		await act(async (): Promise<void> => {
			await renderResult.getByTestId('worktree-file-search-input').fill('AppDelegate');
		});
		await settleBridgeFileViewerBrowserUpdates();
		const eligibleRow = requireHTMLElement(mountedFileTreeRow(focusedPath));
		const searchInput = requireHTMLElement(
			renderResult.getByTestId('worktree-file-search-input').element(),
		);
		await act(async (): Promise<void> => {
			searchInput.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Escape' }));
		});

		// Assert: the owner resolves the current row, not a stale DOM node.
		expect(deepActiveElement()).toBe(eligibleRow);

		// Act: exclude the recorded path before closing the next Search.
		eligibleRow.focus();
		await dispatchFileViewerShortcut({ shiftKey: true });
		await act(async (): Promise<void> => {
			await renderResult.getByTestId('worktree-file-search-input').fill('NoSuchPath');
		});
		await settleBridgeFileViewerBrowserUpdates();
		const excludedSearchInput = requireHTMLElement(
			renderResult.getByTestId('worktree-file-search-input').element(),
		);
		await act(async (): Promise<void> => {
			excludedSearchInput.dispatchEvent(
				new KeyboardEvent('keydown', { bubbles: true, key: 'Escape' }),
			);
		});

		// Assert: an ineligible path falls back to the Search trigger.
		expect(document.activeElement).toBe(
			renderResult.getByTestId('worktree-file-search-toggle').element(),
		);
	});

	test('File category filters use real native classes, preserve ancestors, and Clear restores the tree', async () => {
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
		expect(filterPopover.textContent).toContain('File category');
		expect(filterPopover.textContent).not.toContain('Git status');
		expect(filterPopover.textContent).not.toContain('Binary');
		expect(filterPopover.textContent).not.toContain('Large');
		for (const fileClassLabel of [
			'All',
			'Source code',
			'Tests',
			'Documentation',
			'Configuration',
			'Generated',
			'Dependencies and build output',
			'Fixtures',
			'Other',
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
		expect(document.activeElement?.getAttribute('role')).toBe('menu');
		await dispatchFileViewerMenuKey('ArrowDown');
		await expect.poll(highlightedFileViewerMenuOptionLabel).toBe('All');
		await navigateFileViewerMenuTo('Dependencies and build output');
		const focusedVendorOption = highlightedFileViewerMenuOption();
		expect(focusedVendorOption.textContent).toContain('Dependencies and build output');
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
		for (const categoryCase of categoryFilterCases) {
			await actClickAndSettleFileViewerMenu(
				await waitForFileViewerMenuOptionContaining({ text: categoryCase.label }),
			);
			await settleBridgeFileViewerBrowserUpdates();
			await expect
				.poll((): readonly string[] => mountedFileTreePaths())
				.toEqual(categoryCase.expectedPaths);
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

const categoryFilterCases = [
	{ expectedPaths: ['Sources/App', 'Sources/App/TextFile.ts'], label: 'Source code' },
	{ expectedPaths: ['Tests', 'Tests/TextFile.test.ts'], label: 'Tests' },
	{ expectedPaths: ['Docs', 'Docs/Guide.md'], label: 'Documentation' },
	{ expectedPaths: ['Config', 'Config/package.json'], label: 'Configuration' },
	{ expectedPaths: ['Generated', 'Generated/API.generated.swift'], label: 'Generated' },
	{ expectedPaths: ['Vendor', 'Vendor/Library.js'], label: 'Dependencies and build output' },
	{ expectedPaths: ['Fixtures', 'Fixtures/sample.txt'], label: 'Fixtures' },
	{ expectedPaths: ['Assets', 'Assets/logo.png'], label: 'Other' },
] as const;

const allClassifiedFileTreePaths = categoryFilterCases
	.flatMap((categoryCase): readonly string[] => categoryCase.expectedPaths)
	.concat(['Large', 'Large/blob.txt'])
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

async function dispatchFileViewerSearchCommand(props: {
	readonly mode: 'regex' | 'text';
	readonly query: string;
}): Promise<void> {
	await act(async (): Promise<void> => {
		window.dispatchEvent(
			new CustomEvent('__bridge_review_control', {
				detail: {
					method: 'bridge.fileTree.search',
					searchMode: { kind: props.mode },
					searchText: props.query,
				},
			}),
		);
	});
	await settleBridgeFileViewerBrowserUpdates();
}

async function dispatchFileViewerMenuKey(key: 'ArrowDown' | 'Enter' | 'Escape'): Promise<void> {
	await act(async (): Promise<void> => {
		await userEvent.keyboard(`{${key}}`);
	});
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

function mountedFileTreeRow(path: string): HTMLElement | null {
	const treeHost = document.querySelector(
		'[data-testid="bridge-file-viewer-pierre-file-tree"] file-tree-container',
	);
	const row = [
		...(treeHost?.shadowRoot?.querySelectorAll<HTMLElement>('[data-item-path]') ?? []),
	].find((candidate): boolean => candidate.dataset['itemPath']?.replace(/\/$/u, '') === path);
	return row instanceof HTMLElement ? row : null;
}

function deepActiveElement(): Element | null {
	let activeElement = document.activeElement;
	while (activeElement instanceof HTMLElement) {
		const shadowActiveElement = activeElement.shadowRoot?.activeElement;
		if (shadowActiveElement === null || shadowActiveElement === undefined) break;
		activeElement = shadowActiveElement;
	}
	return activeElement;
}
