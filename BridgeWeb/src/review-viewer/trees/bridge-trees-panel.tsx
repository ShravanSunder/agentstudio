import type { FileTreeSortComparator } from '@pierre/trees';
import { FileTree, useFileTree } from '@pierre/trees/react';
import type { ReactElement } from 'react';
import { useCallback, useEffect, useMemo, useRef } from 'react';

import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import { bridgeReviewTreeStyle, bridgeReviewTreeUnsafeCSS } from './bridge-tree-theme.js';
import { BridgeTreesController, createBridgeTreesSource } from './bridge-trees-controller.js';

const preserveInputOrderSort: FileTreeSortComparator = () => 0;
const bridgeReviewTreeInitialVisibleRowCount = 24;
const bridgeReviewTreeOverscan = 10;

export interface BridgeReviewTreesPanelProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly projection: BridgeReviewProjectionResult;
	readonly selectedItemId: string | null;
	readonly searchOpen: boolean;
	readonly searchText: string;
	readonly onSelectItem: (itemId: string) => void;
	readonly onSearchTextChange?: (searchText: string) => void;
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
	const onSearchTextChangeRef = useRef(props.onSearchTextChange);
	onSearchTextChangeRef.current = props.onSearchTextChange;
	const searchTextRef = useRef(props.searchText);
	searchTextRef.current = props.searchText;
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
	const onSearchChange = useCallback((value: string | null): void => {
		const nextSearchText = value ?? '';
		if (searchTextRef.current === nextSearchText) {
			return;
		}
		onSearchTextChangeRef.current?.(nextSearchText);
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
		onSearchChange,
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
		if (!props.searchOpen) {
			model.setSearch(null);
			model.closeSearch();
			return;
		}
		model.openSearch(props.searchText);
		if (props.searchText.length > 0) {
			model.setSearch(props.searchText);
			const matchedPath = firstBridgeTreeSearchMatchPath({
				orderedPaths: sourceRef.current.orderedPaths,
				searchText: props.searchText,
			});
			if (matchedPath !== null) {
				controllerRef.current?.revealTreePath(matchedPath);
			}
		}
	}, [model, props.searchOpen, props.searchText]);

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

function firstBridgeTreeSearchMatchPath(props: {
	readonly orderedPaths: readonly string[];
	readonly searchText: string;
}): string | null {
	const normalizedSearchText = props.searchText.trim().toLocaleLowerCase();
	if (normalizedSearchText.length === 0) {
		return null;
	}
	return (
		props.orderedPaths.find((path: string): boolean =>
			path.toLocaleLowerCase().includes(normalizedSearchText),
		) ?? null
	);
}
