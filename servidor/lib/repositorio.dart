import 'dart:isolate';

import 'package:postgres/postgres.dart';

import 'base_datos.dart';
import 'contrasena.dart';

/// Error de negocio que la API traduce a una respuesta HTTP.
class ErrorApi implements Exception {
  /// [estado] es el código HTTP. [mensaje] se muestra al usuario.
  ErrorApi(this.estado, this.mensaje);

  /// 400, 401, 403 o 404.
  final int estado;

  /// Texto en español, sin datos internos de la base.
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Acceso a las tablas de Mercado Liebre.
///
/// Todas las consultas usan parámetros con nombre. Ningún texto que
/// llegue del cliente se concatena al SQL.
class Repositorio {
  /// [baseDatos] debe estar abierta. [contrasena] hashea las cuentas.
  Repositorio(this.baseDatos, {this.contrasena = const Contrasena()});

  /// Pool compartido.
  final BaseDatos baseDatos;

  /// Hash de contraseñas.
  final Contrasena contrasena;

  Pool get _pool => baseDatos.pool;

  /// Columnas de producto más su promedio de reseñas. Se completa con WHERE/ORDER.
  static const String _selectProductos = '''
    SELECT p.*,
           COALESCE(s.promedio_estrellas, 0) AS promedio_estrellas,
           COALESCE(s.total_resenas, 0) AS total_resenas
    FROM products p
    LEFT JOIN product_ratings_summary s ON s.product_id = p.id
  ''';

  /// Columnas del vendedor más el promedio y total de reseñas de todos sus
  /// productos. Se completa con WHERE/ORDER usando el alias `s`.
  static const String _selectVendedores = '''
    SELECT s.*,
           COALESCE(r.promedio, 0) AS promedio_estrellas,
           COALESCE(r.total, 0) AS total_resenas
    FROM sellers s
    LEFT JOIN (
      SELECT p.seller_id, AVG(ra.estrellas)::float8 AS promedio, COUNT(*)::int AS total
      FROM ratings ra
      JOIN products p ON p.id = ra.product_id
      GROUP BY p.seller_id
    ) r ON r.seller_id = s.id
  ''';

  static const String _sinNegocio = 'No tienes un perfil de negocio.';
  static const String _productoAjeno = 'No se encontró ese producto en tu negocio.';

  /// Hash con formato válido que ninguna contraseña produce. Ver [iniciarSesion].
  static const String _hashFicticio =
      '00000000000000000000000000000000\$0000000000000000000000000000000000000000000000000000000000000000';

  /// PBKDF2 (260 000 rondas) tarda cientos de ms: se calcula en otro isolate
  /// para no congelar las demás peticiones. Es estático para que el closure
  /// no capture `this` (el pool no se puede enviar a otro isolate).
  static Future<bool> _verificarAparte(Contrasena servicio, String password, String almacenado) {
    return Isolate.run(() => servicio.verificar(password, almacenado));
  }

  static Future<String> _hashearAparte(Contrasena servicio, String password) {
    return Isolate.run(() => servicio.hashear(password));
  }

  /// Comprueba correo y contraseña. No distingue cuál de los dos falló.
  ///
  /// Si el correo no existe se verifica contra un hash ficticio, para que
  /// el tiempo de respuesta no delate qué correos están registrados.
  Future<Map<String, dynamic>> iniciarSesion(String correo, String password) async {
    final fila = await _una(
      'SELECT * FROM users WHERE correo = @correo',
      {'correo': correo.trim().toLowerCase()},
    );
    final almacenado = fila?['password_hash']?.toString() ?? _hashFicticio;
    final valida = await _verificarAparte(contrasena, password, almacenado);
    if (fila == null || !valida) {
      throw ErrorApi(401, 'Correo o contraseña incorrectos.');
    }
    if (fila['bloqueado'] == true) {
      throw ErrorApi(403, 'Esta cuenta fue bloqueada. Contacta a la administración.');
    }
    return _usuario(fila);
  }

  /// Crea una cuenta. El rol público solo puede ser comprador o vendedor.
  Future<Map<String, dynamic>> registrar(Map<String, dynamic> datos) {
    return _crearCuenta(datos, privilegiado: false);
  }

  /// Crea comprador, vendedor, moderador o administrador. Lo autoriza la ruta.
  Future<Map<String, dynamic>> crearPorAdmin(Map<String, dynamic> datos) {
    return _crearCuenta(datos, privilegiado: true);
  }

