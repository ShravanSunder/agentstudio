import type { z } from 'zod';

import { bridgeProductExactUtf8IdentitySet } from './bridge-product-exact-utf8-identity.js';

export function validateBridgeProductSubscriptionDeltaCollection(props: {
	readonly addedValues: readonly string[];
	readonly context: z.RefinementCtx;
	readonly maximumItemCount: number;
	readonly path: readonly (number | string)[];
	readonly removedPath: readonly (number | string)[];
	readonly removedValues: readonly string[];
}): void {
	const addedIdentityKeySet = bridgeProductExactUtf8IdentitySet(props.addedValues);
	const removedIdentityKeySet = bridgeProductExactUtf8IdentitySet(props.removedValues);
	if (addedIdentityKeySet.size !== props.addedValues.length) {
		props.context.addIssue({
			code: 'custom',
			message: 'Bridge product subscription delta additions must be unique.',
			path: [...props.path],
		});
	}
	if (removedIdentityKeySet.size !== props.removedValues.length) {
		props.context.addIssue({
			code: 'custom',
			message: 'Bridge product subscription delta removals must be unique.',
			path: [...props.removedPath],
		});
	}
	if ([...addedIdentityKeySet].some((identityKey) => removedIdentityKeySet.has(identityKey))) {
		props.context.addIssue({
			code: 'custom',
			message: 'Bridge product subscription delta cannot add and remove the same member.',
			path: [...props.path],
		});
	}
	if (props.addedValues.length + props.removedValues.length > props.maximumItemCount) {
		props.context.addIssue({
			code: 'custom',
			message: 'Bridge product subscription delta exceeds its aggregate item ceiling.',
			path: [...props.path],
		});
	}
}
