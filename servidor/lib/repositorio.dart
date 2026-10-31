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

  /// Promedio y total de reseñas aprobadas de cada negocio (alias `r`).
  static const String _promediosNegocio = '''
    LEFT JOIN (
      SELECT p.seller_id, AVG(ra.estrellas)::float8 AS promedio, COUNT(*)::int AS total
      FROM ratings ra
      JOIN products p ON p.id = ra.product_id
      WHERE ra.aprobada
      GROUP BY p.seller_id
    ) r ON r.seller_id = s.id
  ''';

  /// Columnas del vendedor más el promedio y total de reseñas de todos sus
  /// productos. Se completa con WHERE/ORDER usando el alias `s`.
  ///
  /// Solo negocios públicos: si su dueño cambió a modo comprador
  /// ([cambiarModo]) el negocio queda en pausa y no aparece.
  static const String _selectVendedores = '''
    SELECT s.*,
           COALESCE(r.promedio, 0) AS promedio_estrellas,
           COALESCE(r.total, 0) AS total_resenas
    FROM sellers s
    JOIN users dueno ON dueno.id = s.user_id AND dueno.rol <> 'comprador'
    $_promediosNegocio
  ''';

  /// Igual que [_selectVendedores] pero incluye los negocios en pausa.
  /// Para el administrador y para el dueño.
  static const String _selectTodosLosVendedores = '''
    SELECT s.*,
           COALESCE(r.promedio, 0) AS promedio_estrellas,
           COALESCE(r.total, 0) AS total_resenas
    FROM sellers s
    $_promediosNegocio
  ''';

  /// Deja en [_selectProductos] solo los productos de negocios públicos.
  static const String _soloNegociosPublicos = '''
    JOIN sellers sv ON sv.id = p.seller_id
    JOIN users dueno ON dueno.id = sv.user_id AND dueno.rol <> 'comprador'
  ''';

  /// Columna de cada imagen del negocio que sube el vendedor. El tipo que
  /// manda el cliente solo se busca aquí: el SQL usa estos nombres fijos.
  static const Map<String, String> columnasImagenNegocio = {'logo': 'logo_url', 'portada': 'portada_url'};

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
              (nombre, apellido, correo, telefono, numero_control, carrera, password_hash, rol, correo_verificado)
            VALUES
              (@nombre, @apellido, @correo, @telefono, @numero, @carrera, @hash, @rol::user_role, @verificado)
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
            // El registro público verifica con el enlace del correo; las
            // cuentas que crea el administrador ya nacen verificadas.
            'verificado': privilegiado,
          },
        );
        final usuario = insertado.first.toColumnMap();
        if (rol == 'vendedor') {
          await _insertarNegocio(conexion, usuario['id'].toString(), datos);
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

  /// Crea el negocio de [userId] con `nombreNegocio`, `categoria`, `subtipo` y `descripcion` de [datos].
  Future<void> _insertarNegocio(Session conexion, String userId, Map<String, dynamic> datos) async {
    final negocio = _texto(datos['nombreNegocio']);
    final categoria = _texto(datos['categoria']);
    if (negocio.isEmpty || negocio.length > 120) {
      throw ErrorApi(400, 'Un vendedor necesita el nombre del negocio (hasta 120 caracteres).');
    }
    if (!const {'producto', 'comida', 'servicio'}.contains(categoria)) {
      throw ErrorApi(400, 'La categoría debe ser producto, comida o servicio.');
    }
    if (_texto(datos['subtipo']).length > 80 || _texto(datos['descripcion']).length > 500) {
      throw ErrorApi(400, 'La especialidad admite 80 caracteres y la descripción 500.');
    }
    await conexion.execute(
      Sql.named('''
        INSERT INTO sellers (user_id, nombre_negocio, categoria, subtipo, descripcion)
        VALUES (@user, @negocio, @categoria::seller_category, @subtipo, @descripcion)
      '''),
      parameters: {
        'user': userId,
        'negocio': negocio,
        'categoria': categoria,
        'subtipo': _nulo(_texto(datos['subtipo'])),
        'descripcion': _nulo(_texto(datos['descripcion'])),
      },
    );
  }

  /// Cambia la cuenta entre modo `comprador` y modo `vendedor` (`datos['modo']`).
  ///
  /// Solo para cuentas de comprador o vendedor; admin y moderador ya tienen
  /// la vista previa. Al pasar a vendedor por primera vez se crea el negocio
  /// con `nombreNegocio` y `categoria` (obligatorios), `subtipo` y `descripcion`.
  /// Al volver a comprador el negocio no se borra: queda en pausa (cerrado y
  /// fuera de las listas públicas) con su catálogo, horario e imágenes, y
  /// reaparece tal cual al regresar a vendedor. Devuelve la cuenta actualizada.
  Future<Map<String, dynamic>> cambiarModo(String userId, Map<String, dynamic> datos) {
    final modo = _texto(datos['modo']);
    if (modo != 'comprador' && modo != 'vendedor') {
      throw ErrorApi(400, 'El modo debe ser comprador o vendedor.');
    }
    return _pool.runTx((conexion) async {
      final cuenta = await conexion.execute(
        Sql.named('SELECT rol FROM users WHERE id = @id FOR UPDATE'),
        parameters: {'id': userId},
      );
      if (cuenta.isEmpty) {
        throw ErrorApi(404, 'La cuenta ya no existe.');
      }
      final rol = _enum(cuenta.first[0]);
      if (rol != 'comprador' && rol != 'vendedor') {
        throw ErrorApi(400, 'Solo una cuenta de usuario o de vendedor puede cambiar de modo.');
      }
      if (modo == 'vendedor') {
        final negocio = await conexion.execute(
          Sql.named('SELECT 1 FROM sellers WHERE user_id = @id'),
          parameters: {'id': userId},
        );
        if (negocio.isEmpty) {
          await _insertarNegocio(conexion, userId, datos);
        }
      } else {
        await conexion.execute(
          Sql.named('UPDATE sellers SET disponible = FALSE WHERE user_id = @id'),
          parameters: {'id': userId},
        );
      }
      final filas = await conexion.execute(
        Sql.named('UPDATE users SET rol = @modo::user_role WHERE id = @id RETURNING *'),
        parameters: {'modo': modo, 'id': userId},
      );
      return _usuario(filas.first.toColumnMap());
    });
  }

  /// Pone (o quita, con [url] null) la foto de perfil de [userId].
  ///
  /// Devuelve la URL anterior (para borrar el archivo) y la cuenta actualizada.
  Future<(String?, Map<String, dynamic>)> cambiarFotoPerfil(String userId, String? url) {
    return _pool.runTx((conexion) async {
      final actual = await conexion.execute(
        Sql.named('SELECT foto_perfil_url FROM users WHERE id = @id FOR UPDATE'),
        parameters: {'id': userId},
      );
      if (actual.isEmpty) {
        throw ErrorApi(404, 'La cuenta ya no existe.');
      }
      final filas = await conexion.execute(
        Sql.named('UPDATE users SET foto_perfil_url = @url WHERE id = @id RETURNING *'),
        parameters: {'url': url, 'id': userId},
      );
      return (actual.first[0] as String?, _usuario(filas.first.toColumnMap()));
    });
  }

  /// Pone (o quita, con [url] null) el logo o la foto de la tienda del negocio de [userId].
  ///
  /// [tipo] es una clave de [columnasImagenNegocio]. Devuelve la URL anterior
  /// (para borrar el archivo) y el negocio actualizado.
  Future<(String?, Map<String, dynamic>)> cambiarImagenNegocio(String userId, String tipo, String? url) async {
    final columna = columnasImagenNegocio[tipo];
    if (columna == null) {
      throw ErrorApi(404, 'Esa imagen del negocio no existe.');
    }
    final anterior = await _pool.runTx((conexion) async {
      final actual = await conexion.execute(
        Sql.named('SELECT $columna FROM sellers WHERE user_id = @id FOR UPDATE'),
        parameters: {'id': userId},
      );
      if (actual.isEmpty) {
        throw ErrorApi(404, _sinNegocio);
      }
      await conexion.execute(
        Sql.named('UPDATE sellers SET $columna = @url WHERE user_id = @id'),
        parameters: {'url': url, 'id': userId},
      );
      return actual.first[0] as String?;
    });
    return (anterior, (await vendedorDeUsuario(userId))!);
  }

  /// Usuario por id, sin el hash.
  Future<Map<String, dynamic>?> obtenerUsuario(String id) async {
    final fila = await _una('SELECT * FROM users WHERE id = @id', {'id': id});
    if (fila == null) {
      return null;
    }
    return _usuario(fila);
  }

  /// Marca el correo de [userId] como verificado. Falso si la cuenta ya no existe.
  Future<bool> verificarCorreo(String userId) async {
    final resultado = await _pool.execute(
      Sql.named('UPDATE users SET correo_verificado = TRUE WHERE id = @id'),
      parameters: {'id': userId},
    );
    return resultado.affectedRows > 0;
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

  /// Todos los negocios con `ultimoAcceso` (último uso de la app de su dueño).
  ///
  /// Solo para el administrador. Primero los que llevan más tiempo sin usarla,
  /// para encontrar tiendas fantasma.
  Future<List<Map<String, dynamic>>> listarVendedoresAdmin() async {
    final filas = await _pool.execute('''
      SELECT v.*, u.ultimo_acceso
      FROM ($_selectTodosLosVendedores) v
      JOIN users u ON u.id = v.user_id
      ORDER BY u.ultimo_acceso ASC NULLS FIRST, v.nombre_negocio ASC
    ''');
    return filas.map((fila) {
      final mapa = fila.toColumnMap();
      return {..._vendedor(mapa), 'ultimoAcceso': _fecha(mapa['ultimo_acceso'])};
    }).toList();
  }

  /// Anota que [userId] usó la app. Solo escribe si el registro anterior tiene más de una hora.
  Future<void> registrarAcceso(String userId) async {
    await _pool.execute(
      Sql.named('''
        UPDATE users SET ultimo_acceso = now()
        WHERE id = @id AND (ultimo_acceso IS NULL OR ultimo_acceso < now() - interval '1 hour')
      '''),
      parameters: {'id': userId},
    );
  }

  /// Perfil de negocio del usuario (aunque esté en pausa), o null si no tiene.
  Future<Map<String, dynamic>?> vendedorDeUsuario(String userId) async {
    final fila = await _una('$_selectTodosLosVendedores WHERE s.user_id = @id', {'id': userId});
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
      Sql.named('$_selectProductos $_soloNegociosPublicos ORDER BY p.veces_vendido DESC LIMIT @limite'),
      parameters: {'limite': limite},
    );
    return filas.map((fila) => _producto(fila.toColumnMap())).toList();
  }

  /// Negocio público por id, o null si no existe o está en pausa.
  ///
  /// Lo usan los enlaces compartidos (`?vendedor=<id>`).
  Future<Map<String, dynamic>?> vendedorPublico(String sellerId) async {
    final fila = await _una('$_selectVendedores WHERE s.id = @id', {'id': sellerId});
    return fila == null ? null : _vendedor(fila);
  }

  /// Producto de un negocio público por id, o null.
  ///
  /// Lo usan los enlaces compartidos (`?producto=<id>`).
  Future<Map<String, dynamic>?> productoPublico(String productId) async {
    final fila = await _una('$_selectProductos $_soloNegociosPublicos WHERE p.id = @id', {'id': productId});
    return fila == null ? null : _producto(fila);
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
    return filas.map((fila) => _aviso(fila.toColumnMap())).toList();
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

  /// Crea o actualiza la calificación de un comprador o vendedor sobre un producto.
  ///
  /// Exige [correoVerificado]: una cuenta nueva no califica ni comenta
  /// hasta abrir el enlace del correo de verificación.
  ///
  /// La reseña de un vendedor (o de quien tenga un negocio, aunque esté en
  /// pausa) queda pendiente: no se muestra ni cuenta en los promedios hasta
  /// que el administrador la aprueba (evita reseñas de la competencia).
  /// Editarla la vuelve a dejar pendiente. Devuelve true si quedó pendiente.
  Future<bool> calificar({
    required String buyerId,
    required String rol,
    required bool correoVerificado,
    required String productId,
    required int estrellas,
    String? comentario,
  }) async {
    if (rol != 'comprador' && rol != 'vendedor' && rol != 'admin') {
      throw ErrorApi(403, 'Solo compradores y vendedores pueden calificar.');
    }
    if (!correoVerificado) {
      throw ErrorApi(403, 'Verifica tu correo para calificar y comentar. Revisa tu bandeja de entrada.');
    }
    if (estrellas < 1 || estrellas > 5) {
      throw ErrorApi(400, 'La calificación va de 1 a 5 estrellas.');
    }
    final dueno = await _una(
      '''
      SELECT s.user_id, EXISTS (SELECT 1 FROM sellers WHERE user_id = @autor) AS autor_con_negocio
      FROM products p
      JOIN sellers s ON s.id = p.seller_id
      WHERE p.id = @id
      ''',
      {'id': productId, 'autor': buyerId},
    );
    if (dueno == null) {
      throw ErrorApi(404, 'No se encontró el producto.');
    }
    if (dueno['user_id'].toString() == buyerId) {
      throw ErrorApi(403, 'No puedes calificar tus propios productos.');
    }
    // También cuenta un negocio en pausa: pasar a modo comprador no evita la revisión.
    final pendiente = rol != 'admin' && (rol == 'vendedor' || dueno['autor_con_negocio'] == true);
    await _pool.execute(
      Sql.named('''
        INSERT INTO ratings (product_id, buyer_id, estrellas, comentario, aprobada)
        VALUES (@p, @b, @e, @c, @aprobada)
        ON CONFLICT (product_id, buyer_id)
        DO UPDATE SET estrellas = EXCLUDED.estrellas, comentario = EXCLUDED.comentario,
                      aprobada = EXCLUDED.aprobada
      '''),
      parameters: {
        'p': productId,
        'b': buyerId,
        'e': estrellas,
        'c': _nulo(comentario?.trim() ?? ''),
        'aprobada': !pendiente,
      },
    );
    return pendiente;
  }

  /// Reseñas aprobadas de un producto, de la más reciente a la más antigua.
  Future<List<Map<String, dynamic>>> calificacionesDe(String productId) async {
    final filas = await _pool.execute(
      Sql.named('''
        SELECT r.estrellas, r.comentario, r.creado_en, u.nombre, u.foto_perfil_url
        FROM ratings r
        JOIN users u ON u.id = r.buyer_id
        WHERE r.product_id = @id AND r.aprobada
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
        'fotoPerfilUrl': mapa['foto_perfil_url'],
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

  /// Borra la cuenta y, por las llaves foráneas (ON DELETE CASCADE), todo lo
  /// suyo: negocio, productos, reseñas que escribió y que recibieron sus
  /// productos, favoritos, anuncios de su negocio y restablecimientos.
  ///
  /// Devuelve las URLs de las fotos de sus productos, de su perfil y del logo
  /// y foto de su tienda, para que la ruta borre esos archivos del disco.
  Future<List<String>> eliminarUsuario(String userId) {
    return _pool.runTx((conexion) async {
      final fotos = await conexion.execute(
        Sql.named('''
          SELECT p.foto_url FROM products p
          JOIN sellers s ON s.id = p.seller_id
          WHERE s.user_id = @id AND p.foto_url IS NOT NULL
          UNION ALL
          SELECT foto_perfil_url FROM users WHERE id = @id AND foto_perfil_url IS NOT NULL
          UNION ALL
          SELECT unnest(ARRAY[logo_url, portada_url]) FROM sellers WHERE user_id = @id
        '''),
        parameters: {'id': userId},
      );
      await conexion.execute(Sql.named('DELETE FROM users WHERE id = @id'), parameters: {'id': userId});
      return [for (final fila in fotos) if (fila[0] != null) fila[0].toString()];
    });
  }

  // ── Cuenta propia ─────────────────────────────────────────────────────

  /// Borra la cuenta de [userId] tras comprobar su [password]. Ver [eliminarUsuario].
  ///
  /// Un administrador no puede borrarse a sí mismo: la app podría quedarse
  /// sin nadie que la administre. Otro administrador sí puede hacerlo.
  Future<List<String>> eliminarCuentaPropia(String userId, String password) async {
    final fila = await _una('SELECT password_hash, rol FROM users WHERE id = @id', {'id': userId});
    if (fila == null) {
      throw ErrorApi(404, 'La cuenta ya no existe.');
    }
    if (_enum(fila['rol']) == 'admin') {
      throw ErrorApi(400, 'Un administrador no puede eliminar su propia cuenta. Pide a otro administrador que lo haga.');
    }
    if (!await _verificarAparte(contrasena, password, fila['password_hash'].toString())) {
      throw ErrorApi(403, 'La contraseña no es correcta.');
    }
    return eliminarUsuario(userId);
  }

  // ── Restablecimiento de contraseña ────────────────────────────────────

  /// Cuenta con ese correo, o null. Solo para el flujo de "olvidé mi contraseña".
  Future<Map<String, dynamic>?> usuarioPorCorreo(String correo) async {
    final fila = await _una('SELECT * FROM users WHERE correo = @correo', {'correo': correo.trim().toLowerCase()});
    return fila == null ? null : _usuario(fila);
  }

  /// Registra una solicitud de restablecimiento y devuelve su id (va dentro del token del enlace).
  ///
  /// [origen] es `correo` (la pidió la persona) o `admin`. Las solicitudes
  /// anteriores que seguían pendientes se anulan: solo vale el último enlace.
  Future<String> crearRestablecimiento(String userId, {required String origen, required Duration vigencia}) {
    return _pool.runTx((conexion) async {
      await conexion.execute(
        Sql.named('''
          UPDATE restablecimientos SET anulado = TRUE
          WHERE user_id = @user AND usado_en IS NULL AND NOT anulado
        '''),
        parameters: {'user': userId},
      );
      final filas = await conexion.execute(
        Sql.named('''
          INSERT INTO restablecimientos (user_id, origen, vence_en)
          VALUES (@user, @origen, now() + (@minutos::int * interval '1 minute'))
          RETURNING id
        '''),
        parameters: {'user': userId, 'origen': origen, 'minutos': vigencia.inMinutes},
      );
      return filas.first[0].toString();
    });
  }

  /// Verdadero si la solicitud existe, no se usó, no se anuló y no venció.
  Future<bool> restablecimientoVigente(String solicitudId) async {
    final fila = await _una(
      'SELECT 1 FROM restablecimientos WHERE id = @id AND usado_en IS NULL AND NOT anulado AND vence_en > now()',
      {'id': solicitudId},
    );
    return fila != null;
  }

  /// Cambia la contraseña con una solicitud vigente y la marca como usada.
  Future<void> restablecerContrasena(String solicitudId, String password) async {
    _validarPassword(password);
    final hash = await _hashearAparte(contrasena, password);
    await _pool.runTx((conexion) async {
      final filas = await conexion.execute(
        Sql.named('''
          SELECT user_id FROM restablecimientos
          WHERE id = @id AND usado_en IS NULL AND NOT anulado AND vence_en > now()
          FOR UPDATE
        '''),
        parameters: {'id': solicitudId},
      );
      if (filas.isEmpty) {
        throw ErrorApi(400, 'El enlace ya se usó, venció o fue anulado. Pide otro desde "¿Olvidaste tu contraseña?".');
      }
      final userId = filas.first[0].toString();
      await conexion.execute(
        Sql.named('UPDATE users SET password_hash = @hash WHERE id = @id'),
        parameters: {'hash': hash, 'id': userId},
      );
      await conexion.execute(
        Sql.named('UPDATE restablecimientos SET usado_en = now() WHERE id = @id'),
        parameters: {'id': solicitudId},
      );
    });
  }

  /// El administrador fija una contraseña nueva. Queda registrado como restablecimiento usado.
  Future<void> cambiarContrasenaAdmin(String userId, String password) async {
    _validarPassword(password);
    final hash = await _hashearAparte(contrasena, password);
    await _pool.runTx((conexion) async {
      final resultado = await conexion.execute(
        Sql.named('UPDATE users SET password_hash = @hash WHERE id = @id'),
        parameters: {'hash': hash, 'id': userId},
      );
      _exigirAfectada(resultado, 'No se encontró la cuenta.');
      await conexion.execute(
        Sql.named('''
          UPDATE restablecimientos SET anulado = TRUE
          WHERE user_id = @user AND usado_en IS NULL AND NOT anulado
        '''),
        parameters: {'user': userId},
      );
      await conexion.execute(
        Sql.named('''
          INSERT INTO restablecimientos (user_id, origen, vence_en, usado_en)
          VALUES (@user, 'admin', now(), now())
        '''),
        parameters: {'user': userId},
      );
    });
  }

  /// Últimas 100 solicitudes, con la cuenta y un `estado` ya calculado.
  Future<List<Map<String, dynamic>>> listarRestablecimientos() async {
    final filas = await _pool.execute('''
      SELECT r.id, r.user_id, r.origen, r.creado_en, r.vence_en, r.usado_en, r.anulado,
             u.nombre, u.apellido, u.correo,
             CASE
               WHEN r.anulado THEN 'anulado'
               WHEN r.usado_en IS NOT NULL THEN 'usado'
               WHEN r.vence_en <= now() THEN 'vencido'
               ELSE 'pendiente'
             END AS estado
      FROM restablecimientos r
      JOIN users u ON u.id = r.user_id
      ORDER BY r.creado_en DESC
      LIMIT 100
    ''');
    return filas.map((fila) {
      final mapa = fila.toColumnMap();
      return {
        'id': mapa['id'].toString(),
        'userId': mapa['user_id'].toString(),
        'nombre': '${mapa['nombre']} ${mapa['apellido']}'.trim(),
        'correo': mapa['correo'],
        'origen': mapa['origen'],
        'estado': mapa['estado'],
        'creadoEn': _fecha(mapa['creado_en']),
        'venceEn': _fecha(mapa['vence_en']),
        'usadoEn': _fecha(mapa['usado_en']),
      };
    }).toList();
  }

  /// Anula una solicitud pendiente: su enlace deja de servir.
  Future<void> anularRestablecimiento(String solicitudId) async {
    final resultado = await _pool.execute(
      Sql.named('UPDATE restablecimientos SET anulado = TRUE WHERE id = @id AND usado_en IS NULL AND NOT anulado'),
      parameters: {'id': solicitudId},
    );
    _exigirAfectada(resultado, 'Esa solicitud ya no está pendiente.');
  }

  void _validarPassword(String password) {
    if (password.length < 8) {
      throw ErrorApi(400, 'La contraseña debe tener al menos 8 caracteres.');
    }
  }

  // ── Administración: cuentas ───────────────────────────────────────────

  /// Cambia nombre, apellido, correo, rol, verificación y datos opcionales de una cuenta.
  ///
  /// Clave ausente en [datos] = sin cambio. [actorId] es el administrador que
  /// edita: no puede quitarse a sí mismo el rol de administrador.
  Future<Map<String, dynamic>> actualizarUsuarioAdmin(
    String userId,
    Map<String, dynamic> datos, {
    required String actorId,
  }) async {
    final actual = await obtenerUsuario(userId);
    if (actual == null) {
      throw ErrorApi(404, 'No se encontró la cuenta.');
    }
    String campo(String clave) => datos.containsKey(clave) ? _texto(datos[clave]) : (actual[clave] ?? '').toString();
    final nombre = campo('nombre');
    final apellido = campo('apellido');
    final correo = campo('correo').toLowerCase();
    final rol = campo('rol');
    if (nombre.isEmpty || apellido.isEmpty) {
      throw ErrorApi(400, 'Nombre y apellido son obligatorios.');
    }
    if (!correo.contains('@') || !correo.contains('.')) {
      throw ErrorApi(400, 'Ingresa un correo electrónico válido.');
    }
    if (!const {'comprador', 'vendedor', 'moderador', 'admin'}.contains(rol)) {
      throw ErrorApi(400, 'El rol debe ser comprador, vendedor, moderador o admin.');
    }
    if (userId == actorId && rol != 'admin') {
      throw ErrorApi(400, 'No puedes quitarte a ti mismo el rol de administrador.');
    }
    final verificado =
        datos.containsKey('correoVerificado') ? datos['correoVerificado'] == true : actual['correoVerificado'] == true;
    final opcionales = _datosOpcionales({
      for (final clave in const ['telefono', 'numeroControl', 'carrera'])
        clave: datos.containsKey(clave) ? datos[clave] : actual[clave],
    });
    try {
      final filas = await _pool.execute(
        Sql.named('''
          UPDATE users
          SET nombre = @nombre, apellido = @apellido, correo = @correo, rol = @rol::user_role,
              correo_verificado = @verificado, telefono = @telefono, numero_control = @numero, carrera = @carrera
          WHERE id = @id
          RETURNING *
        '''),
        parameters: {
          'nombre': nombre,
          'apellido': apellido,
          'correo': correo,
          'rol': rol,
          'verificado': verificado,
          'telefono': opcionales['telefono'],
          'numero': opcionales['numeroControl'],
          'carrera': opcionales['carrera'],
          'id': userId,
        },
      );
      return _usuario(filas.first.toColumnMap());
    } on ServerException catch (error) {
      if (error.code == '23505') {
        throw ErrorApi(400, 'Ya existe una cuenta con ese correo.');
      }
      rethrow;
    }
  }

  // ── Administración: negocios y productos ──────────────────────────────

  /// Negocio por id (aunque esté en pausa), con su promedio de reseñas, o null.
  Future<Map<String, dynamic>?> vendedorPorId(String sellerId) async {
    final fila = await _una('$_selectTodosLosVendedores WHERE s.id = @id', {'id': sellerId});
    return fila == null ? null : _vendedor(fila);
  }

  /// Edita cualquier negocio. Clave ausente en [datos] = sin cambio.
  ///
  /// `edificio` llega ya validado por la ruta contra el plano (vacío = sin punto).
  /// `destacadoHasta` es una fecha ISO 8601 o vacío (promoción sin fin).
  Future<Map<String, dynamic>> actualizarVendedorAdmin(String sellerId, Map<String, dynamic> datos) async {
    final actual = await vendedorPorId(sellerId);
    if (actual == null) {
      throw ErrorApi(404, 'No se encontró ese negocio.');
    }
    String campo(String clave) => datos.containsKey(clave) ? _texto(datos[clave]) : (actual[clave] ?? '').toString();
    bool interruptor(String clave) => datos.containsKey(clave) ? datos[clave] == true : actual[clave] == true;
    final nombre = campo('nombreNegocio');
    final categoria = campo('categoria');
    final subtipo = campo('subtipo');
    final descripcion = campo('descripcion');
    final hasta = campo('destacadoHasta');
    if (nombre.isEmpty || nombre.length > 120) {
      throw ErrorApi(400, 'El negocio necesita un nombre de hasta 120 caracteres.');
    }
    if (!const {'producto', 'comida', 'servicio'}.contains(categoria)) {
      throw ErrorApi(400, 'La categoría debe ser producto, comida o servicio.');
    }
    if (subtipo.length > 80 || descripcion.length > 500) {
      throw ErrorApi(400, 'La especialidad admite 80 caracteres y la descripción 500.');
    }
    final fechaHasta = hasta.isEmpty ? null : DateTime.tryParse(hasta);
    if (hasta.isNotEmpty && fechaHasta == null) {
      throw ErrorApi(400, 'La fecha de fin de la promoción no es válida.');
    }
    await _pool.execute(
      Sql.named('''
        UPDATE sellers
        SET nombre_negocio = @nombre, categoria = @categoria::seller_category, subtipo = @subtipo,
            descripcion = @descripcion, edificio = @edificio, disponible = @disponible,
            destacado = @destacado, destacado_hasta = @hasta
        WHERE id = @id
      '''),
      parameters: {
        'nombre': nombre,
        'categoria': categoria,
        'subtipo': _nulo(subtipo),
        'descripcion': _nulo(descripcion),
        'edificio': _nulo(campo('edificio').toUpperCase()),
        'disponible': interruptor('disponible'),
        'destacado': interruptor('destacado'),
        'hasta': fechaHasta?.toUtc(),
        'id': sellerId,
      },
    );
    return (await vendedorPorId(sellerId))!;
  }

  /// Borra un negocio con sus productos (y sus reseñas y anuncios). La cuenta
  /// sigue existiendo y pasa a comprador. Devuelve las fotos a borrar del disco.
  Future<List<String>> eliminarNegocio(String sellerId) {
    return _pool.runTx((conexion) async {
      final negocio = await conexion.execute(
        Sql.named('SELECT user_id FROM sellers WHERE id = @id'),
        parameters: {'id': sellerId},
      );
      if (negocio.isEmpty) {
        throw ErrorApi(404, 'No se encontró ese negocio.');
      }
      final fotos = await conexion.execute(
        Sql.named('''
          SELECT foto_url FROM products WHERE seller_id = @id AND foto_url IS NOT NULL
          UNION ALL
          SELECT unnest(ARRAY[logo_url, portada_url]) FROM sellers WHERE id = @id
        '''),
        parameters: {'id': sellerId},
      );
      await conexion.execute(Sql.named('DELETE FROM sellers WHERE id = @id'), parameters: {'id': sellerId});
      await conexion.execute(
        Sql.named("UPDATE users SET rol = 'comprador' WHERE id = @user AND rol = 'vendedor'"),
        parameters: {'user': negocio.first[0].toString()},
      );
      return [for (final fila in fotos) if (fila[0] != null) fila[0].toString()];
    });
  }

  /// Borra cualquier producto. Devuelve su foto para borrar el archivo.
  Future<String?> eliminarProductoAdmin(String productId) async {
    final resultado = await _pool.execute(
      Sql.named('DELETE FROM products WHERE id = @id RETURNING foto_url'),
      parameters: {'id': productId},
    );
    _exigirAfectada(resultado, 'No se encontró ese producto.');
    return resultado.first[0] as String?;
  }

  // ── Publicidad ────────────────────────────────────────────────────────

  /// Anuncios publicados, ordenados por sección y posición.
  ///
  /// Cada uno trae el negocio completo en `vendedor` (o null), para que la
  /// app abra su ficha al tocarlo sin otra petición.
  Future<List<Map<String, dynamic>>> anuncios() async {
    final filas = await _pool.execute('''
      SELECT a.seccion, a.posicion, a.imagen_url, v.*
      FROM anuncios a
      LEFT JOIN ($_selectVendedores) v ON v.id = a.seller_id
      ORDER BY a.seccion, a.posicion
    ''');
    return filas.map((fila) {
      final mapa = fila.toColumnMap();
      return {
        'seccion': mapa['seccion'],
        'posicion': mapa['posicion'],
        'imagenUrl': mapa['imagen_url'],
        'vendedor': mapa['id'] == null ? null : _vendedor(mapa),
      };
    }).toList();
  }

  /// Crea o reemplaza el anuncio de una posición. [sellerId] null = sin negocio enlazado.
  Future<void> guardarAnuncio({
    required int seccion,
    required int posicion,
    required String imagenUrl,
    String? sellerId,
  }) async {
    try {
      await _pool.execute(
        Sql.named('''
          INSERT INTO anuncios (seccion, posicion, imagen_url, seller_id)
          VALUES (@seccion, @posicion, @imagen, @seller)
          ON CONFLICT (seccion, posicion)
          DO UPDATE SET imagen_url = EXCLUDED.imagen_url, seller_id = EXCLUDED.seller_id, actualizado_en = now()
        '''),
        parameters: {'seccion': seccion, 'posicion': posicion, 'imagen': imagenUrl, 'seller': sellerId},
      );
    } on ServerException catch (error) {
      if (error.code == '23503') {
        throw ErrorApi(404, 'No se encontró ese negocio.');
      }
      rethrow;
    }
  }

  /// Quita el anuncio de una posición. La imagen se queda en medios (puede reutilizarse).
  Future<void> eliminarAnuncio(int seccion, int posicion) async {
    final resultado = await _pool.execute(
      Sql.named('DELETE FROM anuncios WHERE seccion = @seccion AND posicion = @posicion'),
      parameters: {'seccion': seccion, 'posicion': posicion},
    );
    _exigirAfectada(resultado, 'Esa posición ya estaba vacía.');
  }

  // ── Administración: avisos ────────────────────────────────────────────

  /// Todos los avisos, activos e inactivos, del más reciente al más antiguo.
  Future<List<Map<String, dynamic>>> avisosAdmin() async {
    final filas = await _pool.execute('SELECT * FROM announcements ORDER BY publicado_en DESC');
    return filas.map((fila) => _aviso(fila.toColumnMap())).toList();
  }

  /// Publica un aviso en la pantalla de inicio.
  Future<Map<String, dynamic>> crearAviso(Map<String, dynamic> datos) async {
    final (titulo, contenido) = _validarAviso(_texto(datos['titulo']), _texto(datos['contenido']));
    final filas = await _pool.execute(
      Sql.named('''
        INSERT INTO announcements (titulo, contenido, activo)
        VALUES (@titulo, @contenido, @activo)
        RETURNING *
      '''),
      parameters: {'titulo': titulo, 'contenido': contenido, 'activo': datos['activo'] != false},
    );
    return _aviso(filas.first.toColumnMap());
  }

  /// Cambia título, contenido o si está activo. Clave ausente = sin cambio.
  Future<Map<String, dynamic>> actualizarAviso(String id, Map<String, dynamic> datos) async {
    final actual = await _una('SELECT * FROM announcements WHERE id = @id', {'id': id});
    if (actual == null) {
      throw ErrorApi(404, 'No se encontró ese aviso.');
    }
    final (titulo, contenido) = _validarAviso(
      datos.containsKey('titulo') ? _texto(datos['titulo']) : actual['titulo'].toString(),
      datos.containsKey('contenido') ? _texto(datos['contenido']) : actual['contenido'].toString(),
    );
    final filas = await _pool.execute(
      Sql.named('''
        UPDATE announcements SET titulo = @titulo, contenido = @contenido, activo = @activo
        WHERE id = @id
        RETURNING *
      '''),
      parameters: {
        'titulo': titulo,
        'contenido': contenido,
        'activo': datos.containsKey('activo') ? datos['activo'] == true : actual['activo'] == true,
        'id': id,
      },
    );
    return _aviso(filas.first.toColumnMap());
  }

  /// Borra un aviso.
  Future<void> eliminarAviso(String id) async {
    final resultado = await _pool.execute(
      Sql.named('DELETE FROM announcements WHERE id = @id'),
      parameters: {'id': id},
    );
    _exigirAfectada(resultado, 'No se encontró ese aviso.');
  }

  (String, String) _validarAviso(String titulo, String contenido) {
    if (titulo.isEmpty || titulo.length > 120) {
      throw ErrorApi(400, 'El aviso necesita un título de hasta 120 caracteres.');
    }
    if (contenido.isEmpty || contenido.length > 2000) {
      throw ErrorApi(400, 'El aviso necesita un texto de hasta 2000 caracteres.');
    }
    return (titulo, contenido);
  }

  // ── Administración: reseñas ───────────────────────────────────────────

  /// Reseñas pendientes de aprobación y las más recientes (100 en total).
  ///
  /// Las pendientes van primero. `negocioAutor` es el negocio de quien la
  /// escribió (si tiene uno), para detectar reseñas de la competencia.
  Future<List<Map<String, dynamic>>> calificacionesRecientes() async {
    final filas = await _pool.execute('''
      SELECT r.product_id, r.buyer_id, r.estrellas, r.comentario, r.creado_en, r.aprobada,
             p.nombre AS producto, s.nombre_negocio, u.nombre, u.apellido, u.correo,
             sa.nombre_negocio AS negocio_autor
      FROM ratings r
      JOIN products p ON p.id = r.product_id
      JOIN sellers s ON s.id = p.seller_id
      JOIN users u ON u.id = r.buyer_id
      LEFT JOIN sellers sa ON sa.user_id = r.buyer_id
      ORDER BY r.aprobada ASC, r.creado_en DESC
      LIMIT 100
    ''');
    return filas.map((fila) {
      final mapa = fila.toColumnMap();
      return {
        'productoId': mapa['product_id'].toString(),
        'autorId': mapa['buyer_id'].toString(),
        'estrellas': mapa['estrellas'],
        'comentario': mapa['comentario'],
        'creadoEn': _fecha(mapa['creado_en']),
        'producto': mapa['producto'],
        'nombreNegocio': mapa['nombre_negocio'],
        'autor': '${mapa['nombre']} ${mapa['apellido']}'.trim(),
        'correo': mapa['correo'],
        'aprobada': mapa['aprobada'] == true,
        'negocioAutor': mapa['negocio_autor'],
      };
    }).toList();
  }

  /// Aprueba la reseña pendiente de [autorId] sobre [productoId]: se vuelve pública.
  Future<void> aprobarCalificacion(String productoId, String autorId) async {
    final resultado = await _pool.execute(
      Sql.named('UPDATE ratings SET aprobada = TRUE WHERE product_id = @p AND buyer_id = @b'),
      parameters: {'p': productoId, 'b': autorId},
    );
    _exigirAfectada(resultado, 'No se encontró esa reseña.');
  }

  /// Borra la reseña de [autorId] sobre [productoId].
  Future<void> eliminarCalificacion(String productoId, String autorId) async {
    final resultado = await _pool.execute(
      Sql.named('DELETE FROM ratings WHERE product_id = @p AND buyer_id = @b'),
      parameters: {'p': productoId, 'b': autorId},
    );
    _exigirAfectada(resultado, 'No se encontró esa reseña.');
  }

  // ── Administración: resumen y registros ───────────────────────────────

  /// Conteos para el tablero del administrador.
  Future<Map<String, dynamic>> resumen() async {
    final filas = await _pool.execute('''
      SELECT
        (SELECT COUNT(*) FROM users)::int AS usuarios,
        (SELECT COUNT(*) FROM users WHERE bloqueado)::int AS bloqueados,
        (SELECT COUNT(*) FROM users WHERE NOT correo_verificado)::int AS sin_verificar,
        (SELECT COUNT(*) FROM users WHERE rol = 'comprador')::int AS compradores,
        (SELECT COUNT(*) FROM users WHERE rol = 'vendedor')::int AS cuentas_vendedor,
        (SELECT COUNT(*) FROM users WHERE rol = 'moderador')::int AS moderadores,
        (SELECT COUNT(*) FROM users WHERE rol = 'admin')::int AS administradores,
        (SELECT COUNT(*) FROM sellers)::int AS vendedores,
        (SELECT COUNT(*) FROM sellers WHERE disponible)::int AS abiertos,
        (SELECT COUNT(*) FROM sellers WHERE edificio IS NULL)::int AS sin_punto,
        (SELECT COUNT(*) FROM products)::int AS productos,
        (SELECT COUNT(*) FROM ratings)::int AS calificaciones,
        (SELECT COUNT(*) FROM ratings WHERE NOT aprobada)::int AS resenas_pendientes,
        (SELECT COUNT(*) FROM favorites)::int AS favoritos,
        (SELECT COUNT(*) FROM announcements WHERE activo)::int AS avisos_activos,
        (SELECT COUNT(*) FROM anuncios)::int AS anuncios,
        (SELECT COUNT(*) FROM restablecimientos
          WHERE usado_en IS NULL AND NOT anulado AND vence_en > now())::int AS restablecimientos_pendientes
    ''');
    final mapa = filas.first.toColumnMap();
    // snake_case → camelCase, como el resto de la API.
    return {
      for (final entrada in mapa.entries)
        entrada.key.replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase()): entrada.value,
    };
  }

  /// Tablas que el explorador de registros puede leer y sus columnas visibles.
  ///
  /// Solo lectura. `password_hash` nunca aparece. El nombre que manda el
  /// cliente solo se usa para buscar en este mapa: el SQL se arma con estos
  /// textos fijos, nunca con lo que escribe la persona.
  static const Map<String, ({String columnas, String orden})> tablasVisibles = {
    'users': (
      columnas: 'id, nombre, apellido, correo, rol, telefono, numero_control, carrera, foto_perfil_url, bloqueado, '
          'correo_verificado, creado_en',
      orden: 'creado_en DESC',
    ),
    'sellers': (
      columnas: 'id, user_id, nombre_negocio, categoria, subtipo, descripcion, horario_apertura, horario_cierre, '
          'dias_atencion, disponible, edificio, destacado, destacado_hasta, whatsapp, telegram, instagram, telefono_fijo, '
          'logo_url, portada_url',
      orden: 'nombre_negocio',
    ),
    'products': (
      columnas: 'id, seller_id, nombre, precio, descripcion, foto_url, agotado, veces_vendido, creado_en, actualizado_en',
      orden: 'creado_en DESC',
    ),
    'ratings': (columnas: 'product_id, buyer_id, estrellas, comentario, aprobada, creado_en', orden: 'creado_en DESC'),
    'favorites': (columnas: 'user_id, seller_id', orden: 'user_id'),
    'announcements': (columnas: 'id, titulo, contenido, activo, publicado_en', orden: 'publicado_en DESC'),
    'anuncios': (columnas: 'seccion, posicion, imagen_url, seller_id, actualizado_en', orden: 'seccion, posicion'),
    'ajustes': (columnas: 'clave, valor', orden: 'clave'),
    'restablecimientos': (
      columnas: 'id, user_id, origen, creado_en, vence_en, usado_en, anulado',
      orden: 'creado_en DESC',
    ),
  };

  /// Nombre y número de filas de cada tabla de [tablasVisibles].
  Future<List<Map<String, dynamic>>> contarTablas() async {
    final resultado = <Map<String, dynamic>>[];
    for (final tabla in tablasVisibles.keys) {
      final filas = await _pool.execute('SELECT COUNT(*)::int FROM $tabla');
      resultado.add({'tabla': tabla, 'filas': filas.first[0]});
    }
    return resultado;
  }

  /// Una página de [tabla] (de [tablasVisibles]) como columnas y filas de valores simples.
  Future<Map<String, dynamic>> leerTabla(String tabla, {int pagina = 1, int limite = 25}) async {
    final definicion = tablasVisibles[tabla];
    if (definicion == null) {
      throw ErrorApi(404, 'Esa tabla no se puede consultar desde el panel.');
    }
    final tamano = limite.clamp(1, 100);
    final numero = pagina < 1 ? 1 : pagina;
    final total = await _pool.execute('SELECT COUNT(*)::int FROM $tabla');
    final filas = await _pool.execute(
      Sql.named('SELECT ${definicion.columnas} FROM $tabla ORDER BY ${definicion.orden} LIMIT @limite OFFSET @desde'),
      parameters: {'limite': tamano, 'desde': (numero - 1) * tamano},
    );
    return {
      'tabla': tabla,
      'columnas': definicion.columnas.split(', '),
      'filas': [
        for (final fila in filas) [for (final valor in fila) _valorSimple(valor)],
      ],
      'total': total.first[0],
      'pagina': numero,
      'limite': tamano,
    };
  }

  /// Valor de una columna listo para JSON (texto, número, booleano o null).
  Object? _valorSimple(Object? valor) {
    return switch (valor) {
      null || bool() || num() || String() => valor,
      DateTime() => valor.toUtc().toIso8601String(),
      Time() => _hora(valor),
      UndecodedBytes() => valor.asString,
      _ => valor.toString(),
    };
  }

  /// Fecha en ISO 8601 UTC, o null.
  String? _fecha(Object? valor) => valor is DateTime ? valor.toUtc().toIso8601String() : valor?.toString();

  Map<String, dynamic> _aviso(Map<String, dynamic> mapa) {
    return {
      'id': mapa['id'].toString(),
      'titulo': mapa['titulo'],
      'contenido': mapa['contenido'],
      'activo': mapa['activo'] == true,
      'publicadoEn': _fecha(mapa['publicado_en']),
    };
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
      'correoVerificado': fila['correo_verificado'] == true,
      'creadoEn': _fecha(fila['creado_en']),
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
      'destacadoHasta': _fecha(fila['destacado_hasta']),
      'whatsapp': fila['whatsapp'],
      'telegram': fila['telegram'],
      'messenger': fila['messenger'],
      'instagram': fila['instagram'],
      'telefonoFijo': fila['telefono_fijo'],
      'aceptaMensajesApp': fila['acepta_mensajes_app'] != false,
      'logoUrl': fila['logo_url'],
      'portadaUrl': fila['portada_url'],
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
