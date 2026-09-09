import { Copy, FileJson2, List, ListFilter, Share2, X } from 'lucide-react';
import type { MouseEvent, ReactElement, ReactNode, Ref } from 'react';

import { Alert, AlertDescription } from '@/components/ui/alert.js';
import { Button } from '@/components/ui/button.js';
import {
	DrawerBody,
	DrawerFooter,
	DrawerHeader,
	DrawerTitle,
	DrawerTrigger,
} from '@/components/ui/drawer.js';
import { Field, FieldTitle } from '@/components/ui/field.js';
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group.js';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip.js';

import { BridgeViewerButton, BridgeViewerIcon } from '../app/bridge-viewer-button.js';
export type WorktreeAnnotationShareScope = 'pending' | 'all';
export type WorktreeAnnotationShareMembership =
	| { readonly kind: 'unknown' }
	| { readonly allCount: number; readonly kind: 'ready'; readonly pendingCount: number };

export function WorktreeAnnotationShareTrigger(props: {
	readonly buttonRef: Ref<HTMLButtonElement>;
	readonly disabled: boolean;
	readonly open: boolean;
}): ReactElement {
	return (
		<Tooltip>
			<DrawerTrigger
				render={
					<TooltipTrigger
						render={
							<BridgeViewerButton
								ariaLabel="Share comments"
								ariaPressed={props.open}
								buttonRef={props.buttonRef}
								size="icon-sm"
								data-tooltip="Share comments"
								disabled={props.disabled}
							/>
						}
					/>
				}
			>
				<BridgeViewerIcon>
					<Share2 aria-hidden="true" />
				</BridgeViewerIcon>
			</DrawerTrigger>
			<TooltipContent side="bottom">Share comments</TooltipContent>
		</Tooltip>
	);
}

export function WorktreeAnnotationShareModeRow(props: {
	readonly children?: ReactNode | undefined;
	readonly error: string | null;
	readonly history: ReactNode;
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
	return (
		<section
			aria-label="Share comments"
			className="flex h-full min-h-0 flex-col"
			data-testid="worktree-annotation-share-mode"
		>
			<DrawerHeader>
				<div className="flex items-center justify-between gap-2">
					<DrawerTitle>Share annotations</DrawerTitle>
					<WorktreeAnnotationShareActionButton
						ariaLabel="Close Share comments"
						size="icon-sm"
						disabled={props.isOutputPending}
						onClick={props.onDone}
						tooltip="Close Share comments (Esc)"
					>
						<BridgeViewerIcon>
							<X aria-hidden="true" />
						</BridgeViewerIcon>
					</WorktreeAnnotationShareActionButton>
				</div>
			</DrawerHeader>
			<DrawerBody>
				<Field>
					<FieldTitle>Include</FieldTitle>
					<ToggleGroup
						aria-label="Comments to share"
						onValueChange={(scopes): void => {
							const nextScope = scopes[0];
							if (nextScope === 'pending' || nextScope === 'all') props.onScopeChange(nextScope);
						}}
						className="grid w-full grid-cols-2"
						role="group"
						size="sm"
						value={[props.scope]}
						variant="segmented"
					>
						<ToggleGroupItem
							aria-label={`Pending comments, ${pendingCountLabel}`}
							autoFocus
							className="w-full"
							value="pending"
						>
							<ListFilter aria-hidden="true" />
							Pending {props.membership.kind === 'unknown' ? '—' : props.membership.pendingCount}
						</ToggleGroupItem>
						<ToggleGroupItem
							aria-label={`All comments, ${allCountLabel}`}
							className="w-full"
							value="all"
						>
							<List aria-hidden="true" />
							All {props.membership.kind === 'unknown' ? '—' : props.membership.allCount}
						</ToggleGroupItem>
					</ToggleGroup>
				</Field>
				{props.error === null ? null : (
					<Alert className="mt-4" variant="destructive">
						<AlertDescription>{props.error}</AlertDescription>
					</Alert>
				)}
				{props.children}
				{props.history}
			</DrawerBody>
			<DrawerFooter>
				<WorktreeAnnotationDrawerActionButton
					ariaLabel="Copy Markdown"
					disabled={outputDisabled}
					onClick={() => props.onCopy(props.scope)}
					tooltip={`Copy ${props.scope} comments as Markdown`}
				>
					<Copy aria-hidden="true" data-icon="inline-start" />
					{props.isOutputPending ? 'Working…' : 'Copy'}
				</WorktreeAnnotationDrawerActionButton>
				<WorktreeAnnotationDrawerActionButton
					ariaLabel="Export JSON"
					disabled={outputDisabled}
					onClick={() => props.onExport(props.scope)}
					tooltip={`Export ${props.scope} comments as JSON`}
				>
					<FileJson2 aria-hidden="true" data-icon="inline-start" />
					Export
				</WorktreeAnnotationDrawerActionButton>
			</DrawerFooter>
		</section>
	);
}

function WorktreeAnnotationDrawerActionButton(props: {
	readonly ariaLabel: string;
	readonly children: ReactNode;
	readonly disabled: boolean;
	readonly onClick: (event: MouseEvent<HTMLButtonElement>) => void;
	readonly tooltip: string;
}): ReactElement {
	return (
		<Tooltip>
			<TooltipTrigger
				render={
					<Button
						aria-label={props.ariaLabel}
						disabled={props.disabled}
						onClick={props.onClick}
						size="sm"
						type="button"
						variant="outline"
					/>
				}
			>
				{props.children}
			</TooltipTrigger>
			<TooltipContent side="left">{props.tooltip}</TooltipContent>
		</Tooltip>
	);
}

function WorktreeAnnotationShareActionButton(props: {
	readonly ariaLabel: string;
	readonly children: ReactNode;
	readonly size?: 'icon-sm' | undefined;
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
						size={props.size ?? 'icon-sm'}
					/>
				}
			>
				{props.children}
			</TooltipTrigger>
			<TooltipContent side="bottom">{props.tooltip}</TooltipContent>
		</Tooltip>
	);
}
