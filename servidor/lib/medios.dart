import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'almacen_s3.dart';
import 'configuracion.dart';

/// Fotografías subidas (perfil, negocio, productos, publicidad).
///
/// PostgreSQL solo guarda la URL pública `/medios/<archivo>`; los bytes viven
/// en el almacenamiento S3 (Garage) si [almacen] existe, o en [directorio] si no.
/// La API sirve `/medios/<archivo>` en ambos casos, así que las URLs guardadas
/// no cambian al pasar del disco a S3.
class Medios {
  /// [directorio] es `datos/medios`, creado al guardar el primer archivo en disco.
  Medios(this.directorio, {this.almacen});

  /// Medios según la configuración: S3 si está definido, si no el disco.
  factory Medios.desde(Configuracion configuracion) {
    final s3 = configuracion.s3;
    return Medios(
      Directory('${configuracion.rutaDatos}/medios'),
      almacen: s3 == null ? null : AlmacenS3(s3),
    );
  }

  /// Carpeta local: destino sin S3 y respaldo de lectura para fotos anteriores a S3.
  final Directory directorio;

  /// Almacenamiento de objetos (Garage). Null = solo disco.
  final AlmacenS3? almacen;

  /// Tamaño máximo de una imagen subida (fotos, medios y adjuntos de reportes).
  static const int maximoBytes = 1500000;

  /// Prefijo de las claves de objeto dentro del bucket.
  static const String prefijoS3 = 'medios/';

  static final RegExp _nombreValido = RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp|gif)$');

  /// Guarda bytes de imagen y devuelve la ruta pública `/medios/archivo`.
  ///
  /// Lanza [FormatException] si la imagen no es válida y [ErrorAlmacen] si S3 falla.
  Future<String> guardar(String nombreOriginal, String datosBase64) async {
    final limpio = datosBase64.contains(',') ? datosBase64.split(',').last : datosBase64;
    Uint8List bytes;
    try {
      bytes = base64Decode(limpio);
    } on FormatException {
      throw const FormatException('La imagen no viene en base64.');
    }
    if (bytes.length > maximoBytes) {
      throw const FormatException('La imagen supera 1.5 MB.');
    }
    final extension = _extension(nombreOriginal);
    if (extension == null) {
      throw const FormatException('Usa una imagen JPG, PNG, WEBP o GIF.');
    }
    final nombre = '${_aleatorio()}.$extension';
    final s3 = almacen;
    if (s3 != null) {
      await s3.subir('$prefijoS3$nombre', bytes, tipo(nombre));
    } else {
      await directorio.create(recursive: true);
      await File('${directorio.path}/$nombre').writeAsBytes(bytes, flush: true);
    }
    return '/medios/$nombre';
  }

  /// Borra la imagen de una URL `/medios/...`. Ignora URLs externas o ya borradas.
  ///
  /// Un fallo de S3 solo se anota en el log: la acción de la persona ya se hizo.
  Future<void> borrar(String? url) async {
    if (url == null || !url.startsWith('/medios/')) {
      return;
    }
    final nombre = url.substring('/medios/'.length);
    if (!_nombreValido.hasMatch(nombre)) {
      return;
    }
    final s3 = almacen;
    if (s3 != null) {
      try {
        await s3.borrar('$prefijoS3$nombre');
      } on ErrorAlmacen catch (error) {
        stderr.writeln('No se pudo borrar $nombre de S3: ${error.message}');
      }
    }
    final archivo = _archivoLocal(nombre);
    if (archivo != null) {
      await archivo.delete();
    }
  }

  /// Bytes y tipo MIME de una imagen, o null si el nombre no es seguro o no existe.
  ///
  /// Con S3 busca primero en el bucket y luego en disco (fotos aún no migradas).
  Future<({Uint8List bytes, String tipo})?> leer(String nombre) async {
    if (!_nombreValido.hasMatch(nombre)) {
      return null;
    }
    final s3 = almacen;
    if (s3 != null) {
      final bytes = await s3.descargar('$prefijoS3$nombre');
      if (bytes != null) {
        return (bytes: bytes, tipo: tipo(nombre));
      }
    }
    final archivo = _archivoLocal(nombre);
    if (archivo == null) {
      return null;
    }
    return (bytes: await archivo.readAsBytes(), tipo: tipo(nombre));
  }

  /// Sube a S3 las fotos que quedaron en disco y borra cada copia local ya subida.
  ///
  /// Devuelve cuántas subió. Sin S3 o sin carpeta no hace nada. Si una falla,
  /// la deja en disco (se sigue sirviendo) y lo intenta en el próximo arranque.
  Future<int> migrarDiscoAS3() async {
    final s3 = almacen;
    if (s3 == null || !await directorio.exists()) {
      return 0;
    }
    var subidas = 0;
    await for (final entrada in directorio.list(followLinks: false)) {
      if (entrada is! File) {
        continue;
      }
      final nombre = entrada.uri.pathSegments.last;
      if (!_nombreValido.hasMatch(nombre)) {
        continue;
      }
      try {
        await s3.subir('$prefijoS3$nombre', await entrada.readAsBytes(), tipo(nombre));
        await entrada.delete();
        subidas++;
      } on ErrorAlmacen catch (error) {
        stderr.writeln('No se pudo migrar $nombre a S3: ${error.message}');
      }
    }
    return subidas;
  }

  /// Archivo local, o null si no existe. [nombre] ya debe estar validado.
  File? _archivoLocal(String nombre) {
    final archivo = File('${directorio.path}/$nombre');
    return archivo.existsSync() ? archivo : null;
  }

  /// Tipo MIME según la extensión ya validada.
  String tipo(String nombre) {
    if (nombre.endsWith('.png')) {
      return 'image/png';
    }
    if (nombre.endsWith('.webp')) {
      return 'image/webp';
    }
    if (nombre.endsWith('.gif')) {
      return 'image/gif';
    }
    return 'image/jpeg';
  }

  String? _extension(String nombre) {
    final punto = nombre.lastIndexOf('.');
    if (punto < 0) {
      return null;
    }
    final extension = nombre.substring(punto + 1).toLowerCase();
    if (extension == 'jpeg') {
      return 'jpg';
    }
    if (const {'jpg', 'png', 'webp', 'gif'}.contains(extension)) {
      return extension;
    }
    return null;
  }

  String _aleatorio() {
    final aleatorio = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(aleatorio.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }
}