  /// Crea el administrador inicial si ese correo todavía no existe.
  Future<void> asegurarAdministrador(String correo, String password) async {
    final limpio = correo.trim().toLowerCase();
    if (limpio.isEmpty || password.length < 8) {
      return;
    }
    final existente = await _una('SELECT id FROM users WHERE correo = @correo', {'correo': limpio});
    if (existente != null) {
      return;
    }
    await _crearCuenta({
      'nombre': 'Administrador',
      'apellido': 'Mercado Liebre',
      'correo': limpio,
      'password': password,
      'rol': 'admin',
    }, privilegiado: true);
  }

  /// Lee las claves de apariencia. Las que no existen no vienen en el mapa.
  Future<Map<String, String>> leerAjustes() async {
    final filas = await _pool.execute('SELECT clave, valor FROM ajustes');
    return {
      for (final fila in filas) fila[0].toString(): fila[1].toString(),
    };
  }

  /// Inserta o actualiza cada clave permitida por la ruta.
  Future<void> guardarAjustes(Map<String, String> valores) async {
    await _pool.runTx((conexion) async {
      for (final entrada in valores.entries) {
        await conexion.execute(
          Sql.named('''
            INSERT INTO ajustes (clave, valor) VALUES (@clave, @valor)
            ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor
          '''),
          parameters: {'clave': entrada.key, 'valor': entrada.value},
        );
      }
    });
  }

  Future<Map<String, dynamic>> _crearCuenta(Map<String, dynamic> datos, {required bool privilegiado}) async {
    final nombre = _texto(datos['nombre']);
    final apellido = _texto(datos['apellido']);
    final correo = _texto(datos['correo']).toLowerCase();
    // Sin trim: el login compara la contraseña tal cual la escribe la persona.
    final password = (datos['password'] ?? '').toString();
    final rol = _texto(datos['rol']).isEmpty ? 'comprador' : _texto(datos['rol']);
    if (nombre.isEmpty || apellido.isEmpty) {
      throw ErrorApi(400, 'Nombre y apellido son obligatorios.');
    }
    if (!correo.contains('@') || !correo.contains('.')) {
      throw ErrorApi(400, 'Ingresa un correo electrónico válido.');
    }
    if (password.length < 8) {
      throw ErrorApi(400, 'La contraseña debe tener al menos 8 caracteres.');
    }
    const rolesPublicos = {'comprador', 'vendedor'};
    const rolesAdmin = {'comprador', 'vendedor', 'moderador', 'admin'};
    final permitidos = privilegiado ? rolesAdmin : rolesPublicos;
    if (!permitidos.contains(rol)) {
      throw ErrorApi(
        400,
        privilegiado
            ? 'El rol debe ser comprador, vendedor, moderador o admin.'
            : 'El registro público solo permite comprador o vendedor.',
      );
    }
    final opcionales = _datosOpcionales(datos);
    final hash = await _hashearAparte(contrasena, password);
    try {
      return await _pool.runTx((conexion) async {
        final insertado = await conexion.execute(
          Sql.named('''
            INSERT INTO users
              (nombre, apellido, correo, telefono, numero_control, carrera, password_hash, rol)
            VALUES
              (@nombre, @apellido, @correo, @telefono, @numero, @carrera, @hash, @rol::user_role)
            RETURNING *
          '''),
          parameters: {
            'nombre': nombre,
            'apellido': apellido,
            'correo': correo,
            'telefono': opcionales['telefono'],
            'numero': opcionales['numeroControl'],
            'carrera': opcionales['carrera'],
            'hash': hash,
            'rol': rol,
          },
        );
        final usuario = insertado.first.toColumnMap();
        if (rol == 'vendedor') {
          final negocio = _texto(datos['nombreNegocio']);
          final categoria = _texto(datos['categoria']);
          if (negocio.isEmpty) {
            throw ErrorApi(400, 'Un vendedor necesita el nombre del negocio.');
          }
          if (!const {'producto', 'comida', 'servicio'}.contains(categoria)) {
            throw ErrorApi(400, 'La categoría debe ser producto, comida o servicio.');
          }
          await conexion.execute(
            Sql.named('''
              INSERT INTO sellers (user_id, nombre_negocio, categoria, subtipo, descripcion)
              VALUES (@user, @negocio, @categoria::seller_category, @subtipo, @descripcion)
            '''),
            parameters: {
              'user': usuario['id'],
              'negocio': negocio,
              'categoria': categoria,
              'subtipo': _nulo(_texto(datos['subtipo'])),
              'descripcion': _nulo(_texto(datos['descripcion'])),
            },
          );
        }
        return _usuario(usuario);
      });
    } on ServerException catch (error) {
      // 23505 = unique_violation; la única llave única de `users` es el correo.
      if (error.code == '23505') {
        throw ErrorApi(400, 'Ya existe una cuenta con ese correo.');
      }
      rethrow;
    }
  }

