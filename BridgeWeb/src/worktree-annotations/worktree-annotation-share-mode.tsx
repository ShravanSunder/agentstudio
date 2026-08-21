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

export type WorktreeAnnotationShareScope = 'new' | 'all';

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
	readonly allCount: number;
	readonly error: string | null;
	readonly isOutputPending: boolean;
	readonly newCount: number;
	readonly onCopy: (scope: WorktreeAnnotationShareScope) => void;
	readonly onDone: () => void;
	readonly onExport: (scope: WorktreeAnnotationShareScope) => void;
	readonly onScopeChange: (scope: WorktreeAnnotationShareScope) => void;
	readonly scope: WorktreeAnnotationShareScope;
}): ReactElement {
	const displayedCount = props.scope === 'new' ? props.newCount : props.allCount;
	const outputDisabled = displayedCount === 0 || props.isOutputPending;
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
						if (nextScope === 'new' || nextScope === 'all') props.onScopeChange(nextScope);
					}}
					className={bridgeViewerChromeSegmentedControlClassName}
					role="group"
					size="sm"
					spacing={0}
					value={[props.scope]}
					variant="default"
				>
					<ToggleGroupItem
						aria-label={`New comments, ${props.newCount}`}
						className={bridgeViewerChromeSegmentButtonClassName}
						value="new"
					>
						New ({props.newCount})
					</ToggleGroupItem>
					<ToggleGroupItem
						aria-label={`All comments, ${props.allCount}`}
						className={bridgeViewerChromeSegmentButtonClassName}
						value="all"
					>
						All ({props.allCount})
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
