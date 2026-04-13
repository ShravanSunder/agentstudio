/**
 * Bridge command sender — dispatches __bridge_command CustomEvents.
 *
 * Creates properly formatted JSON-RPC 2.0 command events with nonce
 * and optional commandId for idempotency.
 */

let commandCounter = 0;

export interface SendCommandOptions {
  method: string;
  params?: Record<string, unknown>;
  /** Optional command ID for idempotency. Auto-generated if not provided. */
  commandId?: string;
  /** JSON-RPC request ID for request/response methods. */
  id?: number | string;
}

/**
 * Dispatch a command to the bridge via __bridge_command CustomEvent.
 *
 * @param nonce - The bridge nonce from the DOM attribute `data-bridge-nonce`
 * @param options - Command details
 */
export function sendCommand(
  nonce: string,
  options: SendCommandOptions,
): string {
  const commandId =
    options.commandId ?? `cmd-${Date.now()}-${++commandCounter}`;

  const detail: Record<string, unknown> = {
    jsonrpc: "2.0",
    method: options.method,
    params: options.params ?? {},
    __nonce: nonce,
    __commandId: commandId,
  };

  if (options.id !== undefined) {
    detail.id = options.id;
  }

  document.dispatchEvent(
    new CustomEvent("__bridge_command", { detail }),
  );

  return commandId;
}

/**
 * Read the bridge nonce from the DOM.
 * Returns null if not available (bridge not initialized).
 */
export function getBridgeNonce(): string | null {
  return document.documentElement.getAttribute("data-bridge-nonce");
}

/** Reset counter. Call between tests. */
export function resetSender(): void {
  commandCounter = 0;
}
