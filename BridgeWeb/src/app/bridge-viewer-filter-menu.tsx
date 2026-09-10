import {
	FilesIcon,
	GitBranchIcon,
	FilePlusIcon,
	FilePenIcon,
	FileMinusIcon,
	FileSymlinkIcon,
	CopyIcon,
	SlidersHorizontalIcon,
	XIcon,
} from 'lucide-react';
import type { ComponentProps, ReactElement, ReactNode } from 'react';

import { Button } from '../components/ui/button.js';
import {
	DropdownMenu,
	DropdownMenuCheckboxItem,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuHeader,
	DropdownMenuDescription,
	DropdownMenuLabel,
	DropdownMenuGroup,
	DropdownMenuSeparator,
	DropdownMenuTrigger,
} from '../components/ui/dropdown-menu.js';
import { StatusBadge } from '../components/ui/status-badge.js';
import {
	bridgeViewerFiltersShortcut,
	bridgeViewerShortcutTitle,
} from './bridge-viewer-local-shortcuts.js';

export interface BridgeViewerFilterOption<TValue extends string> {
	readonly value: TValue;
	readonly label: string;
	readonly selectedLabel?: string;
	readonly icon?: ReactNode;
}

export interface BridgeViewerFacetMenuOption<TValue extends string> {
	readonly value: TValue;
	readonly label: string;
	readonly description: string;
	readonly icon?: ReactNode;
}

export interface BridgeViewerFilterMenuProps<TValue extends string> {
	readonly label: string;
	readonly value: TValue;
	readonly options: readonly BridgeViewerFilterOption<TValue>[];
	readonly showDefaultOptionInMenu?: boolean;
	readonly testId: string;
	readonly onChange: (value: TValue) => void;
}

export function BridgeViewerFilterMenuHeader(props: {
	readonly description: string;
	readonly testId: string;
	readonly title: string;
}): ReactElement {
	return (
		<DropdownMenuHeader title={props.title} data-testid={props.testId}>
			<DropdownMenuDescription>{props.description}</DropdownMenuDescription>
		</DropdownMenuHeader>
	);
}

export function BridgeViewerFilterOptionRow(props: {
	readonly checked: boolean;
	readonly icon: ReactNode;
	readonly label: string;
	readonly onSelect: () => void;
	readonly optionBadgeTestId: string;
	readonly optionLabelTestId: string;
	readonly optionTestId: string;
	readonly value: string;
}): ReactElement {
	return (
		<DropdownMenuCheckboxItem
			checked={props.checked}
			data-testid={props.optionTestId}
			onCheckedChange={props.onSelect}
		>
			<StatusBadge
				aria-hidden="true"
				tone={statusBadgeTone(props.value)}
				data-testid={props.optionBadgeTestId}
			>
				{typeof props.icon === 'string' ? gitStatusIcon(props.value) : props.icon}
			</StatusBadge>
			<span className="min-w-0 truncate" data-testid={props.optionLabelTestId}>
				{props.label}
			</span>
		</DropdownMenuCheckboxItem>
	);
}

export function BridgeViewerFacetToggleRow(props: {
	readonly checked: boolean;
	readonly description: string;
	readonly label: string;
	readonly onCheckedChange: (checked: boolean) => void;
	readonly icon: ReactNode;
	readonly testId: string;
}): ReactElement {
	return (
		<DropdownMenuCheckboxItem
			aria-label={props.label}
			checked={props.checked}
			indicator="switch"
			title={props.description}
			data-testid={props.testId}
			onCheckedChange={(checked: boolean): void => props.onCheckedChange(checked)}
		>
			{props.icon}
			<span data-bridge-filter-row-label="">{props.label}</span>
		</DropdownMenuCheckboxItem>
	);
}

export function BridgeViewerFilterClearItem(props: {
	readonly disabled: boolean;
	readonly label: string;
	readonly onClear: () => void;
	readonly testId: string;
}): ReactElement {
	return (
		<DropdownMenuItem data-testid={props.testId} disabled={props.disabled} onClick={props.onClear}>
			<XIcon aria-hidden="true" />
			<span>{props.label}</span>
		</DropdownMenuItem>
	);
}

