import 'dart:convert';

import 'correo.dart';
import 'medios.dart';
import 'repositorio.dart';

/// Reporte de falla, queja o sugerencia, validado y listo para enviarse.
class Reporte {
  /// Usa [Reporte.desdeJson] para validar lo que manda la app.
  const Reporte({required this.contacto, required this.descripcion, this.foto});

  /// Valida el cuerpo de `POST /api/reportes`.
  ///
  /// [contacto] es un correo o un número de control; [descripcion] es
  /// obligatoria; `foto` es opcional (`{nombre, datos}` en base64).
  factory Reporte.desdeJson(Map<String, dynamic> cuerpo) {
    final contacto = (cuerpo['contacto'] ?? '').toString().trim();
    final descripcion = (cuerpo['descripcion'] ?? '').toString().trim();
    if (!_contactoValido(contacto)) {
      throw ErrorApi(400, 'Escribe tu correo electrónico o tu número de control.');
    }
    if (descripcion.length < 10) {
      throw ErrorApi(400, 'Describe el problema en al menos 10 caracteres.');
    }
    if (descripcion.length > maximoDescripcion) {
      throw ErrorApi(400, 'La descripción no puede pasar de $maximoDescripcion caracteres.');
    }
    final foto = cuerpo['foto'];
    return Reporte(
      contacto: contacto.contains('@') ? contacto.toLowerCase() : contacto.toUpperCase(),
      descripcion: descripcion,
      foto: foto is Map<String, dynamic> ? _foto(foto) : null,
    );
  }

  /// Largo máximo de la descripción, igual que en la app.
  static const int maximoDescripcion = 1000;

  /// Correo o número de control de quien reporta.
  final String contacto;

  /// Qué pasó, con palabras de la persona.
  final String descripcion;

  /// Captura opcional.
  final FotoAdjunta? foto;

  static const Map<String, String> _tipos = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
  };

  /// Correo con @ y punto, o número de control (misma regla que el perfil).
  static bool _contactoValido(String contacto) {
    if (contacto.isEmpty || contacto.length > 120) {
      return false;
    }
    if (contacto.contains('@')) {
      return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(contacto);
    }
    return RegExp(r'^[A-Z]?\d{6,10}$').hasMatch(contacto.toUpperCase());
  }

  static FotoAdjunta _foto(Map<String, dynamic> foto) {
    final nombre = (foto['nombre'] ?? 'foto.jpg').toString().trim();
    final punto = nombre.lastIndexOf('.');
    final extension = punto < 0 ? '' : nombre.substring(punto + 1).toLowerCase();
    final tipo = _tipos[extension];
    if (tipo == null) {
      throw ErrorApi(400, 'La foto debe ser JPG, PNG, WEBP o GIF.');
    }
    final datos = (foto['datos'] ?? '').toString();
    final List<int> bytes;
    try {
      bytes = base64Decode(datos.contains(',') ? datos.split(',').last : datos);
    } on FormatException {
      throw ErrorApi(400, 'La foto no viene en base64.');
    }
    if (bytes.isEmpty) {
      throw ErrorApi(400, 'La foto está vacía.');
    }
    if (bytes.length > Medios.maximoBytes) {
      throw ErrorApi(400, 'La foto supera 1.5 MB.');
    }
    return FotoAdjunta(nombre: 'reporte.$extension', tipo: tipo, bytes: bytes);
  }
}
