const CACHE = "bia-control-static-v10";
const SHELL = [
  "./index.html",
  "./manifest.webmanifest",
  "./pwa-mobile.css?v=20260925-2",
  "./favicon.svg",
  "./pwa-icon-192.png",
  "./pwa-icon-512.png",
  "./pwa-icon-maskable-512.png",
  "./brand/bia-honduras-logo.png",
  "./_next/static/css/6a3edeef37f07abf.css",
  "./_next/static/chunks/webpack-3453c084f985ffaa.js?v=20260925-2",
  "./_next/static/chunks/6e872619-786c051ee335684e.js",
  "./_next/static/chunks/278-af191a4015605946.js",
  "./_next/static/chunks/main-app-6a57d4249a0aab8a.js",
  "./_next/static/chunks/225f4a99-080ca0e0b4cc8aed.js",
  "./_next/static/chunks/212-6c11b835cb7b05c5.js",
  "./_next/static/chunks/app/page-e03e9ef51e579945.js?v=20260925-8",
  "./_next/static/chunks/1b4af218.422aa8c3a13a46c4.js",
  "./_next/static/chunks/44c1821e.1a5ccd9ecd1fe72f.js",
  "./_next/static/chunks/524.ea46500ef32268b6.js",
  "./_next/static/chunks/391.6f3b75d9c2a8410e.js",
  "./_next/static/chunks/polyfills-42372ed130431b0a.js",
  "./supabase-setup.sql",
  "./docs/Guia_Configuracion_Supabase_BIA.pdf",
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key)))).then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== "GET" || url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put(new URL("./index.html", self.location.href), copy));
          return response;
        })
        .catch(() => caches.match(new URL("./index.html", self.location.href))),
    );
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) =>
      cached || fetch(request).then((response) => {
        if (response.ok) caches.open(CACHE).then((cache) => cache.put(request, response.clone()));
        return response;
      }),
    ),
  );
});
