import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

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
	readonly bridgeReadyEpoch: number;
	readonly isActive: boolean;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly sendMetadataInterestRequest: (
		request: ReviewMetadataInterestRequest,
	) => Promise<boolean>;
	readonly setVisibleContentItemIds: (itemIds: readonly string[]) => void;
}

export interface BridgeReviewMetadataInterestRuntime {
	readonly onCodeViewVisibleItemIdsChange: (itemIds: readonly string[]) => void;
	readonly onTreeVisibleItemIdsChange: (itemIds: readonly string[]) => void;
}

interface ReviewMetadataInterestSurfaceSnapshot extends ReviewMetadataInterestSurfaceState {
	readonly surfaceIdentityKey: string | null;
}

interface PendingMetadataInterestRetryBatch {
	readonly requestSignature: string;
	readonly requestKeys: ReadonlySet<string>;
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
		bridgeReadyEpoch,
		isActive,
		reviewPackage,
		selectedItemId,
		sendMetadataInterestRequest,
		setVisibleContentItemIds,
	} = props;
	const latestDispatchIdentityRef = useRef<ReviewMetadataInterestIdentity | null>(null);
	const lastRequestSignatureRef = useRef<string | null>(null);
	const pendingRetryBatchRef = useRef<PendingMetadataInterestRetryBatch | null>(null);
	const retryAttemptSignatureRef = useRef<string | null>(null);
	const retryAttemptsByRequestKeyRef = useRef<Map<string, number>>(new Map());
	const [surfaceSnapshot, setSurfaceSnapshot] =
		useState<ReviewMetadataInterestSurfaceSnapshot>(emptySurfaceSnapshot);
	const [retryEpoch, setRetryEpoch] = useState(0);
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
		const requestSignature = JSON.stringify({ bridgeReadyEpoch, requests });
		if (retryAttemptSignatureRef.current !== requestSignature) {
			retryAttemptsByRequestKeyRef.current.clear();
			retryAttemptSignatureRef.current = requestSignature;
		}
		const pendingRetryBatch = pendingRetryBatchRef.current;
		if (pendingRetryBatch !== null && pendingRetryBatch.requestSignature !== requestSignature) {
			pendingRetryBatchRef.current = null;
		}
		const retryRequestKeys =
			pendingRetryBatch?.requestSignature === requestSignature
				? pendingRetryBatch.requestKeys
				: null;
		if (
			requestSignature === lastRequestSignatureRef.current &&
			(retryRequestKeys === null || retryRequestKeys.size === 0)
		) {
			return;
		}
		const requestsToSend =
			retryRequestKeys === null
				? requests
				: requests.filter((request): boolean =>
						retryRequestKeys.has(metadataInterestRequestRetryKey(request)),
					);
		if (requestsToSend.length === 0) {
			pendingRetryBatchRef.current = null;
			return;
		}
		lastRequestSignatureRef.current = requestSignature;
		void Promise.all(
			requestsToSend.map(
				async (request): Promise<{ readonly didSend: boolean; readonly requestKey: string }> => ({
					didSend: await sendMetadataInterestRequest(request),
					requestKey: metadataInterestRequestRetryKey(request),
				}),
			),
		).then((results): void => {
			if (lastRequestSignatureRef.current !== requestSignature) {
				return;
			}
			const retryRequestKeysForFailures: string[] = [];
			for (const result of results) {
				if (result.didSend) {
					retryAttemptsByRequestKeyRef.current.delete(result.requestKey);
					continue;
				}
				if (
					bridgeReadyEpoch > 0 &&
					metadataInterestRetryAttemptAvailable({
						requestKey: result.requestKey,
						retryAttemptsByRequestKey: retryAttemptsByRequestKeyRef.current,
					})
				) {
					retryRequestKeysForFailures.push(result.requestKey);
				}
			}
			if (retryRequestKeysForFailures.length === 0) {
				pendingRetryBatchRef.current = null;
				return;
			}
			pendingRetryBatchRef.current = {
				requestKeys: new Set(retryRequestKeysForFailures),
				requestSignature,
			};
			if (lastRequestSignatureRef.current === requestSignature) {
				setRetryEpoch((currentRetryEpoch): number => currentRetryEpoch + 1);
			}
		});
	}, [bridgeReadyEpoch, requests, retryEpoch, sendMetadataInterestRequest]);

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

function metadataInterestRetryAttemptAvailable(props: {
	readonly requestKey: string;
	readonly retryAttemptsByRequestKey: Map<string, number>;
}): boolean {
	const currentAttemptCount = props.retryAttemptsByRequestKey.get(props.requestKey) ?? 0;
	if (currentAttemptCount >= 3) {
		return false;
	}
	props.retryAttemptsByRequestKey.set(props.requestKey, currentAttemptCount + 1);
	return true;
}

function metadataInterestRequestRetryKey(request: ReviewMetadataInterestRequest): string {
	return JSON.stringify(request);
}
