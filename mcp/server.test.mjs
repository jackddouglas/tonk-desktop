import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, writeFile, rm, chmod } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';
import { connectRuntime } from './runtime-client.mjs';

test('external stdio client discovers tools, calls both and receives operation errors', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'tonk-mcp-test-'));
  const token = 'a'.repeat(72);
  const calls = [];
  const host = createServer(async (req, res) => {
    assert.equal(req.headers.authorization, `Bearer ${token}`);
    let body = '';
    for await (const chunk of req) body += chunk;
    const value = JSON.parse(body);
    res.setHeader('content-type', 'application/json');
    if (req.url === '/tools') {
      res.end(JSON.stringify({ tools: ['tonk_query', 'tonk_preview'].map(name => ({
        name, description: 'Fixture tool', annotations: { readOnlyHint: true },
        inputSchema: { type: 'object', additionalProperties: false,
          properties: { [name === 'tonk_query' ? 'target' : 'document']: { type: 'string' } },
          required: [name === 'tonk_query' ? 'target' : 'document'] },
      })) }));
    } else {
      calls.push(value);
      res.end(JSON.stringify(value.arguments.document === 'bad'
        ? { error: 'Notation failed validation.' }
        : { result: { committed: false, revision: 'fixture', matches: [] } }));
    }
  });
  await new Promise(resolve => host.listen(0, '127.0.0.1', resolve));
  const config = join(directory, 'connection.json');
  await writeFile(config, JSON.stringify({ version: 1, url: `http://127.0.0.1:${host.address().port}`, token }), { mode: 0o600 });
  const client = new Client({ name: 'independent-test-client', version: '1.0.0' });
  try {
    await client.connect(new StdioClientTransport({
      command: process.execPath,
      args: [fileURLToPath(new URL('./server.mjs', import.meta.url)), config],
      stderr: 'pipe',
    }));
    assert.deepEqual((await client.listTools()).tools.map(tool => tool.name).sort(), ['tonk_preview', 'tonk_query']);
    for (const [name, args] of [['tonk_query', { target: 'packing-item' }], ['tonk_preview', { document: 'packing-item:\n' }]]) {
      const result = await client.callTool({ name, arguments: args });
      assert.equal(result.isError, undefined);
      assert.deepEqual(result.structuredContent, { committed: false, revision: 'fixture', matches: [] });
    }
    const failed = await client.callTool({ name: 'tonk_preview', arguments: { document: 'bad' } });
    assert.equal(failed.isError, true);
    assert.match(failed.content[0].text, /failed validation/);
    assert.equal(calls.length, 3);
    const invalid = await client.callTool({ name: 'tonk_query', arguments: { target: 'thing', space: 'other' } });
    assert.equal(invalid.isError, true);
    assert.equal(calls.length, 3, 'invalid arguments must not reach host');
    await chmod(config, 0o644);
    await assert.rejects(connectRuntime(config), /private file/);
  } finally {
    await client.close();
    await new Promise(resolve => host.close(resolve));
    await rm(directory, { recursive: true, force: true });
  }
});
