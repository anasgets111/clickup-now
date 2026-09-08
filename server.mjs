import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

process.loadEnvFile();
const TOKEN = process.env.CLICKUP_TOKEN;
if (!TOKEN) {
  console.error('Missing CLICKUP_TOKEN. Copy .env.example to .env and paste your token.');
  process.exit(1);
}

const PUBLIC = resolve(fileURLToPath(new URL('./public', import.meta.url)));
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };

async function proxy(req, res) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  // Pass the caller's content-type through rather than forcing JSON: file uploads are
  // multipart and the boundary lives in that header.
  const headers = { Authorization: TOKEN };
  if (req.headers['content-type']) headers['content-type'] = req.headers['content-type'];
  const r = await fetch('https://api.clickup.com/api/v2' + req.url.slice(4), {
    method: req.method,
    headers,
    body: chunks.length ? Buffer.concat(chunks) : undefined,
  });
  res.writeHead(r.status, { 'content-type': 'application/json' });
  res.end(await r.text());
}

createServer(async (req, res) => {
  if (req.url.startsWith('/api/')) return proxy(req, res).catch(() => res.writeHead(502).end('{}'));
  let path;
  try {
    path = decodeURIComponent(req.url.split('?')[0]);
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