  /// Usuario por id, sin el hash.
  Future<Map<String, dynamic>?> obtenerUsuario(String id) async {
    final fila = await _una('SELECT * FROM users WHERE id = @id', {'id': id});
    if (fila == null) {
      return null;
    }
    return _usuario(fila);
  }

  /// Cambia teléfono, número de control y carrera de la cuenta.
  ///
  /// Una clave ausente en [datos] conserva el valor actual; una cadena
  /// vacía lo borra. Devuelve la cuenta actualizada.
  Future<Map<String, dynamic>> actualizarPerfil(String userId, Map<String, dynamic> datos) async {
    final actual = await obtenerUsuario(userId);
    if (actual == null) {
      throw ErrorApi(404, 'La cuenta ya no existe.');
    }
    final nuevos = _datosOpcionales({
      for (final clave in const ['telefono', 'numeroControl', 'carrera'])
        clave: datos.containsKey(clave) ? datos[clave] : actual[clave],
    });
    final filas = await _pool.execute(
      Sql.named('''
        UPDATE users
        SET telefono = @telefono, numero_control = @numero, carrera = @carrera
        WHERE id = @id
        RETURNING *
      '''),
      parameters: {
        'telefono': nuevos['telefono'],
        'numero': nuevos['numeroControl'],
        'carrera': nuevos['carrera'],
        'id': userId,
      },
    );
    return _usuario(filas.first.toColumnMap());
  }

  /// Teléfono, número de control y carrera validados; null si vienen vacíos.
  Map<String, String?> _datosOpcionales(Map<String, dynamic> datos) {
    final telefono = _texto(datos['telefono']);
    final digitos = telefono.replaceAll(RegExp(r'\D'), '');
    if (telefono.isNotEmpty &&
        (!RegExp(r'^[0-9+\-() ]+$').hasMatch(telefono) || digitos.length < 7 || digitos.length > 15)) {
      throw ErrorApi(400, 'El teléfono debe tener entre 7 y 15 dígitos.');
    }
    final numero = _texto(datos['numeroControl']).toUpperCase();
    if (numero.isNotEmpty && !RegExp(r'^[A-Z]?\d{6,10}$').hasMatch(numero)) {
      throw ErrorApi(400, 'El número de control debe tener de 6 a 10 dígitos (puede empezar con una letra).');
    }
    final carrera = _texto(datos['carrera']);
    if (carrera.length > 80) {
      throw ErrorApi(400, 'El nombre de la carrera es demasiado largo.');
    }
    return {'telefono': _nulo(telefono), 'numeroControl': _nulo(numero), 'carrera': _nulo(carrera)};
  }

  /// Vendedores, opcionalmente solo los que están abiertos.
  Future<List<Map<String, dynamic>>> listarVendedores({bool soloDisponibles = false}) async {
    final filtro = soloDisponibles ? 'WHERE s.disponible' : '';
    final filas = await _pool.execute('$_selectVendedores $filtro ORDER BY s.destacado DESC, s.nombre_negocio ASC');
    return filas.map((fila) => _vendedor(fila.toColumnMap())).toList();
  }

  /// Vendedores con promoción vigente.
  Future<List<Map<String, dynamic>>> listarDestacados() async {
    final filas = await _pool.execute('''
      $_selectVendedores
      WHERE s.destacado AND (s.destacado_hasta IS NULL OR s.destacado_hasta > now())
      ORDER BY s.destacado_hasta DESC NULLS LAST
    ''');
    return filas.map((fila) => _vendedor(fila.toColumnMap())).toList();
  }

