import 'dart:convert';
import 'dart:io';

import 'correo.dart';

/// Parámetros de arranque leídos del entorno del proceso.
///
/// La URL de PostgreSQL, el usuario y la contraseña no viven en el código:
/// Coolify (o un archivo `.env` local, ignorado por git) los inyecta al
/// arrancar. Si falta `DATABASE_URL`, el proceso se detiene con un mensaje
/// que no revela ningún secreto.
class Configuracion {
  /// Crea la configuración a partir de las variables ya cargadas.
  Configuracion({
    required this.urlBaseDatos,
    required this.urlEntorno,
    required this.ssl,
    required this.sslEntorno,
    required this.llaveSesion,
    required this.puertoHttp,
    required this.aplicarEsquema,
    required this.rutaEsquema,
    required this.rutaDatos,
    required this.adminCorreo,
    required this.adminPassword,
    this.origenCors = '*',
    this.correo = const ConfiguracionCorreo(),
  });

  /// URL activa `postgres://usuario:contraseña@host:puerto/base`.
  final String urlBaseDatos;

  /// URL que llegó por el entorno, antes de un cambio del administrador.
  final String urlEntorno;

  /// Si la conexión activa exige SSL.
  final bool ssl;

  /// SSL pedido por el entorno, antes de un cambio del administrador.
  final bool sslEntorno;

  /// Secreto HMAC de los tokens. Distinto de la contraseña de la base.
  final String llaveSesion;

  /// Puerto TCP en el que escucha la API.
  final int puertoHttp;

  /// Si es verdadero, se ejecuta `db/schema.sql` al arrancar.
  final bool aplicarEsquema;

  /// Ruta del archivo SQL del esquema.
  final String rutaEsquema;

  /// Carpeta escribible para la conexión guardada y las fotografías.
  final String rutaDatos;

  /// Correo del primer administrador, vacío si no se pidió crearlo.
  final String adminCorreo;

  /// Contraseña del primer administrador. Solo vive en memoria.
  final String adminPassword;

  /// Valor de `Access-Control-Allow-Origin`. `*` si no se define `CORS_ORIGEN`.
  ///
  /// Detrás de nginx (mismo origen) no hace falta cambiarlo; solo importa
  /// cuando una app web en otro dominio llama directo a la API.
  final String origenCors;

  /// SMTP para la verificación de correo y los reportes. Sin credenciales, no envía.
  final ConfiguracionCorreo correo;

  /// Copia con otra URL y otro modo SSL, conservando el resto.
  Configuracion conConexion({required String url, required bool usarSsl}) {
    return Configuracion(
      urlBaseDatos: url,
      urlEntorno: urlEntorno,
      ssl: usarSsl,
      sslEntorno: sslEntorno,
      llaveSesion: llaveSesion,
      puertoHttp: puertoHttp,
      aplicarEsquema: aplicarEsquema,
      rutaEsquema: rutaEsquema,
      rutaDatos: rutaDatos,
      adminCorreo: adminCorreo,
      adminPassword: adminPassword,
      origenCors: origenCors,
      correo: correo,
    );
  }

  /// Host extraído de [urlBaseDatos].
  String get host => _uri.host.isEmpty ? 'localhost' : _uri.host;

  /// Puerto de PostgreSQL extraído de [urlBaseDatos].
  int get puertoBaseDatos => _uri.hasPort ? _uri.port : 5432;

  /// Nombre de la base, sin la barra inicial.
  String get nombreBase {
    final ruta = _uri.path;
    if (ruta.isEmpty || ruta == '/') {
      return 'postgres';
    }
    return ruta.startsWith('/') ? ruta.substring(1) : ruta;
  }

  /// Usuario de PostgreSQL.
  String get usuarioBaseDatos {
    final info = _uri.userInfo;
    final corte = info.indexOf(':');
    if (corte < 0) {
      return Uri.decodeComponent(info);
    }
    return Uri.decodeComponent(info.substring(0, corte));
  }

  /// Contraseña de PostgreSQL. Solo existe en memoria.
  String get contrasenaBaseDatos {
    final info = _uri.userInfo;
    final corte = info.indexOf(':');
    if (corte < 0) {
      return '';
    }
    return Uri.decodeComponent(info.substring(corte + 1));
  }

  late final Uri _uri = Uri.parse(urlBaseDatos);

