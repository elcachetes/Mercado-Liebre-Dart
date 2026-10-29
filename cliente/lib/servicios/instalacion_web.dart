import 'dart:js_interop';

import 'package:flutter/foundation.dart';

/// Objeto `window.liebrePwa` de `web/index.html`.
extension type _PwaJs._(JSObject _) implements JSObject {
  external bool puedeInstalar();
  external bool esIos();
  external bool instalada();
  external JSPromise<JSString> instalar();
  external void alCambiar(JSFunction oyente);
}

@JS('liebrePwa')
external _PwaJs? get _pwa;

/// Instalación como PWA en el navegador. Avisa a sus oyentes cuando el
/// navegador habilita la instalación o cuando la app quedó instalada.
class InstalacionApp extends ChangeNotifier {
  InstalacionApp._() {
    _pwa?.alCambiar(notifyListeners.toJS);
  }

  /// Única instancia, compartida por todos los botones.
  static final InstalacionApp instancia = InstalacionApp._();

  /// El navegador (Chrome, Edge, Samsung Internet…) ofrece su diálogo de instalación.
  bool get disponible => _pwa?.puedeInstalar() ?? false;

  /// iPhone o iPad: Safari no tiene diálogo, se instala desde "Compartir".
  bool get esIos => _pwa?.esIos() ?? false;

  /// Ya corre como app instalada (ventana propia, sin barra del navegador).
  bool get instalada => _pwa?.instalada() ?? false;

  /// Mostrar "Instalar app": hay diálogo del navegador, o es iOS y falta instalar.
  bool get mostrarBoton => !instalada && (disponible || esIos);

  /// Abre el diálogo del navegador. Verdadero si la persona aceptó.
  Future<bool> instalar() async {
    final pwa = _pwa;
    if (pwa == null) {
      return false;
    }
    final resultado = await pwa.instalar().toDart;
    return resultado.toDart == 'accepted';
  }
}
