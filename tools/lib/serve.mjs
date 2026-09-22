import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { extname, join, normalize, resolve } from 'node:path';
import { repoRoot } from './rig.mjs';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.riv': 'application/octet-stream',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.map': 'application/json; charset=utf-8',
};

const RUNTIME_DIR = resolve(repoRoot, 'tools', 'node_modules', '@rive-app', 'webgl2');

/**
 * Serves the lab over http so the Rive runtime's wasm loads with the right MIME
 * type (opening lab/index.html via file:// fails on the wasm fetch).
 *
 * Routes:
 *   /              -> lab/index.html
 *   /vendor/*      -> the pinned @rive-app/webgl2 runtime from node_modules
 *   /rig/*, /app/* -> repo files, so a .riv can be loaded straight from the tree
 */
export function serveLab({ port = 4321, host = '127.0.0.1' } = {}) {
  const runtimeAvailable = existsSync(join(RUNTIME_DIR, 'rive.js'));

  const server = createServer((req, res) => {
    const url = new URL(req.url, `http://${req.headers.host}`);
    let pathname = decodeURIComponent(url.pathname);
    if (pathname === '/') pathname = '/lab/index.html';

    let filePath;
    if (pathname.startsWith('/vendor/')) {
      filePath = join(RUNTIME_DIR, pathname.slice('/vendor/'.length));
    } else if (pathname.startsWith('/lab/') || pathname.startsWith('/rig/') || pathname.startsWith('/app/')) {
      filePath = join(repoRoot, pathname);
    } else {
      filePath = join(repoRoot, 'lab', pathname);
    }

    // Containment check: reject anything that escapes the allowed roots.
    const resolved = normalize(filePath);
    const allowed = [resolve(repoRoot, 'lab'), resolve(repoRoot, 'rig'), resolve(repoRoot, 'app'), RUNTIME_DIR];
    if (!allowed.some((root) => resolved === root || resolved.startsWith(root + '/'))) {
      res.writeHead(403).end('Forbidden');
      return;
    }

    if (!existsSync(resolved) || !statSync(resolved).isFile()) {
      res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      res.end(`404 ${pathname}`);
      return;
    }

    res.writeHead(200, {
      'content-type': MIME[extname(resolved).toLowerCase()] ?? 'application/octet-stream',
      // The lab is a dev tool; never let a stale bundle or .riv be cached.
      'cache-control': 'no-store',
    });
    createReadStream(resolved).pipe(res);
  });

  return new Promise((resolvePromise) => {
    server.listen(port, host, () => resolvePromise({ server, url: `http://${host}:${port}/`, runtimeAvailable }));
  });
}
