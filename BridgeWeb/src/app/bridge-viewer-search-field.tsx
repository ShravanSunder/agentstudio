import { RegexIcon, SearchIcon, XIcon } from 'lucide-react';
import {
	useLayoutEffect,
	useRef,
	type ChangeEvent,
	type KeyboardEvent,
	type ReactElement,
} from 'react';

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
	readonly clearButtonTestId: string;
	readonly inputTestId: string;
	readonly onChange: (value: string) => void;
	readonly onClear: () => void;
	readonly onClose: () => void;
	readonly onSearchModeChange: (mode: BridgeViewerSearchFieldMode) => void;
	readonly regexToggleTestId: string;
	readonly searchMode: BridgeViewerSearchFieldMode;
	readonly value: string;
}

export function BridgeViewerSearchField(props: BridgeViewerSearchFieldProps): ReactElement {
	const isRegexMode = props.searchMode.kind === 'regex';
	const inputRef = useRef<HTMLInputElement>(null);
	useLayoutEffect((): void => {
		inputRef.current?.focus({ preventScroll: true });
		inputRef.current?.select();
	}, []);
	return (
		<div
			className={cn(
				'm-2 flex h-7 min-w-0 items-center gap-1 rounded-md border px-1.5',
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
					'shrink-0 text-[var(--bridge-text-muted)]',
				)}
				data-bridge-viewer-search-icon="true"
			/>
			<Input
				aria-invalid={props.errorMessage === null ? undefined : true}
				aria-label="Search files"
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
				onKeyDown={(event: KeyboardEvent<HTMLInputElement>): void => {
					if (event.key !== 'Escape') return;
					event.preventDefault();
					event.stopPropagation();
					props.onClose();
				}}
				placeholder={isRegexMode ? 'Search files with regex' : 'Search files'}
				spellCheck={false}
				ref={inputRef}
				type="text"
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
			<BridgeViewerButton
				ariaLabel={props.value.length === 0 ? 'Close search' : 'Clear search'}
				className={cn(
					bridgeViewerChromeIconButtonClassName,
					'h-5 min-h-5 w-5 min-w-5 disabled:opacity-35',
				)}
				onClick={props.onClear}
				testId={props.clearButtonTestId}
				title={props.value.length === 0 ? 'Close search' : 'Clear search'}
			>
				<BridgeViewerIcon>
					<XIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
				</BridgeViewerIcon>
			</BridgeViewerButton>
		</div>
	);
}

export function BridgeViewerSearchStatus(props: {
	readonly message: string | null;
	readonly testId: string;
}): ReactElement {
	return (
		<div aria-live="polite" className="sr-only" data-testid={props.testId} role="status">
			{props.message ?? ''}
		</div>
	);
}
