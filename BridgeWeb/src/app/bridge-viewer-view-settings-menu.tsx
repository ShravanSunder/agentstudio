import { RotateCcwIcon, SettingsIcon } from 'lucide-react';
import { useEffect, type ReactElement } from 'react';

import {
	DropdownMenu,
	DropdownMenuCheckboxItem,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuRadioGroup,
	DropdownMenuRadioItem,
	DropdownMenuSeparator,
	DropdownMenuTrigger,
} from '../components/ui/dropdown-menu.js';
import { bridgeViewerChromeLucideIconClassName } from './bridge-viewer-chrome.js';
import {
	bridgeViewerFilterClearClassName,
	bridgeViewerFilterMenuSurfaceClassName,
	bridgeViewerFilterOptionClassName,
	BridgeViewerFilterMenuHeader,
	bridgeViewerMenuTriggerClassName,
} from './bridge-viewer-filter-menu.js';
import type {
	BridgeFilesViewSettings,
	BridgeReviewChangeIndicators,
	BridgeReviewDiffLayout,
	BridgeReviewViewSettings,
} from './bridge-viewer-view-settings.js';
import { cn } from './class-name.js';

interface BridgeFilesViewSettingsMenuProps {
	readonly disabled?: boolean;
	readonly defaultSettings: Readonly<BridgeFilesViewSettings>;
	readonly onChange: (settings: BridgeFilesViewSettings) => void;
	readonly onOpenChange: (open: boolean) => void;
	readonly open: boolean;
	readonly settings: Readonly<BridgeFilesViewSettings>;
	readonly surface: 'file';
}

interface BridgeReviewViewSettingsMenuProps {
	readonly disabled?: boolean;
	readonly defaultSettings: Readonly<BridgeReviewViewSettings>;
	readonly onChange: (settings: BridgeReviewViewSettings) => void;
	readonly onOpenChange: (open: boolean) => void;
	readonly open: boolean;
	readonly settings: Readonly<BridgeReviewViewSettings>;
	readonly surface: 'review';
}

export type BridgeViewerViewSettingsMenuProps =
	| BridgeFilesViewSettingsMenuProps
	| BridgeReviewViewSettingsMenuProps;

export function BridgeViewerViewSettingsMenu(
	props: BridgeViewerViewSettingsMenuProps,
): ReactElement {
	const { disabled, onOpenChange, open } = props;
	const testPrefix = `bridge-${props.surface}-view-settings`;
	const settingsChanged = !bridgeViewerViewSettingsAreEqual(props);
	useEffect((): void => {
		if (disabled === true && open) onOpenChange(false);
	}, [disabled, onOpenChange, open]);
	const updateLineNumbers = (lineNumbers: boolean): void => {
		if (props.surface === 'file') props.onChange({ ...props.settings, lineNumbers });
		else props.onChange({ ...props.settings, lineNumbers });
	};
	const updateWordWrap = (wordWrap: boolean): void => {
		if (props.surface === 'file') props.onChange({ ...props.settings, wordWrap });
		else props.onChange({ ...props.settings, wordWrap });
	};
	const resetViewSettings = (): void => {
		if (props.surface === 'file') props.onChange(props.defaultSettings);
		else props.onChange(props.defaultSettings);
	};
	return (
		<DropdownMenu onOpenChange={props.onOpenChange} open={props.open}>
			<DropdownMenuTrigger
				aria-label="View settings"
				className={bridgeViewerMenuTriggerClassName}
				data-testid={`${testPrefix}-trigger`}
				disabled={props.disabled}
				title="View settings"
			>
				<SettingsIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
			</DropdownMenuTrigger>
			<DropdownMenuContent
				align="end"
				className={cn(bridgeViewerFilterMenuSurfaceClassName, 'w-64')}
				data-testid={`${testPrefix}-content`}
				sideOffset={6}
			>
				<BridgeViewerFilterMenuHeader
					description={`Change how ${props.surface === 'file' ? 'file' : 'review'} content is displayed`}
					testId={`${testPrefix}-header`}
					title="View Settings"
				/>
				<DropdownMenuSeparator className="my-1 bg-[var(--bridge-border-subtle)]" />
				<section aria-label="Appearance">
					<ViewSettingsToggleRow
						checked={props.settings.lineNumbers}
						label="Line numbers"
						onCheckedChange={updateLineNumbers}
					/>
					<ViewSettingsToggleRow
						checked={props.settings.wordWrap}
						label="Word wrap"
						onCheckedChange={updateWordWrap}
					/>
					{props.surface === 'review' ? (
						<ViewSettingsToggleRow
							checked={props.settings.changeBackgrounds}
							label="Change backgrounds"
							onCheckedChange={(changeBackgrounds): void =>
								props.onChange({ ...props.settings, changeBackgrounds })
							}
						/>
					) : null}
				</section>
				{props.surface === 'review' ? (
					<>
						<DropdownMenuSeparator className="my-1 bg-[var(--bridge-border-subtle)]" />
						<ViewSettingsRadioGroup
							label="Diff layout"
							onSelect={(diffLayout): void => props.onChange({ ...props.settings, diffLayout })}
							options={diffLayoutOptions}
							value={props.settings.diffLayout}
						/>
						<DropdownMenuSeparator className="my-1 bg-[var(--bridge-border-subtle)]" />
						<ViewSettingsRadioGroup
							label="Change indicators"
							onSelect={(changeIndicators): void =>
								props.onChange({ ...props.settings, changeIndicators })
							}
							options={changeIndicatorOptions}
							value={props.settings.changeIndicators}
						/>
					</>
				) : null}
				<DropdownMenuSeparator className="my-1 bg-[var(--bridge-border-subtle)]" />
				<DropdownMenuItem
					className={bridgeViewerFilterClearClassName}
					data-testid={`${testPrefix}-reset`}
					disabled={!settingsChanged}
					onClick={resetViewSettings}
				>
					<span className="flex size-5 shrink-0 items-center justify-center rounded-[6px] bg-[var(--bridge-surface-muted-bg)] text-[var(--bridge-text-secondary)]">
						<RotateCcwIcon aria-hidden="true" className="size-3.5" />
					</span>
					<span>Reset View Settings</span>
				</DropdownMenuItem>
			</DropdownMenuContent>
		</DropdownMenu>
	);
}

