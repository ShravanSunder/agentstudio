import { Combobox as ComboboxPrimitive } from '@base-ui/react/combobox';
import { useVirtualizer } from '@tanstack/react-virtual';
import { RotateCcwIcon, TriangleAlertIcon } from 'lucide-react';
import { useEffect, useRef, useState, type ReactElement, type RefObject } from 'react';

import { Alert } from '../components/ui/alert.js';
import { Button } from '../components/ui/button.js';
import {
	Combobox,
	ComboboxEmpty,
	ComboboxInput,
	ComboboxItem,
	ComboboxItemDescription,
	ComboboxList,
	ComboboxViewport,
} from '../components/ui/combobox.js';
import { Field, FieldTitle } from '../components/ui/field.js';
import { ItemContent, ItemLabel, ItemMetadata } from '../components/ui/item-content.js';
import { Skeleton } from '../components/ui/skeleton.js';
import { ToggleGroup, ToggleGroupItem } from '../components/ui/toggle-group.js';
import type {
	BridgeProductReviewComparisonBranchTarget,
	BridgeProductReviewComparisonTargetCatalog,
} from '../core/comm-worker/bridge-product-review-comparison-contracts.js';
import type {
	BridgeWorkerPanelChromePatchPayload,
	BridgeWorkerReviewComparisonUpdateCommand,
} from '../core/comm-worker/bridge-worker-contracts.js';
import { bridgeDesignRowMetrics } from '../design-tokens/bridge-design-row-metrics.js';
import type { BridgeReviewComparisonTargetsQueryState } from './bridge-app-review-render-snapshot-controller.js';
import { BridgeReviewComparisonIcon } from './bridge-review-comparison-icon.js';

type ReviewComparisonPresentation = NonNullable<
	BridgeWorkerPanelChromePatchPayload['reviewComparison']
>;
type ReviewComparisonTarget = NonNullable<ReviewComparisonPresentation['activeTarget']>;
type ReviewComparisonBranchTarget = BridgeProductReviewComparisonBranchTarget;
export type BridgeReviewComparisonBranchBasis = 'branchTip' | 'commonCommit';

export function BridgeReviewComparisonBranchSelector(props: {
	readonly activeTarget: ReviewComparisonTarget | null;
	readonly comparisonBasis: BridgeReviewComparisonBranchBasis;
	readonly onComparisonBasisChange: (basis: BridgeReviewComparisonBranchBasis) => void;
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
		<div className="col-span-2 grid min-h-0 grid-cols-subgrid grid-rows-[auto_minmax(0,1fr)] gap-y-2">
			<Field
				className="col-span-2 grid grid-cols-subgrid items-center gap-x-3 px-1"
				orientation="horizontal"
			>
				<FieldTitle>
					<BridgeReviewComparisonIcon kind="branch-basis" />
					<span>Using</span>
				</FieldTitle>
				<ToggleGroup
					aria-label="Branch comparison basis"
					className="grid w-full grid-cols-2"
					role="group"
					size="sm"
					spacing={0}
					value={[props.comparisonBasis]}
					variant="outline"
				>
					<ToggleGroupItem
						className="w-full"
						onPressedChange={(pressed): void => {
							if (pressed) props.onComparisonBasisChange('commonCommit');
						}}
						value="commonCommit"
					>
						Common
					</ToggleGroupItem>
					<ToggleGroupItem
						className="w-full"
						onPressedChange={(pressed): void => {
							if (pressed) props.onComparisonBasisChange('branchTip');
						}}
						value="branchTip"
					>
						Branch Tip
					</ToggleGroupItem>
				</ToggleGroup>
			</Field>
			<Combobox<ReviewComparisonBranchTarget>
				inline
				items={targetCatalog?.branches ?? []}
				inputValue={search}
				isItemEqualToValue={branchTargetsEqual}
				itemToStringLabel={branchTargetLabel}
				onItemHighlighted={(branch): void => setHighlightedBranch(branch ?? null)}
				onInputValueChange={setSearch}
				onValueChange={(branch): void => {
					if (branch !== null) {
						props.onSelectTarget(comparisonTargetForBranch(branch, props.comparisonBasis));
					}
				}}
				open={true}
				virtualized
				value={selectedBranch}
			>
				<div
					className="col-span-2 flex min-h-0 flex-col gap-2"
					data-testid="bridge-review-comparison-branch-selector"
				>
					{props.targetQueryState.status === 'failed' ? (
						<BranchOptionsFailure
							message={props.targetQueryState.message}
							onRetry={props.onRetry}
						/>
					) : (
						<>
							<ComboboxInput
								aria-label="Search branches"
								placeholder="Search branches…"
								ref={props.searchInputRef}
								showTrigger={false}
							/>
							{props.targetQueryState.status === 'loading' ? (
								<BranchOptionsSkeleton />
							) : (
								<VirtualizedBranchOptions
									highlightedBranch={highlightedBranch}
									onFilteredItemCountChange={setFilteredBranchCount}
									selectedBranch={selectedBranch}
									targetCatalog={targetCatalog}
								/>
							)}
							{targetCatalog === null ? null : (
								<p
									className="px-2 py-2 text-xs/relaxed text-muted-foreground"
									data-testid="bridge-review-comparison-catalog-explanation"
								>
									Showing branches from the last 30 days.
								</p>
							)}
							{props.targetQueryState.status === 'empty' ||
							(props.targetQueryState.status === 'ready' && filteredBranchCount === 0) ? (
								<ComboboxEmpty className="flex">
									{props.targetQueryState.status === 'empty'
										? props.targetQueryState.message
										: 'No matching branches.'}
								</ComboboxEmpty>
							) : null}
						</>
					)}
				</div>
			</Combobox>
		</div>
	);
}

