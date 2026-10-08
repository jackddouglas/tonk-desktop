import { fileURLToPath, pathToFileURL } from 'node:url';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// The sync script records the selected checkout outside source control.
let localRoot;
try { localRoot = readFileSync(new URL('./.canonical-root', import.meta.url), 'utf8').trim(); }
catch (error) { if (error.code !== 'ENOENT') throw error; }
const root = process.env.TONK_MCP_ROOT || localRoot || fileURLToPath(new URL('../../tonk/mcp/', import.meta.url));
export const sharedModule = name => pathToFileURL(resolve(root, name)).href;
