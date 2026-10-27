import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart' show ServerException;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'apariencia.dart';
import 'configuracion.dart';
import 'medios.dart';
import 'plano.dart';
import 'repositorio.dart';
import 'token_sesion.dart';

export 'plano.dart' show codigosDelPlano;

/// Roles que pueden administrar un negocio. El admin entra para dar soporte.
const Set<String> _rolesVendedor = {'vendedor', 'admin'};

/// Roles que ven y bloquean cuentas.
const Set<String> _rolesModeracion = {'moderador', 'admin'};

/// Construye las rutas HTTP de la API.
///
/// Cada ruta lee el cuerpo, delega la regla de negocio en [Repositorio]
/// y responde JSON. Los errores de negocio se lanzan como [ErrorApi] y
/// [capturarErrores] los traduce a `{ "error": "..." }`.
Router construirRutas(Repositorio repositorio, TokenSesion tokens) {
  final router = Router();
  final sesion = _Sesion(repositorio, tokens);
  final medios = Medios(Directory('${repositorio.baseDatos.configuracion.rutaDatos}/medios'));

  // ── Salud ─────────────────────────────────────────────────────────────
  router.get('/salud', (Request request) => _json(200, {'estado': 'ok'}));

  // ── Cuentas y sesión ──────────────────────────────────────────────────
  router.post('/api/sesion', (Request request) async {
    final cuerpo = await _cuerpo(request);
    // La contraseña va tal cual: los espacios forman parte de ella.
    final password = (cuerpo['password'] ?? '').toString();
    final usuario = await repositorio.iniciarSesion(_texto(cuerpo, 'correo'), password);
    return _json(200, {'token': tokens.emitir(usuario['id'] as String), 'usuario': usuario});
  });

  router.post('/api/usuarios', (Request request) async {
    final usuario = await repositorio.registrar(await _cuerpo(request));
    return _json(201, {'token': tokens.emitir(usuario['id'] as String), 'usuario': usuario});
  });

  router.get('/api/yo', (Request request) async {
    return _json(200, await sesion.usuario(request));
  });

  router.patch('/api/yo', (Request request) async {
    final usuario = await sesion.usuario(request);
    return _json(200, await repositorio.actualizarPerfil(usuario['id'] as String, await _cuerpo(request)));
  });

  // ── Vendedores ────────────────────────────────────────────────────────
  router.get('/api/vendedores', (Request request) async {
    final solo = request.url.queryParameters['soloDisponibles'] == 'true';
    return _json(200, await repositorio.listarVendedores(soloDisponibles: solo));
  });

  router.get('/api/vendedores/destacados', (Request request) async {
    return _json(200, await repositorio.listarDestacados());
  });

  router.get('/api/vendedores/mio', (Request request) async {
    final usuario = await sesion.usuario(request);
    final vendedor = await repositorio.vendedorDeUsuario(usuario['id'] as String);
    if (vendedor == null) {
      throw ErrorApi(404, 'No tienes un perfil de negocio.');
    }
    return _json(200, vendedor);
  });

  router.post('/api/vendedores/punto', (Request request) async {
    final usuario = await sesion.vendedor(request);
    final codigo = _texto(await _cuerpo(request), 'edificio').toUpperCase();
    await repositorio.asignarPunto(
      userId: usuario['id'] as String,
      edificio: codigo,
      codigoValido: codigosDelPlano.contains(codigo),
    );
    return _json(200, {'edificio': codigo});
  });

  router.patch('/api/vendedores/horario', (Request request) async {
    final usuario = await sesion.vendedor(request);
    final cuerpo = await _cuerpo(request);
    await repositorio.actualizarHorario(
      userId: usuario['id'] as String,
      apertura: _texto(cuerpo, 'apertura'),
      cierre: _texto(cuerpo, 'cierre'),
      dias: _texto(cuerpo, 'dias'),
    );
    return _json(200, {'ok': true});
  });

  router.patch('/api/vendedores/contacto', (Request request) async {
    final usuario = await sesion.vendedor(request);
    final cuerpo = await _cuerpo(request);
    await repositorio.actualizarContacto(
      userId: usuario['id'] as String,
      whatsapp: cuerpo['whatsapp']?.toString(),
      telegram: cuerpo['telegram']?.toString(),
      instagram: cuerpo['instagram']?.toString(),
      telefonoFijo: cuerpo['telefonoFijo']?.toString(),
    );
    return _json(200, {'ok': true});
  });

  router.patch('/api/vendedores/disponibilidad', (Request request) async {
    final usuario = await sesion.vendedor(request);
    final disponible = (await _cuerpo(request))['disponible'] == true;
    await repositorio.actualizarDisponibilidad(userId: usuario['id'] as String, disponible: disponible);
    return _json(200, {'disponible': disponible});
  });

  // ── Productos ─────────────────────────────────────────────────────────
  router.get('/api/productos', (Request request) async {
    final sellerId = request.url.queryParameters['vendedor'] ?? '';
    if (sellerId.isEmpty) {
      throw ErrorApi(400, 'Indica el vendedor.');
    }
    return _json(200, await repositorio.productosDe(sellerId));
  });

  router.get('/api/productos/mas-vendidos', (Request request) async {
    return _json(200, await repositorio.masVendidos());
  });

  router.post('/api/productos', (Request request) async {
    final usuario = await sesion.vendedor(request);
    final cuerpo = await _cuerpo(request);
    final producto = await repositorio.publicarProducto(
      userId: usuario['id'] as String,
      nombre: _texto(cuerpo, 'nombre'),
      precio: _precio(cuerpo['precio']),
      descripcion: cuerpo['descripcion']?.toString(),
    );
    return _json(201, producto);
  });

  router.patch('/api/productos/<id>', (Request request, String id) async {
    final usuario = await sesion.vendedor(request);
    final cuerpo = await _cuerpo(request);
    await repositorio.actualizarProducto(
      userId: usuario['id'] as String,
      productId: id,
      nombre: _texto(cuerpo, 'nombre'),
      precio: _precio(cuerpo['precio']),
      agotado: cuerpo['agotado'] == true,
      descripcion: cuerpo['descripcion']?.toString(),
    );
    return _json(200, {'ok': true});
  });

  router.delete('/api/productos/<id>', (Request request, String id) async {
    final usuario = await sesion.vendedor(request);
    final foto = await repositorio.eliminarProducto(userId: usuario['id'] as String, productId: id);
    await medios.borrar(foto);
    return _json(200, {'ok': true});
  });

  router.post('/api/productos/<id>/foto', (Request request, String id) async {
    final usuario = await sesion.vendedor(request);
    final cuerpo = await _cuerpo(request);
    final datos = _texto(cuerpo, 'datos');
    if (datos.isEmpty) {
      throw ErrorApi(400, 'Falta la imagen.');
    }
    final String url;
    try {
      url = await medios.guardar(cuerpo['nombre']?.toString() ?? 'foto.jpg', datos);
    } on FormatException catch (error) {
      throw ErrorApi(400, error.message);
    }
    try {
      final anterior = await repositorio.cambiarFotoProducto(userId: usuario['id'] as String, productId: id, url: url);
      await medios.borrar(anterior);
    } catch (_) {
      await medios.borrar(url); // No dejar archivos huérfanos si el producto no era suyo.
      rethrow;
    }
    return _json(200, {'fotoUrl': url});
  });

  router.delete('/api/productos/<id>/foto', (Request request, String id) async {
    final usuario = await sesion.vendedor(request);
    final anterior = await repositorio.cambiarFotoProducto(userId: usuario['id'] as String, productId: id, url: null);
    await medios.borrar(anterior);
    return _json(200, {'ok': true});
  });

  // ── Búsqueda, avisos y favoritos ──────────────────────────────────────
  router.get('/api/buscar', (Request request) async {
    final parametros = request.url.queryParameters;
    return _json(
      200,
      await repositorio.buscar(
        parametros['q'] ?? '',
        categoria: parametros['categoria'],
        soloDisponibles: parametros['soloDisponibles'] == 'true',
      ),
    );
  });

  router.get('/api/avisos', (Request request) async {
    return _json(200, await repositorio.avisos());
  });

  router.get('/api/favoritos', (Request request) async {
    final usuario = await sesion.usuario(request);
    return _json(200, await repositorio.favoritosDe(usuario['id'] as String));
  });

  router.post('/api/favoritos/<sellerId>', (Request request, String sellerId) async {
    final usuario = await sesion.usuario(request);
    final marcado = await repositorio.alternarFavorito(usuario['id'] as String, sellerId);
    return _json(200, {'marcado': marcado});
  });

  // ── Calificaciones ────────────────────────────────────────────────────
  router.get('/api/calificaciones', (Request request) async {
    final producto = request.url.queryParameters['producto'] ?? '';
    if (producto.isEmpty) {
      throw ErrorApi(400, 'Indica el producto.');
    }
    return _json(200, await repositorio.calificacionesDe(producto));
  });

  router.post('/api/calificaciones', (Request request) async {
    final usuario = await sesion.usuario(request);
    final cuerpo = await _cuerpo(request);
    final estrellas = cuerpo['estrellas'];
    await repositorio.calificar(
      buyerId: usuario['id'] as String,
      rol: usuario['rol'] as String,
      productId: _texto(cuerpo, 'productoId'),
      estrellas: estrellas is int ? estrellas : int.tryParse('$estrellas') ?? 0,
      comentario: cuerpo['comentario']?.toString(),
    );
    return _json(200, {'ok': true});
  });

  // ── Moderación ────────────────────────────────────────────────────────
  router.get('/api/moderacion/usuarios', (Request request) async {
    await sesion.conRol(request, _rolesModeracion, 'No tienes permiso para ver las cuentas.');
    return _json(200, await repositorio.listarUsuarios());
  });

  router.post('/api/moderacion/usuarios/<id>/bloqueo', (Request request, String id) async {
    final actor = await sesion.conRol(request, _rolesModeracion, 'Solo un moderador o administrador puede bloquear.');
    final objetivo = await _otraCuenta(repositorio, actor, id);
    // Un moderador no puede bloquear a otro moderador ni al administrador.
    if (actor['rol'] != 'admin' && _rolesModeracion.contains(objetivo['rol'])) {
      throw ErrorApi(403, 'Solo el administrador puede bloquear a moderadores o administradores.');
    }
    await repositorio.fijarBloqueo(id, (await _cuerpo(request))['bloqueado'] == true);
    return _json(200, {'ok': true});
  });

  router.delete('/api/moderacion/usuarios/<id>', (Request request, String id) async {
    final actor = await sesion.admin(request);
    await _otraCuenta(repositorio, actor, id);
    await repositorio.eliminarUsuario(id);
    return _json(200, {'ok': true});
  });

  // ── Apariencia y medios ───────────────────────────────────────────────
  router.get('/api/apariencia', (Request request) async {
    return _json(200, aparienciaVisible(await repositorio.leerAjustes()));
  });

  router.patch('/api/admin/apariencia', (Request request) async {
    await sesion.admin(request);
    final cuerpo = await _cuerpo(request);
    final valores = <String, String>{
      for (final clave in aparienciaPredeterminada.keys)
        if (cuerpo.containsKey(clave)) clave: _valorApariencia(clave, _texto(cuerpo, clave)),
    };
    if (valores.isEmpty) {
      throw ErrorApi(400, 'No hay cambios de apariencia.');
    }
    await repositorio.guardarAjustes(valores);
    return _json(200, aparienciaVisible(await repositorio.leerAjustes()));
  });

  router.post('/api/admin/usuarios', (Request request) async {
    await sesion.admin(request);
    return _json(201, await repositorio.crearPorAdmin(await _cuerpo(request)));
  });

  router.post('/api/admin/medios', (Request request) async {
    await sesion.admin(request);
    final cuerpo = await _cuerpo(request);
    final datos = _texto(cuerpo, 'datos');
    if (datos.isEmpty) {
      throw ErrorApi(400, 'Falta la imagen.');
    }
    try {
      final nombre = cuerpo['nombre']?.toString() ?? 'imagen.jpg';
      return _json(201, {'url': await medios.guardar(nombre, datos)});
    } on FormatException catch (error) {
      throw ErrorApi(400, error.message);
    }
  });

  router.get('/medios/<archivo>', (Request request, String archivo) async {
    final file = medios.buscar(archivo);
    if (file == null) {
      throw ErrorApi(404, 'No se encontró la imagen.');
    }
    // El nombre es aleatorio y nunca se reutiliza: el navegador puede guardarlo para siempre.
    return Response.ok(file.openRead(), headers: {
      'content-type': medios.tipo(archivo),
      'cache-control': 'public, max-age=31536000, immutable',
    });
  });

  // ── Conexión a PostgreSQL (solo admin) ────────────────────────────────
  router.get('/api/admin/conexion', (Request request) async {
    await sesion.admin(request);
    return _json(200, await _estadoConexion(repositorio));
  });

  router.post('/api/admin/conexion/probar', (Request request) async {
    await sesion.admin(request);
    final candidata = _candidata(repositorio, await _cuerpo(request));
    try {
      await repositorio.baseDatos.probar(candidata);
    } catch (_) {
      throw ErrorApi(400, 'No se pudo conectar con esos datos.');
    }
    return _json(200, {'ok': true, 'mensaje': 'La conexión respondió.'});
  });

  router.patch('/api/admin/conexion', (Request request) async {
    await sesion.admin(request);
    final cuerpo = await _cuerpo(request);
    final base = repositorio.baseDatos;
    final restaurar = cuerpo['restaurarEntorno'] == true;
    final anterior = base.configuracion;
    final candidata = restaurar
        ? base.configuracion.conConexion(
            url: base.configuracion.urlEntorno,
            usarSsl: base.configuracion.sslEntorno,
          )
        : _candidata(repositorio, cuerpo);
    try {
      await base.usar(candidata);
      if (base.configuracion.aplicarEsquema) {
        await base.aplicarEsquema();
      }
    } catch (_) {
      // Si conectó pero el esquema falló, vuelve a la base anterior para que
      // el mensaje sea cierto y la app no quede apuntando a una base a medias.
      if (!identical(base.configuracion, anterior)) {
        try {
          await base.usar(anterior);
        } catch (_) {
          // La anterior tampoco responde: se queda la nueva y lo dirán los logs.
        }
      }
      throw ErrorApi(400, 'No se pudo conectar. Se conservó la conexión anterior.');
    }
    final archivo = File('${base.configuracion.rutaDatos}/conexion.json');
    if (restaurar) {
      if (await archivo.exists()) {
        await archivo.delete();
      }
    } else {
      await archivo.writeAsString(jsonEncode({'url': candidata.urlBaseDatos, 'ssl': candidata.ssl}));
    }
    return _json(200, await _estadoConexion(repositorio));
  });

  return router;
}

