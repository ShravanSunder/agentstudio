import { CheckIcon } from 'lucide-react';
import { useState, type ReactElement, type RefObject } from 'react';

import {
	Combobox,
	ComboboxEmpty,
	ComboboxInput,
	ComboboxItem,
	ComboboxList,
} from '../components/ui/combobox.js';
import type {
	BridgeWorkerPanelChromePatchPayload,
	BridgeWorkerReviewComparisonUpdateCommand,
} from '../core/comm-worker/bridge-worker-contracts.js';
import { cn } from './class-name.js';

type ReviewComparisonPresentation = NonNullable<
	BridgeWorkerPanelChromePatchPayload['reviewComparison']
>;
type ReviewComparisonTarget = NonNullable<ReviewComparisonPresentation['activeTarget']>;
type ReviewComparisonTargetCatalog = NonNullable<ReviewComparisonPresentation['targetCatalog']>;
type ReviewComparisonBranchTarget = ReviewComparisonTargetCatalog['branches'][number];

export function BridgeReviewComparisonBranchSelector(props: {
	readonly activeTarget: ReviewComparisonTarget | null;
	readonly onSelectTarget: (target: BridgeWorkerReviewComparisonUpdateCommand['target']) => void;
	readonly searchInputRef: RefObject<HTMLInputElement | null>;
	readonly targetCatalog: ReviewComparisonTargetCatalog | null;
}): ReactElement {
	const [search, setSearch] = useState('');
	const branches =
		props.targetCatalog?.branches.filter((branch) =>
			branchTargetLabel(branch).toLocaleLowerCase().includes(search.trim().toLocaleLowerCase()),
		) ?? [];
	const selectedBranch =
		props.targetCatalog?.branches.find((branch) =>
			branchMatchesTarget(branch, props.activeTarget),
		) ?? null;
	return (
		<Combobox<ReviewComparisonBranchTarget>
			inputValue={search}
			isItemEqualToValue={branchTargetsEqual}
			itemToStringLabel={branchTargetLabel}
			onInputValueChange={setSearch}
			onValueChange={(branch): void => {
				if (branch !== null) {
					props.onSelectTarget(comparisonTargetForBranch(branch));
				}
			}}
			open={true}
			value={selectedBranch}
		>
			<ComboboxInput
				aria-label="Search branches"
				placeholder="Search branches…"
				ref={props.searchInputRef}
			/>
			<ComboboxList>
				{branches.map((branch, index) => (
					<ComboboxItem
						data-testid={`comparison-branch-${branchTargetTestId(branch)}`}
						index={index}
						key={branchTargetKey(branch)}
						value={branch}
					>
						<CheckIcon
							aria-hidden="true"
							className={cn(
								'mr-2 size-3 shrink-0',
								branchTargetsEqual(branch, selectedBranch) ? 'opacity-100' : 'opacity-0',
							)}
						/>
						<span className="min-w-0 flex-1">
							<span className="flex items-center gap-1.5">
								<span className="truncate text-[var(--bridge-text-primary)]">
									{branchTargetLabel(branch)}
								</span>
								{branchTargetsEqual(branch, props.targetCatalog?.defaultTarget ?? null) ? (
									<span className="text-[10px] font-medium text-[var(--bridge-text-muted)]">
										DEFAULT
									</span>
								) : null}
								<span className="text-[10px] text-[var(--bridge-text-muted)]">
									{branch.kind === 'local' ? 'LOCAL' : 'REMOTE-TRACKING'}
								</span>
							</span>
							<BranchRevision value={branch.oid} />
						</span>
					</ComboboxItem>
				))}
			</ComboboxList>
			{props.targetCatalog !== null && branches.length === 0 ? (
				<ComboboxEmpty>No matching branches.</ComboboxEmpty>
			) : null}
			{props.targetCatalog === null ? (
				<ComboboxEmpty>
					Branch choices are unavailable. Refresh the review and try again.
				</ComboboxEmpty>
			) : null}
		</Combobox>
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
	if (branch.kind === 'local') return { kind: 'branch', name: branch.branchName };
	return {
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
