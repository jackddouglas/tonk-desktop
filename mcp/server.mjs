import { McpServer } from '@modelcontextprotocol/server';
import { serveStdio } from '@modelcontextprotocol/server/stdio';
import * as z from 'zod/v4';
import { connectRuntime } from './runtime-client.mjs';

const path = process.argv[2];
if (!path || process.argv.length !== 3) {
  console.error('Usage: node server.mjs /absolute/path/to/MCP/connection.json');
  process.exit(1);
}

try {
  const callRuntime = await connectRuntime(path);
  const { tools } = await callRuntime('/tools', {});
  if (!Array.isArray(tools) || !['tonk_preview,tonk_query', 'tonk_apply,tonk_preview,tonk_query'].includes(
      tools.map(tool => tool.name).sort().join(','))) {
    throw new Error('The runtime exposes an unsupported tool contract.');
  }
  serveStdio(() => {
    const server = new McpServer({ name: 'tonk-runtime', version: '0.1.0' });
    for (const tool of tools) {
      server.registerTool(tool.name, {
        description: tool.description,
        inputSchema: z.fromJSONSchema(tool.inputSchema),
        annotations: tool.annotations,
      }, async (args, context) => {
        try {
          const response = await callRuntime('/call', { name: tool.name, arguments: args }, context.signal);
          if (typeof response.error === 'string') {
            return { isError: true, content: [{ type: 'text', text: response.error }] };
          }
          if (!response.result || typeof response.result !== 'object' || Array.isArray(response.result)) {
            throw new Error('Invalid runtime result.');
          }
          return {
            content: [{ type: 'text', text: JSON.stringify(response.result) }],
            structuredContent: response.result,
          };
        } catch {
          const text = tool.name === 'tonk_apply'
            ? 'The write outcome is unknown. Reconnect and query the space before deciding what to do. Do not repeat the write automatically.'
            : 'The local runtime connection failed. Reconnect to Tonk Town and retry this read-only operation.';
          return { isError: true, content: [{ type: 'text', text }] };
        }
      });
    }
    return server;
  }, { onerror: () => console.error('MCP transport error.') });
} catch {
  // Credentials, paths and space contents never belong in startup diagnostics.
  console.error('Could not connect to the local Tonk runtime. Check that the app is running with --mcp-space and that its private connection file is available.');
  process.exitCode = 1;
}
