import type { CodeViewOptions } from '@pierre/diffs';
import { CodeView, type CodeViewHandle } from '@pierre/diffs/react';
import type { ReactElement } from 'react';
import { useEffect, useMemo, useRef } from 'react';

import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import { recordBridgeCodeViewHydrationTelemetry } from '../telemetry/bridge-review-viewer-telemetry.js';
import { BridgePierreWorkerPoolProvider } from '../workers/pierre/bridge-pierre-worker-pool.js';
import {
	BridgeCodeViewController,
	type BridgeCodeViewModel,
} from './bridge-code-view-controller.js';
import {
	createBridgeCodeViewInitialItems,
	materializeBridgeCodeViewItem,
	type BridgeCodeViewContentResources,
} from './bridge-code-view-materialization.js';

export interface BridgeCodeViewPanelProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly projection: BridgeReviewProjectionResult;
	readonly selectedItemId: string | null;
	readonly selectedContentResources?: BridgeCodeViewContentResources | null;
	readonly workerPoolEnabled?: boolean;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
	readonly telemetryParentTraceContext?: BridgeTraceContext | null;
}

interface BridgeCodeViewControllerEntry {
	readonly handle: CodeViewHandle<undefined>;
	readonly controller: BridgeCodeViewController;
}

export const bridgeCodeViewOptions: CodeViewOptions<undefined> = {
	theme: 'pierre-dark',
	themeType: 'dark',
	diffStyle: 'split',
	overflow: 'scroll',
	lineDiffType: 'word',
	hunkSeparators: 'line-info-basic',
	disableVirtualizationBuffers: false,
	layout: {
		paddingTop: 8,
		paddingBottom: 16,
		gap: 8,
	},
};

export function BridgeCodeViewPanel(props: BridgeCodeViewPanelProps): ReactElement {
	const viewerKey = makeViewerKey(props);
	const codeViewHandleRef = useRef<CodeViewHandle<undefined> | null>(null);
	const controllerEntryRef = useRef<BridgeCodeViewControllerEntry | null>(null);
	const lastEffectViewerKeyRef = useRef<string | null>(null);
	const initialItems = useMemo(
		() =>
			createInitialCodeViewItems({
				reviewPackage: props.reviewPackage,
				projection: props.projection,
				selectedItemId: props.selectedItemId,
				selectedContentResources: props.selectedContentResources ?? null,
			}),
		[props.projection, props.reviewPackage, props.selectedContentResources, props.selectedItemId],
	);

	useEffect((): void => {
		controllerEntryRef.current = null;
	}, [viewerKey]);

	useEffect((): void => {
		const isNewViewerMount = lastEffectViewerKeyRef.current !== viewerKey;
		lastEffectViewerKeyRef.current = viewerKey;
		if (
			isNewViewerMount &&
			props.selectedContentResources !== null &&
			props.selectedContentResources !== undefined
		) {
			return;
		}
		if (
			props.selectedItemId === null ||
			props.selectedContentResources === null ||
			props.selectedContentResources === undefined
		) {
			return;
		}
		const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
		if (selectedItem === undefined) {
			return;
		}
		const codeViewHandle = codeViewHandleRef.current;
		if (codeViewHandle === null) {
			return;
		}
		const materializedItem = materializeBridgeCodeViewItem({
			item: selectedItem,
			resources: props.selectedContentResources,
		});
		if (materializedItem === null) {
			return;
		}
		controllerForHandle({
			handle: codeViewHandle,
			controllerEntryRef,
		}).applyItemUpdate(materializedItem, { scrollIntoView: true });
		if (props.telemetryRecorder !== undefined) {
			recordBridgeCodeViewHydrationTelemetry({
				telemetryRecorder: props.telemetryRecorder,
				parentTraceContext: props.telemetryParentTraceContext ?? null,
				projection: props.projection,
				item: selectedItem,
				resources: props.selectedContentResources,
				workerPoolEnabled: props.workerPoolEnabled !== false,
			});
		}
	}, [
		props.projection,
		props.reviewPackage,
		props.selectedContentResources,
		props.selectedItemId,
		props.telemetryParentTraceContext,
		props.telemetryRecorder,
		props.workerPoolEnabled,
		viewerKey,
	]);

	return (
		<section
			aria-label="Review content"
			className="bridge-code-view-panel h-full min-h-0 bg-[var(--bridge-canvas-bg)]"
			data-testid="bridge-code-view-panel"
		>
			<BridgePierreWorkerPoolProvider
				{...(props.workerPoolEnabled === undefined ? {} : { enabled: props.workerPoolEnabled })}
			>
				<CodeView
					key={viewerKey}
					ref={codeViewHandleRef}
					initialItems={initialItems}
					options={bridgeCodeViewOptions}
					style={{ height: '100%' }}
				/>
			</BridgePierreWorkerPoolProvider>
		</section>
	);
}

interface ControllerForHandleProps {
	readonly handle: CodeViewHandle<undefined>;
	readonly controllerEntryRef: {
		current: BridgeCodeViewControllerEntry | null;
	};
}

function controllerForHandle(props: ControllerForHandleProps): BridgeCodeViewController {
	const currentEntry = props.controllerEntryRef.current;
	if (currentEntry !== null && currentEntry.handle === props.handle) {
		return currentEntry.controller;
	}

	const controller = new BridgeCodeViewController({
		model: modelForHandle(props.handle),
	});
	props.controllerEntryRef.current = {
		handle: props.handle,
		controller,
	};
	return controller;
}

function modelForHandle(handle: CodeViewHandle<undefined>): BridgeCodeViewModel {
	return {
		addItems: (items) => handle.addItems(items),
		getItem: (id) => handle.getItem(id),
		updateItem: (item) => handle.updateItem(item),
		updateItemId: (oldId, newId) => handle.updateItemId(oldId, newId),
		scrollTo: (target) => handle.scrollTo(target),
		setSelectedLines: (selection) => handle.setSelectedLines(selection),
		renderImmediately: () => handle.getInstance()?.render(true),
	};
}

interface CreateInitialCodeViewItemsProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly projection: BridgeReviewProjectionResult;
	readonly selectedItemId: string | null;
	readonly selectedContentResources: BridgeCodeViewContentResources | null;
}

function createInitialCodeViewItems(
	props: CreateInitialCodeViewItemsProps,
): ReturnType<typeof createBridgeCodeViewInitialItems> {
	const initialItems = createBridgeCodeViewInitialItems({
		reviewPackage: props.reviewPackage,
		projection: props.projection,
	});
	if (props.selectedItemId === null || props.selectedContentResources === null) {
		return initialItems;
	}

	const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
	if (selectedItem === undefined) {
		return initialItems;
	}
	const materializedItem = materializeBridgeCodeViewItem({
		item: selectedItem,
		resources: props.selectedContentResources,
	});
	if (materializedItem === null) {
		return initialItems;
	}

	return initialItems.map((item) => (item.id === materializedItem.id ? materializedItem : item));
}

function makeViewerKey(props: BridgeCodeViewPanelProps): string {
	return [
		props.reviewPackage.packageId,
		props.reviewPackage.reviewGeneration,
		props.reviewPackage.revision,
		props.projection.projectionId,
	].join(':');
}
