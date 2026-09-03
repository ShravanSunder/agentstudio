import type { CodeViewItem } from '@pierre/diffs';
import { ChevronDownIcon, ChevronRightIcon, FileCodeCornerIcon } from 'lucide-react';
import type { ReactNode } from 'react';
import { useLayoutEffect } from 'react';

import {
	bridgeViewerChromeCompactMetadataClassName,
	bridgeViewerChromeIconButtonClassName,
	bridgeViewerChromeLucideIconClassName,
} from '../../app/bridge-viewer-chrome.js';
import { cn } from '../../app/class-name.js';
import { Button } from '../../components/ui/button.js';
import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import { isBridgeCodeViewItem } from './bridge-code-view-panel-support.js';

interface BridgeCodeViewHeaderRenderers {
	readonly renderHeaderMetadata: (item: CodeViewItem) => ReactNode;
	readonly renderHeaderPrefix: (item: CodeViewItem) => ReactNode;
}

interface CreateBridgeCodeViewHeaderRenderersProps {
	readonly collapsedItemIds: ReadonlySet<string>;
	readonly onHeaderVisibilityChange: (itemId: string, isVisible: boolean) => void;
	readonly onToggleItemCollapse: (itemId: string) => void;
	readonly onOpenFile: ((path: string) => void) | undefined;
	readonly reviewPackage: BridgeReviewPackage;
}

export function createBridgeCodeViewHeaderRenderers(
	props: CreateBridgeCodeViewHeaderRenderersProps,
): BridgeCodeViewHeaderRenderers {
	return {
		renderHeaderPrefix: (item: CodeViewItem): ReactNode =>
			renderBridgeCodeViewHeaderPrefix({ ...props, item }),
		renderHeaderMetadata: (item: CodeViewItem): ReactNode =>
			renderBridgeCodeViewHeaderMetadata({ ...props, item }),
	};
}

interface RenderBridgeCodeViewHeaderProps extends CreateBridgeCodeViewHeaderRenderersProps {
	readonly item: CodeViewItem;
}

function renderBridgeCodeViewHeaderPrefix(props: RenderBridgeCodeViewHeaderProps): ReactNode {
	const descriptor = bridgeReviewItemForCodeViewItem(props);
	if (descriptor === null || !isBridgeCodeViewItem(props.item)) return null;
	const itemId = props.item.bridgeMetadata.itemId;
	const collapsed = props.collapsedItemIds.has(itemId) || props.item.collapsed === true;
	return (
		<span className="ml-[-2px] inline-flex items-center">
			<BridgeCodeViewVisibleHeaderReporter
				itemId={itemId}
				onHeaderVisibilityChange={props.onHeaderVisibilityChange}
			/>
			<Button
				aria-expanded={!collapsed}
				aria-label={collapsed ? 'Expand file' : 'Collapse file'}
				className={cn(
					bridgeViewerChromeIconButtonClassName,
					'cursor-pointer text-[var(--bridge-text-secondary)] transition-colors',
					'aria-expanded:bg-transparent aria-expanded:text-[var(--bridge-text-secondary)]',
					'hover:border-[var(--bridge-border-opaque)] hover:bg-[var(--bridge-list-hover-bg)] hover:text-[var(--bridge-text-primary)]',
					'focus-visible:border-[var(--bridge-focus-border)] focus-visible:outline-none',
				)}
				data-bridge-code-view-item-id={itemId}
				data-testid="bridge-code-view-header-collapse-button"
				onClick={(event): void => {
					event.preventDefault();
					event.stopPropagation();
					props.onToggleItemCollapse(itemId);
				}}
				size="icon-sm"
				type="button"
				variant="ghost"
			>
				{collapsed ? (
					<ChevronRightIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
				) : (
					<ChevronDownIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
				)}
			</Button>
		</span>
	);
}

function BridgeCodeViewVisibleHeaderReporter(props: {
	readonly itemId: string;
	readonly onHeaderVisibilityChange: (itemId: string, isVisible: boolean) => void;
}): null {
	const { itemId, onHeaderVisibilityChange } = props;
	useLayoutEffect((): (() => void) => {
		onHeaderVisibilityChange(itemId, true);
		return (): void => onHeaderVisibilityChange(itemId, false);
	}, [itemId, onHeaderVisibilityChange]);
	return null;
}

function renderBridgeCodeViewHeaderMetadata(props: RenderBridgeCodeViewHeaderProps): ReactNode {
	const descriptor = bridgeReviewItemForCodeViewItem(props);
	if (descriptor === null || !isBridgeCodeViewItem(props.item)) return null;
	const contentState = props.item.bridgeMetadata.contentState;
	const pendingContentLabel =
		contentState === 'placeholder'
			? 'Waiting for content'
			: contentState === 'loading'
				? 'Loading content'
				: null;
	const filePath = descriptor.headPath ?? null;
	return (
		<span
			className={cn(
				bridgeViewerChromeCompactMetadataClassName,
				'ml-auto inline-flex min-w-0 items-center gap-2 text-[var(--bridge-text-muted)]',
			)}
			data-bridge-code-view-content-state={contentState}
			data-testid="bridge-code-view-header-metadata"
		>
			{pendingContentLabel === null ? null : (
				<span className="shrink-0">{pendingContentLabel}</span>
			)}
			<span className="shrink-0 text-[var(--bridge-deleted)]">{`-${descriptor.deletions}`}</span>
			<span className="shrink-0 text-[var(--bridge-added)]">{`+${descriptor.additions}`}</span>
			{props.onOpenFile === undefined || filePath === null ? null : (
				<Button
					aria-label={`Open ${filePath} in Files`}
					data-bridge-code-view-file-path={filePath}
					data-testid="bridge-code-view-open-file-button"
					onClick={(event): void => {
						event.preventDefault();
						event.stopPropagation();
						props.onOpenFile?.(filePath);
					}}
					size="icon"
					title="Open in Files"
					type="button"
					variant="ghost"
				>
					<FileCodeCornerIcon aria-hidden="true" />
				</Button>
			)}
		</span>
	);
}

function bridgeReviewItemForCodeViewItem(
	props: RenderBridgeCodeViewHeaderProps,
): BridgeReviewPackage['itemsById'][string] | null {
	if (!isBridgeCodeViewItem(props.item)) return null;
	return props.reviewPackage.itemsById[props.item.bridgeMetadata.itemId] ?? null;
}
