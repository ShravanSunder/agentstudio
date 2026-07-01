import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type { BridgeRPCClient, BridgeRPCCommand } from '../bridge/bridge-rpc-client.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewFrameAuthority } from './bridge-app-review-frame-authority.js';
import {
	reviewMetadataInterestIdentityForViewState,
	reviewMetadataInterestRequestsForViewState,
	type ReviewMetadataInterestIdentity,
	type ReviewMetadataInterestRequest,
} from './bridge-app-review-metadata-interest-controller.js';
import { uniqueReviewVisibleItemIds } from './bridge-app-review-metadata-package.js';

export interface ReviewMetadataInterestSurfaceState {
	readonly codeViewVisibleItemIds: readonly string[];
	readonly treeVisibleItemIds: readonly string[];
}

export interface ReviewMetadataInterestRuntimeState extends ReviewMetadataInterestSurfaceState {
	readonly activeSurfaceIdentityKey: string | null;
	readonly isActive: boolean;
	readonly surfaceIdentityKey: string | null;
}

export interface UseBridgeReviewMetadataInterestRuntimeProps {
	readonly authority: BridgeReviewFrameAuthority | null;
	readonly isActive: boolean;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly rpcClient: BridgeRPCClient;
	readonly selectedItemId: string | null;
	readonly setVisibleContentItemIds: (itemIds: readonly string[]) => void;
}

export interface BridgeReviewMetadataInterestRuntime {
	readonly onCodeViewVisibleItemIdsChange: (itemIds: readonly string[]) => void;
	readonly onTreeVisibleItemIdsChange: (itemIds: readonly string[]) => void;
}

interface ReviewMetadataInterestSurfaceSnapshot extends ReviewMetadataInterestSurfaceState {
	readonly surfaceIdentityKey: string | null;
}

const emptySurfaceSnapshot: ReviewMetadataInterestSurfaceSnapshot = {
	codeViewVisibleItemIds: [],
	surfaceIdentityKey: null,
	treeVisibleItemIds: [],
};

