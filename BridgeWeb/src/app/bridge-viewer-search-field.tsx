import { RegexIcon, SearchIcon, XIcon } from 'lucide-react';
import {
	useLayoutEffect,
	useRef,
	type ChangeEvent,
	type KeyboardEvent,
	type ReactElement,
} from 'react';

import { InputGroup, InputGroupAddon, InputGroupInput } from '../components/ui/input-group.js';
import { BridgeViewerButton } from './bridge-viewer-button.js';

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
		<InputGroup className="m-2 w-auto" data-bridge-viewer-search-field="true">
			<InputGroupAddon>
				<SearchIcon aria-hidden="true" data-bridge-viewer-search-icon="true" />
			</InputGroupAddon>
			<InputGroupInput
				aria-invalid={props.errorMessage === null ? undefined : true}
				aria-label="Search files"
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
			<InputGroupAddon align="inline-end">
				<BridgeViewerButton
					ariaLabel={isRegexMode ? 'Use text search' : 'Use regex search'}
					ariaPressed={isRegexMode}
					size="icon-xs"
					onClick={(): void => {
						props.onSearchModeChange(isRegexMode ? { kind: 'text' } : { kind: 'regex' });
					}}
					testId={props.regexToggleTestId}
					title={isRegexMode ? 'Use text search' : 'Use regex search'}
				>
					<RegexIcon aria-hidden="true" />
				</BridgeViewerButton>
				<BridgeViewerButton
					ariaLabel={props.value.length === 0 ? 'Close search' : 'Clear search'}
					size="icon-xs"
					onClick={props.onClear}
					testId={props.clearButtonTestId}
					title={props.value.length === 0 ? 'Close search' : 'Clear search'}
				>
					<XIcon aria-hidden="true" />
				</BridgeViewerButton>
			</InputGroupAddon>
		</InputGroup>
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