  /// Perfil de negocio del usuario, o null si no es vendedor.
  Future<Map<String, dynamic>?> vendedorDeUsuario(String userId) async {
    final fila = await _una('$_selectVendedores WHERE s.user_id = @id', {'id': userId});
    if (fila == null) {
      return null;
    }
    return _vendedor(fila);
  }

  /// Productos de un vendedor, con promedio de estrellas.
  Future<List<Map<String, dynamic>>> productosDe(String sellerId) async {
    final filas = await _pool.execute(
      Sql.named('$_selectProductos WHERE p.seller_id = @id ORDER BY p.creado_en DESC'),
      parameters: {'id': sellerId},
    );
    return filas.map((fila) => _producto(fila.toColumnMap())).toList();
  }

  /// Los más vendidos, según `veces_vendido`.
  Future<List<Map<String, dynamic>>> masVendidos({int limite = 8}) async {
    final filas = await _pool.execute(
      Sql.named('$_selectProductos ORDER BY p.veces_vendido DESC LIMIT @limite'),
      parameters: {'limite': limite},
    );
    return filas.map((fila) => _producto(fila.toColumnMap())).toList();
  }

  /// Busca por negocio, subtipo o nombre de producto.
  ///
  /// Con [termino] vacío no filtra por texto: sirve para explorar una
  /// [categoria] completa. [soloDisponibles] deja solo los abiertos.
  /// Hace dos consultas en total (vendedores y sus productos), sin
  /// importar cuántos vendedores coincidan. Las coincidencias exactas
  /// van primero y el resto conserva el orden de la base.
  Future<List<Map<String, dynamic>>> buscar(
    String termino, {
    String? categoria,
    bool soloDisponibles = false,
  }) async {
    final limpio = termino.trim().toLowerCase();
    if (limpio.length == 1) {
      return [];
    }
    final patron = limpio.isEmpty
        ? null
        : '%${limpio.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
    final filas = await _pool.execute(
      Sql.named('''
        $_selectVendedores
        WHERE (
          @patron::text IS NULL
          OR s.nombre_negocio ILIKE @patron ESCAPE '\\'
          OR COALESCE(s.subtipo, '') ILIKE @patron ESCAPE '\\'
          OR EXISTS (
            SELECT 1 FROM products p
            WHERE p.seller_id = s.id AND p.nombre ILIKE @patron ESCAPE '\\'
          )
        )
        AND (@categoria::text IS NULL OR s.categoria::text = @categoria)
        AND (NOT @solo::boolean OR s.disponible)
        ORDER BY s.destacado DESC, s.nombre_negocio ASC
      '''),
      parameters: {'patron': patron, 'categoria': categoria, 'solo': soloDisponibles},
    );
    if (filas.isEmpty) {
      return [];
    }
    final vendedores = filas.map((fila) => _vendedor(fila.toColumnMap())).toList();
    final productosPorVendedor = await _productosDeVarios([
      for (final vendedor in vendedores) vendedor['id'] as String,
    ]);

    final exactas = <Map<String, dynamic>>[];
    final resto = <Map<String, dynamic>>[];
    for (final vendedor in vendedores) {
      final productos = productosPorVendedor[vendedor['id']] ?? const [];
      final negocio = (vendedor['nombreNegocio'] as String).toLowerCase();
      final subtipo = (vendedor['subtipo'] as String? ?? '').toLowerCase();
      // Si coincide el negocio o su especialidad se muestran todos sus productos.
      final coincideNegocio = limpio.isEmpty || negocio.contains(limpio) || subtipo.contains(limpio);
      final exacta = limpio.isNotEmpty && negocio == limpio ||
          productos.any((producto) => (producto['nombre'] as String).toLowerCase() == limpio);
      (exacta ? exactas : resto).add({
        'vendedor': vendedor,
        'productos': coincideNegocio
            ? productos
            : productos.where((producto) => (producto['nombre'] as String).toLowerCase().contains(limpio)).toList(),
        'coincidenciaExacta': exacta,
      });
    }
    return [...exactas, ...resto];
  }

