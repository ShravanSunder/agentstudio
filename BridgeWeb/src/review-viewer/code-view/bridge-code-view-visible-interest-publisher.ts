export interface BridgeCodeViewVisibleInterestPublisher {
	readonly cancel: () => void;
	readonly publishAtScrollIdle: () => void;
	readonly publishDuringScroll: () => void;
}

export interface CreateBridgeCodeViewVisibleInterestPublisherProps<TTimeoutHandle> {
	readonly clearTimeout: (handle: TTimeoutHandle) => void;
	readonly now: () => number;
	readonly publish: () => void;
	readonly setTimeout: (callback: () => void, delayMilliseconds: number) => TTimeoutHandle;
	readonly throttleMilliseconds: number;
}

export function createBridgeCodeViewVisibleInterestPublisher<TTimeoutHandle>(
	props: CreateBridgeCodeViewVisibleInterestPublisherProps<TTimeoutHandle>,
): BridgeCodeViewVisibleInterestPublisher {
	let lastPublishedAtMilliseconds: number | null = null;
	let pendingTimeoutHandle: TTimeoutHandle | null = null;

	const clearPendingTimeout = (): void => {
		if (pendingTimeoutHandle === null) {
			return;
		}
		props.clearTimeout(pendingTimeoutHandle);
		pendingTimeoutHandle = null;
	};
	const publishNow = (): void => {
		lastPublishedAtMilliseconds = props.now();
		props.publish();
	};

	return {
		cancel: (): void => {
			clearPendingTimeout();
			lastPublishedAtMilliseconds = null;
		},
		publishAtScrollIdle: (): void => {
			clearPendingTimeout();
			lastPublishedAtMilliseconds = null;
			props.publish();
		},
		publishDuringScroll: (): void => {
			const nowMilliseconds = props.now();
			if (
				lastPublishedAtMilliseconds === null ||
				nowMilliseconds - lastPublishedAtMilliseconds >= props.throttleMilliseconds
			) {
				clearPendingTimeout();
				publishNow();
				return;
			}
			if (pendingTimeoutHandle !== null) {
				return;
			}
			pendingTimeoutHandle = props.setTimeout(
				(): void => {
					pendingTimeoutHandle = null;
					publishNow();
				},
				props.throttleMilliseconds - (nowMilliseconds - lastPublishedAtMilliseconds),
			);
		},
	};
}