/// Convierte [ErrorApi] en JSON y oculta los errores inesperados.
///
/// Un error inesperado se escribe en stderr (visible en los logs de
/// Coolify) y el cliente solo recibe un mensaje genérico.
Middleware capturarErrores() {
  return (Handler interno) {
    return (Request request) async {
      try {
        return await interno(request);
      } on ErrorApi catch (error) {
        return _json(error.estado, {'error': error.mensaje});
      } catch (error, pila) {
        // 22P02 = invalid_text_representation: llegó un id que no es UUID.
        if (error is ServerException && error.code == '22P02') {
          return _json(404, {'error': 'No se encontró lo que buscas.'});
        }
        stderr.writeln('[${DateTime.now().toUtc().toIso8601String()}] '
            'Error en ${request.method} /${request.url.path}: $error\n$pila');
        return _json(500, {'error': 'No se pudo completar la operación.'});
      }
    };
  };
}

/// Lee el token `Authorization: Bearer …` y exige rol cuando hace falta.
class _Sesion {
  _Sesion(this.repositorio, this.tokens);

  final Repositorio repositorio;
  final TokenSesion tokens;

  /// Cualquier cuenta válida y no bloqueada.
  Future<Map<String, dynamic>> usuario(Request request) async {
    final encabezado = request.headers['authorization'] ?? '';
    if (!encabezado.startsWith('Bearer ')) {
      throw ErrorApi(401, 'Inicia sesión para continuar.');
    }
    final id = tokens.leer(encabezado.substring(7).trim());
    if (id == null) {
      throw ErrorApi(401, 'La sesión expiró. Vuelve a entrar.');
    }
    final usuario = await repositorio.obtenerUsuario(id);
    if (usuario == null) {
      throw ErrorApi(401, 'La cuenta ya no existe.');
    }
    if (usuario['bloqueado'] == true) {
      throw ErrorApi(403, 'Esta cuenta fue bloqueada.');
    }
    return usuario;
  }