  /// Productos de varios negocios en una sola consulta, agrupados por `sellerId`.
  Future<Map<String, List<Map<String, dynamic>>>> _productosDeVarios(List<String> sellerIds) async {
    final filas = await _pool.execute(
      Sql.named('$_selectProductos WHERE p.seller_id = ANY(@ids::uuid[]) ORDER BY p.creado_en DESC'),
      parameters: {'ids': TypedValue(Type.textArray, sellerIds)},
    );
    final agrupados = <String, List<Map<String, dynamic>>>{};
    for (final fila in filas) {
      final producto = _producto(fila.toColumnMap());
      agrupados.putIfAbsent(producto['sellerId'] as String, () => []).add(producto);
    }
    return agrupados;
  }

  /// Avisos institucionales activos.
  Future<List<Map<String, dynamic>>> avisos() async {
    final filas = await _pool.execute(
      'SELECT * FROM announcements WHERE activo = TRUE ORDER BY publicado_en DESC',
    );
    return filas.map((fila) {
      final mapa = fila.toColumnMap();
      return {
        'id': mapa['id'].toString(),
        'titulo': mapa['titulo'],
        'contenido': mapa['contenido'],
        'publicadoEn': mapa['publicado_en']?.toString(),
      };
    }).toList();
  }

  /// Ids de vendedores marcados como favoritos.
  Future<List<String>> favoritosDe(String userId) async {
    final filas = await _pool.execute(
      Sql.named('SELECT seller_id FROM favorites WHERE user_id = @id'),
      parameters: {'id': userId},
    );
    return filas.map((fila) => fila[0].toString()).toList();
  }

  /// Agrega o quita un favorito. Devuelve true si quedó marcado.
  ///
  /// Primero intenta borrar; si no había nada, inserta. Dos toques
  /// simultáneos no rompen la llave primaria gracias a `ON CONFLICT`.
  Future<bool> alternarFavorito(String userId, String sellerId) async {
    final parametros = {'u': userId, 's': sellerId};
    final borrado = await _pool.execute(
      Sql.named('DELETE FROM favorites WHERE user_id = @u AND seller_id = @s'),
      parameters: parametros,
    );
    if (borrado.affectedRows > 0) {
      return false;
    }
    try {
      await _pool.execute(
        Sql.named('INSERT INTO favorites (user_id, seller_id) VALUES (@u, @s) ON CONFLICT DO NOTHING'),
        parameters: parametros,
      );
    } on ServerException catch (error) {
      // 23503 = foreign_key_violation: el vendedor no existe.
      if (error.code == '23503') {
        throw ErrorApi(404, 'No se encontró ese vendedor.');
      }
      rethrow;
    }
    return true;
  }

  /// Crea o actualiza la calificación de un comprador sobre un producto.
  Future<void> calificar({
    required String buyerId,
    required String rol,
    required String productId,
    required int estrellas,
    String? comentario,
  }) async {
    if (rol != 'comprador' && rol != 'admin') {
      throw ErrorApi(403, 'Solo un comprador puede calificar.');
    }
    if (estrellas < 1 || estrellas > 5) {
      throw ErrorApi(400, 'La calificación va de 1 a 5 estrellas.');
    }
    final dueno = await _una(
      '''
      SELECT s.user_id
      FROM products p
      JOIN sellers s ON s.id = p.seller_id
      WHERE p.id = @id
      ''',
      {'id': productId},
    );
    if (dueno == null) {
      throw ErrorApi(404, 'No se encontró el producto.');
    }
    if (dueno['user_id'].toString() == buyerId) {
      throw ErrorApi(403, 'No puedes calificar tus propios productos.');
    }
    await _pool.execute(
      Sql.named('''
        INSERT INTO ratings (product_id, buyer_id, estrellas, comentario)
        VALUES (@p, @b, @e, @c)
        ON CONFLICT (product_id, buyer_id)
        DO UPDATE SET estrellas = EXCLUDED.estrellas, comentario = EXCLUDED.comentario
      '''),
      parameters: {
        'p': productId,
        'b': buyerId,
        'e': estrellas,
        'c': _nulo(comentario?.trim() ?? ''),
      },
    );
  }

  /// Reseñas de un producto, de la más reciente a la más antigua.
  Future<List<Map<String, dynamic>>> calificacionesDe(String productId) async {
    final filas = await _pool.execute(
      Sql.named('''
        SELECT r.estrellas, r.comentario, r.creado_en, u.nombre
        FROM ratings r
        JOIN users u ON u.id = r.buyer_id
        WHERE r.product_id = @id
        ORDER BY r.creado_en DESC
        LIMIT 20
      '''),
      parameters: {'id': productId},
    );
    return filas.map((fila) {
      final mapa = fila.toColumnMap();
      return {
        'estrellas': mapa['estrellas'],
        'comentario': mapa['comentario'],
        'nombre': mapa['nombre'],
        'creadoEn': mapa['creado_en']?.toString(),
      };
    }).toList();
  }

