import type { ReactElement } from 'react';
import { useRef, useState } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

import { createBridgeDemandScheduler } from '../core/demand/bridge-demand-scheduler.js';
import { createBridgeResourceExecutor } from '../core/demand/bridge-resource-executor.js';
import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../core/resources/bridge-resource-registry.js';
import type { BridgeTextResourceStreamResult } from '../core/resources/bridge-resource-stream.js';
import {
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import {
	createDeferred,
	registerPackageContentDescriptors,
} from '../review-viewer/content/review-content-demand-loader.test-support.js';
import { createBridgeReviewContentRegistry } from '../review-viewer/content/review-content-registry.js';
import { useBridgeReviewContentPrefetchController } from './bridge-app-review-content-prefetch-controller.js';

describe('Bridge review content prefetch controller', () => {
	test('does not retry the same speculative item when the effect re-arms after cleanup', async () => {
		document.body.replaceChildren();
		const reviewPackage = makeReviewPackageWithItemIds(['item-selected', 'item-prefetch']);
		const descriptorRegistry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const attachedDescriptorsByHandleId = registerPackageContentDescriptors({
			registry: descriptorRegistry,
			reviewPackage,
		});
		const descriptorRefsByHandleId = new Map<string, BridgeDescriptorRef>(
			Array.from(attachedDescriptorsByHandleId).map(
				([handleId, attachedDescriptor]): readonly [string, BridgeDescriptorRef] => [
					handleId,
					attachedDescriptor.ref,
				],
			),
		);
		const requestedDescriptorIds: string[] = [];
		const neverResolvingLoad = createDeferred<{
			readonly content: BridgeTextResourceStreamResult;
			readonly byteLength: number;
		}>();
		const resourceExecutor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry: descriptorRegistry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => {
				requestedDescriptorIds.push(descriptor.descriptorId);
				return await neverResolvingLoad.promise;
			},
		});

		render(
			<PrefetchHarness
				descriptorRefsByHandleId={descriptorRefsByHandleId}
				resourceExecutor={resourceExecutor}
				reviewPackage={reviewPackage}
			/>,
		);

		await expect.poll(() => requestedDescriptorIds.length).toBeGreaterThan(0);
		requireHTMLButtonElement(document.querySelector('[data-testid="pause-prefetch"]')).click();
		await expect
			.poll(() =>
				document
					.querySelector('[data-testid="prefetch-state"]')
					?.getAttribute('data-scroll-active'),
			)
			.toBe('true');
		requireHTMLButtonElement(document.querySelector('[data-testid="resume-prefetch"]')).click();

		await expect
			.poll(() => requestedDescriptorIds)
			.toEqual(['descriptor-handle-item-prefetch-base', 'descriptor-handle-item-prefetch-head']);
	});

	test('does not prefetch item ids owned by visible hydration', async () => {
		document.body.replaceChildren();
		const reviewPackage = makeReviewPackageWithItemIds(['item-selected', 'item-prefetch']);
		const descriptorRegistry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const attachedDescriptorsByHandleId = registerPackageContentDescriptors({
			registry: descriptorRegistry,
			reviewPackage,
		});
		const descriptorRefsByHandleId = new Map<string, BridgeDescriptorRef>(
			Array.from(attachedDescriptorsByHandleId).map(
				([handleId, attachedDescriptor]): readonly [string, BridgeDescriptorRef] => [
					handleId,
					attachedDescriptor.ref,
				],
			),
		);
		const requestedDescriptorIds: string[] = [];
		const resourceExecutor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry: descriptorRegistry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ descriptor }) => {
				requestedDescriptorIds.push(descriptor.descriptorId);
				return {
					content: {
						authoritative: true,
						byteLength: 4,
						readText: (): string => 'text',
					},
					byteLength: 4,
				};
			},
		});

		render(
			<PrefetchHarness
				descriptorRefsByHandleId={descriptorRefsByHandleId}
				resourceExecutor={resourceExecutor}
				reviewPackage={reviewPackage}
				visibleOwnedItemIds={new Set(['item-prefetch'])}
			/>,
		);

		await expect.poll(() => requestedDescriptorIds).toEqual([]);
	});

	test('does not abort an in-flight speculative prefetch when visible ownership changes', async () => {
		document.body.replaceChildren();
		const reviewPackage = makeReviewPackageWithItemIds([
			'item-selected',
			'item-prefetch',
			'item-visible',
		]);
		const descriptorRegistry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const attachedDescriptorsByHandleId = registerPackageContentDescriptors({
			registry: descriptorRegistry,
			reviewPackage,
		});
		const descriptorRefsByHandleId = new Map<string, BridgeDescriptorRef>(
			Array.from(attachedDescriptorsByHandleId).map(
				([handleId, attachedDescriptor]): readonly [string, BridgeDescriptorRef] => [
					handleId,
					attachedDescriptor.ref,
				],
			),
		);
		const loadSignals: AbortSignal[] = [];
		const neverResolvingLoad = createDeferred<{
			readonly content: BridgeTextResourceStreamResult;
			readonly byteLength: number;
		}>();
		const resourceExecutor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry: descriptorRegistry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: 4096,
			maxQueuedLoads: 8,
			maxQueuedBytes: 4096,
			loadResource: async ({ signal }) => {
				loadSignals.push(signal);
				return await neverResolvingLoad.promise;
			},
		});

		render(
			<PrefetchHarness
				descriptorRefsByHandleId={descriptorRefsByHandleId}
				resourceExecutor={resourceExecutor}
				reviewPackage={reviewPackage}
				showVisibleOwnershipToggle
			/>,
		);

		await expect.poll(() => loadSignals.length).toBeGreaterThan(0);
		requireHTMLButtonElement(document.querySelector('[data-testid="own-visible-item"]')).click();

		await expect.poll(() => loadSignals[0]?.aborted ?? null).toBe(false);
	});
});