  /// Cuenta cuyo rol está en [roles]; si no, 403 con [mensaje].
  Future<Map<String, dynamic>> conRol(Request request, Set<String> roles, String mensaje) async {
    final cuenta = await usuario(request);
    if (!roles.contains(cuenta['rol'])) {
      throw ErrorApi(403, mensaje);
    }
    return cuenta;
  }

  /// Vendedor o administrador. El repositorio exige además que exista el negocio.
  Future<Map<String, dynamic>> vendedor(Request request) {
    return conRol(request, _rolesVendedor, 'Solo un vendedor puede modificar su negocio.');
  }

  /// Solo el rol `admin`. Los moderadores no editan la base ni la apariencia.
  Future<Map<String, dynamic>> admin(Request request) {
    return conRol(request, const {'admin'}, 'Solo el administrador puede hacer esto.');
  }
}

String _valorApariencia(String clave, String valor) {
  final limpio = valor.trim();
  if (clave.startsWith('icono') && clave != 'iconoUrl') {
    if (!iconosDeMenu.contains(limpio)) {
      throw ErrorApi(400, 'Ese icono no está disponible.');
    }
    return limpio;
  }
  if (clave.endsWith('Url')) {
    if (limpio.isEmpty) {
      return '';
    }
    final permitida = limpio.startsWith('https://') ||
        limpio.startsWith('http://') ||
        limpio.startsWith('/medios/');
    if (!permitida || limpio.length > 500) {
      throw ErrorApi(400, 'La imagen debe ser una URL http(s) o una foto subida.');
    }
    return limpio;
  }
  if (limpio.isEmpty || limpio.length > 40) {
    throw ErrorApi(400, 'El texto del menú debe tener entre 1 y 40 caracteres.');
  }
  return limpio;
}

