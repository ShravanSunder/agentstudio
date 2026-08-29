import { Copy, FileJson2, List, Share2, X } from 'lucide-react';
import type { KeyboardEvent, MouseEvent, ReactElement, ReactNode } from 'react';

import { Alert, AlertDescription } from '@/components/ui/alert.js';
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group.js';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip.js';

import { BridgeViewerActionToolbar } from '../app/bridge-viewer-action-toolbar.js';
import { BridgeViewerButton, BridgeViewerIcon } from '../app/bridge-viewer-button.js';
import {
	bridgeViewerChromeIconButtonClassName,
	bridgeViewerChromeLucideIconClassName,
	bridgeViewerChromeSegmentButtonClassName,
	bridgeViewerChromeSegmentedControlClassName,
} from '../app/bridge-viewer-chrome.js';

const shareScopeButtonClassName = `${bridgeViewerChromeSegmentButtonClassName} data-pressed:bg-[var(--bridge-header-control-active-bg)] data-pressed:text-[var(--bridge-text-primary)] aria-pressed:bg-[var(--bridge-header-control-active-bg)] aria-pressed:text-[var(--bridge-text-primary)]`;

export type WorktreeAnnotationShareScope = 'pending' | 'all';
export type WorktreeAnnotationShareMembership =
	| { readonly kind: 'unknown' }
	| { readonly allCount: number; readonly kind: 'ready'; readonly pendingCount: number };

export function WorktreeAnnotationShareTrigger(props: {
	readonly disabled: boolean;
	readonly onOpen: () => void;
}): ReactElement {
	return (
		<Tooltip>
			<TooltipTrigger
				render={
					<BridgeViewerButton
						ariaLabel="Share comments"
						className={bridgeViewerChromeIconButtonClassName}
						data-tooltip="Share comments"
						disabled={props.disabled}
						onClick={props.onOpen}
					/>
				}
			>
				<BridgeViewerIcon>
					<Share2 aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
				</BridgeViewerIcon>
			</TooltipTrigger>
			<TooltipContent side="bottom">Share comments</TooltipContent>
		</Tooltip>
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
				<div className="mr-auto flex items-center gap-1.5 text-[11px] font-medium text-[var(--bridge-text-primary)]">
					<BridgeViewerIcon className="text-[var(--bridge-text-muted)]">
						<Share2 aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
					</BridgeViewerIcon>
					<span>Share</span>
				</div>
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
						className={shareScopeButtonClassName}
						value="pending"
					>
						<span aria-hidden="true" className="size-1.5 rounded-full bg-warning" />
						Pending {props.membership.kind === 'unknown' ? '—' : props.membership.pendingCount}
					</ToggleGroupItem>
					<ToggleGroupItem
						aria-label={`All comments, ${allCountLabel}`}
						className={shareScopeButtonClassName}
						value="all"
					>
						<List aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
						All {props.membership.kind === 'unknown' ? '—' : props.membership.allCount}
					</ToggleGroupItem>
				</ToggleGroup>
				<div className="flex items-center gap-1">
					<WorktreeAnnotationShareActionButton
						ariaLabel="Copy Markdown"
						className="bg-[var(--bridge-accent-soft)] text-[var(--bridge-accent)] hover:bg-[var(--bridge-accent-soft)] hover:text-[var(--bridge-accent)]"
						disabled={outputDisabled}
						onClick={() => props.onCopy(props.scope)}
						tooltip={`Copy ${props.scope} comments as Markdown`}
					>
						<BridgeViewerIcon>
							<Copy aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
						</BridgeViewerIcon>
						{props.isOutputPending ? 'Working…' : 'Copy'}
					</WorktreeAnnotationShareActionButton>
					<WorktreeAnnotationShareActionButton
						ariaLabel="Export JSON"
						disabled={outputDisabled}
						onClick={() => props.onExport(props.scope)}
						tooltip={`Export ${props.scope} comments as JSON`}
					>
						<BridgeViewerIcon>
							<FileJson2 aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
						</BridgeViewerIcon>
						Export
					</WorktreeAnnotationShareActionButton>
					<WorktreeAnnotationShareActionButton
						ariaLabel="Close Share comments"
						className={bridgeViewerChromeIconButtonClassName}
						disabled={props.isOutputPending}
						onClick={props.onDone}
						tooltip="Close Share comments (Esc)"
					>
						<BridgeViewerIcon>
							<X aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
						</BridgeViewerIcon>
					</WorktreeAnnotationShareActionButton>
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

function WorktreeAnnotationShareActionButton(props: {
	readonly ariaLabel: string;
	readonly children: ReactNode;
	readonly className?: string | undefined;
	readonly disabled: boolean;
	readonly onClick: (event: MouseEvent<HTMLButtonElement>) => void;
	readonly tooltip: string;
}): ReactElement {
	return (
		<Tooltip>
			<TooltipTrigger
				render={
					<BridgeViewerButton
						ariaLabel={props.ariaLabel}
						disabled={props.disabled}
						onClick={props.onClick}
						{...(props.className === undefined ? {} : { className: props.className })}
					/>
				}
			>
				{props.children}
			</TooltipTrigger>
			<TooltipContent side="bottom">{props.tooltip}</TooltipContent>
		</Tooltip>
	);
}
