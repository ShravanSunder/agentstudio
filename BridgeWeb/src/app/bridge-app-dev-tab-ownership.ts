import { uuidv7 } from 'uuidv7';

const bridgeAppDevTabOwnershipLockName = 'agentstudio.bridge.dev-tab-bootstrap.v1';
const bridgeAppDevTabCurrentOwnerStorageKey = 'agentstudio.bridge.dev-tab-current-owner.v1';
const bridgeAppDevTabSupersededStorageKey = 'agentstudio.bridge.dev-tab-superseded.v1';
const bridgeAppDevTabSupersededStorageValue = 'superseded';
const bridgeAppDevTabMaximumOwnerIdLength = 128;

interface BridgeAppDevTabStorageEventTarget {
	addEventListener(type: 'storage', listener: (event: BridgeAppDevTabStorageEvent) => void): void;
	removeEventListener(
		type: 'storage',
		listener: (event: BridgeAppDevTabStorageEvent) => void,
	): void;
}

interface BridgeAppDevTabStorageEvent {
	readonly key: string | null;
}

type BridgeAppDevTabRunExclusive = <TResult>(
	operation: (signal: AbortSignal) => Promise<TResult>,
	signal: AbortSignal,
) => Promise<TResult>;

export interface BridgeAppDevTabOwnership {
	readonly clearSuperseded: () => void;
	readonly dispose: () => void;
	readonly isSuperseded: () => boolean;
	readonly runBootstrap: <TResult>(
		operation: () => Promise<TResult>,
		signal: AbortSignal,
	) => Promise<TResult>;
}

export function createBridgeAppDevTabOwnership(props: {
	readonly onSuperseded: () => void;
	readonly ownerId?: string;
	readonly runExclusive?: BridgeAppDevTabRunExclusive;
	readonly sharedStorage?: Pick<Storage, 'getItem' | 'setItem'>;
	readonly storage?: Pick<Storage, 'getItem' | 'removeItem' | 'setItem'>;
	readonly storageEventTarget?: BridgeAppDevTabStorageEventTarget;
}): BridgeAppDevTabOwnership {
	const ownerId = validateOwnerId(props.ownerId ?? uuidv7());
	const storage = props.storage ?? requireSessionStorage();
	const sharedStorage = props.sharedStorage ?? requireLocalStorage();
	const storageEventTarget = props.storageEventTarget ?? requireStorageEventTarget();
	const runExclusive = props.runExclusive ?? runUnderWebLock;
	let disposed = false;
	let hasClaimedOwnership = false;
	let superseded =
		storage.getItem(bridgeAppDevTabSupersededStorageKey) === bridgeAppDevTabSupersededStorageValue;
	const becomeSuperseded = (): void => {
		if (superseded) return;
		superseded = true;
		storage.setItem(bridgeAppDevTabSupersededStorageKey, bridgeAppDevTabSupersededStorageValue);
		props.onSuperseded();
	};

	const receiveOwnershipChange = (event: BridgeAppDevTabStorageEvent): void => {
		if (
			event.key !== bridgeAppDevTabCurrentOwnerStorageKey ||
			disposed ||
			superseded ||
			!hasClaimedOwnership
		)
			return;
		const currentOwnerId = sharedStorage.getItem(bridgeAppDevTabCurrentOwnerStorageKey);
		if (currentOwnerId === null || currentOwnerId === ownerId) return;
		becomeSuperseded();
	};
	storageEventTarget.addEventListener('storage', receiveOwnershipChange);

	return {
		clearSuperseded: (): void => {
			superseded = false;
			hasClaimedOwnership = false;
			storage.removeItem(bridgeAppDevTabSupersededStorageKey);
		},
		dispose: (): void => {
			if (disposed) return;
			disposed = true;
			storageEventTarget.removeEventListener('storage', receiveOwnershipChange);
		},
		isSuperseded: (): boolean => superseded,
		runBootstrap: async <TResult>(
			operation: () => Promise<TResult>,
			signal: AbortSignal,
		): Promise<TResult> => {
			assertBootstrapMayRun({ disposed, superseded });
			signal.throwIfAborted();
			return await runExclusive(async (exclusiveSignal): Promise<TResult> => {
				assertBootstrapMayRun({ disposed, superseded });
				exclusiveSignal.throwIfAborted();
				if (
					hasClaimedOwnership &&
					sharedStorage.getItem(bridgeAppDevTabCurrentOwnerStorageKey) !== ownerId
				) {
					becomeSuperseded();
					assertBootstrapMayRun({ disposed, superseded });
				}
				const result = await operation();
				exclusiveSignal.throwIfAborted();
				assertBootstrapMayRun({ disposed, superseded });
				hasClaimedOwnership = true;
				sharedStorage.setItem(bridgeAppDevTabCurrentOwnerStorageKey, ownerId);
				return result;
			}, signal);
		},
	};
}

function assertBootstrapMayRun(props: {
	readonly disposed: boolean;
	readonly superseded: boolean;
}): void {
	if (props.disposed) throw new Error('Bridge app development-tab ownership is disposed.');
	if (props.superseded) throw new Error('Bridge app development tab is superseded.');
}

function requireLocalStorage(): Storage {
	if (typeof localStorage === 'undefined') {
		throw new Error('Bridge app development-tab ownership requires localStorage.');
	}
	return localStorage;
}

function requireSessionStorage(): Storage {
	if (typeof sessionStorage === 'undefined') {
		throw new Error('Bridge app development-tab ownership requires sessionStorage.');
	}
	return sessionStorage;
}

function requireStorageEventTarget(): BridgeAppDevTabStorageEventTarget {
	if (typeof window === 'undefined') {
		throw new Error('Bridge app development-tab ownership requires window storage events.');
	}
	return window;
}

async function runUnderWebLock<TResult>(
	operation: (signal: AbortSignal) => Promise<TResult>,
	signal: AbortSignal,
): Promise<TResult> {
	if (typeof navigator === 'undefined' || navigator.locks === undefined) {
		throw new Error('Bridge app development-tab ownership requires the Web Locks API.');
	}
	return await navigator.locks.request(
		bridgeAppDevTabOwnershipLockName,
		{ mode: 'exclusive', signal },
		async (): Promise<TResult> => await operation(signal),
	);
}

function validateOwnerId(ownerId: string): string {
	if (ownerId.length === 0 || ownerId.length > bridgeAppDevTabMaximumOwnerIdLength) {
		throw new Error('Bridge app development-tab owner ID is outside its bounds.');
	}
	return ownerId;
}
