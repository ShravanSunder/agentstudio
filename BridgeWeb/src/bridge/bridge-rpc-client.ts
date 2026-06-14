export type BridgeRPCId = string | number;

export interface BridgeRPCCommand {
	readonly id?: BridgeRPCId;
	readonly method: string;
	readonly params?: unknown;
}

export interface BridgeRPCClient {
	readonly sendCommand: (command: BridgeRPCCommand) => boolean;
}

export interface CreateBridgeRPCClientProps {
	readonly target?: EventTarget;
	readonly getBridgeNonce?: () => string | null;
	readonly createCommandId?: () => string;
}

export function createBridgeRPCClient(props: CreateBridgeRPCClientProps = {}): BridgeRPCClient {
	const target = props.target ?? document;
	const getBridgeNonce = props.getBridgeNonce ?? defaultBridgeNonceReader;
	const createCommandId = props.createCommandId ?? defaultCommandIdFactory;

	return {
		sendCommand: (command: BridgeRPCCommand): boolean => {
			const bridgeNonce = getBridgeNonce();
			if (bridgeNonce === null) {
				return false;
			}
			target.dispatchEvent(
				new CustomEvent('__bridge_command', {
					detail: makeCommandDetail(command, bridgeNonce, createCommandId()),
				}),
			);
			return true;
		},
	};
}

function makeCommandDetail(
	command: BridgeRPCCommand,
	bridgeNonce: string,
	commandId: string,
): Readonly<Record<string, unknown>> {
	return {
		jsonrpc: '2.0',
		...(command.id === undefined ? {} : { id: command.id }),
		method: command.method,
		...(command.params === undefined ? {} : { params: command.params }),
		__nonce: bridgeNonce,
		__commandId: commandId,
	};
}

function defaultBridgeNonceReader(): string | null {
	return document.documentElement.getAttribute('data-bridge-nonce');
}

function defaultCommandIdFactory(): string {
	return `cmd_${crypto.randomUUID()}`;
}
