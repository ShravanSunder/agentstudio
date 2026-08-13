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
	ComboboxList,
} from '../components/ui/combobox.js';
import { Field, FieldTitle } from '../components/ui/field.js';
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
		<div className="col-span-2 grid grid-cols-subgrid gap-y-2">
			<Field
				className="col-span-2 grid grid-cols-subgrid items-center gap-x-3 px-1"
				orientation="horizontal"
			>
				<FieldTitle className="text-muted-foreground">
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
					className="col-span-2 overflow-hidden rounded-md border border-input bg-input/20 transition-colors focus-within:border-ring"
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
								className="rounded-none border-x-0 border-t-0 border-b border-border bg-transparent"
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
									className="border-t border-border px-2 py-2 text-xs/relaxed text-muted-foreground"
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
		<Alert className="flex flex-col items-center gap-2 rounded-none border-0 bg-transparent px-3 py-4 text-muted-foreground">
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
		<div
			className="max-h-56 overflow-y-auto"
			data-testid="bridge-review-comparison-branch-scroll"
			ref={scrollElementRef}
		>
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
							key={branchTargetKey(branch)}
							ref={virtualizer.measureElement}
							style={{ transform: `translateY(${virtualRow.start}px)` }}
							value={branch}
						>
							<span className="flex min-w-0 flex-1 flex-col gap-0.5">
								<span className="truncate text-foreground">{branchTargetLabel(branch)}</span>
								<span className="flex min-w-0 items-baseline gap-1.5 text-xs/relaxed text-muted-foreground">
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
		<code className="font-mono text-muted-foreground" title={props.value}>
			<span aria-hidden="true">{props.value.slice(0, 12)}</span>
			<span className="sr-only">{props.value}</span>
		</code>
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