Configuracion _candidata(Repositorio repositorio, Map<String, dynamic> cuerpo) {
  final actual = repositorio.baseDatos.configuracion;
  final host = (cuerpo['host'] ?? actual.host).toString().trim();
  final baseNombre = (cuerpo['base'] ?? actual.nombreBase).toString().trim();
  final usuario = (cuerpo['usuario'] ?? actual.usuarioBaseDatos).toString().trim();
  final escrita = (cuerpo['contrasena'] ?? '').toString();
  final contrasena = escrita.isEmpty ? actual.contrasenaBaseDatos : escrita;
  final puerto = cuerpo['puerto'] is int
      ? cuerpo['puerto'] as int
      : int.tryParse('${cuerpo['puerto'] ?? actual.puertoBaseDatos}') ?? 0;
  final ssl = cuerpo.containsKey('ssl') ? cuerpo['ssl'] == true : actual.ssl;
  // Solo caracteres que no necesitan codificarse dentro de la URL.
  if (!RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(host)) {
    throw ErrorApi(400, 'El host no es válido.');
  }
  if (puerto < 1 || puerto > 65535) {
    throw ErrorApi(400, 'El puerto no es válido.');
  }
  if (usuario.isEmpty || !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(baseNombre)) {
    throw ErrorApi(400, 'Escribe el usuario y un nombre de base con letras, números, _ . o -.');
  }
  final url =
      'postgres://${Uri.encodeComponent(usuario)}:${Uri.encodeComponent(contrasena)}@$host:$puerto/$baseNombre';
  return actual.conConexion(url: url, usarSsl: ssl);
}

