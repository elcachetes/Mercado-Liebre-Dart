// Service worker de Mercado Liebre (PWA). Lo registra index.html.
//
// Estrategia "primero la red": con internet todo llega fresco del servidor
// (nginx ya marca index.html y main.dart.js como no-cache), y cada respuesta
// se guarda en la caché para poder abrir la app sin conexión.
//
// Nunca toca /api/, /medios/ ni /salud: los datos siempre van al servidor.
//
// Si cambias la lista ESENCIALES o la estrategia, sube la versión de CACHE
// para que los navegadores borren la caché anterior.
const CACHE = 'mercado-liebre-v2';

// Lo mínimo para mostrar la app y su icono sin red.
const ESENCIALES = [
  './',
  'index.html',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
];

// nginx manda ETag y Last-Modified: si coinciden, la copia guardada ya es la vigente.
function mismaVersion(guardada, nueva) {
  const etag = nueva.headers.get('ETag');
  if (etag) {
    return guardada.headers.get('ETag') === etag;
  }
  const fecha = nueva.headers.get('Last-Modified');
  return fecha !== null && guardada.headers.get('Last-Modified') === fecha;
}

self.addEventListener('install', (evento) => {
  evento.waitUntil(
    caches.open(CACHE)
      .then((cache) => cache.addAll(ESENCIALES))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (evento) => {
  evento.waitUntil(
    caches.keys()
      .then((nombres) => Promise.all(nombres.filter((n) => n !== CACHE).map((n) => caches.delete(n))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (evento) => {
  const peticion = evento.request;
  if (peticion.method !== 'GET') {
    return;
  }
  const url = new URL(peticion.url);
  if (url.origin !== self.location.origin || /^\/(api\/|medios\/|salud$)/.test(url.pathname)) {
    return;
  }
  evento.respondWith(
    fetch(peticion)
      .then(async (respuesta) => {
        if (respuesta.ok && respuesta.type === 'basic') {
          // Solo se guarda si cambió: canvaskit.wasm y main.dart.js pesan ~10 MB
          // y reescribirlos en cada apertura hace lento el arranque en iPhone.
          const cache = await caches.open(CACHE);
          const guardada = await cache.match(peticion);
          if (!guardada || !mismaVersion(guardada, respuesta)) {
            cache.put(peticion, respuesta.clone());
          }
        }
        return respuesta;
      })
      .catch(() =>
        caches.match(peticion).then((guardada) => {
          if (guardada) {
            return guardada;
          }
          // Sin red y sin copia: una navegación abre la app guardada.
          return peticion.mode === 'navigate' ? caches.match('index.html') : Response.error();
        }),
      ),
  );
});
