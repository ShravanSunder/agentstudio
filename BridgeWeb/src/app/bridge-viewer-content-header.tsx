import { FileTextIcon, ListChecksIcon } from 'lucide-react';
import type { ReactElement, ReactNode } from 'react';

import { ToggleGroup, ToggleGroupItem } from '../components/ui/toggle-group.js';
import {
	bridgeViewerChromeHeaderClassName,
	bridgeViewerChromeLucideIconClassName,
	bridgeViewerChromeSegmentButtonClassName,
	bridgeViewerChromeSegmentedControlClassName,
} from './bridge-viewer-chrome.js';
import { cn } from './class-name.js';

export function BridgeViewerContentHeader(props: {
	readonly controls?: ReactNode;
	readonly eyebrow: string;
	readonly statusText: string | null;
	readonly title: string;
}): ReactElement {
	return (
		<header
			className={cn(
				'flex min-w-0 items-center justify-between gap-3 px-3',
				bridgeViewerChromeHeaderClassName,
			)}
			data-bridge-viewer-content-topbar="true"
			data-testid="bridge-viewer-content-topbar"
		>
			<div className="flex min-w-0 items-baseline gap-2">
				<span className="shrink-0 text-[11px] font-medium text-[var(--bridge-text-primary)]">
					{props.eyebrow}
				</span>
				<span
					className="min-w-0 truncate text-[11px] text-[var(--bridge-text-secondary)]"
					data-testid="bridge-viewer-content-title"
				>
					{props.title}
				</span>
				{props.statusText === null ? null : (
					<span
						aria-atomic="true"
						aria-live="polite"
						className="shrink-0 text-[11px] text-[var(--bridge-text-secondary)]"
						data-testid="bridge-viewer-content-status"
						role="status"
					>
						{props.statusText}
					</span>
				)}
			</div>
			{props.controls === undefined ? null : (
				<div
					className="flex shrink-0 items-center gap-1"
					data-testid="bridge-viewer-content-topbar-controls"
				>
					{props.controls}
				</div>
			)}
		</header>
	);
}

export function BridgeViewerContextSwitcher(props: {
	readonly mode: 'file' | 'review';
	readonly onModeChange: (mode: 'file' | 'review') => void;
}): ReactElement {
	return (
		<ToggleGroup
			aria-label="Bridge viewer context"
			className={bridgeViewerChromeSegmentedControlClassName}
			data-bridge-segmented-control="viewer-context"
			data-testid="bridge-viewer-context-switcher"
			onValueChange={(modes): void => {
				const nextMode = modes[0];
				switch (nextMode) {
					case 'file':
					case 'review':
						if (nextMode !== props.mode) props.onModeChange(nextMode);
						return;
					case undefined:
						return;
					default:
						return;
				}
			}}
			role="group"
			size="sm"
			value={[props.mode]}
		>
			<BridgeViewerContextButton isSelected={props.mode === 'file'} label="Files" mode="file" />
			<BridgeViewerContextButton
				isSelected={props.mode === 'review'}
				label="Review"
				mode="review"
			/>
		</ToggleGroup>
	);
}

function BridgeViewerContextButton(props: {
	readonly isSelected: boolean;
	readonly label: string;
	readonly mode: 'file' | 'review';
}): ReactElement {
	return (
		<ToggleGroupItem
			aria-label={props.label}
			className={cn(
				bridgeViewerChromeSegmentButtonClassName,
				props.isSelected ? 'shadow-none' : undefined,
			)}
			data-bridge-viewer-context-selected={props.isSelected ? 'true' : 'false'}
			data-bridge-viewer-context-target={props.mode}
			data-testid={`bridge-viewer-context-${props.mode}`}
			size="sm"
			title={props.label}
			value={props.mode}
		>
			{props.mode === 'file' ? (
				<FileTextIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
			) : (
				<ListChecksIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
			)}
			<span>{props.label}</span>
		</ToggleGroupItem>
	);
}
