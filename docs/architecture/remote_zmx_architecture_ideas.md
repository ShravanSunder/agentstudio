# Remote zmx Architecture

This document captures architectural thinking around running zmx daemons on remote machines with Agent Studio connecting as a thin client, and the longer-term case for forking zmx.

## Context

zmx is a terminal session multiplexer that runs as a daemon-client model over Unix sockets. The daemon owns the PTY and shell process, persists across app disconnections, and maintains an internal `ghostty_vt` terminal for session state serialization. Agent Studio currently uses zmx for local session persistence — surviving app restarts without losing terminal state.

The natural extension: run zmx daemons on remote servers, connect from Agent Studio over the network.

## The Terminfo Problem

Ghostty's creator has discussed the architectural difficulty of SSH and remote terminal sessions. The core issue is **terminfo propagation**: when a terminal connects to a remote host, the remote side needs to know what escape sequences and capabilities the terminal supports. If `$TERM=ghostty` isn't in the remote's terminfo database, applications fall back to lowest-common-denominator behavior — losing true color, styled underlines, Kitty keyboard protocol, and OSC sequences.

Ghostty solves this by auto-injecting its terminfo database into remote hosts during SSH connections. This is tightly coupled to Ghostty's native SSH implementation and unavailable through generic TCP tunnels.

For zmx remote daemons, the inner `ghostty_vt` sets `TERM=ghostty` when spawning the shell. The terminfo must be present on the remote host for this to work correctly.

## Three Architecture Options

### Option A: Ghostty SSH + zmx IPC over TCP

```
LOCAL (macOS)                              REMOTE (Server)
+----------------------+                   +--------------------------+
|  Agent Studio        |                   |                          |
|                      |                   |  +---------------------+ |
|  +----------------+  |   Ghostty SSH     |  |  Ghostty SSH Server | |
|  | Ghostty Surface|--+----------------->|  |  +- terminfo inject | |
|  | (outer term)   |  |  (PTY channel)    |  |  +- PTY-A --> ???  | |
|  +----------------+  |                   |  +---------------------+ |
|                      |                   |         ^ CONFLICT       |
|  +----------------+  |   TCP tunnel      |  +------+--------------+ |
|  | ZmxIPCClient   |--+----------------->|  |  zmx daemon         | |
|  | (control only) |  |  (IPC protocol)   |  |  +- ghostty_vt      | |
|  +----------------+  |                   |  |  +- PTY-B --> zsh  | |
|                      |                   |  +---------------------+ |
+----------------------+                   +--------------------------+
```

**Problem**: Two PTYs. Ghostty SSH owns PTY-A, zmx daemon owns PTY-B. Who runs the shell? They fight unless zmx can attach to Ghostty's SSH-created PTY — which it cannot today. Would require fundamental zmx architecture changes.

### Option B: zmx IPC over Raw TCP

```
LOCAL (macOS)                              REMOTE (Server)
+----------------------+                   +--------------------------+
|  Agent Studio        |                   |                          |
|                      |                   |  +---------------------+ |
|  +----------------+  |                   |  |  zmx daemon         | |
|  | Ghostty Surface|  |                   |  |  +- ghostty_vt      | |
|  | (outer term)   |  |   Raw TCP         |  |  |  (TERM=ghostty)  | |
|  |                |<-+----------------->|  |  +- PTY --> zsh    | |
|  +-------+--------+  |  (all IPC tags)   |  +---------------------+ |
|          |           |                   |                          |
|  +-------+--------+  |  Output bytes     |  Must solve:            |
|  | ZmxIPCClient   |  |  flow over same   |  - terminfo install     |
|  | (all commands) |  |  TCP connection    |  - TCP port exposure    |
|  +----------------+  |                   |  - Auth (none built-in) |
+----------------------+                   +--------------------------+
```

Simplest architecture — one connection carries everything. But no encryption, no authentication, no terminfo injection. Must solve security entirely outside zmx.

### Option C: zmx IPC over SSH Tunnel (Recommended)

