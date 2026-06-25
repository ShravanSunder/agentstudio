import type { ReactElement, ReactNode } from 'react';

import { Button } from '../components/ui/button.js';
import { cn } from './class-name.js';

export function BridgeViewerAppShell(props: {
	readonly appOwner: 'BridgeApp';
	readonly children: ReactNode;
	readonly mode: 'file' | 'review';
	readonly onModeChange?: (mode: 'file' | 'review') => void;
}): ReactElement {
	return (
		<div
			className="dark relative h-screen min-h-screen w-full overflow-hidden bg-[var(--bridge-app-bg)] text-[var(--bridge-text-primary)] antialiased"
			data-bridge-app-owner={props.appOwner}
			data-bridge-viewer-mode={props.mode}
			data-bridge-viewer-shell-owner="BridgeViewerAppShell"
			data-testid="bridge-app-root"
		>
			{props.onModeChange === undefined ? null : (
				<BridgeViewerContextSwitcher mode={props.mode} onModeChange={props.onModeChange} />
			)}
			{props.children}
		</div>
	);
}

function BridgeViewerContextSwitcher(props: {
	readonly mode: 'file' | 'review';
	readonly onModeChange: (mode: 'file' | 'review') => void;
}): ReactElement {
	return (
		<div
			aria-label="Bridge viewer context"
			className="absolute left-1/2 top-2 z-50 inline-flex h-7 -translate-x-1/2 items-center gap-0.5 rounded-md border border-[var(--bridge-border-subtle)] bg-[var(--bridge-header-control-bg)]/95 p-0.5 shadow-[0_8px_24px_rgb(0_0_0_/_0.35)] backdrop-blur"
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
		<Button
			aria-checked={props.isSelected ? 'true' : 'false'}
			aria-label={props.label}
			className={cn(
				'h-6 min-w-16 rounded-[5px] border border-transparent px-2 text-[11px] leading-none',
				'text-[var(--bridge-text-secondary)] hover:bg-[var(--bridge-surface-raised-bg)] hover:text-[var(--bridge-text-primary)]',
				'focus-visible:border-[var(--bridge-accent)] focus-visible:outline-none',
				props.isSelected &&
					'bg-[var(--bridge-accent-soft)] text-[var(--bridge-text-primary)] shadow-[inset_0_0_0_1px_rgb(137_180_250_/_0.16)]',
			)}
			data-bridge-viewer-context-selected={props.isSelected ? 'true' : 'false'}
			data-bridge-viewer-context-target={props.mode}
			data-testid={`bridge-viewer-context-${props.mode}`}
			onClick={(): void => {
				if (!props.isSelected) {
					props.onModeChange(props.mode);
				}
			}}
			role="radio"
			size="sm"
			type="button"
			variant="ghost"
		>
			{props.label}
		</Button>
	);
}
