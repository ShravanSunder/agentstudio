import type { BridgeProductDeadlineClock } from './bridge-product-deadline-clock.js';

export class BridgeProductContentProgressDeadlineExpired extends Error {
	readonly retryable = true;

	constructor() {
		super('Bridge product content read made no progress within its deadline.');
		this.name = 'BridgeProductContentProgressDeadlineExpired';
	}
}

/** Bounds one pending network step; every verified chunk starts a fresh step. */
export async function awaitBridgeProductContentProgress<TValue>(props: {
	readonly abortRead: () => void;
	readonly clock: BridgeProductDeadlineClock;
	readonly delayMilliseconds: number;
	readonly pending: () => Promise<TValue>;
}): Promise<TValue> {
	let cancelDeadline: () => void = (): void => {};
	const expired = new Promise<never>((_, reject): void => {
		cancelDeadline = props.clock.schedule(props.delayMilliseconds, (): void => {
			reject(new BridgeProductContentProgressDeadlineExpired());
			props.abortRead();
		});
	});
	try {
		return await Promise.race([props.pending(), expired]);
	} finally {
		cancelDeadline();
	}
}