export function BridgeViewerFilterTrigger(props: {
	readonly activeIndicatorTestId: string;
	readonly hasActiveFilter: boolean;
	readonly label: string;
	readonly selectedLabel: string;
	readonly testId: string;
	readonly title?: string;
	readonly triggerGlyphTestId: string;
}): ReactElement {
	return (
		<DropdownMenuTrigger
			aria-label={props.label}
			render={<Button size="icon-sm" variant="ghost" />}
			data-testid={props.testId}
			title={props.title ?? props.label}
		>
			<span className="relative flex min-w-0 items-center truncate">
				<FilterTriggerGlyph testId={props.triggerGlyphTestId} />
				{props.hasActiveFilter ? (
					<StatusBadge
						appearance="indicator"
						className="absolute -right-0.5 -top-0.5"
						data-testid={props.activeIndicatorTestId}
					/>
				) : null}
				<span className="sr-only">{props.selectedLabel}</span>
			</span>
		</DropdownMenuTrigger>
	);
}

export function BridgeViewerFacetMenu(props: {
	readonly columns?: boolean;
	readonly children: ReactNode;
	readonly clearDisabled: boolean;
	readonly clearLabel: string;
	readonly clearTestId: string;
	readonly contentTestId: string;
	readonly description: string;
	readonly hasActiveFilter: boolean;
	readonly headerTestId: string;
	readonly label: string;
	readonly onClear: () => void;
	readonly onOpenChange: (open: boolean) => void;
	readonly open: boolean;
	readonly selectedLabel: string;
	readonly testId: string;
	readonly title: string;
	readonly triggerActiveIndicatorTestId: string;
	readonly triggerGlyphTestId: string;
}): ReactElement {
	return (
		<DropdownMenu onOpenChange={props.onOpenChange} open={props.open}>
			<BridgeViewerFilterTrigger
				activeIndicatorTestId={props.triggerActiveIndicatorTestId}
				hasActiveFilter={props.hasActiveFilter}
				label={props.label}
				selectedLabel={props.selectedLabel}
				testId={props.testId}
				title={bridgeViewerShortcutTitle(props.label, bridgeViewerFiltersShortcut)}
				triggerGlyphTestId={props.triggerGlyphTestId}
			/>
			<DropdownMenuContent
				align="end"
				className={
					props.columns ? 'w-[520px] max-w-[calc(100vw-32px)]' : 'w-72 max-w-[calc(100vw-32px)]'
				}
				data-testid={props.contentTestId}
				sideOffset={6}
			>
				{props.children}
				<DropdownMenuSeparator />
				<BridgeViewerFilterClearItem
					disabled={props.clearDisabled}
					label={props.clearLabel}
					onClear={props.onClear}
					testId={props.clearTestId}
				/>
			</DropdownMenuContent>
		</DropdownMenu>
	);
}

export function BridgeViewerFacetGroup<TValue extends string>(props: {
	readonly activeValue: TValue;
	readonly defaultValue: TValue;
	readonly label: string;
	readonly onChange: (value: TValue) => void;
	readonly optionBadgeTestId: string;
	readonly optionLabelTestId: string;
	readonly optionTestId: string;
	readonly options: readonly BridgeViewerFacetMenuOption<TValue>[];
	readonly testId: string;
}): ReactElement {
	const options = (
		<DropdownMenuGroup aria-label={props.label} data-testid={props.testId}>
			<DropdownMenuLabel>
				{props.label === 'Git status' ? (
					<GitBranchIcon aria-hidden="true" />
				) : (
					<FilesIcon aria-hidden="true" />
				)}
				{props.label}
			</DropdownMenuLabel>
			<div className="space-y-0.5">
				{props.options.map(
					(option: BridgeViewerFacetMenuOption<TValue>): ReactElement => (
						<BridgeViewerFilterOptionRow
							checked={option.value === props.activeValue}
							icon={option.icon ?? option.label.slice(0, 1)}
							key={option.value}
							label={option.label}
							onSelect={() => props.onChange(option.value)}
							optionBadgeTestId={props.optionBadgeTestId}
							optionLabelTestId={props.optionLabelTestId}
							optionTestId={props.optionTestId}
							value={option.value}
						/>
					),
				)}
			</div>
		</DropdownMenuGroup>
	);
	return options;
}

