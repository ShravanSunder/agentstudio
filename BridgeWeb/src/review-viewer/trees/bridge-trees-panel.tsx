import type { FileTreeSortComparator } from '@pierre/trees';
import { FileTree, useFileTree } from '@pierre/trees/react';
import type { CSSProperties, ReactElement } from 'react';
import { useCallback, useEffect, useMemo, useRef } from 'react';

import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import { BridgeTreesController, createBridgeTreesSource } from './bridge-trees-controller.js';

const preserveInputOrderSort: FileTreeSortComparator = () => 0;
const bridgeReviewTreeInitialVisibleRowCount = 24;
const bridgeReviewTreeOverscan = 10;

type BridgeReviewTreeStyle = CSSProperties &
	Record<
		| '--trees-bg-override'
		| '--trees-fg-override'
		| '--trees-fg-muted-override'
		| '--trees-bg-muted-override'
		| '--trees-search-fg-override'
		| '--trees-search-bg-override'
		| '--trees-border-color-override'
		| '--trees-selected-fg-override'
		| '--trees-selected-bg-override'
		| '--trees-selected-focused-border-color-override'
		| '--trees-focus-ring-color-override'
		| '--trees-padding-inline-override'
		| '--trees-git-renamed-color-override',
		number | string
	>;

const bridgeReviewTreeStyle: BridgeReviewTreeStyle = {
	colorScheme: 'dark',
	display: 'block',
	height: '100%',
	'--trees-bg-override': 'var(--bridge-surface-bg)',
	'--trees-fg-override': 'var(--bridge-text-primary)',
	'--trees-fg-muted-override': 'var(--bridge-text-muted)',
	'--trees-bg-muted-override': 'var(--bridge-surface-raised-bg)',
	'--trees-search-fg-override': 'var(--bridge-text-primary)',
	'--trees-search-bg-override': 'var(--bridge-canvas-bg)',
	'--trees-border-color-override': 'var(--bridge-border-subtle)',
	'--trees-selected-fg-override': 'var(--bridge-text-primary)',
	'--trees-selected-bg-override': 'color-mix(in oklch, var(--bridge-accent) 18%, transparent)',
	'--trees-selected-focused-border-color-override':
		'color-mix(in oklch, var(--bridge-accent) 82%, white 8%)',
	'--trees-focus-ring-color-override': 'var(--bridge-accent)',
	'--trees-padding-inline-override': 8,
	'--trees-git-renamed-color-override': 'var(--bridge-accent)',
};

const bridgeReviewTreeUnsafeCSS = `
  [data-file-tree-virtualized-scroll="true"] {
    padding-inline-start: 0;
    padding-inline-end: 2px;
    margin-inline-end: 2px;
  }

  [data-file-tree-search-container][data-open='false'] {
    display: none;
  }

  [data-file-tree-search-container] {
    margin: 0 4px 8px 0;
    padding: 0 4px 8px 1px;
    border-bottom: 1px solid var(--bridge-border-subtle);
  }

  [data-file-tree-sticky-overlay-content] {
    box-shadow: 0 2px 4px -4px rgb(0 0 0 / 90%);
  }

  [data-item-type='folder'] {
    color: var(--bridge-text-primary);
    font-weight: 500;
  }
`;

export interface BridgeReviewTreesPanelProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly projection: BridgeReviewProjectionResult;
	readonly selectedItemId: string | null;
	readonly searchText: string;
	readonly onSelectItem: (itemId: string) => void;
}

export function BridgeReviewTreesPanel(props: BridgeReviewTreesPanelProps): ReactElement {
	const source = useMemo(
		() =>
			createBridgeTreesSource({
				reviewPackage: props.reviewPackage,
				projection: props.projection,
			}),
		[props.projection, props.reviewPackage],
	);
	const sourceRef = useRef(source);
	sourceRef.current = source;
	const initialSourceRef = useRef(source);
	const onSelectItemRef = useRef(props.onSelectItem);
	onSelectItemRef.current = props.onSelectItem;
	const onSelectionChange = useCallback((selectedPaths: readonly string[]): void => {
		if (selectedPaths.length !== 1) {
			return;
		}
		const [path] = selectedPaths;
		if (path === undefined) {
			return;
		}
		const itemId = sourceRef.current.primaryItemIdByTreePath[path];
		if (itemId !== undefined) {
			onSelectItemRef.current(itemId);
		}
	}, []);
	const { model } = useFileTree({
		paths: initialSourceRef.current.orderedPaths,
		preparedInput: initialSourceRef.current.preparedInput,
		initialExpandedPaths: initialSourceRef.current.initialExpandedPaths,
		gitStatus: initialSourceRef.current.gitStatusEntries,
		sort: preserveInputOrderSort,
		search: true,
		fileTreeSearchMode: 'expand-matches',
		flattenEmptyDirectories: true,
		density: 'compact',
		initialVisibleRowCount: bridgeReviewTreeInitialVisibleRowCount,
		overscan: bridgeReviewTreeOverscan,
		onSelectionChange,
		stickyFolders: true,
		unsafeCSS: bridgeReviewTreeUnsafeCSS,
	});
	const controllerRef = useRef<BridgeTreesController | null>(null);
	controllerRef.current ??= new BridgeTreesController({ model });

	useEffect((): void => {
		const updatePlan = controllerRef.current?.applySource(source);
		if (updatePlan?.kind !== 'appendOnly') {
			return;
		}
		const controller = controllerRef.current;
		const pathsToReveal = updatePlan.addedPaths;
		const revealAppendedPathAncestors = (): void => {
			for (const path of pathsToReveal) {
				controller?.revealTreePathAncestors(path);
			}
		};
		revealAppendedPathAncestors();
		queueMicrotask(revealAppendedPathAncestors);
		requestAnimationFrame(revealAppendedPathAncestors);
		setTimeout(revealAppendedPathAncestors, 0);
	}, [source]);

	useEffect((): void => {
		if (props.searchText.length === 0) {
			model.setSearch(null);
			model.closeSearch();
			return;
		}
		model.openSearch(props.searchText);
		model.setSearch(props.searchText);
	}, [model, props.searchText]);

	useEffect((): void => {
		if (props.selectedItemId === null) {
			return;
		}
		const path = props.projection.primaryDisplayPathByItemId[props.selectedItemId];
		if (path === undefined) {
			return;
		}
		controllerRef.current?.selectTreePath(path);
		model.getItem(path)?.select();
	}, [model, props.projection, props.selectedItemId]);

	return (
		<div
			aria-label="Review file tree"
			className="h-full min-h-0 overflow-hidden bg-[var(--bridge-surface-bg)] text-[var(--bridge-text-secondary)]"
			data-testid="bridge-review-trees-panel"
		>
			<FileTree model={model} style={bridgeReviewTreeStyle} />
		</div>
	);
}
