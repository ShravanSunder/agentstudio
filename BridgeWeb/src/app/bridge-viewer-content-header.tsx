import { FileTextIcon, ListChecksIcon } from 'lucide-react';
import type { ReactElement, ReactNode } from 'react';

import {
	BridgeReviewButton,
	BridgeReviewIcon,
} from '../review-viewer/chrome/bridge-review-button.js';
import { cn } from './class-name.js';

export function BridgeViewerContentHeader(props: {
	readonly controls?: ReactNode;
	readonly eyebrow: string;
	readonly title: string;
}): ReactElement {
	return (
		<header
			className="flex h-9 min-w-0 items-center justify-between gap-3 border-b border-[var(--bridge-border-subtle)] bg-[var(--bridge-app-bg)] px-3 shadow-[0_1px_0_rgb(205_214_244_/_0.06)]"
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
		<div
			aria-label="Bridge viewer context"
			className="inline-flex h-7 items-center gap-1 rounded-lg border border-[var(--bridge-border-subtle)] bg-[var(--bridge-surface-bg)] p-0.5"
			data-bridge-segmented-control="viewer-context"
			data-testid="bridge-viewer-context-switcher"
			role="radiogroup"
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
		</div>
	);
}

function BridgeViewerContextButton(props: {
	readonly isSelected: boolean;
	readonly label: string;
	readonly mode: 'file' | 'review';
	readonly onModeChange: (mode: 'file' | 'review') => void;
}): ReactElement {
	return (
		<BridgeReviewButton
			ariaLabel={props.label}
			ariaPressed={props.isSelected}
			className={cn('h-6 rounded-md px-2', props.isSelected && 'shadow-none')}
			data-bridge-viewer-context-selected={props.isSelected ? 'true' : 'false'}
			data-bridge-viewer-context-target={props.mode}
			data-testid={`bridge-viewer-context-${props.mode}`}
			onClick={(): void => {
				if (!props.isSelected) {
					props.onModeChange(props.mode);
				}
			}}
			title={props.label}
		>
			<BridgeReviewIcon>
				{props.mode === 'file' ? (
					<FileTextIcon aria-hidden="true" className="size-4" />
				) : (
					<ListChecksIcon aria-hidden="true" className="size-4" />
				)}
			</BridgeReviewIcon>
			<span>{props.label}</span>
		</BridgeReviewButton>
	);
}