Future<Map<String, dynamic>> _estadoConexion(Repositorio repositorio) async {
  final actual = repositorio.baseDatos.configuracion;
  var conectada = false;
  try {
    await repositorio.baseDatos.pool.execute('SELECT 1');
    conectada = true;
  } catch (_) {
    conectada = false;
  }
  return {
    'host': actual.host,
    'puerto': actual.puertoBaseDatos,
    'base': actual.nombreBase,
    'usuario': actual.usuarioBaseDatos,
    'ssl': actual.ssl,
    'tieneContrasena': actual.contrasenaBaseDatos.isNotEmpty,
    'conectada': conectada,
    'usaEntorno': actual.urlBaseDatos == actual.urlEntorno && actual.ssl == actual.sslEntorno,
  };
}

/// Precio numérico del JSON. Rechaza texto que no sea un número.
double _precio(Object? valor) {
  final numero = valor is num ? valor.toDouble() : double.tryParse('${valor ?? ''}');
  if (numero == null || !numero.isFinite) {
    throw ErrorApi(400, 'El precio debe ser un número.');
  }
  return numero;
}

/// Cuenta [id] distinta de [actor]. 404 si no existe; 400 si es la propia.
Future<Map<String, dynamic>> _otraCuenta(Repositorio repositorio, Map<String, dynamic> actor, String id) async {
  if (id == actor['id']) {
    throw ErrorApi(400, 'No puedes hacer esto con tu propia cuenta.');
  }
  final cuenta = await repositorio.obtenerUsuario(id);
  if (cuenta == null) {
    throw ErrorApi(404, 'No se encontró la cuenta.');
  }
  return cuenta;
}

/// `cuerpo[clave]` como texto sin espacios; vacío si no viene.
String _texto(Map<String, dynamic> cuerpo, String clave) => (cuerpo[clave] ?? '').toString().trim();

Future<Map<String, dynamic>> _cuerpo(Request request) async {
  final crudo = await request.readAsString();
  if (crudo.trim().isEmpty) {
    return {};
  }
  final Object? decodificado;
  try {
    decodificado = jsonDecode(crudo);
  } on FormatException {
    throw ErrorApi(400, 'El cuerpo no es JSON válido.');
  }
  if (decodificado is! Map<String, dynamic>) {
    throw ErrorApi(400, 'El cuerpo debe ser un objeto JSON.');
  }
  return decodificado;
}

Response _json(int estado, Object cuerpo) {
  return Response(
    estado,
    body: jsonEncode(cuerpo),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
