{{flutter_js}}
{{flutter_build_config}}

// Plantilla propia del arranque (flutter build web la usa en lugar de la
// predeterminada y rellena las dos líneas de arriba).
//
// - Sin serviceWorkerSettings: el service worker de Flutter está obsoleto.
//   El de la PWA es web/sw.js y se registra en index.html.
// - canvasKitBaseUrl local: CanvasKit se sirve desde este mismo dominio
//   (carpeta canvaskit/ del build) en lugar de gstatic.com, así la app
//   instalada no depende de otro sitio y el service worker puede guardarlo.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
