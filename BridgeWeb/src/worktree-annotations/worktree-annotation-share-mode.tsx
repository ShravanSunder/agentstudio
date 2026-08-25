import { Share2 } from 'lucide-react';
import type { KeyboardEvent, ReactElement } from 'react';

import { Alert, AlertDescription } from '@/components/ui/alert.js';
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group.js';

import { BridgeViewerActionToolbar } from '../app/bridge-viewer-action-toolbar.js';
import { BridgeViewerButton, BridgeViewerIcon } from '../app/bridge-viewer-button.js';
import {
	bridgeViewerChromeSegmentButtonClassName,
	bridgeViewerChromeSegmentedControlClassName,
} from '../app/bridge-viewer-chrome.js';

export type WorktreeAnnotationShareScope = 'pending' | 'all';
export type WorktreeAnnotationShareMembership =
	| { readonly kind: 'unknown' }
	| { readonly allCount: number; readonly kind: 'ready'; readonly pendingCount: number };

export function WorktreeAnnotationShareTrigger(props: {
	readonly disabled: boolean;
	readonly onOpen: () => void;
}): ReactElement {
	return (
		<BridgeViewerButton disabled={props.disabled} onClick={props.onOpen}>
			<BridgeViewerIcon>
				<Share2 />
			</BridgeViewerIcon>
			Share comments
		</BridgeViewerButton>
	);
}

export function WorktreeAnnotationShareModeRow(props: {
	readonly error: string | null;
	readonly isOutputPending: boolean;
	readonly isOutputReady?: boolean | undefined;
	readonly membership: WorktreeAnnotationShareMembership;
	readonly onCopy: (scope: WorktreeAnnotationShareScope) => void;
	readonly onDone: () => void;
	readonly onExport: (scope: WorktreeAnnotationShareScope) => void;
	readonly onScopeChange: (scope: WorktreeAnnotationShareScope) => void;
	readonly scope: WorktreeAnnotationShareScope;
}): ReactElement {
	const displayedCount =
		props.membership.kind === 'unknown'
			? null
			: props.scope === 'pending'
				? props.membership.pendingCount
				: props.membership.allCount;
	const outputDisabled =
		displayedCount === null ||
		displayedCount === 0 ||
		props.isOutputPending ||
		props.isOutputReady === false;
	const pendingCountLabel =
		props.membership.kind === 'unknown' ? 'unknown' : String(props.membership.pendingCount);
	const allCountLabel =
		props.membership.kind === 'unknown' ? 'unknown' : String(props.membership.allCount);
	const handleKeyDown = (event: KeyboardEvent<HTMLElement>): void => {
		if (event.key !== 'Escape') return;
		event.preventDefault();
		props.onDone();
	};

	return (
		<BridgeViewerActionToolbar
			ariaLabel="Share comments"
			testId="worktree-annotation-share-mode"
			onKeyDown={handleKeyDown}
		>
			<div className="flex w-full flex-wrap items-center gap-2">
				<p className="mr-auto text-[11px] font-medium text-[var(--bridge-text-primary)]">
					Share comments
				</p>
				<ToggleGroup
					aria-label="Comments to share"
					onValueChange={(scopes): void => {
						const nextScope = scopes[0];
						if (nextScope === 'pending' || nextScope === 'all') props.onScopeChange(nextScope);
					}}
					className={bridgeViewerChromeSegmentedControlClassName}
					role="group"
					size="sm"
					spacing={0}
					value={[props.scope]}
					variant="default"
				>
					<ToggleGroupItem
						aria-label={`Pending comments, ${pendingCountLabel}`}
						autoFocus
						className={bridgeViewerChromeSegmentButtonClassName}
						value="pending"
					>
						Pending ({props.membership.kind === 'unknown' ? '—' : props.membership.pendingCount})
					</ToggleGroupItem>
					<ToggleGroupItem
						aria-label={`All comments, ${allCountLabel}`}
						className={bridgeViewerChromeSegmentButtonClassName}
						value="all"
					>
						All ({props.membership.kind === 'unknown' ? '—' : props.membership.allCount})
					</ToggleGroupItem>
				</ToggleGroup>
				<div className="flex items-center gap-1">
					<BridgeViewerButton disabled={outputDisabled} onClick={() => props.onCopy(props.scope)}>
						{props.isOutputPending ? 'Working…' : 'Copy Markdown'}
					</BridgeViewerButton>
					<BridgeViewerButton disabled={outputDisabled} onClick={() => props.onExport(props.scope)}>
						Export JSON
					</BridgeViewerButton>
					<BridgeViewerButton disabled={props.isOutputPending} onClick={props.onDone}>
						Done
					</BridgeViewerButton>
				</div>
			</div>
			{props.error === null ? null : (
				<Alert className="mt-2" variant="destructive">
					<AlertDescription>{props.error}</AlertDescription>
				</Alert>
			)}
		</BridgeViewerActionToolbar>
	);
}
