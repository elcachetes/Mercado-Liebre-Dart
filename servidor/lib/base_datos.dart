import 'dart:io';

import 'package:postgres/postgres.dart';

import 'configuracion.dart';

/// Pool de conexiones a PostgreSQL.
///
/// Es el único lugar del sistema que abre la base. La app Flutter nunca
/// recibe el host, el usuario ni la contraseña.
class BaseDatos {
  /// Abre el pool con los datos ya resueltos por [Configuracion].
  BaseDatos(this.configuracion);

  /// Origen de host, puerto, usuario y contraseña. Cambia si el administrador edita la conexión.
  Configuracion configuracion;

  Pool? _pool;

  /// Pool listo para consultas. Lanza si [abrir] no se llamó.
  Pool get pool {
    final actual = _pool;
    if (actual == null) {
      throw StateError('La base de datos no está abierta.');
    }
    return actual;
  }

  /// Crea el pool. No imprime la URL.
  Future<void> abrir() async {
    _pool = _poolDe(configuracion, 8);
  }

  /// Abre una conexión temporal y ejecuta `SELECT 1`. No cambia el pool activo.
  Future<void> probar(Configuracion candidata) async {
    final temporal = _poolDe(candidata, 1);
    try {
      await temporal.execute('SELECT 1');
    } finally {
      await temporal.close();
    }
  }

  /// Sustituye el pool solo si la candidata responde. El pool anterior se cierra después.
  Future<void> usar(Configuracion candidata) async {
    final nuevo = _poolDe(candidata, 8);
    try {
      await nuevo.execute('SELECT 1');
    } catch (error) {
      await nuevo.close();
      rethrow;
    }
    final anterior = _pool;
    _pool = nuevo;
    configuracion = candidata;
    await anterior?.close();
  }

  Pool _poolDe(Configuracion origen, int maximo) {
    return Pool.withEndpoints(
      [
        Endpoint(
          host: origen.host,
          port: origen.puertoBaseDatos,
          database: origen.nombreBase,
          username: origen.usuarioBaseDatos,
          password: origen.contrasenaBaseDatos,
        ),
      ],
      settings: PoolSettings(
        maxConnectionCount: maximo,
        sslMode: origen.ssl ? SslMode.require : SslMode.disable,
      ),
    );
  }

  /// Cierra el pool al apagar el proceso.
  Future<void> cerrar() async {
    await _pool?.close();
    _pool = null;
  }

  /// Ejecuta [db/schema.sql] dividido en sentencias.
  ///
  /// El archivo usa `IF NOT EXISTS` y bloques que ignoran un tipo ya
  /// creado, así que se puede correr en cada arranque.
  Future<void> aplicarEsquema() async {
    final archivo = File(configuracion.rutaEsquema);
    if (!await archivo.exists()) {
      throw StateError(
        'No se encontró el esquema en ${configuracion.rutaEsquema}.',
      );
    }
    final sql = await archivo.readAsString();
    final sentencias = dividirSentenciasSql(sql);
    await pool.withConnection((conexion) async {
      for (final sentencia in sentencias) {
        await conexion.execute(sentencia);
      }
    });
  }
}

/// Separa un script SQL por `;`, respetando comentarios `--` y bloques `$$`.
List<String> dividirSentenciasSql(String sql) {
  final sentencias = <String>[];
  final actual = StringBuffer();
  var enDollar = false;
  var enLineaComentario = false;
  var enTexto = false;

  for (var i = 0; i < sql.length; i++) {
    final caracter = sql[i];
    final siguiente = i + 1 < sql.length ? sql[i + 1] : '';

    if (enLineaComentario) {
      actual.write(caracter);
      if (caracter == '\n') {
        enLineaComentario = false;
      }
      continue;
    }
    if (!enDollar && !enTexto && caracter == '-' && siguiente == '-') {
      enLineaComentario = true;
      actual.write(caracter);
      continue;
    }
    if (!enDollar && caracter == "'") {
      enTexto = !enTexto;
      actual.write(caracter);
      continue;
    }
    if (!enTexto && caracter == '\$' && siguiente == '\$') {
      enDollar = !enDollar;
      actual.write('\$\$');
      i++;
      continue;
    }
    if (!enDollar && !enTexto && caracter == ';') {
      final texto = actual.toString().trim();
      if (texto.isNotEmpty) {
        sentencias.add(texto);
      }
      actual.clear();
      continue;
    }
    actual.write(caracter);
  }
  final resto = actual.toString().trim();
  if (resto.isNotEmpty) {
    sentencias.add(resto);
  }
  return sentencias;
}