  /// Mueve el puesto del vendedor autenticado a un edificio del plano.
  Future<void> asignarPunto({
    required String userId,
    required String edificio,
    required bool codigoValido,
  }) async {
    if (!codigoValido) {
      throw ErrorApi(400, 'Ese punto no existe en el mapa del plantel.');
    }
    final resultado = await _pool.execute(
      Sql.named('UPDATE sellers SET edificio = @edificio WHERE user_id = @id'),
      parameters: {'edificio': edificio, 'id': userId},
    );
    _exigirAfectada(resultado, _sinNegocio);
  }

  /// Enciende o apaga la disponibilidad del negocio.
  Future<void> actualizarDisponibilidad({
    required String userId,
    required bool disponible,
  }) async {
    final resultado = await _pool.execute(
      Sql.named('UPDATE sellers SET disponible = @disponible WHERE user_id = @id'),
      parameters: {'disponible': disponible, 'id': userId},
    );
    _exigirAfectada(resultado, _sinNegocio);
  }

  /// Publica un producto del negocio de [userId].
  ///
  /// El id del negocio se toma de la cuenta, no del cuerpo de la petición,
  /// para que nadie publique a nombre de otro vendedor.
  Future<Map<String, dynamic>> publicarProducto({
    required String userId,
    required String nombre,
    required double precio,
    String? descripcion,
  }) async {
    final limpio = _validarProducto(nombre, precio);
    final negocio = await _idNegocio(userId);
    final filas = await _pool.execute(
      Sql.named('''
        INSERT INTO products (seller_id, nombre, precio, descripcion)
        VALUES (@seller, @nombre, @precio, @descripcion)
        RETURNING *
      '''),
      parameters: {
        'seller': negocio,
        'nombre': limpio,
        'precio': precio,
        'descripcion': _nulo(descripcion?.trim() ?? ''),
      },
    );
    return _producto(filas.first.toColumnMap());
  }

  /// Cambia nombre, precio, descripción o agotado de un producto propio.
  Future<void> actualizarProducto({
    required String userId,
    required String productId,
    required String nombre,
    required double precio,
    required bool agotado,
    String? descripcion,
  }) async {
    final limpio = _validarProducto(nombre, precio);
    final resultado = await _pool.execute(
      Sql.named('''
        UPDATE products
        SET nombre = @nombre,
            precio = @precio,
            descripcion = @descripcion,
            agotado = @agotado,
            actualizado_en = now()
        WHERE id = @id
          AND seller_id = (SELECT id FROM sellers WHERE user_id = @user)
      '''),
      parameters: {
        'nombre': limpio,
        'precio': precio,
        'descripcion': _nulo(descripcion?.trim() ?? ''),
        'agotado': agotado,
        'id': productId,
        'user': userId,
      },
    );
    _exigirAfectada(resultado, _productoAjeno);
  }

  /// Borra un producto propio. Las reseñas se van con la llave foránea.
  ///
  /// Devuelve la `fotoUrl` que tenía, para que la ruta borre el archivo.
  Future<String?> eliminarProducto({required String userId, required String productId}) async {
    final resultado = await _pool.execute(
      Sql.named('''
        DELETE FROM products
        WHERE id = @id
          AND seller_id = (SELECT id FROM sellers WHERE user_id = @user)
        RETURNING foto_url
      '''),
      parameters: {'id': productId, 'user': userId},
    );
    _exigirAfectada(resultado, _productoAjeno);
    return resultado.first[0] as String?;
  }

  /// Pone (o quita, con [url] null) la foto de un producto propio.
  ///
  /// Devuelve la URL anterior, para que la ruta borre ese archivo.
  Future<String?> cambiarFotoProducto({
    required String userId,
    required String productId,
    required String? url,
  }) {
    return _pool.runTx((conexion) async {
      final filas = await conexion.execute(
        Sql.named('''
          SELECT p.foto_url
          FROM products p
          JOIN sellers s ON s.id = p.seller_id
          WHERE p.id = @id AND s.user_id = @user
          FOR UPDATE OF p
        '''),
        parameters: {'id': productId, 'user': userId},
      );
      if (filas.isEmpty) {
        throw ErrorApi(404, _productoAjeno);
      }
      await conexion.execute(
        Sql.named('UPDATE products SET foto_url = @url, actualizado_en = now() WHERE id = @id'),
        parameters: {'url': url, 'id': productId},
      );
      return filas.first[0] as String?;
    });
  }

