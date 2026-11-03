import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Datos de conexión al almacenamiento de objetos compatible con S3 (Garage en Coolify).
///
/// Las llaves solo viven en el entorno (`S3_ACCESS_KEY`, `S3_SECRET_KEY`) y
/// nunca se imprimen.
class ConfiguracionS3 {
  /// Valores ya resueltos. Ver [ConfiguracionS3.desdeEntorno].
  const ConfiguracionS3({
    required this.endpoint,
    required this.bucket,
    required this.llaveAcceso,
    required this.llaveSecreta,
    this.region = 'garage',
  });

  /// Lee `S3_ENDPOINT`, `S3_BUCKET`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` y `S3_REGION`.
  ///
  /// Null si no hay ninguna (las fotos se guardan en disco). Si solo hay
  /// algunas, lanza [StateError] con los nombres que faltan, sin valores.
  static ConfiguracionS3? desdeEntorno(Map<String, String> valores) {
    String texto(String clave) => (valores[clave] ?? '').trim();
    const obligatorias = ['S3_ENDPOINT', 'S3_BUCKET', 'S3_ACCESS_KEY', 'S3_SECRET_KEY'];
    final faltan = obligatorias.where((clave) => texto(clave).isEmpty).toList();
    if (faltan.length == obligatorias.length) {
      return null;
    }
    if (faltan.isNotEmpty) {
      throw StateError('Configuración S3 incompleta: falta ${faltan.join(', ')}.');
    }
    final endpoint = Uri.tryParse(texto('S3_ENDPOINT'));
    if (endpoint == null || !(endpoint.isScheme('https') || endpoint.isScheme('http')) || endpoint.host.isEmpty) {
      throw StateError('S3_ENDPOINT debe ser una URL http(s)://host.');
    }
    final bucket = texto('S3_BUCKET');
    if (!RegExp(r'^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$').hasMatch(bucket)) {
      throw StateError('S3_BUCKET no es un nombre de bucket válido.');
    }
    final region = texto('S3_REGION');
    return ConfiguracionS3(
      endpoint: endpoint,
      bucket: bucket,
      llaveAcceso: texto('S3_ACCESS_KEY'),
      llaveSecreta: texto('S3_SECRET_KEY'),
      region: region.isEmpty ? 'garage' : region,
    );
  }

  /// URL de la API S3, por ejemplo `https://s3-xxxx.sslip.io` o `http://garage:3900`.
  final Uri endpoint;

  /// Bucket donde viven las fotos.
  final String bucket;

  /// Access Key ID de la llave de Garage.
  final String llaveAcceso;

  /// Secret Access Key. Solo en memoria.
  final String llaveSecreta;

  /// Región de firma (`s3_region` de garage.toml; Garage usa `garage` por defecto).
  final String region;
}

/// Falla al hablar con el almacenamiento S3 (red, credenciales, bucket).
///
/// [message] nunca incluye llaves; trae el código HTTP para los logs.
class ErrorAlmacen implements Exception {
  /// Crea el error con un mensaje apto para logs.
  const ErrorAlmacen(this.message);

  /// Descripción para los logs.
  final String message;

  @override
  String toString() => 'ErrorAlmacen: $message';
}

