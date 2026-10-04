# Local Tonk MCP experiment

By default two read-only tools, `tonk_query` and `tonk_preview`, run inside the running Tonk
Town worker. No CLI process or second replica is created. MCP stdio uses the
official TypeScript SDK; a small authenticated loopback transport connects the
adapter to the native host. It is local IPC, not the Tonk sync server.

Build the app with `bash scripts/build-app.sh`. Quit the running instance, then
launch it with one explicit space capability:

```sh
open '.build/Tonk Town.app' --args --staging --mcp-space 'did:key:YOUR_SPACE'
```

The account must already have access to that space. Switching the displayed space
does not retarget external tools. Quit the app to stop access. Relaunching rotates
the token; restart the MCP client afterward. The bridge is off unless launched
with `--mcp-space`. It binds only 127.0.0.1, requires a fresh bearer token, rejects
browser-origin requests and accepts only the two read-only operations.

For an agent authorized to build in this pinned space, add `--mcp-write` when
launching the app. This also exposes `tonk_apply`. Pass the exact `revision` from
preview as `expectedRevision` together with the document. A changed head rejects
the write; read and preview again. A timeout or disconnected reply is an unknown
outcome: query first and never automatically repeat the write. This requires a
worker with `/evaluate/conditional`; older workers reject it and the harness does
not fall back to unconditional evaluation. Changing this flag requires restarting
the app and MCP client. It does not broaden which space the connection can access.

Install the adapter dependencies with `cd mcp && npm ci --ignore-scripts` (Node 22+).
Configure any local MCP host to run:

```json
{
  "command": "/absolute/path/to/node",
  "args": [
    "/absolute/path/to/tonk-town/mcp/server.mjs",
    "/Users/YOU/Library/Application Support/Tonk Town Staging/MCP/connection.json"
  ]
}
```

For production the support directory is `Tonk Town`. Keep this private connection
file out of source control, logs and agent context; it grants access to the pinned
space's read-only operations. The adapter reads it directly. Neither an MCP client
nor its model receives account grants or chooses arbitrary URLs, scripts or spaces.

Preview validates notation; it does not commit, render proposed UI, or compute a
proposed-state diff. Results describe the local replica at the reported revision;
there is no forced network pull. Background sync can still run. Conditional apply
reports a local revision, not confirmation of rendered UI or remote sync. Revision-
aware render completion, guide resources and non-Mac runtime hosts remain pending.
The conditional worker patch must be installed before using direct writes; the
existing CLI remains available during migration.

Run `npm test` for a separate-process SDK client/server test; `swift test --filter
LocalRuntimeBridgeTests` covers the real native loopback authorization boundary.
