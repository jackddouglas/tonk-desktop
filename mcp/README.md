# Local Tonk MCP experiment

Two read-only tools, `tonk_query` and `tonk_preview`, run inside the running Tonk
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
there is no forced network pull. Background sync can still run. Apply, revision-
aware render completion, guide resources and non-Mac runtime hosts are not yet
implemented. The app's agent still uses the CLI for writes.

Run `npm test` for a separate-process SDK client/server test; `swift test --filter
LocalRuntimeBridgeTests` covers the real native loopback authorization boundary.
