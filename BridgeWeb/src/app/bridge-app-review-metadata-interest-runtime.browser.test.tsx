import type { ReactElement } from 'react';
import { useState } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

import type { BridgeRPCClient, BridgeRPCCommand } from '../bridge/bridge-rpc-client.js';
import {
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import { useBridgeReviewMetadataInterestRuntime } from './bridge-app-review-metadata-interest-runtime.js';

describe('Bridge review metadata interest runtime', () => {
	test('replays current interest after bridge-ready when pre-ready dispatch was dropped', async () => {
		document.body.replaceChildren();
		const commandDetails: BridgeRPCCommand[] = [];
		let sendAccepted = false;
		const rpcClient: BridgeRPCClient = {
			sendCommand: (command): boolean => {
				commandDetails.push(command);
				return sendAccepted;
			},
		};
		const reviewPackage = makeReviewPackageWithIdentity({
			itemIds: ['item-a', 'item-b'],
			packageId: 'package-a',
			reviewGeneration: 7,
			revision: 11,
		});
		render(
			<RuntimeHarness
				reviewPackage={reviewPackage}
				rpcClient={rpcClient}
				selectedItemId="item-a"
				setVisibleContentItemIds={(): void => {}}
			/>,
		);

		await expect.poll(() => commandDetails.length).toBeGreaterThanOrEqual(2);
		const preReadyCommandCount = commandDetails.length;
		expect(lastCommandsByLane(commandDetails).foreground).toEqual(['item-a']);

		sendAccepted = true;
		requireHTMLButtonElement(document.querySelector('[data-testid="bridge-ready"]')).click();

		await expect.poll(() => commandDetails.length).toBeGreaterThan(preReadyCommandCount);
		expect(lastCommandsByLane(commandDetails).foreground).toEqual(['item-a']);
	});

	test('dispatches hook-driven interest updates and clears stale surface ids across package revisions', async () => {
		document.body.replaceChildren();
		const commandDetails: BridgeRPCCommand[] = [];
		const visibleContentItemIdsCalls: string[][] = [];
		const rpcClient: BridgeRPCClient = {
			sendCommand: (command): boolean => {
				commandDetails.push(command);
				return true;
			},
		};
		const packageRevisionA = makeReviewPackageWithIdentity({
			itemIds: ['item-a', 'item-b'],
			packageId: 'package-a',
			reviewGeneration: 7,
			revision: 11,
		});
		render(
			<RuntimeHarness
				reviewPackage={packageRevisionA}
				rpcClient={rpcClient}
				selectedItemId="item-a"
				setVisibleContentItemIds={(itemIds): void => {
					visibleContentItemIdsCalls.push([...itemIds]);
				}}
			/>,
		);

		await expect.poll(() => commandDetails.length).toBeGreaterThanOrEqual(2);
		expect(lastCommandsByLane(commandDetails)).toEqual({
			foreground: ['item-a'],
			visible: [],
		});

		requireHTMLButtonElement(document.querySelector('[data-testid="tree-visible"]')).click();
		requireHTMLButtonElement(document.querySelector('[data-testid="code-visible"]')).click();

		await expect.poll(() => lastCommandsByLane(commandDetails).visible).toEqual(['item-b']);
		expect(lastVisibleContentItemIdsCall(visibleContentItemIdsCalls)).toEqual(['item-a', 'item-b']);

		requireHTMLButtonElement(document.querySelector('[data-testid="clear-selected"]')).click();
		requireHTMLButtonElement(document.querySelector('[data-testid="clear-visible"]')).click();

		await expect
			.poll(() => lastCommandsByLane(commandDetails))
			.toEqual({
				foreground: [],
				visible: [],
			});

		requireHTMLButtonElement(document.querySelector('[data-testid="select-item-a"]')).click();
		requireHTMLButtonElement(document.querySelector('[data-testid="tree-visible"]')).click();

		await expect.poll(() => lastCommandsByLane(commandDetails).visible).toEqual(['item-b']);

		requireHTMLButtonElement(document.querySelector('[data-testid="switch-package"]')).click();

		await expect.poll(() => lastVisibleContentItemIdsCall(visibleContentItemIdsCalls)).toEqual([]);
		await expect
			.poll(() => lastCommandsByLane(commandDetails))
			.toEqual({
				foreground: ['item-a'],
				visible: [],
			});

		requireHTMLButtonElement(document.querySelector('[data-testid="tree-visible"]')).click();

		await expect.poll(() => lastCommandsByLane(commandDetails).visible).toEqual(['item-b']);
	});

	test('clears both interest lanes on hide and re-declares interest on show', async () => {
		document.body.replaceChildren();
		const commandDetails: BridgeRPCCommand[] = [];
		const rpcClient: BridgeRPCClient = {
			sendCommand: (command): boolean => {
				commandDetails.push(command);
				return true;
			},
		};
		const reviewPackage = makeReviewPackageWithIdentity({
			itemIds: ['item-a', 'item-b'],
			packageId: 'package-a',
			reviewGeneration: 7,
			revision: 11,
		});

		// Arrange: declare foreground (selected) + visible interest while the surface is active.
		render(
			<RuntimeHarness
				reviewPackage={reviewPackage}
				rpcClient={rpcClient}
				selectedItemId="item-a"
				setVisibleContentItemIds={(): void => {}}
			/>,
		);
		await expect.poll(() => commandDetails.length).toBeGreaterThanOrEqual(2);
		requireHTMLButtonElement(document.querySelector('[data-testid="tree-visible"]')).click();
		await expect
			.poll(() => lastCommandsByLane(commandDetails))
			.toEqual({
				foreground: ['item-a'],
				visible: ['item-b'],
			});

		// Act: hide the review surface.
		requireHTMLButtonElement(document.querySelector('[data-testid="set-inactive"]')).click();

		// Assert: both lanes are re-declared with empty item ids so native drops all interest.
		await expect
			.poll(() => lastCommandsByLane(commandDetails))
			.toEqual({
				foreground: [],
				visible: [],
			});

		// Act: show the review surface again.
		requireHTMLButtonElement(document.querySelector('[data-testid="set-active"]')).click();

		// Assert: selection re-declares immediately; visible re-declares once the surface reports again.
		await expect
			.poll(() => lastCommandsByLane(commandDetails))
			.toEqual({
				foreground: ['item-a'],
				visible: [],
			});
		requireHTMLButtonElement(document.querySelector('[data-testid="tree-visible"]')).click();
		await expect.poll(() => lastCommandsByLane(commandDetails).visible).toEqual(['item-b']);
	});
});

function RuntimeHarness(props: {
	readonly isActive?: boolean;
	readonly reviewPackage: BridgeReviewPackage;
	readonly rpcClient: BridgeRPCClient;
	readonly selectedItemId: string | null;
	readonly setVisibleContentItemIds: (itemIds: readonly string[]) => void;
}): ReactElement {
	const [reviewPackage, setReviewPackage] = useState(props.reviewPackage);
	const [bridgeReadyEpoch, setBridgeReadyEpoch] = useState(0);
	const [isActive, setIsActive] = useState(props.isActive ?? true);
	const [selectedItemId, setSelectedItemId] = useState<string | null>(props.selectedItemId);
	const runtime = useBridgeReviewMetadataInterestRuntime({
		authority: { paneId: 'pane-1', streamId: 'review:pane-1' },
		bridgeReadyEpoch,
		isActive,
		reviewPackage,
		rpcClient: props.rpcClient,
		selectedItemId,
		setVisibleContentItemIds: props.setVisibleContentItemIds,
	});
	return (
		<div>
			<button
				data-testid="bridge-ready"
				onClick={(): void => setBridgeReadyEpoch((currentEpoch) => currentEpoch + 1)}
				type="button"
			/>
			<button data-testid="set-inactive" onClick={(): void => setIsActive(false)} type="button" />
			<button data-testid="set-active" onClick={(): void => setIsActive(true)} type="button" />
			<button
				data-testid="tree-visible"
				onClick={(): void => runtime.onTreeVisibleItemIdsChange(['item-a', 'item-b'])}
				type="button"
			/>
			<button
				data-testid="code-visible"
				onClick={(): void => runtime.onCodeViewVisibleItemIdsChange(['item-b'])}
				type="button"
			/>
			<button
				data-testid="clear-visible"
				onClick={(): void => {
					runtime.onTreeVisibleItemIdsChange([]);
					runtime.onCodeViewVisibleItemIdsChange([]);
				}}
				type="button"
			/>
			<button
				data-testid="clear-selected"
				onClick={(): void => setSelectedItemId(null)}
				type="button"
			/>
			<button
				data-testid="select-item-a"
				onClick={(): void => setSelectedItemId('item-a')}
				type="button"
			/>
			<button
				data-testid="switch-package"
				onClick={(): void => {
					setReviewPackage(
						makeReviewPackageWithIdentity({
							itemIds: ['item-a', 'item-b'],
							packageId: 'package-b',
							reviewGeneration: reviewPackage.reviewGeneration,
							revision: 13,
						}),
					);
				}}
				type="button"
			/>
		</div>
	);
}

function makeReviewPackageWithIdentity(props: {
	readonly itemIds: readonly string[];
	readonly packageId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
}): BridgeReviewPackage {
	const itemsById = Object.fromEntries(
		props.itemIds.map((itemId): readonly [string, ReturnType<typeof makeBridgeReviewItem>] => [
			itemId,
			makeBridgeReviewItem({ itemId, path: `Sources/App/${itemId}.swift` }),
		]),
	);
	return {
		...makeBridgeReviewPackage(),
		itemsById,
		orderedItemIds: [...props.itemIds],
		packageId: props.packageId,
		reviewGeneration: props.reviewGeneration,
		revision: props.revision,
	};
}

function lastCommandsByLane(
	commands: readonly BridgeRPCCommand[],
): Readonly<Record<'foreground' | 'visible', readonly string[] | null>> {
	return {
		foreground: lastItemIdsForLane({
			commands,
			lane: 'foreground',
		}),
		visible: lastItemIdsForLane({
			commands,
			lane: 'visible',
		}),
	};
}

function lastItemIdsForLane(props: {
	readonly commands: readonly BridgeRPCCommand[];
	readonly lane: 'foreground' | 'visible';
}): readonly string[] | null {
	for (const command of props.commands.toReversed()) {
		if (
			command.method === 'bridge.metadata_interest.update' &&
			command.params.lane === props.lane
		) {
			return command.params.itemIds ?? [];
		}
	}
	return null;
}

function lastVisibleContentItemIdsCall(calls: readonly (readonly string[])[]): readonly string[] {
	return calls.at(-1) ?? [];
}

function requireHTMLButtonElement(element: Element | null): HTMLButtonElement {
	if (!(element instanceof HTMLButtonElement)) {
		throw new Error('Expected an HTML button element.');
	}
	return element;
}
