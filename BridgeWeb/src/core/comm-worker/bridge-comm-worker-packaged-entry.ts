import {
	type BridgeCommWorkerGlobalScope,
	registerBridgeCommWorkerEntry,
} from './bridge-comm-worker-entry.js';
import { executeAgentStudioBridgeProductRequest } from './bridge-product-agent-studio-request-executor.js';

declare const self: BridgeCommWorkerGlobalScope;

registerBridgeCommWorkerEntry(self, {
	executeProductRequest: executeAgentStudioBridgeProductRequest,
});
