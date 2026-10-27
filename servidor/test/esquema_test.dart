import 'package:mercado_liebre_api/base_datos.dart';
import 'package:test/test.dart';

void main() {
  test('un bloque dollar quote se queda en una sola sentencia', () {
    final partes = dividirSentenciasSql('''
DO \$\$ BEGIN
  CREATE TYPE user_role AS ENUM ('admin');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END \$\$;

CREATE TABLE IF NOT EXISTS users (id INT);
''');
    expect(partes, hasLength(2));
    expect(partes.first, contains('CREATE TYPE user_role'));
    expect(partes.first, contains('END \$\$'));
    expect(partes.last, 'CREATE TABLE IF NOT EXISTS users (id INT)');
  });
}