/// Cliente mínimo de S3 (PUT, GET y DELETE de objetos) con firma AWS SigV4.
///
/// Usa direcciones estilo ruta (`endpoint/bucket/clave`), que Garage admite
/// siempre, y `dart:io` para no sumar dependencias.
class AlmacenS3 {
  /// Cliente para [configuracion]. [reloj] permite fijar la hora en pruebas.
  AlmacenS3(this.configuracion, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  /// Endpoint, bucket y llaves.
  final ConfiguracionS3 configuracion;

  final DateTime Function() _reloj;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  static const Duration _espera = Duration(seconds: 30);

  /// Sube [bytes] a [clave] con su tipo MIME.
  Future<void> subir(String clave, List<int> bytes, String tipo) async {
    final respuesta = await _pedir('PUT', clave, cuerpo: bytes, cabeceras: {'content-type': tipo});
    if (respuesta.estado != 200) {
      throw ErrorAlmacen('PUT $clave respondió ${respuesta.estado}.');
    }
  }

  /// Bytes de [clave], o null si el objeto no existe.
  Future<Uint8List?> descargar(String clave) async {
    final respuesta = await _pedir('GET', clave);
    if (respuesta.estado == 404) {
      return null;
    }
    if (respuesta.estado != 200) {
      throw ErrorAlmacen('GET $clave respondió ${respuesta.estado}.');
    }
    return respuesta.cuerpo;
  }

  /// Borra [clave]. No falla si ya no existía.
  Future<void> borrar(String clave) async {
    final respuesta = await _pedir('DELETE', clave);
    if (respuesta.estado != 204 && respuesta.estado != 200 && respuesta.estado != 404) {
      throw ErrorAlmacen('DELETE $clave respondió ${respuesta.estado}.');
    }
  }

  /// Cierra las conexiones abiertas.
  void cerrar() => _http.close(force: true);

  Future<({int estado, Uint8List cuerpo})> _pedir(
    String metodo,
    String clave, {
    List<int> cuerpo = const [],
    Map<String, String> cabeceras = const {},
  }) async {
    final base = configuracion.endpoint;
    final segmentos = [
      ...base.pathSegments.where((s) => s.isNotEmpty),
      configuracion.bucket,
      ...clave.split('/'),
    ];
    final ruta = '/${segmentos.map(codificarS3).join('/')}';
    final uri = Uri.parse('${base.scheme}://${base.authority}$ruta');
    final firmadas = firmarS3(
      metodo: metodo,
      host: base.hasPort ? '${base.host}:${base.port}' : base.host,
      rutaCanonica: ruta,
      cabeceras: cabeceras,
      hashCuerpo: sha256.convert(cuerpo).toString(),
      fecha: _reloj(),
      region: configuracion.region,
      llaveAcceso: configuracion.llaveAcceso,
      llaveSecreta: configuracion.llaveSecreta,
    );
    try {
      final peticion = await _http.openUrl(metodo, uri).timeout(_espera);
      firmadas.forEach((nombre, valor) {
        if (nombre != 'host') {
          peticion.headers.set(nombre, valor, preserveHeaderCase: true);
        }
      });
      peticion.contentLength = cuerpo.length;
      if (cuerpo.isNotEmpty) {
        peticion.add(cuerpo);
      }
      final respuesta = await peticion.close().timeout(_espera);
      final bytes = BytesBuilder(copy: false);
      await respuesta.forEach(bytes.add).timeout(_espera);
      return (estado: respuesta.statusCode, cuerpo: bytes.takeBytes());
    } on SocketException catch (error) {
      throw ErrorAlmacen('Sin conexión con S3 (${error.osError?.message ?? error.message}).');
    } on HttpException catch (error) {
      throw ErrorAlmacen('Error HTTP con S3 (${error.message}).');
    } on TimeoutException {
      throw ErrorAlmacen('S3 tardó demasiado en responder.');
    }
  }
}

/// Cabeceras firmadas con AWS Signature V4 para una petición S3 sin query.
///
/// Devuelve [cabeceras] más `host`, `x-amz-date`, `x-amz-content-sha256` y
/// `authorization`. Pública para poder probarla con los ejemplos de AWS.
Map<String, String> firmarS3({
  required String metodo,
  required String host,
  required String rutaCanonica,
  required Map<String, String> cabeceras,
  required String hashCuerpo,
  required DateTime fecha,
  required String region,
  required String llaveAcceso,
  required String llaveSecreta,
}) {
  final utc = fecha.toUtc();
  String dos(int n) => n.toString().padLeft(2, '0');
  final dia = '${utc.year.toString().padLeft(4, '0')}${dos(utc.month)}${dos(utc.day)}';
  final momento = '${dia}T${dos(utc.hour)}${dos(utc.minute)}${dos(utc.second)}Z';

  final todas = <String, String>{
    for (final entrada in cabeceras.entries) entrada.key.toLowerCase(): entrada.value.trim(),
    'host': host,
    'x-amz-content-sha256': hashCuerpo,
    'x-amz-date': momento,
  };
  final nombres = todas.keys.toList()..sort();
  final canonicas = nombres.map((n) => '$n:${todas[n]}\n').join();
  final firmadas = nombres.join(';');
  final peticionCanonica = [metodo, rutaCanonica, '', canonicas, firmadas, hashCuerpo].join('\n');

  final alcance = '$dia/$region/s3/aws4_request';
  final textoAFirmar = [
    'AWS4-HMAC-SHA256',
    momento,
    alcance,
    sha256.convert(utf8.encode(peticionCanonica)).toString(),
  ].join('\n');

  List<int> hmac(List<int> llave, String texto) => Hmac(sha256, llave).convert(utf8.encode(texto)).bytes;
  final llaveFirma = hmac(hmac(hmac(hmac(utf8.encode('AWS4$llaveSecreta'), dia), region), 's3'), 'aws4_request');
  final firma = Hmac(sha256, llaveFirma).convert(utf8.encode(textoAFirmar)).toString();

  return {
    ...todas,
    'authorization': 'AWS4-HMAC-SHA256 Credential=$llaveAcceso/$alcance, '
        'SignedHeaders=$firmadas, Signature=$firma',
  };
}

/// Codifica un segmento de ruta como lo exige SigV4 (RFC 3986, sin `/`).
String codificarS3(String segmento) {
  final buffer = StringBuffer();
  for (final byte in utf8.encode(segmento)) {
    final c = String.fromCharCode(byte);
    if (RegExp(r'[A-Za-z0-9\-_.~]').hasMatch(c)) {
      buffer.write(c);
    } else {
      buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return buffer.toString();
}
