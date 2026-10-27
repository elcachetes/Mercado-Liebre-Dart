import 'package:mercado_liebre_api/contrasena.dart';
import 'package:test/test.dart';

void main() {
  const servicio = Contrasena();

  test('rechaza una contraseña distinta', () {
    final hash = servicio.hashear('una-clave-larga');
    expect(servicio.verificar('otra-clave-larga', hash), isFalse);
  });

  test('acepta la contraseña que se acaba de hashear', () {
    final hash = servicio.hashear('mercado-liebre');
    expect(servicio.verificar('mercado-liebre', hash), isTrue);
  });

  test('verifica el hash PBKDF2 que ya usa la semilla de PostgreSQL', () {
    const almacenado =
        'a1b2c3d4e5f60718293a4b5c6d7e8f90\$4e246e60f09beed7e0b296cabc197214a72a7ac708dd2d2266ec017a58995a1f';
    expect(servicio.verificar('demo1234', almacenado), isTrue);
    expect(servicio.verificar('incorrecta', almacenado), isFalse);
  });
}
