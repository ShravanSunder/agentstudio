import { FileTextIcon, ListChecksIcon } from 'lucide-react';
import type { ReactElement, ReactNode } from 'react';

import { ToggleGroup, ToggleGroupItem } from '../components/ui/toggle-group.js';
import {
	bridgeViewerChromeHeaderClassName,
	bridgeViewerChromeLucideIconClassName,
} from './bridge-viewer-chrome.js';
import { cn } from './class-name.js';

export function BridgeViewerContentHeader(props: {
	readonly controls?: ReactNode;
	readonly eyebrow: string;
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
			data-bridge-segmented-control="viewer-context"
			data-testid="bridge-viewer-context-switcher"
			role="group"
			size="sm"
		>
			<BridgeViewerContextButton
				isSelected={props.mode === 'file'}
				label="Files"
				mode="file"
				onModeChange={props.onModeChange}
			/>
			<BridgeViewerContextButton
				isSelected={props.mode === 'review'}
				label="Review"
				mode="review"
				onModeChange={props.onModeChange}
			/>
		</ToggleGroup>
	);
}

function BridgeViewerContextButton(props: {
	readonly isSelected: boolean;
	readonly label: string;
	readonly mode: 'file' | 'review';
	readonly onModeChange: (mode: 'file' | 'review') => void;
}): ReactElement {
	return (
		<ToggleGroupItem
			aria-label={props.label}
			className={props.isSelected ? 'shadow-none' : undefined}
			data-bridge-viewer-context-selected={props.isSelected ? 'true' : 'false'}
			data-bridge-viewer-context-target={props.mode}
			data-testid={`bridge-viewer-context-${props.mode}`}
			onClick={(): void => {
				if (!props.isSelected) {
					props.onModeChange(props.mode);
				}
			}}
			pressed={props.isSelected}
			size="sm"
			title={props.label}
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
