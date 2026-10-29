/// Instalar Mercado Liebre como app (PWA) desde el navegador.
///
/// En web usa `window.liebrePwa`, definido en `web/index.html`, que guarda el
/// evento `beforeinstallprompt` del navegador. En Android, iOS y escritorio
/// nativos la app ya está instalada y [InstalacionApp.mostrarBoton] es falso.
library;

export 'instalacion_otras.dart' if (dart.library.js_interop) 'instalacion_web.dart';
