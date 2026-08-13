import {
	GitBranchIcon,
	GitCommitIcon,
	GitCompareIcon,
	GitMergeIcon,
	type OcticonProps,
} from '@primer/octicons-react';
import type { ReactElement } from 'react';

export type BridgeReviewComparisonIconKind =
	| 'branch-basis'
	| 'current-branch'
	| 'effective-commit'
	| 'trigger'
	| 'target-kind';

const comparisonIconProps = {
	'aria-hidden': true,
	className: 'size-3.5 shrink-0 text-muted-foreground',
	size: 14,
} satisfies OcticonProps;

export function BridgeReviewComparisonIcon(props: {
	readonly kind: BridgeReviewComparisonIconKind;
}): ReactElement {
	switch (props.kind) {
		case 'branch-basis':
			return (
				<GitMergeIcon
					{...comparisonIconProps}
					data-testid="bridge-review-comparison-branch-basis-icon"
				/>
			);
		case 'current-branch':
			return (
				<GitBranchIcon
					{...comparisonIconProps}
					data-testid="bridge-review-comparison-current-branch-icon"
				/>
			);
		case 'effective-commit':
			return (
				<GitCommitIcon
					{...comparisonIconProps}
					data-testid="bridge-review-comparison-effective-commit-icon"
				/>
			);
		case 'target-kind':
			return (
				<GitCompareIcon
					{...comparisonIconProps}
					data-testid="bridge-review-comparison-target-kind-icon"
				/>
			);
		case 'trigger':
			return (
				<GitCompareIcon
					{...comparisonIconProps}
					data-testid="bridge-review-comparison-trigger-icon"
				/>
			);
	}
	return assertNeverComparisonIconKind(props.kind);
}

function assertNeverComparisonIconKind(iconKind: never): never {
	throw new Error(`Unhandled comparison icon kind: ${String(iconKind)}`);
}