export function BridgeViewerFilterMenu<TValue extends string>(
	props: BridgeViewerFilterMenuProps<TValue>,
): ReactElement {
	const selectedOption =
		props.options.find(
			(option: BridgeViewerFilterOption<TValue>): boolean => option.value === props.value,
		) ?? props.options[0];
	const selectedLabel = selectedOption?.selectedLabel ?? selectedOption?.label ?? props.label;
	const clearOption = props.options[0];
	const canClear = clearOption !== undefined && props.value !== clearOption.value;
	const isDefaultSelection = clearOption !== undefined && props.value === clearOption.value;
	const menuOptions =
		props.showDefaultOptionInMenu === false ? props.options.slice(1) : props.options;
	const testIds = bridgeViewerFilterMenuTestIds(props.testId);

	return (
		<DropdownMenu>
			<BridgeViewerFilterTrigger
				activeIndicatorTestId={testIds.activeIndicator}
				hasActiveFilter={!isDefaultSelection}
				label={titleForFilterLabel(props.label)}
				selectedLabel={selectedLabel}
				testId={props.testId}
				title={bridgeViewerShortcutTitle(
					titleForFilterLabel(props.label),
					bridgeViewerFiltersShortcut,
				)}
				triggerGlyphTestId={testIds.triggerGlyph}
			/>
			<DropdownMenuContent
				align="end"
				className="w-64 max-h-[min(460px,calc(100vh-96px))]"
				data-testid={testIds.popover}
				sideOffset={6}
			>
				<BridgeViewerFilterMenuHeader
					description={descriptionForFilterLabel(props.label)}
					testId={testIds.popoverHeader}
					title={titleForFilterLabel(props.label)}
				/>
				<DropdownMenuSeparator />
				{menuOptions.map(
					(option: BridgeViewerFilterOption<TValue>): ReactElement => (
						<BridgeViewerFilterOptionRow
							checked={option.value === props.value}
							icon={option.icon ?? option.label.slice(0, 1)}
							key={option.value}
							label={option.label}
							onSelect={() => props.onChange(option.value)}
							optionBadgeTestId={testIds.optionBadge}
							optionLabelTestId={testIds.optionLabel}
							optionTestId={testIds.option}
							value={option.value}
						/>
					),
				)}
				<DropdownMenuSeparator />
				<BridgeViewerFilterClearItem
					disabled={!canClear}
					label="Clear filter"
					onClear={() => {
						if (clearOption !== undefined) {
							props.onChange(clearOption.value);
						}
					}}
					testId={testIds.clear}
				/>
			</DropdownMenuContent>
		</DropdownMenu>
	);
}

function FilterTriggerGlyph(props: { readonly testId: string }): ReactElement {
	return <SlidersHorizontalIcon aria-hidden="true" data-testid={props.testId} />;
}

function titleForFilterLabel(label: string): string {
	if (label === 'Git status filter') {
		return 'Filter by Git status';
	}
	if (label === 'File class filter') {
		return 'Filter by file class';
	}
	return label;
}

function descriptionForFilterLabel(label: string): string {
	if (label === 'Git status filter') {
		return 'Option-click to isolate one status';
	}
	if (label === 'File class filter') {
		return 'Scope the rail without changing metadata';
	}
	return 'Filter visible files';
}

interface BridgeViewerFilterMenuTestIds {
	readonly activeIndicator: string;
	readonly chevron: string;
	readonly clear: string;
	readonly option: string;
	readonly optionBadge: string;
	readonly optionLabel: string;
	readonly popover: string;
	readonly popoverHeader: string;
	readonly triggerGlyph: string;
}

function bridgeViewerFilterMenuTestIds(testId: string): BridgeViewerFilterMenuTestIds {
	return {
		activeIndicator: `${testId}-active-indicator`,
		chevron: `${testId}-chevron`,
		clear: `${testId}-clear`,
		option: `${testId}-option`,
		optionBadge: `${testId}-option-badge`,
		optionLabel: `${testId}-option-label`,
		popover: `${testId}-popover`,
		popoverHeader: `${testId}-popover-header`,
		triggerGlyph: `${testId}-trigger-glyph`,
	};
}

function statusBadgeTone(value: string): ComponentProps<typeof StatusBadge>['tone'] {
	switch (value) {
		case 'added':
			return 'success';
		case 'modified':
			return 'primary';
		case 'renamed':
			return 'warning';
		case 'deleted':
			return 'destructive';
		case 'copied':
		case 'generated':
		case 'vendor':
		case 'config':
			return 'neutral';
		default:
			return 'neutral';
	}
}

function gitStatusIcon(value: string): ReactElement {
	switch (value) {
		case 'added':
			return <FilePlusIcon aria-hidden="true" />;
		case 'modified':
			return <FilePenIcon aria-hidden="true" />;
		case 'deleted':
			return <FileMinusIcon aria-hidden="true" />;
		case 'renamed':
			return <FileSymlinkIcon aria-hidden="true" />;
		case 'copied':
			return <CopyIcon aria-hidden="true" />;
		default:
			return <FilesIcon aria-hidden="true" />;
	}
}