  /// Lee el entorno del proceso y, si hace falta, un archivo `.env`.
  ///
  /// Busca `.env` en el directorio actual y en el padre, para poder
  /// arrancar tanto desde `servidor/` como desde la raíz del repositorio.
  /// Una variable ya definida en el proceso (por ejemplo en Coolify)
  /// no se pisa con el archivo.
  static Future<Configuracion> cargar() async {
    final valores = Map<String, String>.from(Platform.environment);
    await _mezclarArchivoEntorno(valores, File('.env'));
    await _mezclarArchivoEntorno(valores, File('../.env'));

    final urlEntorno = valores['DATABASE_URL']?.trim() ?? '';
    if (urlEntorno.isEmpty) {
      throw StateError(
        'Falta DATABASE_URL. Defínela en el entorno del servidor, '
        'no dentro del código. Revisa .env.example.',
      );
    }
    final rutaDatos = _textoOr(valores['DATOS_PATH'], 'datos');
    await Directory(rutaDatos).create(recursive: true);
    final guardada = await _leerConexionGuardada(File('$rutaDatos/conexion.json'));
    final url = guardada?.url ?? urlEntorno;
    final sslEntorno = _esVerdadero(valores['DATABASE_SSL'], porDefecto: false);
    final ssl = guardada?.ssl ?? sslEntorno;
    final llave = valores['APP_SECRET_KEY']?.trim() ?? '';
    if (llave.length < 16) {
      throw StateError(
        'APP_SECRET_KEY debe tener al menos 16 caracteres y venir del entorno.',
      );
    }
    final puerto = int.tryParse(valores['PORT'] ?? '') ?? 8080;
    final aplicar = _esVerdadero(valores['APLICAR_ESQUEMA'], porDefecto: true);
    final ruta = _textoOr(
      valores['SCHEMA_PATH'],
      _primeraRutaExistente(['db/schema.sql', '../db/schema.sql', '/app/db/schema.sql']),
    );
    return Configuracion(
      urlBaseDatos: url,
      urlEntorno: urlEntorno,
      ssl: ssl,
      sslEntorno: sslEntorno,
      llaveSesion: llave,
      puertoHttp: puerto,
      aplicarEsquema: aplicar,
      rutaEsquema: ruta,
      rutaDatos: rutaDatos,
      adminCorreo: valores['ADMIN_CORREO']?.trim() ?? '',
      adminPassword: valores['ADMIN_PASSWORD'] ?? '',
      origenCors: _textoOr(valores['CORS_ORIGEN'], '*'),
      correo: ConfiguracionCorreo.desdeEntorno(valores),
    );
  }

  /// Lee la conexión que el administrador guardó. Null si no hay archivo válido.
  static Future<({String url, bool ssl})?> _leerConexionGuardada(File archivo) async {
    if (!await archivo.exists()) {
      return null;
    }
    try {
      final decodificado = jsonDecode(await archivo.readAsString());
      if (decodificado is! Map) {
        return null;
      }
      final url = (decodificado['url'] ?? '').toString().trim();
      if (!url.startsWith('postgres://') && !url.startsWith('postgresql://')) {
        return null;
      }
      return (url: url, ssl: decodificado['ssl'] == true);
    } catch (_) {
      return null;
    }
  }

  static String _primeraRutaExistente(List<String> rutas) {
    for (final ruta in rutas) {
      if (File(ruta).existsSync()) {
        return ruta;
      }
    }
    return rutas.first;
  }
}

/// [valor] sin espacios, o [respaldo] si viene vacío.
String _textoOr(String? valor, String respaldo) {
  final limpio = valor?.trim() ?? '';
  return limpio.isEmpty ? respaldo : limpio;
}

bool _esVerdadero(String? valor, {required bool porDefecto}) {
  if (valor == null || valor.trim().isEmpty) {
    return porDefecto;
  }
  return const {'1', 'true', 'yes', 'si', 'sí', 'on'}.contains(valor.trim().toLowerCase());
}

/// Completa [valores] con el archivo solo donde la clave aún está vacía.
Future<void> _mezclarArchivoEntorno(Map<String, String> valores, File archivo) async {
  if (!await archivo.exists()) {
    return;
  }
  final lineas = await archivo.readAsLines();
  for (final cruda in lineas) {
    final linea = cruda.trim();
    if (linea.isEmpty || linea.startsWith('#')) {
      continue;
    }
    final corte = linea.indexOf('=');
    if (corte <= 0) {
      continue;
    }
    final clave = linea.substring(0, corte).trim();
    var valor = linea.substring(corte + 1).trim();
    if ((valor.startsWith('"') && valor.endsWith('"')) ||
        (valor.startsWith("'") && valor.endsWith("'"))) {
      valor = valor.substring(1, valor.length - 1);
    }
    if ((valores[clave] ?? '').isEmpty) {
      valores[clave] = valor;
    }
  }
}