```
LOCAL (macOS)                              REMOTE (Server)
+----------------------+                   +--------------------------+
|  Agent Studio        |                   |                          |
|                      |                   |  +---------------------+ |
|  +----------------+  |                   |  |  zmx daemon         | |
|  | Ghostty Surface|  |                   |  |  +- ghostty_vt      | |
|  | (outer term)   |  |                   |  |  |  (TERM=ghostty)  | |
|  |                |  |                   |  |  +- PTY --> zsh    | |
|  +-------+--------+  |                   |  +----------+----------+ |
|          |           |                   |             |            |
|  +-------+--------+  |   SSH tunnel      |    Unix socket           |
|  | ZmxIPCClient   |--+----------------->|    /tmp/zmx-{id}.sock   |
|  |                |  |  (socket fwd)     |                          |
|  +----------------+  |                   |  zmx daemon listens on   |
|                      |  ssh -L local:    |  Unix socket as usual -- |
|  local Unix socket --+--/tmp/zmx.sock    |  zero changes needed     |
|  (mode 0700)         |                   |                          |
+----------------------+                   +--------------------------+
```

SSH provides encryption, authentication, key management, and socket forwarding. zmx daemon requires zero changes — still listens on its Unix socket. Agent Studio connects to the forwarded local socket as if it were local.

### Comparison

| Criterion | A: Ghostty SSH + TCP | B: Raw TCP | C: SSH Tunnel |
|-----------|---------------------|------------|---------------|
| PTY conflict | Yes — two PTYs | None | None |
| Auth/Encryption | Ghostty SSH handles | DIY | SSH handles |
| Terminfo | Auto-injected | Manual install | ghostty_vt sets TERM |
| zmx changes required | Major | Minor (TCP listener) | **None** |
| Complexity | High | Medium | **Low** |
| Security model | Mixed | Weak | **Strong (battle-tested)** |

**Option C is the clear winner.** It requires zero zmx changes, leverages SSH's battle-tested security, and the IPC protocol passes through byte-for-byte since SSH is transparent at the transport layer.

## Security Model (Option C)

### Layer 1: SSH Authentication

Standard SSH key/certificate authentication. Agent Studio manages SSH connections — key selection, passphrase prompts (via Keychain), MFA if configured. This is the identity layer: "who is allowed to reach the remote machine?"

### Layer 2: Unix Socket Permissions (Remote)

zmx daemon sockets are created with owner-only permissions (mode `0700`). The SSH session runs as the authenticated user. The kernel enforces that only processes running as that UID can connect to the socket. Another user SSH'd into the same box cannot access your zmx sockets.

### Layer 3: Unix Socket Permissions (Local)

The critical refinement: use **socket forwarding** instead of TCP port forwarding.

```bash
# TCP port forwarding (weaker)
ssh -L 9999:/tmp/zmx-{id}.sock remote
# Any local process can connect to localhost:9999

# Socket forwarding (stronger)
ssh -L /tmp/zmx-local-{id}.sock:/tmp/zmx-{id}.sock remote
# Only your UID can connect to the local socket (mode 0700)
```

Socket forwarding mirrors zmx's existing security model symmetrically: remote socket perms protect the remote side, local socket perms protect the local side.

### Layer 4: zmx Daemon (Current State)

Today, zmx accepts any connection to its socket without authentication. No token, no handshake beyond Init. Any process that can open the socket can send keystrokes, read output, resize, or kill the session.

This is acceptable because Unix socket permissions are the access control boundary. The same trust model applies to local terminals — any process running as your user can read your PTY.

### Threat Model

| Threat | Mitigation | Status |
|--------|-----------|--------|
| Unauthorized remote access | SSH authentication | Solved by SSH |
| Cross-user access on remote | Unix socket perms (0700) | Solved by OS |
| Local process snooping (TCP port) | Use socket forwarding, not TCP port | Solved by design choice |
| Local process snooping (Unix socket) | Socket perms (0700), same as local terminal | Acceptable — matches tmux/screen model |
| Man-in-the-middle | SSH encryption | Solved by SSH |
| Session hijacking after SSH disconnect | zmx daemon keeps running, socket perms still enforced | Acceptable |

### SSH Connection Management

```
SSH ControlMaster for connection reuse:

  ~/.ssh/config:
    Host devbox
      ControlMaster auto
      ControlPath ~/.ssh/sockets/%r@%h-%p
      ControlPersist 10m

Multiple zmx sessions share ONE SSH connection.
No extra auth prompts. Single tunnel, multiple socket forwards.
Agent Studio manages ControlMaster lifecycle.
```

## Agent Studio Integration

### Connection Lifecycle

