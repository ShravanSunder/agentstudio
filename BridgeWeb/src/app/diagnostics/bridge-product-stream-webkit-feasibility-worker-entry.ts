import {
	runProductStreamWebKitFeasibilityProbe,
	type BridgeProductStreamWebKitFeasibilityRequest,
} from './bridge-product-stream-webkit-feasibility-probe.js';

self.addEventListener(
	'message',
	(event: MessageEvent<BridgeProductStreamWebKitFeasibilityRequest>): void => {
		void runProductStreamWebKitFeasibilityProbe(event.data);
	},
);