  /// Guarda apertura, cierre y días de atención del negocio propio.
  Future<void> actualizarHorario({
    required String userId,
    required String apertura,
    required String cierre,
    required String dias,
  }) async {
    if (!_horaValida(apertura) || !_horaValida(cierre)) {
      throw ErrorApi(400, 'Usa el horario en formato 24 horas, por ejemplo 08:30.');
    }
    final diasLimpios = dias.trim();
    if (diasLimpios.isEmpty || diasLimpios.length > 40) {
      throw ErrorApi(400, 'Indica los días de atención, por ejemplo Lun-Vie.');
    }
    final resultado = await _pool.execute(
      Sql.named('''
        UPDATE sellers
        SET horario_apertura = @apertura::time,
            horario_cierre = @cierre::time,
            dias_atencion = @dias
        WHERE user_id = @user
      '''),
      parameters: {
        'apertura': apertura,
        'cierre': cierre,
        'dias': diasLimpios,
        'user': userId,
      },
    );
    _exigirAfectada(resultado, _sinNegocio);
  }

  /// Guarda los canales de contacto. Un texto vacío borra ese canal.
  Future<void> actualizarContacto({
    required String userId,
    String? whatsapp,
    String? telegram,
    String? instagram,
    String? telefonoFijo,
  }) async {
    final resultado = await _pool.execute(
      Sql.named('''
        UPDATE sellers
        SET whatsapp = @whatsapp,
            telegram = @telegram,
            instagram = @instagram,
            telefono_fijo = @telefono
        WHERE user_id = @user
      '''),
      parameters: {
        'whatsapp': _nulo(whatsapp?.trim() ?? ''),
        'telegram': _nulo(telegram?.trim() ?? ''),
        'instagram': _nulo(instagram?.trim() ?? ''),
        'telefono': _nulo(telefonoFijo?.trim() ?? ''),
        'user': userId,
      },
    );
    _exigirAfectada(resultado, _sinNegocio);
  }

  /// Id del negocio de la cuenta, o un error si no es vendedor.
  Future<String> _idNegocio(String userId) async {
    final fila = await _una('SELECT id FROM sellers WHERE user_id = @id', {'id': userId});
    if (fila == null) {
      throw ErrorApi(404, _sinNegocio);
    }
    return fila['id'].toString();
  }

  /// Nombre sin espacios sobrantes. Lanza si el nombre o el precio no sirven.
  String _validarProducto(String nombre, double precio) {
    final limpio = nombre.trim();
    if (limpio.isEmpty || limpio.length > 120) {
      throw ErrorApi(400, 'El producto necesita un nombre de hasta 120 caracteres.');
    }
    // isFinite descarta NaN e Infinity, que pasarían las comparaciones de rango.
    if (!precio.isFinite || precio < 0 || precio > 999999) {
      throw ErrorApi(400, 'El precio no es válido.');
    }
    return limpio;
  }

  /// Lanza 404 con [mensaje] si el UPDATE/DELETE no tocó ninguna fila.
  void _exigirAfectada(Result resultado, String mensaje) {
    if (resultado.affectedRows == 0) {
      throw ErrorApi(404, mensaje);
    }
  }

  /// `HH:mm` en 24 horas.
  bool _horaValida(String valor) {
    return RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(valor.trim());
  }

  /// Cuentas, para el panel de moderación. Sin hashes.
  Future<List<Map<String, dynamic>>> listarUsuarios() async {
    final filas = await _pool.execute('SELECT * FROM users ORDER BY creado_en DESC');
    return filas.map((fila) => _usuario(fila.toColumnMap())).toList();
  }

  /// Bloquea o desbloquea. Lo autoriza la capa de rutas.
  Future<void> fijarBloqueo(String userId, bool bloqueado) async {
    await _pool.execute(
      Sql.named('UPDATE users SET bloqueado = @bloqueado WHERE id = @id'),
      parameters: {'bloqueado': bloqueado, 'id': userId},
    );
  }

