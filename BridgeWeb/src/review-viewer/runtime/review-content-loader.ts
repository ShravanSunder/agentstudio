import type {
	BridgeContentFetch,
	BridgeContentResource,
	LoadBridgeContentResourceProps,
} from '../../foundation/content/content-resource-loader.js';
import { loadBridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import type {
	BridgeContentHandle,
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import type { BridgeCodeViewContentResources } from '../code-view/bridge-code-view-materialization.js';

export interface LoadSelectedReviewItemContentProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedItemId: string | null;
	readonly fetchContent?: BridgeContentFetch;
	readonly traceContext?: BridgeTraceContext | null;
	readonly sendTraceparentHeader?: boolean;
	readonly signal?: AbortSignal;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
}

export async function loadSelectedReviewItemContent(
	props: LoadSelectedReviewItemContentProps,
): Promise<BridgeContentResource | null> {
	if (props.selectedItemId === null) {
		return null;
	}
	const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
	if (selectedItem === undefined) {
		return null;
	}
	const contentHandle = preferredContentHandle(selectedItem);
	if (contentHandle === null) {
		return null;
	}
	return await loadContentHandle({
		handle: contentHandle.handle,
		expectedRole: contentHandle.expectedRole,
		selectedItem,
		props,
	});
}

export async function loadSelectedReviewItemContentResources(
	props: LoadSelectedReviewItemContentProps,
): Promise<BridgeCodeViewContentResources | null> {
	if (props.selectedItemId === null) {
		return null;
	}
	const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
	if (selectedItem === undefined) {
		return null;
	}

	const baseHandle = selectedItem.contentRoles.base ?? null;
	const headHandle = selectedItem.contentRoles.head ?? null;
	if (selectedItem.itemKind === 'diff' && baseHandle !== null && headHandle !== null) {
		const [base, head] = await Promise.all([
			loadContentHandle({ handle: baseHandle, expectedRole: 'base', selectedItem, props }),
			loadContentHandle({ handle: headHandle, expectedRole: 'head', selectedItem, props }),
		]);
		return { base, head };
	}

	const diffHandle = selectedItem.contentRoles.diff ?? null;
	if (selectedItem.itemKind === 'diff' && diffHandle !== null) {
		return {
			diff: await loadContentHandle({
				handle: diffHandle,
				expectedRole: 'diff',
				selectedItem,
				props,
			}),
		};
	}

	const contentHandle = preferredContentHandle(selectedItem);
	if (contentHandle === null) {
		return null;
	}

	const content = await loadContentHandle({
		handle: contentHandle.handle,
		expectedRole: contentHandle.expectedRole,
		selectedItem,
		props,
	});
	return {
		[contentHandle.expectedRole]: content,
	};
}

interface LoadContentHandleProps {
	readonly handle: BridgeContentHandle;
	readonly expectedRole: BridgeContentRole;
	readonly selectedItem: BridgeReviewItemDescriptor;
	readonly props: LoadSelectedReviewItemContentProps;
}

async function loadContentHandle(
	loadContentHandleProps: LoadContentHandleProps,
): Promise<BridgeContentResource> {
	const props = loadContentHandleProps.props;
	assertSelectedContentHandleOwnership({
		handle: loadContentHandleProps.handle,
		expectedRole: loadContentHandleProps.expectedRole,
		selectedItem: loadContentHandleProps.selectedItem,
		reviewPackage: props.reviewPackage,
	});
	const loadProps: LoadBridgeContentResourceProps = {
		handle: loadContentHandleProps.handle,
		traceContext: props.traceContext ?? null,
		sendTraceparentHeader: props.sendTraceparentHeader ?? false,
		...(props.signal === undefined ? {} : { signal: props.signal }),
		...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
		...(props.telemetryRecorder === undefined
			? {}
			: { telemetryRecorder: props.telemetryRecorder }),
	};
	return await loadBridgeContentResource(loadProps);
}

interface PreferredContentHandle {
	readonly handle: BridgeContentHandle;
	readonly expectedRole: BridgeContentRole;
}

function preferredContentHandle(item: BridgeReviewItemDescriptor): PreferredContentHandle | null {
	const headHandle = item.contentRoles.head ?? null;
	if (headHandle !== null) {
		return { handle: headHandle, expectedRole: 'head' };
	}
	const fileHandle = item.contentRoles.file ?? null;
	if (fileHandle !== null) {
		return { handle: fileHandle, expectedRole: 'file' };
	}
	const diffHandle = item.contentRoles.diff ?? null;
	if (diffHandle !== null) {
		return { handle: diffHandle, expectedRole: 'diff' };
	}
	const baseHandle = item.contentRoles.base ?? null;
	return baseHandle === null ? null : { handle: baseHandle, expectedRole: 'base' };
}

function assertSelectedContentHandleOwnership(props: {
	readonly handle: BridgeContentHandle;
	readonly expectedRole: BridgeContentRole;
	readonly selectedItem: BridgeReviewItemDescriptor;
	readonly reviewPackage: BridgeReviewPackage;
}): void {
	if (
		props.handle.itemId !== props.selectedItem.itemId ||
		props.handle.role !== props.expectedRole ||
		props.handle.reviewGeneration !== props.reviewPackage.reviewGeneration
	) {
		throw new Error('Bridge content handle does not match selected review item');
	}
}
