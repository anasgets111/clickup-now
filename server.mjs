import { createServer } from 'node:http';
/** @import { IncomingMessage, ServerResponse } from 'node:http' */
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

process.loadEnvFile();
/** @param {string} why @returns {never} */
function die(why) {
  console.error(why);
  process.exit(1);
}

const TOKEN = process.env.CLICKUP_TOKEN
  ?? die('Missing CLICKUP_TOKEN. Copy .env.example to .env and paste your token.');

const PUBLIC = resolve(fileURLToPath(new URL('./public', import.meta.url)));
/** @type {Record<string, string>} */
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };
const OURS = ['http://localhost:4400', 'http://127.0.0.1:4400'];

/** @param {IncomingMessage} req @param {ServerResponse} res */
async function proxy(req, res) {
  // Any page in the browser can reach 127.0.0.1, and this holds a token that can change
  // the workspace. CORS blocks reading a reply, but a no-cors POST still fires. Refuse a
  // foreign Origin; same-origin requests omit the header or send one of ours.
  const from = req.headers.origin;
  if (from && !OURS.includes(from)) return res.writeHead(403).end('{}');

  const chunks = [];
  for await (const c of req) chunks.push(c);
  // Pass the caller's content-type through. Uploads are multipart and carry the boundary.
  /** @type {Record<string, string>} */
  const headers = { Authorization: TOKEN };
  if (req.headers['content-type']) headers['content-type'] = req.headers['content-type'];
  const r = await fetch('https://api.clickup.com/api/v2' + (req.url ?? '').slice(4), {
    method: req.method,
    headers,
    body: chunks.length ? Buffer.concat(chunks) : undefined,
  });
  res.writeHead(r.status, { 'content-type': 'application/json' });
  res.end(await r.text());
}

createServer(async (req, res) => {
  // Node types url as optional. Read it once so the rest does not care.
  const url = req.url ?? '/';
  if (url.startsWith('/api/')) {
    // If the upstream body fails mid-read the status is already out, and a second
    // writeHead would throw and take the server down.
    return proxy(req, res).catch(() => {
      if (!res.headersSent) res.writeHead(502, { 'content-type': 'application/json' });
      res.end('{}');
    });
  }
  let path;
  try {
    path = decodeURIComponent(url.split('?')[0]);
  } catch {
    return res.writeHead(400).end('Bad path');
  }
  const file = resolve(PUBLIC, '.' + (path === '/' ? '/index.html' : path));
  if (!file.startsWith(PUBLIC + sep)) return res.writeHead(403).end('Nope');
  let body;
  try {
    body = await readFile(file);
  } catch {
    return res.writeHead(404).end('Not found');
  }
  // A local tool edited in place: never let the browser hold a stale page.
  res.writeHead(200, {
    'content-type': TYPES[extname(file)] ?? 'application/octet-stream',
    'cache-control': 'no-store',
  });
  res.end(body);
}).listen(4400, '127.0.0.1', () => console.log('http://localhost:4400'));
