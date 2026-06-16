import type { FileTreeSortComparator } from '@pierre/trees';
import { FileTree, useFileTree } from '@pierre/trees/react';
import type { ReactElement } from 'react';
import { useCallback, useEffect, useMemo, useRef } from 'react';

import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import { BridgeTreesController, createBridgeTreesSource } from './bridge-trees-controller.js';

const preserveInputOrderSort: FileTreeSortComparator = () => 0;

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
		fileTreeSearchMode: 'hide-non-matches',
		flattenEmptyDirectories: true,
		initialVisibleRowCount: 18,
		itemHeight: 28,
		overscan: 8,
		onSelectionChange,
	});
	const controllerRef = useRef<BridgeTreesController | null>(null);
	controllerRef.current ??= new BridgeTreesController({ model });

	useEffect((): void => {
		controllerRef.current?.applySource(source);
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
		const item = model.getItem(path);
		item?.select();
		model.focusPath(path);
		model.scrollToPath(path, { focus: true });
	}, [model, props.projection, props.selectedItemId]);

	return (
		<div
			aria-label="Review file tree"
			className="h-full min-h-0 overflow-hidden bg-[var(--bridge-surface-bg)] text-[var(--bridge-text-secondary)]"
			data-testid="bridge-review-trees-panel"
		>
			<FileTree model={model} />
		</div>
	);
}
