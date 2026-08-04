import {
	type BridgeCommWorkerGlobalScope,
	registerBridgeCommWorkerEntry,
} from './bridge-comm-worker-entry.js';
import { executeHttpBridgeProductRequest } from './bridge-product-http-request-executor.js';

declare const self: BridgeCommWorkerGlobalScope;

registerBridgeCommWorkerEntry(self, {
	executeProductRequest: executeHttpBridgeProductRequest,
	maximumConcurrentContentResponses: 4,
});
