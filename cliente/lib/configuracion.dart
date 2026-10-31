import 'package:flutter/foundation.dart';

/// Valores de compilación de la app.
///
/// La app no conoce PostgreSQL. Solo habla con la API, cuya dirección se
/// inyecta al compilar:
/// `flutter run --dart-define=API_BASE_URL=https://tu-api.ejemplo.com`
///
/// En Coolify el valor `same` usa el mismo origen: nginx reenvía `/api`.
class ConfiguracionApp {
  const ConfiguracionApp._();

  static const String _definido = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );

  /// Origen HTTP de la API Dart, sin barra final.
  static String get apiBaseUrl {
    if (_definido == 'same' && kIsWeb) {
      return Uri.base.origin;
    }
    return _definido.endsWith('/') ? _definido.substring(0, _definido.length - 1) : _definido;
  }

  /// Dirección pública de la app web, sin barra final. Base de los enlaces para compartir.
  ///
  /// En el navegador es el sitio abierto; en Android, iOS y Windows es el
  /// dominio de la API, que en producción sirve también la versión web.
  static String get urlApp => kIsWeb ? Uri.base.origin : apiBaseUrl;

  /// Convierte `/medios/...` en una URL absoluta de la API.
  static String urlPublica(String ruta) {
    if (ruta.startsWith('http://') || ruta.startsWith('https://')) {
      return ruta;
    }
    return '$apiBaseUrl$ruta';
  }
}
