import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Token de sesión firmado (JWT compacto, HMAC-SHA256).
///
/// El cliente lo guarda y lo envía como `Authorization: Bearer …`.
/// No contiene la contraseña ni datos de la base: solo el id del usuario
/// y la fecha de expiración.
class TokenSesion {
  /// [llave] es `APP_SECRET_KEY`. [vigencia] por defecto es 7 días.
  const TokenSesion(this.llave, {this.vigencia = const Duration(days: 7)});

  /// Secreto HMAC. No se incluye en el token.
  final String llave;

  /// Tiempo de vida de un token nuevo.
  final Duration vigencia;

  /// Firma un token para [usuarioId].
  String emitir(String usuarioId) {
    final encabezado = _b64(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
    final expira = DateTime.now().toUtc().add(vigencia).millisecondsSinceEpoch ~/ 1000;
    final cuerpo = _b64(utf8.encode(jsonEncode({'sub': usuarioId, 'exp': expira})));
    final firma = _firmar('$encabezado.$cuerpo');
    return '$encabezado.$cuerpo.$firma';
  }

  /// Devuelve el id de usuario si la firma es válida y no expiró.
  String? leer(String token) {
    final partes = token.split('.');
    if (partes.length != 3) {
      return null;
    }
    final firma = _firmar('${partes[0]}.${partes[1]}');
    if (!_igual(firma, partes[2])) {
      return null;
    }
    try {
      final json = jsonDecode(utf8.decode(_b64Inverso(partes[1]))) as Map<String, dynamic>;
      final exp = json['exp'];
      if (exp is! int) {
        return null;
      }
      final ahora = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      if (ahora >= exp) {
        return null;
      }
      final sub = json['sub'];
      if (sub is! String || sub.isEmpty) {
        return null;
      }
      return sub;
    } on FormatException {
      return null;
    }
  }

  String _firmar(String contenido) {
    final mac = Hmac(sha256, utf8.encode(llave));
    return _b64(mac.convert(utf8.encode(contenido)).bytes);
  }

  String _b64(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  List<int> _b64Inverso(String valor) {
    final faltan = (4 - valor.length % 4) % 4;
    return base64Url.decode(valor + ('=' * faltan));
  }

  bool _igual(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    var diferencia = 0;
    for (var i = 0; i < a.length; i++) {
      diferencia |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diferencia == 0;
  }
}