function bridgeViewerViewSettingsAreEqual(props: BridgeViewerViewSettingsMenuProps): boolean {
	if (props.surface === 'file') {
		return (
			props.settings.lineNumbers === props.defaultSettings.lineNumbers &&
			props.settings.wordWrap === props.defaultSettings.wordWrap
		);
	}
	return (
		props.settings.changeBackgrounds === props.defaultSettings.changeBackgrounds &&
		props.settings.changeIndicators === props.defaultSettings.changeIndicators &&
		props.settings.diffLayout === props.defaultSettings.diffLayout &&
		props.settings.lineNumbers === props.defaultSettings.lineNumbers &&
		props.settings.wordWrap === props.defaultSettings.wordWrap
	);
}

function ViewSettingsToggleRow(props: {
	readonly checked: boolean;
	readonly label: string;
	readonly onCheckedChange: (checked: boolean) => void;
}): ReactElement {
	return (
		<DropdownMenuCheckboxItem
			checked={props.checked}
			className={cn(bridgeViewerFilterOptionClassName, 'h-8 py-0')}
			onCheckedChange={props.onCheckedChange}
		>
			<span data-bridge-view-settings-row-label="">{props.label}</span>
		</DropdownMenuCheckboxItem>
	);
}

function ViewSettingsRadioGroup<TValue extends string>(props: {
	readonly label: string;
	readonly onSelect: (value: TValue) => void;
	readonly options: readonly { readonly label: string; readonly value: TValue }[];
	readonly value: TValue;
}): ReactElement {
	return (
		<section aria-label={props.label}>
			<p className="px-2 py-1 text-[11px] font-medium text-[var(--bridge-text-muted)]">
				{props.label}
			</p>
			<DropdownMenuRadioGroup value={props.value}>
				{props.options.map(
					(option): ReactElement => (
						<DropdownMenuRadioItem
							className={cn(bridgeViewerFilterOptionClassName, 'h-8 py-0')}
							key={option.value}
							onClick={(): void => props.onSelect(option.value)}
							value={option.value}
						>
							<span data-bridge-view-settings-row-label="">{option.label}</span>
						</DropdownMenuRadioItem>
					),
				)}
			</DropdownMenuRadioGroup>
		</section>
	);
}

const diffLayoutOptions: readonly {
	readonly label: string;
	readonly value: BridgeReviewDiffLayout;
}[] = [
	{ label: 'Split', value: 'split' },
	{ label: 'Unified', value: 'unified' },
];

const changeIndicatorOptions: readonly {
	readonly label: string;
	readonly value: BridgeReviewChangeIndicators;
}[] = [
	{ label: 'Bars', value: 'bars' },
	{ label: 'Symbols', value: 'symbols' },
	{ label: 'None', value: 'none' },
];