function BranchOptionsFailure(props: {
	readonly message: string;
	readonly onRetry: () => void;
}): ReactElement {
	return (
		<Alert layout="inline">
			<div className="flex items-center gap-1.5">
				<TriangleAlertIcon aria-hidden="true" className="size-3.5 shrink-0" />
				<span>{props.message}</span>
			</div>
			<Button onClick={props.onRetry} size="sm" type="button" variant="outline">
				<RotateCcwIcon aria-hidden="true" data-icon="inline-start" />
				Retry
			</Button>
		</Alert>
	);
}

function BranchOptionsSkeleton(): ReactElement {
	return (
		<div
			aria-hidden="true"
			className="flex h-44 flex-col gap-2 px-3 py-3"
			data-testid="bridge-review-comparison-branch-skeleton"
		>
			<Skeleton className="h-8 w-full" />
			<Skeleton className="h-8 w-11/12" />
			<Skeleton className="h-8 w-full" />
			<Skeleton className="h-8 w-4/5" />
		</div>
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
		estimateSize: (): number => bridgeDesignRowMetrics.descriptive,
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
		<ComboboxViewport data-testid="bridge-review-comparison-branch-scroll" ref={scrollElementRef}>
			<ComboboxList
				className="relative m-0 max-h-none overflow-visible py-1"
				style={{ height: `${virtualizer.getTotalSize()}px` }}
			>
				{virtualRows.map((virtualRow) => {
					const branch = filteredBranches[virtualRow.index];
					if (branch === undefined) return null;
					return (
						<ComboboxItem
							aria-posinset={virtualRow.index + 1}
							aria-setsize={filteredBranches.length}
							className="absolute left-0 top-0 w-full"
							data-index={virtualRow.index}
							data-testid={`comparison-branch-${branchTargetTestId(branch)}`}
							index={virtualRow.index}
							presentation="descriptive"
							key={branchTargetKey(branch)}
							ref={virtualizer.measureElement}
							style={{ transform: `translateY(${virtualRow.start}px)` }}
							value={branch}
						>
							<ItemContent>
								<ItemLabel>{branchTargetLabel(branch)}</ItemLabel>
								<ComboboxItemDescription>
									{branchTargetsEqual(branch, props.targetCatalog?.defaultTarget ?? null) ? (
										<ItemMetadata emphasis="strong">Default</ItemMetadata>
									) : null}
									{branchTargetsEqual(branch, props.targetCatalog?.currentTarget ?? null) ? (
										<ItemMetadata emphasis="strong">Current</ItemMetadata>
									) : null}
									<ItemMetadata>
										{branch.kind === 'local' ? 'Local' : 'Remote-tracking'}
									</ItemMetadata>
									<span aria-hidden="true">·</span>
									<BranchRevision value={branch.oid} />
								</ComboboxItemDescription>
							</ItemContent>
						</ComboboxItem>
					);
				})}
			</ComboboxList>
		</ComboboxViewport>
	);
}

function BranchRevision(props: { readonly value: string }): ReactElement {
	return (
		<ItemMetadata font="mono" title={props.value}>
			<span aria-hidden="true">{props.value.slice(0, 12)}</span>
			<span className="sr-only">{props.value}</span>
		</ItemMetadata>
	);
}

function comparisonTargetForBranch(
	branch: ReviewComparisonBranchTarget,
	basis: 'branchTip' | 'commonCommit',
): BridgeWorkerReviewComparisonUpdateCommand['target'] {
	if (branch.kind === 'local') {
		return { basis, kind: 'branch', name: branch.branchName };
	}
	return {
		basis,
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
