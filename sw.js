const CACHE = "bia-control-static-v26";
const SHELL = [
  "./login.html",
  "./report-excel-v2.js?v=20261021-5",
  "./index.html",
  "./manifest.webmanifest",
  "./pwa-mobile.css?v=20261021-5",
  "./favicon-bia.png?v=20261021-5",
  "./pwa-icon-192.png",
  "./pwa-icon-512.png",
  "./pwa-icon-maskable-512.png",
  "./brand/bia-honduras-logo.png",
  "./_next/static/css/6a3edeef37f07abf.css",
  "./_next/static/chunks/webpack-3453c084f985ffaa.js?v=20261021-5",
  "./_next/static/chunks/6e872619-786c051ee335684e.js",
  "./_next/static/chunks/278-af191a4015605946.js",
  "./_next/static/chunks/main-app-6a57d4249a0aab8a.js",
  "./_next/static/chunks/225f4a99-080ca0e0b4cc8aed.js",
  "./_next/static/chunks/212-6c11b835cb7b05c5.js",
  "./_next/static/chunks/app/page-e03e9ef51e579945.js?v=20261021-5",
  "./_next/static/chunks/1b4af218.422aa8c3a13a46c4.js",
  "./_next/static/chunks/44c1821e.1a5ccd9ecd1fe72f.js",
  "./_next/static/chunks/524.ea46500ef32268b6.js",
  "./_next/static/chunks/391.20261019photos.js",
  "./_next/static/chunks/polyfills-42372ed130431b0a.js",
  "./supabase-setup.sql",
  "./docs/Guia_Configuracion_Supabase_BIA.pdf",
];

// Clone synchronously before returning a response to the browser. Cache writes
// may finish later; they must never clone a body that has already been consumed.
function remember(event, request, response) {
  if (!response.ok) return response;
  const copy = response.clone();
  event.waitUntil(caches.open(CACHE).then(cache => cache.put(request, copy)).catch(() => {}));
  return response;
}
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(
    keys.filter(key => key.startsWith('bia-control-static-v') && key !== CACHE).map(key => caches.delete(key))
  )).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  const request = event.request, url = new URL(request.url);
  // Other apps, external libraries and APIs use the browser's normal network.
  if (request.method !== 'GET' || url.origin !== self.location.origin || !url.pathname.startsWith(new URL(self.registration.scope).pathname)) return;
  if (request.mode === 'navigate') {
    event.respondWith(fetch(request).then(response => remember(event, request, response)).catch(async () => {
      const cache = await caches.open(CACHE);
      return await cache.match(request) || await cache.match('./login.html') || new Response('Sin conexión. Recarga cuando se restablezca la red.', {status:503, headers:{'Content-Type':'text/plain; charset=utf-8'}});
    }));
    return;
  }
  if (!/\.(?:html|js|mjs|css|png|svg|webmanifest|ico|woff2?|jpg|jpeg|pdf|sql)$/.test(url.pathname)) return;
  event.respondWith(caches.open(CACHE).then(async cache => {
    const cached = await cache.match(request);
    if (cached) return cached;
    return fetch(request).then(response => remember(event, request, response));
  }));
});
self.addEventListener('message', event => { if (event.data === 'SKIP_WAITING') self.skipWaiting(); });
