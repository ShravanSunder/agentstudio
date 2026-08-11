import { Combobox as ComboboxPrimitive } from '@base-ui/react/combobox';
import { useVirtualizer } from '@tanstack/react-virtual';
import { CheckIcon } from 'lucide-react';
import { useEffect, useRef, useState, type ReactElement, type RefObject } from 'react';

import {
	Combobox,
	ComboboxEmpty,
	ComboboxInput,
	ComboboxItem,
	ComboboxList,
} from '../components/ui/combobox.js';
import type {
	BridgeProductReviewComparisonBranchTarget,
	BridgeProductReviewComparisonTargetCatalog,
} from '../core/comm-worker/bridge-product-review-comparison-contracts.js';
import type {
	BridgeWorkerPanelChromePatchPayload,
	BridgeWorkerReviewComparisonUpdateCommand,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeReviewComparisonTargetsQueryState } from './bridge-app-review-render-snapshot-controller.js';
import { cn } from './class-name.js';

type ReviewComparisonPresentation = NonNullable<
	BridgeWorkerPanelChromePatchPayload['reviewComparison']
>;
type ReviewComparisonTarget = NonNullable<ReviewComparisonPresentation['activeTarget']>;
type ReviewComparisonBranchTarget = BridgeProductReviewComparisonBranchTarget;

export function BridgeReviewComparisonBranchSelector(props: {
	readonly activeTarget: ReviewComparisonTarget | null;
	readonly onSelectTarget: (target: BridgeWorkerReviewComparisonUpdateCommand['target']) => void;
	readonly onRetry: () => void;
	readonly searchInputRef: RefObject<HTMLInputElement | null>;
	readonly targetQueryState: BridgeReviewComparisonTargetsQueryState;
}): ReactElement {
	const [search, setSearch] = useState('');
	const targetCatalog =
		props.targetQueryState.status === 'ready' || props.targetQueryState.status === 'empty'
			? props.targetQueryState.catalog
			: null;
	const selectedBranch =
		targetCatalog?.branches.find((branch) => branchMatchesTarget(branch, props.activeTarget)) ??
		null;
	const [highlightedBranch, setHighlightedBranch] = useState<ReviewComparisonBranchTarget | null>(
		null,
	);
	const [filteredBranchCount, setFilteredBranchCount] = useState(
		targetCatalog?.branches.length ?? 0,
	);
	return (
		<Combobox<ReviewComparisonBranchTarget>
			items={targetCatalog?.branches ?? []}
			inputValue={search}
			isItemEqualToValue={branchTargetsEqual}
			itemToStringLabel={branchTargetLabel}
			onItemHighlighted={(branch): void => setHighlightedBranch(branch ?? null)}
			onInputValueChange={setSearch}
			onValueChange={(branch): void => {
				if (branch !== null) {
					props.onSelectTarget(comparisonTargetForBranch(branch));
				}
			}}
			open={true}
			virtualized
			value={selectedBranch}
		>
			<div
				className="overflow-hidden rounded-md border border-[var(--bridge-border-opaque)] bg-[var(--bridge-header-control-bg)] transition-colors focus-within:border-[var(--bridge-focus-border)]"
				data-testid="bridge-review-comparison-branch-selector"
			>
				<ComboboxInput
					aria-label="Search branches"
					className="rounded-none border-x-0 border-t-0 border-b border-[var(--bridge-border-subtle)] bg-transparent"
					placeholder="Search branches…"
					ref={props.searchInputRef}
				/>
				<VirtualizedBranchOptions
					highlightedBranch={highlightedBranch}
					onFilteredItemCountChange={setFilteredBranchCount}
					selectedBranch={selectedBranch}
					targetCatalog={targetCatalog}
				/>
				{targetCatalog === null ? null : (
					<p
						className="border-t border-[var(--bridge-border-subtle)] px-2 py-2 text-[10px] leading-relaxed text-[var(--bridge-text-muted)]"
						data-testid="bridge-review-comparison-catalog-explanation"
					>
						Showing branches updated in the previous 30 days, from{' '}
						{formatCatalogDate(targetCatalog.cutoffUnixMilliseconds)} through{' '}
						{formatCatalogDate(targetCatalog.capturedAtUnixMilliseconds)}. The default and current
						targets are retained when available.
						{targetCatalog.isTruncated
							? ' This list is limited by capacity; exact commit entry remains available for a pinned comparison.'
							: ''}
					</p>
				)}
				{props.targetQueryState.status === 'empty' ||
				(props.targetQueryState.status === 'ready' && filteredBranchCount === 0) ? (
					<ComboboxEmpty>
						{props.targetQueryState.status === 'empty'
							? props.targetQueryState.message
							: 'No matching branches.'}
					</ComboboxEmpty>
				) : null}
				{props.targetQueryState.status === 'loading' ? (
					<ComboboxEmpty>Loading branch choices…</ComboboxEmpty>
				) : null}
				{props.targetQueryState.status === 'failed' ? (
					<ComboboxEmpty>
						<span>{props.targetQueryState.message}</span>
						<button className="mt-2 underline" onClick={props.onRetry} type="button">
							Retry
						</button>
					</ComboboxEmpty>
				) : null}
			</div>
		</Combobox>
	);
}