export function useBridgeReviewMetadataInterestRuntime(
	props: UseBridgeReviewMetadataInterestRuntimeProps,
): BridgeReviewMetadataInterestRuntime {
	const {
		authority,
		isActive,
		reviewPackage,
		rpcClient,
		selectedItemId,
		setVisibleContentItemIds,
	} = props;
	const latestDispatchIdentityRef = useRef<ReviewMetadataInterestIdentity | null>(null);
	const lastRequestSignatureRef = useRef<string | null>(null);
	const [surfaceSnapshot, setSurfaceSnapshot] =
		useState<ReviewMetadataInterestSurfaceSnapshot>(emptySurfaceSnapshot);
	const activeIdentity = useMemo(
		(): ReviewMetadataInterestIdentity | null =>
			reviewMetadataInterestIdentityForViewState({
				authority,
				reviewPackage,
			}),
		[authority, reviewPackage],
	);
	const activeSurfaceIdentityKey = reviewMetadataInterestSurfaceIdentityKeyForViewState({
		authority,
		reviewPackage,
	});
	const dispatchIdentity = activeIdentity ?? latestDispatchIdentityRef.current;
	const effectiveVisibleItemIds = useMemo(
		(): readonly string[] =>
			reviewMetadataInterestEffectiveVisibleItemIdsForRuntimeState({
				activeSurfaceIdentityKey,
				codeViewVisibleItemIds: surfaceSnapshot.codeViewVisibleItemIds,
				isActive,
				surfaceIdentityKey: surfaceSnapshot.surfaceIdentityKey,
				treeVisibleItemIds: surfaceSnapshot.treeVisibleItemIds,
			}),
		[activeSurfaceIdentityKey, isActive, surfaceSnapshot],
	);
	const requests = useMemo(
		(): readonly ReviewMetadataInterestRequest[] =>
			reviewMetadataInterestRequestsForViewState({
				identity: dispatchIdentity,
				isActive: isActive && activeIdentity !== null,
				reviewPackage,
				selectedItemId,
				visibleItemIds: effectiveVisibleItemIds,
			}),
		[
			activeIdentity,
			dispatchIdentity,
			effectiveVisibleItemIds,
			isActive,
			reviewPackage,
			selectedItemId,
		],
	);

	useEffect((): void => {
		if (activeIdentity !== null) {
			latestDispatchIdentityRef.current = activeIdentity;
		}
	}, [activeIdentity]);

	useEffect((): void => {
		const nextSurfaceIdentityKey = isActive ? activeSurfaceIdentityKey : null;
		setSurfaceSnapshot((currentSnapshot): ReviewMetadataInterestSurfaceSnapshot => {
			if (
				isActive &&
				nextSurfaceIdentityKey !== null &&
				currentSnapshot.surfaceIdentityKey === nextSurfaceIdentityKey
			) {
				return currentSnapshot;
			}
			return {
				codeViewVisibleItemIds: [],
				surfaceIdentityKey: nextSurfaceIdentityKey,
				treeVisibleItemIds: [],
			};
		});
	}, [activeSurfaceIdentityKey, isActive]);

	useEffect((): void => {
		setVisibleContentItemIds(effectiveVisibleItemIds);
	}, [effectiveVisibleItemIds, setVisibleContentItemIds]);

	useEffect((): void => {
		const requestSignature = JSON.stringify(requests);
		if (requestSignature === lastRequestSignatureRef.current) {
			return;
		}
		lastRequestSignatureRef.current = requestSignature;
		for (const request of requests) {
			sendReviewMetadataInterestRequest({
				request,
				rpcClient,
			});
		}
	}, [requests, rpcClient]);

	const onCodeViewVisibleItemIdsChange = useCallback(
		(itemIds: readonly string[]): void => {
			setSurfaceSnapshot(
				(currentSnapshot): ReviewMetadataInterestSurfaceSnapshot => ({
					...currentSnapshot,
					codeViewVisibleItemIds: itemIds,
					surfaceIdentityKey: activeSurfaceIdentityKey,
				}),
			);
		},
		[activeSurfaceIdentityKey],
	);
	const onTreeVisibleItemIdsChange = useCallback(
		(itemIds: readonly string[]): void => {
			setSurfaceSnapshot(
				(currentSnapshot): ReviewMetadataInterestSurfaceSnapshot => ({
					...currentSnapshot,
					surfaceIdentityKey: activeSurfaceIdentityKey,
					treeVisibleItemIds: itemIds,
				}),
			);
		},
		[activeSurfaceIdentityKey],
	);

	return {
		onCodeViewVisibleItemIdsChange,
		onTreeVisibleItemIdsChange,
	};
}

export function reviewMetadataInterestEffectiveVisibleItemIdsForRuntimeState(
	props: ReviewMetadataInterestRuntimeState,
): readonly string[] {
	if (
		!props.isActive ||
		props.activeSurfaceIdentityKey === null ||
		props.surfaceIdentityKey !== props.activeSurfaceIdentityKey
	) {
		return [];
	}
	return reviewMetadataInterestVisibleItemIdsForSurfaceState({
		codeViewVisibleItemIds: props.codeViewVisibleItemIds,
		treeVisibleItemIds: props.treeVisibleItemIds,
	});
}

export function reviewMetadataInterestVisibleItemIdsForSurfaceState(
	props: ReviewMetadataInterestSurfaceState,
): readonly string[] {
	return uniqueReviewVisibleItemIds([...props.treeVisibleItemIds, ...props.codeViewVisibleItemIds]);
}

export function reviewMetadataInterestSurfaceIdentityKeyForViewState(props: {
	readonly authority: BridgeReviewFrameAuthority | null;
	readonly reviewPackage: BridgeReviewPackage | null;
}): string | null {
	if (props.authority === null || props.reviewPackage === null) {
		return null;
	}
	return [
		props.authority.streamId,
		props.reviewPackage.packageId,
		String(props.reviewPackage.reviewGeneration),
		props.reviewPackage.revision,
	].join(':');
}

function sendReviewMetadataInterestRequest(props: {
	readonly request: ReviewMetadataInterestRequest;
	readonly rpcClient: BridgeRPCClient;
}): void {
	const command: BridgeRPCCommand = {
		method: 'bridge.metadata_interest.update',
		params: {
			...props.request,
			itemIds: [...props.request.itemIds],
		},
	};
	props.rpcClient.sendCommand(command);
}
