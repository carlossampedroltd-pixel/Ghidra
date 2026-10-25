// Offline shell: network-first for our own files (so updates arrive right away),
// cache fallback when offline. Google APIs and model downloads are not touched.
const CACHE = 'notrafree-v2';
const SHELL = ['./', 'index.html', 'styles.css', 'app.js', 'db.js', 'drive.js', 'ble.js', 'audio.js',
  'summarize.js', 'settings.js', 'transcribe-worker.js', 'llm.js', 'llm-worker.js', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png', 'apple-touch-icon.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return;
  e.respondWith(
    fetch(e.request)
      .then((resp) => {
        const copy = resp.clone();
        caches.open(CACHE).then((c) => c.put(e.request, copy));
        return resp;
      })
      .catch(() => caches.match(e.request, { ignoreSearch: true })),
  );
});
