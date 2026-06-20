// @vitest-environment jsdom

import { act, type CSSProperties, type ReactElement } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, describe, expect, test, vi } from 'vitest';

import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { BridgeReviewTreesPanel } from './bridge-trees-panel.js';

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

interface UseFileTreeCall {
	readonly density?: 'compact' | 'default' | 'relaxed' | number;
	readonly fileTreeSearchMode?: string;
	readonly flattenEmptyDirectories?: boolean;
	readonly initialVisibleRowCount?: number;
	readonly onSelectionChange?: (selectedPaths: readonly string[]) => void;
	readonly overscan?: number;
	readonly preparedInput?: unknown;
	readonly presorted?: boolean;
	readonly search?: boolean;
	readonly stickyFolders?: boolean;
	readonly unsafeCSS?: string;
}

type FileTreeStyleForTest = CSSProperties & Readonly<Record<string, string | number | undefined>>;

const treesReactMock = vi.hoisted(() => ({
	fileTreeStyles: [] as FileTreeStyleForTest[],
	useFileTreeCalls: [] as UseFileTreeCall[],
	directoryExpand: vi.fn(),
	fileSelect: vi.fn(),
	model: {
		batch: vi.fn(),
		closeSearch: vi.fn(),
		focusPath: vi.fn(),
		getItem: vi.fn((path: string) =>
			path.endsWith('.swift')
				? {
						deselect: vi.fn(),
						focus: vi.fn(),
						getPath: vi.fn(() => path),
						isDirectory: () => false,
						isFocused: () => false,
						isSelected: () => false,
						select: treesReactMock.fileSelect,
						toggleSelect: vi.fn(),
					}
				: {
						collapse: vi.fn(),
						deselect: vi.fn(),
						expand: treesReactMock.directoryExpand,
						focus: vi.fn(),
						getPath: vi.fn(() => path),
						isDirectory: () => true,
						isExpanded: () => false,
						isFocused: () => false,
						isSelected: () => false,
						select: vi.fn(),
						toggle: vi.fn(),
						toggleSelect: vi.fn(),
					},
		),
		openSearch: vi.fn(),
		resetPaths: vi.fn(),
		scrollToPath: vi.fn(),
		setGitStatus: vi.fn(),
		setSearch: vi.fn(),
	},
}));

vi.mock('@pierre/trees/react', () => ({
	FileTree: (props: { readonly style?: FileTreeStyleForTest }): ReactElement => {
		if (props.style !== undefined) {
			treesReactMock.fileTreeStyles.push(props.style);
		}
		return <div data-testid="mock-file-tree" />;
	},
	useFileTree: (options: UseFileTreeCall): { readonly model: typeof treesReactMock.model } => {
		treesReactMock.useFileTreeCalls.push(options);
		return { model: treesReactMock.model };
	},
}));

let mountedRoot: ReturnType<typeof createRoot> | null = null;

describe('BridgeReviewTreesPanel', () => {
	afterEach(() => {
		if (mountedRoot !== null) {
			act((): void => {
				mountedRoot?.unmount();
			});
			mountedRoot = null;
		}
		document.body.replaceChildren();
		treesReactMock.fileTreeStyles.length = 0;
		treesReactMock.useFileTreeCalls.length = 0;
		vi.clearAllMocks();
	});

	test('configures Pierre FileTree for compact prepared review navigation', () => {
		renderTreesPanel();

		const [options] = treesReactMock.useFileTreeCalls;

		expect(options).toEqual(
			expect.objectContaining({
				flattenEmptyDirectories: true,
				fileTreeSearchMode: 'expand-matches',
				density: 'compact',
				initialVisibleRowCount: 24,
				overscan: 10,
				search: true,
				stickyFolders: true,
			}),
		);
		expect(options).not.toHaveProperty('itemHeight');
		expect(options?.preparedInput).toBeDefined();
		expect(options?.unsafeCSS).toContain('data-file-tree-virtualized-scroll');
		expect(options?.unsafeCSS).toContain('scrollbar-width: thin');
		expect(options?.unsafeCSS).toContain('scrollbar-color: rgb(205 214 244 / 0.24) transparent');
		expect(options?.unsafeCSS).toContain('width: 4px');
		expect(options?.unsafeCSS).toContain('height: 4px');
		expect(options?.unsafeCSS).toContain('data-file-tree-sticky-overlay-content');
		expect(options?.unsafeCSS).not.toContain(
			"[data-item-contains-git-change='true'] > [data-item-section='git']",
		);
	});

	test('uses Pierre FileTree CSS custom properties for dark theme colors', () => {
		renderTreesPanel();

		const [style] = treesReactMock.fileTreeStyles;

		expect(style).toEqual(
			expect.objectContaining({
				colorScheme: 'dark',
				display: 'block',
				height: '100%',
				'--trees-bg-override': 'var(--bridge-surface-bg)',
				'--trees-bg-muted-override': 'var(--bridge-surface-raised-bg)',
				'--trees-fg-override': 'var(--bridge-text-primary)',
				'--trees-fg-muted-override': 'var(--bridge-text-muted)',
				'--trees-search-bg-override': 'var(--bridge-header-control-bg)',
				'--trees-selected-bg-override':
					'color-mix(in oklch, var(--bridge-accent) 18%, transparent)',
				'--trees-padding-inline-override': 8,
				'--trees-git-renamed-color-override': 'var(--bridge-accent)',
				'--trees-theme-git-added-fg': '#A6E3A1',
				'--trees-theme-git-deleted-fg': '#F38BA8',
				'--trees-theme-git-modified-fg': '#89B4FA',
				'--trees-theme-list-active-selection-bg': '#45475A',
				'--trees-theme-sidebar-bg': '#181825',
				'--trees-theme-sidebar-fg': '#CDD6F4',
			}),
		);
		expect(style).not.toHaveProperty('--trees-density-override');
	});
});

function renderTreesPanel(): void {
	const reviewPackage = makeBridgeViewerProjectionFixture();
	const projection = buildBridgeReviewProjection({
		reviewPackage,
		request: { base: { kind: 'allFiles' }, refinements: [] },
	});
	const container = document.createElement('div');
	document.body.append(container);
	mountedRoot = createRoot(container);

	act((): void => {
		mountedRoot?.render(
			<BridgeReviewTreesPanel
				onSelectItem={() => undefined}
				projection={projection}
				reviewPackage={reviewPackage}
				searchOpen={false}
				searchText=""
				selectedItemId="source-high"
			/>,
		);
	});
}
