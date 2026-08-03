import type {
	BridgeProductRequestExecutor,
	BridgeProductRequestRoute,
} from './bridge-product-request-executor.js';

export const BRIDGE_PRODUCT_HTTP_COMMAND_ENDPOINT = '/__bridge-product/command';
export const BRIDGE_PRODUCT_HTTP_CONTENT_ENDPOINT = '/__bridge-product/content';
export const BRIDGE_PRODUCT_HTTP_STREAM_ENDPOINT = '/__bridge-product/stream';

export const executeHttpBridgeProductRequest: BridgeProductRequestExecutor = (
	route,
	requestInit,
): Promise<Response> => fetch(httpEndpointForBridgeProductRoute(route), requestInit);

function httpEndpointForBridgeProductRoute(route: BridgeProductRequestRoute): string {
	switch (route) {
		case 'command':
			return BRIDGE_PRODUCT_HTTP_COMMAND_ENDPOINT;
		case 'content':
			return BRIDGE_PRODUCT_HTTP_CONTENT_ENDPOINT;
		case 'stream':
			return BRIDGE_PRODUCT_HTTP_STREAM_ENDPOINT;
	}
	throw new Error('Unsupported Bridge product request route.');
}
