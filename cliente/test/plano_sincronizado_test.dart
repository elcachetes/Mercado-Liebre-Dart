import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercado_liebre/mapa/puntos_campus.dart';

/// El servidor valida los códigos del plano con su propia lista
/// (`servidor/lib/plano.dart`). Si alguien agrega un edificio solo en
/// un lado, este test falla antes de que llegue a producción.
void main() {
  test('los códigos del plano coinciden entre cliente y servidor', () {
    final archivo = File('../servidor/lib/plano.dart');
    if (!archivo.existsSync()) {
      markTestSkipped('No se encontró ../servidor/lib/plano.dart');
      return;
    }
    final conjunto = RegExp(r'\{([^}]*)\}', dotAll: true).firstMatch(archivo.readAsStringSync())!.group(1)!;
    final servidor = RegExp(r"'([^']+)'").allMatches(conjunto).map((m) => m.group(1)!).toSet();
    final cliente = puntosCampus.map((punto) => punto.codigo).toSet();

    expect(cliente.difference(servidor), isEmpty, reason: 'Códigos solo en el cliente');
    expect(servidor.difference(cliente), isEmpty, reason: 'Códigos solo en el servidor');
  });
}
