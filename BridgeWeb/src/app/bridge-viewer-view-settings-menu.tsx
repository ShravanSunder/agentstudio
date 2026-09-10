import {
	AlignJustifyIcon,
	Columns2Icon,
	ListOrderedIcon,
	RotateCcwIcon,
	SettingsIcon,
	WrapTextIcon,
	type LucideIcon,
} from 'lucide-react';
import { useEffect, useId, type ReactElement } from 'react';

import { Button } from '../components/ui/button.js';
import { Field, FieldLabel } from '../components/ui/field.js';
import { Popover, PopoverContent, PopoverTrigger } from '../components/ui/popover.js';
import { Switch } from '../components/ui/switch.js';
import { ToggleGroup, ToggleGroupItem } from '../components/ui/toggle-group.js';
import type {
	BridgeFilesViewSettings,
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
	const switchIdPrefix = `${useId()}-${testPrefix}-switch`;
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
		<Popover onOpenChange={props.onOpenChange} open={props.open}>
			<PopoverTrigger
				aria-label="View settings"
				render={<Button size="icon-sm" variant="ghost" />}
				data-testid={`${testPrefix}-trigger`}
				disabled={props.disabled}
				title="View settings"
			>
				<SettingsIcon aria-hidden="true" />
			</PopoverTrigger>
			<PopoverContent
				aria-label="View settings"
				align="end"
				scrollable
				className="w-64"
				data-testid={`${testPrefix}-content`}
				sideOffset={6}
			>
				<section aria-label="Appearance" className="flex flex-col gap-2 py-1">
					<ViewSettingsToggleRow
						checked={props.settings.lineNumbers}
						icon={ListOrderedIcon}
						id={`${switchIdPrefix}-line-numbers`}
						label="Line numbers"
						onCheckedChange={updateLineNumbers}
					/>
					<ViewSettingsToggleRow
						checked={props.settings.wordWrap}
						icon={WrapTextIcon}
						id={`${switchIdPrefix}-word-wrap`}
						label="Word wrap"
						onCheckedChange={updateWordWrap}
					/>
				</section>
				{props.surface === 'review' ? (
					<div className="flex flex-col gap-2 py-1">
						<ViewSettingsRadioGroup
							label="Layout"
							onSelect={(diffLayout): void => props.onChange({ ...props.settings, diffLayout })}
							options={diffLayoutOptions}
							value={props.settings.diffLayout}
						/>
					</div>
				) : null}
				<Button
					className="w-full justify-start"
					data-testid={`${testPrefix}-reset`}
					disabled={!settingsChanged}
					onClick={resetViewSettings}
					size="sm"
					variant="ghost"
				>
					<RotateCcwIcon aria-hidden="true" data-icon="inline-start" />
					<span>Reset defaults</span>
				</Button>
			</PopoverContent>
		</Popover>
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
	readonly icon: LucideIcon;
	readonly id: string;
	readonly label: string;
	readonly onCheckedChange: (checked: boolean) => void;
}): ReactElement {
	const Icon = props.icon;
	return (
		<Field className="px-1" orientation="setting">
			<FieldLabel htmlFor={props.id}>
				<Icon aria-hidden="true" />
				<span>{props.label}</span>
			</FieldLabel>
			<Switch
				aria-label={props.label}
				checked={props.checked}
				id={props.id}
				onCheckedChange={props.onCheckedChange}
			/>
		</Field>
	);
}

function ViewSettingsRadioGroup<TValue extends string>(props: {
	readonly label: string;
	readonly onSelect: (value: TValue) => void;
	readonly options: readonly {
		readonly icon: LucideIcon;
		readonly label: string;
		readonly value: TValue;
	}[];
	readonly value: TValue;
}): ReactElement {
	return (
		<section aria-label={props.label}>
			<Field className="px-1" orientation="setting">
				<FieldLabel>
					<Columns2Icon aria-hidden="true" />
					<span>{props.label}</span>
				</FieldLabel>
				<ToggleGroup
					aria-label={props.label}
					className="grid grid-cols-2"
					size="xs"
					value={[props.value]}
					variant="segmented"
				>
					{props.options.map((option): ReactElement => {
						const Icon = option.icon;
						const choice = (
							<ToggleGroupItem
								aria-label={option.label}
								className="w-full"
								key={option.value}
								onPressedChange={(pressed): void => {
									if (pressed) props.onSelect(option.value);
								}}
								value={option.value}
							>
								<Icon aria-hidden="true" data-icon="inline-start" />
								<span>{option.label}</span>
							</ToggleGroupItem>
						);
						return choice;
					})}
				</ToggleGroup>
			</Field>
		</section>
	);
}

const diffLayoutOptions: readonly {
	readonly icon: LucideIcon;
	readonly label: string;
	readonly value: BridgeReviewDiffLayout;
}[] = [
	{ icon: Columns2Icon, label: 'Split', value: 'split' },
	{ icon: AlignJustifyIcon, label: 'Unified', value: 'unified' },
];
