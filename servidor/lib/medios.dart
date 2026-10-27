import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Fotografías que sube el administrador. Viven fuera del repositorio.
class Medios {
  /// [directorio] es `datos/medios`, creado al guardar el primer archivo.
  Medios(this.directorio);

  /// Carpeta de los archivos servidos en `/medios/`.
  final Directory directorio;

  static const int _maximoBytes = 1500000;

  /// Guarda bytes de imagen y devuelve la ruta pública `/medios/archivo`.
  Future<String> guardar(String nombreOriginal, String datosBase64) async {
    final limpio = datosBase64.contains(',') ? datosBase64.split(',').last : datosBase64;
    List<int> bytes;
    try {
      bytes = base64Decode(limpio);
    } on FormatException {
      throw const FormatException('La imagen no viene en base64.');
    }
    if (bytes.length > _maximoBytes) {
      throw const FormatException('La imagen supera 1.5 MB.');
    }
    final extension = _extension(nombreOriginal);
    if (extension == null) {
      throw const FormatException('Usa una imagen JPG, PNG, WEBP o GIF.');
    }
    await directorio.create(recursive: true);
    final nombre = '${_aleatorio()}.$extension';
    await File('${directorio.path}/$nombre').writeAsBytes(bytes, flush: true);
    return '/medios/$nombre';
  }

  /// Borra el archivo de una URL `/medios/...`. Ignora URLs externas o ya borradas.
  Future<void> borrar(String? url) async {
    if (url == null || !url.startsWith('/medios/')) {
      return;
    }
    final archivo = buscar(url.substring('/medios/'.length));
    if (archivo != null) {
      await archivo.delete();
    }
  }

  /// Archivo público, o null si el nombre no es seguro o no existe.
  File? buscar(String nombre) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp|gif)$').hasMatch(nombre)) {
      return null;
    }
    final archivo = File('${directorio.path}/$nombre');
    if (!archivo.existsSync()) {
      return null;
    }
    return archivo;
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