function VirtualizedBranchOptions(props: {
	readonly highlightedBranch: ReviewComparisonBranchTarget | null;
	readonly onFilteredItemCountChange: (count: number) => void;
	readonly selectedBranch: ReviewComparisonBranchTarget | null;
	readonly targetCatalog: BridgeProductReviewComparisonTargetCatalog | null;
}): ReactElement {
	const { onFilteredItemCountChange } = props;
	const filteredBranches = ComboboxPrimitive.useFilteredItems<ReviewComparisonBranchTarget>();
	const scrollElementRef = useRef<HTMLDivElement>(null);
	const virtualizer = useVirtualizer({
		count: filteredBranches.length,
		getScrollElement: (): HTMLDivElement | null => scrollElementRef.current,
		estimateSize: (): number => 44,
		overscan: 8,
	});
	const virtualRows = virtualizer.getVirtualItems();
	useEffect((): void => {
		onFilteredItemCountChange(filteredBranches.length);
	}, [filteredBranches.length, onFilteredItemCountChange]);
	useEffect((): void => {
		if (props.highlightedBranch === null) return;
		const highlightedIndex = filteredBranches.findIndex((branch) =>
			branchTargetsEqual(branch, props.highlightedBranch),
		);
		if (highlightedIndex >= 0) virtualizer.scrollToIndex(highlightedIndex, { align: 'auto' });
	}, [filteredBranches, props.highlightedBranch, virtualizer]);
	return (
		<div className="max-h-56 overflow-y-auto" ref={scrollElementRef}>
			<ComboboxList
				className="relative m-0 max-h-none overflow-visible py-1"
				style={{ height: `${virtualizer.getTotalSize()}px` }}
			>
				{virtualRows.map((virtualRow) => {
					const branch = filteredBranches[virtualRow.index];
					if (branch === undefined) return null;
					return (
						<ComboboxItem
							className="absolute left-0 top-0 w-full"
							data-index={virtualRow.index}
							data-testid={`comparison-branch-${branchTargetTestId(branch)}`}
							index={virtualRow.index}
							key={branchTargetKey(branch)}
							ref={virtualizer.measureElement}
							style={{ transform: `translateY(${virtualRow.start}px)` }}
							value={branch}
						>
							<CheckIcon
								aria-hidden="true"
								className={cn(
									'mr-2 size-3 shrink-0',
									branchTargetsEqual(branch, props.selectedBranch) ? 'opacity-100' : 'opacity-0',
								)}
							/>
							<span className="flex min-w-0 flex-1 flex-col gap-0.5">
								<span className="truncate text-[var(--bridge-text-primary)]">
									{branchTargetLabel(branch)}
								</span>
								<span className="flex min-w-0 items-baseline gap-1.5 text-[10px] text-[var(--bridge-text-muted)]">
									{branchTargetsEqual(branch, props.targetCatalog?.defaultTarget ?? null) ? (
										<span className="font-medium">Default</span>
									) : null}
									{branchTargetsEqual(branch, props.targetCatalog?.currentTarget ?? null) ? (
										<span className="font-medium">Current</span>
									) : null}
									<span>{branch.kind === 'local' ? 'Local' : 'Remote-tracking'}</span>
									<span aria-hidden="true">·</span>
									<BranchRevision value={branch.oid} />
								</span>
							</span>
						</ComboboxItem>
					);
				})}
			</ComboboxList>
		</div>
	);
}

function BranchRevision(props: { readonly value: string }): ReactElement {
	return (
		<code className="font-mono text-[var(--bridge-text-secondary)]" title={props.value}>
			<span aria-hidden="true">{props.value.slice(0, 12)}</span>
			<span className="sr-only">{props.value}</span>
		</code>
	);
}

function comparisonTargetForBranch(
	branch: ReviewComparisonBranchTarget,
): BridgeWorkerReviewComparisonUpdateCommand['target'] {
	if (branch.kind === 'local') {
		return { basis: 'commonCommit', kind: 'branch', name: branch.branchName };
	}
	return {
		basis: 'commonCommit',
		branchName: branch.branchName,
		kind: 'originDefaultBranch',
		remoteName: branch.remoteName,
	};
}

function branchMatchesTarget(
	branch: ReviewComparisonBranchTarget,
	target: ReviewComparisonTarget | null,
): boolean {
	if (target === null) return false;
	if (branch.kind === 'local') {
		return (
			(target.kind === 'branch' && target.name === branch.branchName) ||
			(target.kind === 'localDefaultBranch' && target.branchName === branch.branchName)
		);
	}
	return (
		(target.kind === 'originDefaultBranch' &&
			target.remoteName === branch.remoteName &&
			target.branchName === branch.branchName) ||
		(target.kind === 'ref' && target.name === branchTargetLabel(branch))
	);
}

function branchTargetsEqual(
	leftTarget: ReviewComparisonBranchTarget | null,
	rightTarget: ReviewComparisonBranchTarget | null,
): boolean {
	if (leftTarget === null || rightTarget === null || leftTarget.kind !== rightTarget.kind) {
		return false;
	}
	if (leftTarget.kind === 'local') {
		return rightTarget.kind === 'local' && leftTarget.branchName === rightTarget.branchName;
	}
	return (
		rightTarget.kind === 'remoteTracking' &&
		leftTarget.remoteName === rightTarget.remoteName &&
		leftTarget.branchName === rightTarget.branchName
	);
}

function branchTargetLabel(branch: ReviewComparisonBranchTarget): string {
	return branch.kind === 'local' ? branch.branchName : `${branch.remoteName}/${branch.branchName}`;
}

function branchTargetKey(branch: ReviewComparisonBranchTarget): string {
	return `${branch.kind}:${branchTargetLabel(branch)}`;
}

function branchTargetTestId(branch: ReviewComparisonBranchTarget): string {
	return branchTargetLabel(branch).replaceAll('/', '-');
}

function formatCatalogDate(unixMilliseconds: number): string {
	return new Date(unixMilliseconds).toISOString().slice(0, 10);
}