function PrefetchHarness(props: {
	readonly descriptorRefsByHandleId: ReadonlyMap<string, BridgeDescriptorRef>;
	readonly resourceExecutor: ReturnType<
		typeof createBridgeResourceExecutor<BridgeTextResourceStreamResult>
	>;
	readonly reviewPackage: BridgeReviewPackage;
	readonly showVisibleOwnershipToggle?: boolean;
	readonly visibleOwnedItemIds?: ReadonlySet<string>;
}): ReactElement {
	const [isCodeViewScrollActive, setIsCodeViewScrollActive] = useState(false);
	const [visibleOwnedItemIds, setVisibleOwnedItemIds] = useState<ReadonlySet<string>>(
		props.visibleOwnedItemIds ?? new Set<string>(),
	);
	const contentRegistryRef = useRef(createBridgeReviewContentRegistry());
	const descriptorRefsByHandleIdRef = useRef(props.descriptorRefsByHandleId);
	descriptorRefsByHandleIdRef.current = props.descriptorRefsByHandleId;
	const demandSchedulerRef = useRef(
		createBridgeDemandScheduler({
			maxQueuedIntentsPerLane: 8,
			maxQueuedEstimatedBytes: 4096,
		}),
	);
	useBridgeReviewContentPrefetchController({
		contentRegistry: contentRegistryRef.current,
		isActive: true,
		isCodeViewScrollActive,
		resourceExecutor: props.resourceExecutor,
		reviewContentDescriptorRefsByHandleIdRef: descriptorRefsByHandleIdRef,
		reviewContentInvalidationVersion: 0,
		reviewDemandScheduler: demandSchedulerRef.current,
		reviewPackage: props.reviewPackage,
		selectedContentLoading: false,
		selectedItemId: 'item-selected',
		visibleOwnedItemIds,
		visibleLoadingItemCount: 0,
	});
	return (
		<div data-scroll-active={String(isCodeViewScrollActive)} data-testid="prefetch-state">
			<button
				data-testid="pause-prefetch"
				type="button"
				onClick={(): void => {
					setIsCodeViewScrollActive(true);
				}}
			/>
			<button
				data-testid="resume-prefetch"
				type="button"
				onClick={(): void => {
					setIsCodeViewScrollActive(false);
				}}
			/>
			{props.showVisibleOwnershipToggle === true ? (
				<button
					data-testid="own-visible-item"
					type="button"
					onClick={(): void => {
						setVisibleOwnedItemIds(new Set(['item-visible']));
					}}
				/>
			) : null}
		</div>
	);
}

function makeReviewPackageWithItemIds(itemIds: readonly string[]): BridgeReviewPackage {
	const basePackage = makeBridgeReviewPackage();
	const itemsById = Object.fromEntries(
		itemIds.map((itemId): readonly [string, ReturnType<typeof makeBridgeReviewItem>] => [
			itemId,
			makeBridgeReviewItem({ itemId, path: `Sources/${itemId}.swift` }),
		]),
	);
	return {
		...basePackage,
		orderedItemIds: [...itemIds],
		itemsById,
	};
}

function requireHTMLButtonElement(element: Element | null): HTMLButtonElement {
	if (!(element instanceof HTMLButtonElement)) {
		throw new Error('Expected button element');
	}
	return element;
}