  /// Borra la cuenta y, por las llaves foráneas, su negocio y favoritos.
  Future<void> eliminarUsuario(String userId) async {
    await _pool.execute(
      Sql.named('DELETE FROM users WHERE id = @id'),
      parameters: {'id': userId},
    );
  }

  Future<Map<String, dynamic>?> _una(String sql, Map<String, dynamic> parametros) async {
    final filas = await _pool.execute(Sql.named(sql), parameters: parametros);
    if (filas.isEmpty) {
      return null;
    }
    return filas.first.toColumnMap();
  }

  Map<String, dynamic> _usuario(Map<String, dynamic> fila) {
    return {
      'id': fila['id'].toString(),
      'nombre': fila['nombre'],
      'apellido': fila['apellido'],
      'correo': fila['correo'],
      'rol': _enum(fila['rol']),
      'telefono': fila['telefono'],
      'numeroControl': fila['numero_control'],
      'carrera': fila['carrera'],
      'fotoPerfilUrl': fila['foto_perfil_url'],
      'bloqueado': fila['bloqueado'] == true,
      'perfilEditable': fila['perfil_editable'] == true,
    };
  }

  Map<String, dynamic> _vendedor(Map<String, dynamic> fila) {
    final apertura = _hora(fila['horario_apertura']);
    final cierre = _hora(fila['horario_cierre']);
    final dias = (fila['dias_atencion'] ?? 'Lun-Vie').toString();
    return {
      'id': fila['id'].toString(),
      'userId': fila['user_id'].toString(),
      'nombreNegocio': fila['nombre_negocio'],
      'categoria': _enum(fila['categoria']),
      'subtipo': fila['subtipo'],
      'descripcion': fila['descripcion'],
      'horarioApertura': apertura,
      'horarioCierre': cierre,
      'diasAtencion': dias,
      'horarioTexto': apertura != null && cierre != null ? '$dias · $apertura - $cierre' : 'Horario no especificado',
      'disponible': fila['disponible'] == true,
      'edificio': fila['edificio'],
      'destacado': fila['destacado'] == true,
      'whatsapp': fila['whatsapp'],
      'telegram': fila['telegram'],
      'messenger': fila['messenger'],
      'instagram': fila['instagram'],
      'telefonoFijo': fila['telefono_fijo'],
      'aceptaMensajesApp': fila['acepta_mensajes_app'] != false,
      'promedioEstrellas': double.parse((fila['promedio_estrellas'] ?? 0).toString()),
      'totalResenas': int.parse((fila['total_resenas'] ?? 0).toString()),
    };
  }

  Map<String, dynamic> _producto(Map<String, dynamic> fila) {
    final precio = fila['precio'];
    return {
      'id': fila['id'].toString(),
      'sellerId': fila['seller_id'].toString(),
      'nombre': fila['nombre'],
      'descripcion': fila['descripcion'],
      'precio': precio is num ? precio.toDouble() : double.parse(precio.toString()),
      'fotoUrl': fila['foto_url'],
      'agotado': fila['agotado'] == true,
      'vecesVendido': int.parse(fila['veces_vendido'].toString()),
      'promedioEstrellas': double.parse((fila['promedio_estrellas'] ?? 0).toString()),
      'totalResenas': int.parse((fila['total_resenas'] ?? 0).toString()),
    };
  }

  String _texto(Object? valor) => (valor ?? '').toString().trim();

  /// Valor de una columna ENUM (`user_role`, `seller_category`).
  ///
  /// El driver no conoce esos tipos y los entrega como [UndecodedBytes];
  /// `toString()` daría "Instance of 'UndecodedBytes'".
  String _enum(Object? valor) => valor is UndecodedBytes ? valor.asString : '${valor ?? ''}';

  String? _nulo(String valor) => valor.isEmpty ? null : valor;

  /// Columna TIME como `HH:mm`. El driver la entrega como [Time].
  String? _hora(Object? valor) {
    if (valor == null) {
      return null;
    }
    if (valor is Time) {
      return '${valor.hour.toString().padLeft(2, '0')}:${valor.minute.toString().padLeft(2, '0')}';
    }
    final texto = valor.toString();
    return texto.length >= 5 ? texto.substring(0, 5) : texto;
  }
}
