import type {
	BridgeProductRequestExecutor,
	BridgeProductRequestRoute,
} from './bridge-product-request-executor.js';

export const executeAgentStudioBridgeProductRequest: BridgeProductRequestExecutor = (
	route,
	requestInit,
): Promise<Response> => fetch(agentStudioEndpointForBridgeProductRoute(route), requestInit);

function agentStudioEndpointForBridgeProductRoute(route: BridgeProductRequestRoute): string {
	switch (route) {
		case 'command':
			return 'agentstudio://rpc/command';
		case 'content':
			return 'agentstudio://rpc/content';
		case 'stream':
			return 'agentstudio://rpc/stream';
	}
	throw new Error('Unsupported Bridge product request route.');
}
