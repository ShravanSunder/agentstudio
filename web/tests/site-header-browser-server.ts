import { dev } from "astro";

const [websiteRoot, portArgument] = process.argv.slice(2);
const port = Number(portArgument);
if (websiteRoot === undefined || !Number.isInteger(port)) {
  throw new Error("Header browser-test server requires a website root and integer port");
}

const server = await dev({
  logLevel: "silent",
  root: websiteRoot,
  server: { host: "127.0.0.1", port },
  vite: { server: { strictPort: true } },
});
if (process.send === undefined) {
  await server.stop();
  throw new Error("Header browser-test server requires an IPC owner");
}
process.send({ kind: "ready", port: server.address.port });

const stopServer = async (): Promise<void> => {
  await server.stop();
  process.exit(0);
};

process.once("SIGTERM", (): void => {
  void stopServer();
});

await new Promise<void>(() => undefined);