```
1. User adds remote host in Agent Studio
   +- SSH identity configured (key, host, user)
   +- Agent Studio tests connectivity

2. User creates terminal pane targeting remote host
   +- Agent Studio establishes SSH connection (ControlMaster)
   +- SSH forwards zmx socket to local Unix socket
   +- ZmxIPCClient connects to local socket
   +- From here, identical to local zmx flow

3. Session persistence
   +- zmx daemon persists on remote (survives disconnect)
   +- Agent Studio reconnects SSH tunnel on next launch
   +- ZmxIPCClient reattaches to existing daemon
   +- Terminal state restored from daemon's ghostty_vt

4. Disconnect handling
   +- SSH drops: ZmxIPCClient detects broken socket
   +- Agent Studio shows "disconnected" state on pane
   +- Auto-reconnect with backoff
   +- On reconnect: re-forward socket, reattach, restore state
```

### Data Flow

```
Local zmx (today):
  ZmxIPCClient --> Unix socket --> zmx daemon --> PTY --> shell

Remote zmx (Option C):
  ZmxIPCClient --> local Unix socket --> SSH tunnel --> remote Unix socket --> zmx daemon --> PTY --> shell
                   (forwarded)          (encrypted)    (original)

The ZmxIPCClient code is identical in both cases.
Only the socket path changes.
```

## The Case for Forking zmx

zmx is a young project that serves Agent Studio's needs well for basic session persistence. However, several architectural directions suggest a fork will become necessary:

### Why Fork

1. **IPC protocol extensions**: Agent Studio needs richer session metadata, health reporting, and potentially new IPC tags (snapshot, configuration) that may not align with upstream's goals.

2. **The two-terminal problem**: zmx's inner `ghostty_vt` and the outer Ghostty surface can diverge in behavior (prompt redraw, cursor position, resize timing). Fundamental fixes may require architectural changes upstream won't accept.

3. **Remote-first features**: Session token authentication, TCP listener mode, connection multiplexing — these serve Agent Studio's remote architecture but add complexity upstream may not want.

4. **Tight Ghostty coupling**: zmx depends on Ghostty's terminal internals (`ghostty_vt`). As both Ghostty and Agent Studio evolve, the integration surface may need changes that serve Agent Studio specifically.

5. **Build system integration**: Currently a git submodule with Zig build. Deeper integration with Agent Studio's Swift/SPM build pipeline may require structural changes.

### Fork Strategy

**Phase 1 — Contribute upstream**: Continue contributing fixes (like PR #112 for prompt redraw). Build relationship with maintainer. Understand which changes are welcome.

**Phase 2 — Soft fork**: Maintain a fork with Agent Studio-specific patches on top of upstream main. Regularly rebase. Upstream what's accepted.

**Phase 3 — Hard fork (if needed)**: If architectural directions permanently diverge, maintain an independent fork. Rename to avoid confusion. Credit and license compliance.

### What a Fork Would Change

| Area | Upstream zmx | Agent Studio Fork |
|------|-------------|-------------------|
| IPC protocol | Current 11 tags | Extended with health, snapshot, config |
| Authentication | None (socket perms only) | Optional session tokens |
| Transport | Unix socket only | Unix socket + TCP listener |
| Inner terminal | Full ghostty_vt with resize | Potentially simplified (no resize, state-only) |
| Session metadata | Basic (pid, cmd, cwd) | Rich (labels, groups, remote host, reconnect info) |
| Build | Standalone Zig | Integrated with Agent Studio build |

### What NOT to Fork

Ghostty's terminal internals (`ghostty_vt`, escape sequence parsing, terminal state machine) should never be forked. These are complex, well-maintained, and zmx's value comes from leveraging them. A fork changes the daemon's IPC and session management layer, not the terminal core.

## Open Questions

1. **Terminfo on remote hosts**: How does Agent Studio ensure `ghostty` terminfo is installed on remote servers? Auto-install on first connect? Require manual setup?

2. **Latency budget**: What's the acceptable latency for live terminal interaction over SSH tunnel? Resize SIGWINCH relay adds SSH round-trip on top of existing zmx relay latency.

3. **Multiple remote hosts**: How does Agent Studio's UI represent sessions across different hosts? Per-host grouping in sidebar?

4. **File sync**: Terminal sessions are remote, but Agent Studio's workspace model is local. How do project files relate to remote terminals?

5. **zmx daemon management**: Who starts/stops zmx daemons on remote hosts? Agent Studio via SSH commands? A remote agent? Manual user setup?
