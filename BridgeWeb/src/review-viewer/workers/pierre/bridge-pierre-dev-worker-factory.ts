import pierrePortableWorkerSource from '@pierre/diffs/worker/worker-portable.js?raw';

import {
	createBridgePierreBlobWorkerFactory,
	type BridgePierreBlobWorkerFactory,
} from './bridge-pierre-worker-pool.js';

export function createBridgePierrePortableBlobWorkerFactory(): BridgePierreBlobWorkerFactory {
	return createBridgePierreBlobWorkerFactory({
		workerSource: pierrePortableWorkerSource,
	});
}
