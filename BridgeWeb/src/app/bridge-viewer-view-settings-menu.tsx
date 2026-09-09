import { RotateCcwIcon, SettingsIcon } from 'lucide-react';
import { useEffect, type ReactElement } from 'react';

import { Button } from '../components/ui/button.js';
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
import { BridgeViewerFilterMenuHeader } from './bridge-viewer-filter-menu.js';
import type {
	BridgeFilesViewSettings,
	BridgeReviewChangeIndicators,
	BridgeReviewDiffLayout,
	BridgeReviewViewSettings,
} from './bridge-viewer-view-settings.js';

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
				render={<Button size="icon-sm" variant="ghost" />}
				data-testid={`${testPrefix}-trigger`}
				disabled={props.disabled}
				title="View settings"
			>
				<SettingsIcon aria-hidden="true" />
			</DropdownMenuTrigger>
			<DropdownMenuContent
				align="end"
				className="w-64"
				data-testid={`${testPrefix}-content`}
				sideOffset={6}
			>
				<BridgeViewerFilterMenuHeader
					description={`Change how ${props.surface === 'file' ? 'file' : 'review'} content is displayed`}
					testId={`${testPrefix}-header`}
					title="View Settings"
				/>
				<DropdownMenuSeparator />
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
						<DropdownMenuSeparator />
						<ViewSettingsRadioGroup
							label="Diff layout"
							onSelect={(diffLayout): void => props.onChange({ ...props.settings, diffLayout })}
							options={diffLayoutOptions}
							value={props.settings.diffLayout}
						/>
						<DropdownMenuSeparator />
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
				<DropdownMenuSeparator />
				<DropdownMenuItem
					data-testid={`${testPrefix}-reset`}
					disabled={!settingsChanged}
					onClick={resetViewSettings}
				>
					<RotateCcwIcon aria-hidden="true" />
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
		<DropdownMenuCheckboxItem checked={props.checked} onCheckedChange={props.onCheckedChange}>
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
