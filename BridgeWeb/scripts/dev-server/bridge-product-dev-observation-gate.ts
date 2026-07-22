export type BridgeProductDevObservationDisposition = 'accepted' | 'idempotentReplay' | 'rejected';

export interface BridgeProductDevObservationGateSnapshot {
	readonly hasOutstandingObservation: boolean;
	readonly waiterCount: number;
}

interface BridgeProductDevOutstandingObservation<TObservation> {
	readonly key: string;
	readonly observation: TObservation;
	readonly onObserved: (() => void) | undefined;
	readonly reject: (error: Error) => void;
	readonly resolve: () => void;
}

export class BridgeProductDevObservationGate<TObservation> {
	readonly #identityKey: (observation: TObservation) => string;
	#lastAcceptedKey: string | null = null;
	#outstanding: BridgeProductDevOutstandingObservation<TObservation> | null = null;

	constructor(identityKey: (observation: TObservation) => string = defaultObservationIdentityKey) {
		this.#identityKey = identityKey;
	}

	register(props: {
		readonly observation: TObservation;
		readonly onObserved?: () => void;
	}): Promise<void> {
		if (this.#outstanding !== null) {
			throw new Error('Bridge product dev observation gate already owns an outstanding frame.');
		}
		const key = this.#identityKey(props.observation);
		return new Promise<void>((resolve, reject): void => {
			this.#outstanding = {
				key,
				observation: props.observation,
				onObserved: props.onObserved,
				reject,
				resolve,
			};
		});
	}

	observe(observation: TObservation): BridgeProductDevObservationDisposition {
		const key = this.#identityKey(observation);
		const outstanding = this.#outstanding;
		if (outstanding !== null && outstanding.key === key) {
			this.#outstanding = null;
			this.#lastAcceptedKey = key;
			outstanding.onObserved?.();
			outstanding.resolve();
			return 'accepted';
		}
		return this.#lastAcceptedKey === key ? 'idempotentReplay' : 'rejected';
	}

	cancel(reason = 'Bridge product dev observation gate was cancelled.'): void {
		const outstanding = this.#outstanding;
		if (outstanding === null) return;
		this.#outstanding = null;
		outstanding.reject(new Error(reason));
	}

	snapshot(): BridgeProductDevObservationGateSnapshot {
		return {
			hasOutstandingObservation: this.#outstanding !== null,
			waiterCount: this.#outstanding === null ? 0 : 1,
		};
	}
}

function defaultObservationIdentityKey(observation: unknown): string {
	return JSON.stringify(sortObservationValue(observation));
}

function sortObservationValue(value: unknown): unknown {
	if (Array.isArray(value)) return value.map(sortObservationValue);
	if (typeof value !== 'object' || value === null) return value;
	return Object.fromEntries(
		Object.entries(value)
			.toSorted(([leftKey], [rightKey]) => leftKey.localeCompare(rightKey))
			.map(([key, entryValue]) => [key, sortObservationValue(entryValue)]),
	);
}
