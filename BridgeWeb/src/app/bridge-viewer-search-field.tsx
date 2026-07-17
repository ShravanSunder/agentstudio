import { RegexIcon, SearchIcon } from 'lucide-react';
import type { ChangeEvent, ReactElement } from 'react';

import { Input } from '../components/ui/input.js';
import { BridgeViewerButton, BridgeViewerIcon } from './bridge-viewer-button.js';
import {
	bridgeViewerChromeIconButtonClassName,
	bridgeViewerChromeLucideIconClassName,
} from './bridge-viewer-chrome.js';
import { cn } from './class-name.js';

export type BridgeViewerSearchFieldMode = { readonly kind: 'regex' | 'text' };

export interface BridgeViewerSearchFieldProps {
	readonly errorMessage: string | null;
	readonly inputTestId: string;
	readonly onChange: (value: string) => void;
	readonly onSearchModeChange: (mode: BridgeViewerSearchFieldMode) => void;
	readonly regexToggleTestId: string;
	readonly searchMode: BridgeViewerSearchFieldMode;
	readonly statusTestId: string;
	readonly value: string;
}

export function BridgeViewerSearchField(props: BridgeViewerSearchFieldProps): ReactElement {
	const isRegexMode = props.searchMode.kind === 'regex';
	return (
		<>
			<div
				className={cn(
					'mx-2 mb-2 flex h-7 min-w-0 items-center gap-1 rounded-md border px-1',
					'border-[var(--bridge-border-subtle)] bg-[var(--bridge-header-control-bg)]',
					'focus-within:border-[var(--bridge-focus-border)] focus-within:ring-1 focus-within:ring-[var(--bridge-focus-ring)]',
					props.errorMessage === null
						? null
						: 'border-[var(--destructive)] ring-1 ring-[color-mix(in_oklch,var(--destructive)_25%,transparent)]',
				)}
				data-bridge-viewer-search-field="true"
			>
				<SearchIcon
					aria-hidden="true"
					className={cn(
						bridgeViewerChromeLucideIconClassName,
						'ml-0.5 shrink-0 text-[var(--bridge-text-muted)]',
					)}
				/>
				<Input
					aria-invalid={props.errorMessage === null ? undefined : true}
					aria-label="Search files"
					autoFocus
					className={cn(
						'h-6 min-h-6 flex-1 border-0 bg-transparent px-1 py-0 shadow-none',
						'!text-[11px] !leading-none text-[var(--bridge-text-primary)]',
						'placeholder:text-[var(--bridge-text-muted)] focus-visible:border-0 focus-visible:ring-0',
						'dark:bg-transparent dark:aria-invalid:border-0 dark:aria-invalid:ring-0',
					)}
					data-testid={props.inputTestId}
					onChange={(event: ChangeEvent<HTMLInputElement>): void => {
						props.onChange(event.currentTarget.value);
					}}
					placeholder={isRegexMode ? 'Search files with regex' : 'Search files'}
					spellCheck={false}
					type="search"
					value={props.value}
				/>
				<BridgeViewerButton
					ariaLabel={isRegexMode ? 'Use text search' : 'Use regex search'}
					ariaPressed={isRegexMode}
					className={cn(bridgeViewerChromeIconButtonClassName, 'h-5 min-h-5 w-5 min-w-5')}
					onClick={(): void => {
						props.onSearchModeChange(isRegexMode ? { kind: 'text' } : { kind: 'regex' });
					}}
					testId={props.regexToggleTestId}
					title={isRegexMode ? 'Use text search' : 'Use regex search'}
				>
					<BridgeViewerIcon>
						<RegexIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
					</BridgeViewerIcon>
				</BridgeViewerButton>
			</div>
			<div aria-live="polite" className="sr-only" data-testid={props.statusTestId} role="status">
				{props.errorMessage ?? ''}
			</div>
		</>
	);
}
