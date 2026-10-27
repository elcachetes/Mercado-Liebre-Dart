import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Número de rondas PBKDF2. Igual que la app Python anterior, para que
/// las cuentas ya sembradas sigan pudiendo entrar.
const int iteracionesContrasena = 260000;

/// Longitud del salt aleatorio, en bytes.
const int _bytesSalt = 16;

/// Genera y comprueba hashes de contraseña.
///
/// No se cifra la contraseña de forma reversible: se guarda un hash
/// PBKDF2-HMAC-SHA256 con salt propio. El formato almacenado en
/// `users.password_hash` es `saltHex$hashHex`.
class Contrasena {
  const Contrasena();

  /// Crea un hash nuevo. Cada llamada usa un salt distinto.
  String hashear(String contrasenaPlana) {
    final salt = _saltAleatorio();
    final hash = _derivar(utf8.encode(contrasenaPlana), salt);
    return '${_hex(salt)}\$${_hex(hash)}';
  }

  /// Compara [contrasenaPlana] con el valor guardado, en tiempo constante.
  bool verificar(String contrasenaPlana, String almacenado) {
    final partes = almacenado.split('\$');
    if (partes.length != 2) {
      return false;
    }
    List<int> salt;
    try {
      salt = _deHex(partes[0]);
    } on FormatException {
      return false;
    }
    final esperado = _derivar(utf8.encode(contrasenaPlana), salt);
    final recibido = partes[1].toLowerCase();
    final calculado = _hex(esperado);
    if (calculado.length != recibido.length) {
      return false;
    }
    var diferencia = 0;
    for (var i = 0; i < calculado.length; i++) {
      diferencia |= calculado.codeUnitAt(i) ^ recibido.codeUnitAt(i);
    }
    return diferencia == 0;
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018), 32 bytes de salida.
  List<int> _derivar(List<int> contrasena, List<int> salt) {
    final hmac = Hmac(sha256, contrasena);
    final bloque = ByteData(4)..setUint32(0, 1);
    var u = hmac.convert([...salt, ...bloque.buffer.asUint8List()]).bytes;
    final acumulado = List<int>.from(u);
    for (var ronda = 1; ronda < iteracionesContrasena; ronda++) {
      u = hmac.convert(u).bytes;
      for (var i = 0; i < acumulado.length; i++) {
        acumulado[i] ^= u[i];
      }
    }
    return acumulado;
  }

  List<int> _saltAleatorio() {
    final aleatorio = Random.secure();
    return List<int>.generate(_bytesSalt, (_) => aleatorio.nextInt(256));
  }

  String _hex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  List<int> _deHex(String hex) {
    if (hex.length.isOdd) {
      throw const FormatException('hex impar');
    }
    return List<int>.generate(hex.length ~/ 2, (i) {
      return int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    });
  }
}
