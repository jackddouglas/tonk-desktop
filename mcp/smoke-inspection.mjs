// Read-only live check against the existing disposable packing-checklist fixture.
// The caller selects the private connection file; no credentials are printed.
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';

if (process.argv.length !== 3) throw new Error('Provide the private MCP connection file.');
const client = new Client({ name: 'tonk-inspection-smoke', version: '0.1.0' });
try {
  await client.connect(new StdioClientTransport({
    command: process.execPath,
    args: [fileURLToPath(new URL('./server.mjs', import.meta.url)), process.argv[2]],
    stderr: 'inherit',
  }));
  assert.deepEqual((await client.listTools()).tools.map(t => t.name).sort(), ['tonk_preview', 'tonk_query']);
  async function call(name, args) {
    const reply = await client.callTool({ name, arguments: args });
    assert.ok(!reply.isError, reply.content?.[0]?.text);
    assert.equal(reply.structuredContent.committed, false);
    return reply.structuredContent;
  }
  const before = await call('tonk_query', { target: 'packing-item' });
  const rows = before.matches.flatMap(block => block.results);
  assert.equal(rows.length, 3);
  const item = rows.find(row => row.fields.title === 'Check forecast together');
  assert.ok(item, 'Expected disposable inspection fixture');
  assert.match(item.this, /^did:key:z[1-9A-HJ-NP-Za-km-z]+$/);
  const preview = await call('tonk_preview', {
    document: `packing-item!:\n  this: ${item.this}\n  title: "MCP preview only - must not persist"\n`,
  });
  const after = await call('tonk_query', { target: 'packing-item' });
  assert.deepEqual(preview.revision, before.revision);
  assert.deepEqual(after.revision, before.revision);
  assert.deepEqual(after.matches, before.matches);
  const invalid = await client.callTool({ name: 'tonk_preview', arguments: { document: 'not-valid: [' } });
  assert.equal(invalid.isError, true);
  console.log('PASS: external MCP discovery, live query, dry-run assertion, unchanged revision/records, and notation error.');
} finally {
  await client.close();
}
