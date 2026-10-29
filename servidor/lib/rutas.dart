import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart' show ServerException;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'apariencia.dart';
import 'configuracion.dart';
import 'correo.dart';
import 'medios.dart';
import 'plano.dart';
import 'reportes.dart';
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
///
/// [correo] envía la verificación de cuentas y los reportes; sin él (pruebas)
/// se usa uno sin credenciales que responde 503 al intentar enviar.
Router construirRutas(Repositorio repositorio, TokenSesion tokens, {Correo? correo}) {
  final router = Router();
  final sesion = _Sesion(repositorio, tokens);
  final medios = Medios(Directory('${repositorio.baseDatos.configuracion.rutaDatos}/medios'));
  final cartero = correo ?? Correo(const ConfiguracionCorreo());
  // Llave distinta a la de sesión: un token de sesión no verifica correos y viceversa.
  final tokensCorreo = TokenSesion('${tokens.llave}|verificar-correo', vigencia: const Duration(hours: 48));
  final limiteReportes = _Limite(5, const Duration(hours: 1));
  final limiteVerificacion = _Limite(1, const Duration(minutes: 1));
  // Restablecimiento de contraseña: otra llave derivada, así ni un token de
  // sesión ni uno de verificación sirven para cambiar contraseñas.
  const vigenciaRestablecimiento = Duration(hours: 1);
  final tokensRestablecer = TokenSesion('${tokens.llave}|restablecer-contrasena', vigencia: vigenciaRestablecimiento);
  final limiteOlvidoIp = _Limite(5, const Duration(hours: 1));
  final limiteOlvidoCorreo = _Limite(1, const Duration(minutes: 1));

  /// Crea una solicitud de restablecimiento para [usuario] y le manda el enlace.
  /// Devuelve si el correo salió. [origen] es `correo` o `admin`.
  Future<bool> enviarRestablecimiento(Request request, Map<String, dynamic> usuario, {required String origen}) async {
    final solicitud = await repositorio.crearRestablecimiento(
      usuario['id'] as String,
      origen: origen,
      vigencia: vigenciaRestablecimiento,
    );
    final enlace =
        '${_urlPublica(request, cartero.configuracion)}/api/restablecer?token=${tokensRestablecer.emitir(solicitud)}';
    try {
      await cartero.enviarRestablecimiento(
        para: usuario['correo'] as String,
        nombre: usuario['nombre'] as String,
        enlace: enlace,
        vigencia: vigenciaRestablecimiento,
      );
      return true;
    } on ErrorApi catch (error) {
      stderr.writeln('Restablecimiento de ${usuario['id']} no enviado: ${error.mensaje}');
      return false;
    }
  }

  /// Manda el enlace de verificación a [usuario]. Devuelve si se pudo enviar.
  Future<bool> enviarVerificacion(Request request, Map<String, dynamic> usuario) async {
    final token = tokensCorreo.emitir(usuario['id'] as String);
    final enlace = '${_urlPublica(request, cartero.configuracion)}/api/verificar-correo?token=$token';
    try {
      await cartero.enviarVerificacion(
        para: usuario['correo'] as String,
        nombre: usuario['nombre'] as String,
        enlace: enlace,
      );
      return true;
    } on ErrorApi catch (error) {
      stderr.writeln('Verificación de ${usuario['id']} no enviada: ${error.mensaje}');
      return false;
    }
  }

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
    // La cuenta queda creada aunque el correo falle: puede pedir otro desde la app.
    final enviado = usuario['correoVerificado'] == true ? false : await enviarVerificacion(request, usuario);
    return _json(201, {
      'token': tokens.emitir(usuario['id'] as String),
      'usuario': usuario,
      'correoEnviado': enviado,
    });
  });

  router.get('/api/yo', (Request request) async {
    return _json(200, await sesion.usuario(request));
  });

  router.post('/api/yo/verificacion', (Request request) async {
    final usuario = await sesion.usuario(request);
    if (usuario['correoVerificado'] == true) {
      throw ErrorApi(400, 'Tu correo ya está verificado.');
    }
    if (!limiteVerificacion.permitir(usuario['id'] as String)) {
      throw ErrorApi(429, 'Ya te enviamos un correo. Espera un minuto antes de pedir otro.');
    }
    if (!await enviarVerificacion(request, usuario)) {
      throw ErrorApi(502, 'No se pudo enviar el correo de verificación. Inténtalo más tarde.');
    }
    return _json(200, {'ok': true, 'correo': usuario['correo']});
  });

  router.get('/api/verificar-correo', (Request request) async {
    final id = tokensCorreo.leer(request.url.queryParameters['token'] ?? '');
    final inicio = _urlPublica(request, cartero.configuracion);
    if (id == null) {
      return _pagina(400, 'Enlace no válido',
          'El enlace venció o está incompleto. Entra a Mercado Liebre y pide otro correo de verificación.', inicio);
    }
    if (!await repositorio.verificarCorreo(id)) {
      return _pagina(404, 'Cuenta no encontrada', 'Esta cuenta ya no existe.', inicio);
    }
    return _pagina(200, '¡Correo verificado!', 'Ya puedes calificar y comentar productos en Mercado Liebre.', inicio);
  });

  router.patch('/api/yo', (Request request) async {
    final usuario = await sesion.usuario(request);
    return _json(200, await repositorio.actualizarPerfil(usuario['id'] as String, await _cuerpo(request)));
  });

  // Borra la cuenta de la sesión con todo lo suyo. Pide la contraseña para
  // que un celular prestado o una sesión olvidada no baste para hacerlo.
  router.delete('/api/yo', (Request request) async {
    final usuario = await sesion.usuario(request);
    final password = ((await _cuerpo(request))['password'] ?? '').toString();
    if (password.isEmpty) {
      throw ErrorApi(400, 'Escribe tu contraseña para confirmar.');
    }
    final fotos = await repositorio.eliminarCuentaPropia(usuario['id'] as String, password);
    for (final foto in fotos) {
      await medios.borrar(foto);
    }
    return _json(200, {'ok': true});
  });

  // ── Contraseña olvidada ───────────────────────────────────────────────
  router.post('/api/contrasena/olvido', (Request request) async {
    if (!limiteOlvidoIp.permitir(_ip(request))) {
      throw ErrorApi(429, 'Pediste varios enlaces seguidos. Inténtalo de nuevo en una hora.');
    }
    final correo = _texto(await _cuerpo(request), 'correo').toLowerCase();
    if (!correo.contains('@') || !correo.contains('.')) {
      throw ErrorApi(400, 'Escribe el correo de tu cuenta.');
    }
    if (!cartero.configuracion.configurado) {
      throw ErrorApi(503, 'El envío de correos no está configurado. Pide ayuda a la administración.');
    }
    // La respuesta es la misma exista o no la cuenta, y el envío corre aparte
    // para que el tiempo de respuesta tampoco delate qué correos están registrados.
    if (limiteOlvidoCorreo.permitir(correo)) {
      unawaited(() async {
        try {
          final usuario = await repositorio.usuarioPorCorreo(correo);
          if (usuario != null && usuario['bloqueado'] != true) {
            await enviarRestablecimiento(request, usuario, origen: 'correo');
          }
        } catch (error) {
          stderr.writeln('Fallo al preparar un restablecimiento: $error');
        }
      }());
    }
    return _json(200, {'ok': true});
  });

  // El enlace del correo abre esta página (HTML) con el formulario.
  router.get('/api/restablecer', (Request request) async {
    final token = request.url.queryParameters['token'] ?? '';
    final solicitud = tokensRestablecer.leer(token);
    final inicio = _urlPublica(request, cartero.configuracion);
    if (solicitud == null || !await repositorio.restablecimientoVigente(solicitud)) {
      return _pagina(400, 'Enlace no válido', _enlaceRestablecerVencido, inicio);
    }
    return _formularioContrasena(token: token);
  });

  // El formulario de la página anterior se envía aquí (application/x-www-form-urlencoded).
  router.post('/api/restablecer', (Request request) async {
    final campos = Uri.splitQueryString(await request.readAsString());
    final token = campos['token'] ?? '';
    final password = campos['password'] ?? '';
    final inicio = _urlPublica(request, cartero.configuracion);
    final solicitud = tokensRestablecer.leer(token);
    if (solicitud == null) {
      return _pagina(400, 'Enlace no válido', _enlaceRestablecerVencido, inicio);
    }
    if (password.length < 8) {
      return _formularioContrasena(token: token, error: 'La contraseña debe tener al menos 8 caracteres.');
    }
    if (password != campos['confirmacion']) {
      return _formularioContrasena(token: token, error: 'Las dos contraseñas no coinciden.');
    }
    try {
      await repositorio.restablecerContrasena(solicitud, password);
    } on ErrorApi catch (error) {
      return _pagina(error.estado, 'No se pudo cambiar', error.mensaje, inicio);
    }
    return _pagina(200, '¡Contraseña actualizada!', 'Ya puedes entrar a Mercado Liebre con tu contraseña nueva.', inicio);
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
      correoVerificado: usuario['correoVerificado'] == true,
      productId: _texto(cuerpo, 'productoId'),
      estrellas: estrellas is int ? estrellas : int.tryParse('$estrellas') ?? 0,
      comentario: cuerpo['comentario']?.toString(),
    );
    return _json(200, {'ok': true});
  });

  // ── Reportes de fallas, quejas y sugerencias ──────────────────────────
  router.post('/api/reportes', (Request request) async {
    // Público: no exige sesión, pero si la hay se anota la cuenta.
    if (!limiteReportes.permitir(_ip(request))) {
      throw ErrorApi(429, 'Enviaste varios reportes seguidos. Inténtalo de nuevo en una hora.');
    }
    final reporte = Reporte.desdeJson(await _cuerpo(request));
    String? cuenta;
    if (request.headers.containsKey('authorization')) {
      try {
        cuenta = (await sesion.usuario(request))['correo'] as String?;
      } on ErrorApi {
        cuenta = null; // Token vencido: el reporte se envía igual, sin cuenta.
      }
    }
    await cartero.enviarReporte(
      contacto: reporte.contacto,
      descripcion: reporte.descripcion,
      cuenta: cuenta,
      foto: reporte.foto,
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
    for (final foto in await repositorio.eliminarUsuario(id)) {
      await medios.borrar(foto);
    }
    return _json(200, {'ok': true});
  });

  // ── Publicidad ────────────────────────────────────────────────────────
  router.get('/api/anuncios', (Request request) async {
    return _json(200, await repositorio.anuncios());
  });

  router.put('/api/admin/anuncios/<seccion>/<posicion>', (Request request, String seccion, String posicion) async {
    await sesion.admin(request);
    final (numeroSeccion, numeroPosicion) = _posicionAnuncio(seccion, posicion);
    final cuerpo = await _cuerpo(request);
    final imagen = _urlImagen(_texto(cuerpo, 'imagenUrl'));
    if (imagen.isEmpty) {
      throw ErrorApi(400, 'El anuncio necesita una imagen.');
    }
    final vendedor = _texto(cuerpo, 'vendedorId');
    await repositorio.guardarAnuncio(
      seccion: numeroSeccion,
      posicion: numeroPosicion,
      imagenUrl: imagen,
      sellerId: vendedor.isEmpty ? null : vendedor,
    );
    return _json(200, await repositorio.anuncios());
  });

  router.delete('/api/admin/anuncios/<seccion>/<posicion>', (Request request, String seccion, String posicion) async {
    await sesion.admin(request);
    final (numeroSeccion, numeroPosicion) = _posicionAnuncio(seccion, posicion);
    await repositorio.eliminarAnuncio(numeroSeccion, numeroPosicion);
    return _json(200, await repositorio.anuncios());
  });

  // ── Administración: tablero, cuentas y contraseñas ────────────────────
  router.get('/api/admin/resumen', (Request request) async {
    await sesion.admin(request);
    return _json(200, await repositorio.resumen());
  });

  router.patch('/api/admin/usuarios/<id>', (Request request, String id) async {
    final actor = await sesion.admin(request);
    return _json(
      200,
      await repositorio.actualizarUsuarioAdmin(id, await _cuerpo(request), actorId: actor['id'] as String),
    );
  });

  router.post('/api/admin/usuarios/<id>/contrasena', (Request request, String id) async {
    await sesion.admin(request);
    final password = ((await _cuerpo(request))['password'] ?? '').toString();
    await repositorio.cambiarContrasenaAdmin(id, password);
    return _json(200, {'ok': true});
  });

  router.post('/api/admin/usuarios/<id>/restablecimiento', (Request request, String id) async {
    await sesion.admin(request);
    if (!cartero.configuracion.configurado) {
      throw ErrorApi(503, 'El envío de correos no está configurado. Usa "Fijar contraseña" en su lugar.');
    }
    final usuario = await repositorio.obtenerUsuario(id);
    if (usuario == null) {
      throw ErrorApi(404, 'No se encontró la cuenta.');
    }
    if (!await enviarRestablecimiento(request, usuario, origen: 'admin')) {
      throw ErrorApi(502, 'No se pudo enviar el correo. Inténtalo más tarde.');
    }
    return _json(200, {'ok': true, 'correo': usuario['correo']});
  });

  router.get('/api/admin/restablecimientos', (Request request) async {
    await sesion.admin(request);
    return _json(200, await repositorio.listarRestablecimientos());
  });

  router.post('/api/admin/restablecimientos/<id>/anular', (Request request, String id) async {
    await sesion.admin(request);
    await repositorio.anularRestablecimiento(id);
    return _json(200, {'ok': true});
  });

  // ── Administración: negocios, productos y mapa ────────────────────────
  router.patch('/api/admin/vendedores/<id>', (Request request, String id) async {
    await sesion.admin(request);
    final cuerpo = await _cuerpo(request);
    if (cuerpo.containsKey('edificio')) {
      final codigo = _texto(cuerpo, 'edificio').toUpperCase();
      if (codigo.isNotEmpty && !codigosDelPlano.contains(codigo)) {
        throw ErrorApi(400, 'Ese punto no existe en el mapa del plantel.');
      }
      cuerpo['edificio'] = codigo;
    }
    return _json(200, await repositorio.actualizarVendedorAdmin(id, cuerpo));
  });

  router.delete('/api/admin/vendedores/<id>', (Request request, String id) async {
    await sesion.admin(request);
    for (final foto in await repositorio.eliminarNegocio(id)) {
      await medios.borrar(foto);
    }
    return _json(200, {'ok': true});
  });

  router.delete('/api/admin/productos/<id>', (Request request, String id) async {
    await sesion.admin(request);
    await medios.borrar(await repositorio.eliminarProductoAdmin(id));
    return _json(200, {'ok': true});
  });

  // ── Administración: avisos y reseñas ──────────────────────────────────
  router.get('/api/admin/avisos', (Request request) async {
    await sesion.admin(request);
    return _json(200, await repositorio.avisosAdmin());
  });

  router.post('/api/admin/avisos', (Request request) async {
    await sesion.admin(request);
    return _json(201, await repositorio.crearAviso(await _cuerpo(request)));
  });

  router.patch('/api/admin/avisos/<id>', (Request request, String id) async {
    await sesion.admin(request);
    return _json(200, await repositorio.actualizarAviso(id, await _cuerpo(request)));
  });

  router.delete('/api/admin/avisos/<id>', (Request request, String id) async {
    await sesion.admin(request);
    await repositorio.eliminarAviso(id);
    return _json(200, {'ok': true});
  });

  router.get('/api/admin/calificaciones', (Request request) async {
    await sesion.admin(request);
    return _json(200, await repositorio.calificacionesRecientes());
  });

  router.delete('/api/admin/calificaciones/<producto>/<autor>', (Request request, String producto, String autor) async {
    await sesion.admin(request);
    await repositorio.eliminarCalificacion(producto, autor);
    return _json(200, {'ok': true});
  });

  // ── Administración: explorador de registros (solo lectura) ────────────
  router.get('/api/admin/tablas', (Request request) async {
    await sesion.admin(request);
    return _json(200, await repositorio.contarTablas());
  });

  router.get('/api/admin/tablas/<tabla>', (Request request, String tabla) async {
    await sesion.admin(request);
    final parametros = request.url.queryParameters;
    return _json(
      200,
      await repositorio.leerTabla(
        tabla,
        pagina: int.tryParse(parametros['pagina'] ?? '') ?? 1,
        limite: int.tryParse(parametros['limite'] ?? '') ?? 25,
      ),
    );
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
    return _urlImagen(limpio);
  }
  if (limpio.isEmpty || limpio.length > 40) {
    throw ErrorApi(400, 'El texto del menú debe tener entre 1 y 40 caracteres.');
  }
  return limpio;
}

/// Imagen `http(s)://…` o `/medios/…` (subida al servidor). Vacía se respeta.
///
/// Nada de `javascript:` ni `data:`: la URL se pinta tal cual en la app.
String _urlImagen(String valor) {
  final limpio = valor.trim();
  if (limpio.isEmpty) {
    return '';
  }
  final permitida = limpio.startsWith('https://') || limpio.startsWith('http://') || limpio.startsWith('/medios/');
  if (!permitida || limpio.length > 500) {
    throw ErrorApi(400, 'La imagen debe ser una URL http(s) o una foto subida.');
  }
  return limpio;
}

/// Sección (1–[seccionesPublicidad]) y posición (1–[anunciosPorSeccion]) de la URL.
(int, int) _posicionAnuncio(String seccion, String posicion) {
  final s = int.tryParse(seccion) ?? 0;
  final p = int.tryParse(posicion) ?? 0;
  if (s < 1 || s > seccionesPublicidad || p < 1 || p > anunciosPorSeccion) {
    throw ErrorApi(404, 'Esa posición de publicidad no existe.');
  }
  return (s, p);
}

const String _enlaceRestablecerVencido =
    'El enlace venció, ya se usó o está incompleto. En Mercado Liebre toca "Entrar" → "¿Olvidaste tu contraseña?" '
    'para pedir otro.';

/// Página con el formulario para elegir contraseña nueva. [token] va oculto.
Response _formularioContrasena({required String token, String? error}) {
  const seguro = HtmlEscape();
  final aviso = error == null ? '' : '<p class="error">${seguro.convert(error)}</p>';
  return _paginaHtml(200, 'Contraseña nueva', '''
<h1>Elige tu contraseña nueva</h1>
$aviso
<form method="post" action="/api/restablecer">
  <input type="hidden" name="token" value="${seguro.convert(token)}">
  <label>Contraseña nueva<input type="password" name="password" minlength="8" required autocomplete="new-password"></label>
  <label>Repítela<input type="password" name="confirmacion" minlength="8" required autocomplete="new-password"></label>
  <button type="submit">Guardar contraseña</button>
</form>
<p class="nota">Mínimo 8 caracteres. El enlace sirve una sola vez.</p>
''');
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

/// Cuenta cuántas veces se usó una acción por clave (IP o cuenta) en una ventana de tiempo.
///
/// Vive en memoria: se reinicia con la API, suficiente para frenar abusos
/// de las rutas que envían correo.
class _Limite {
  _Limite(this.maximo, this.ventana);

  final int maximo;
  final Duration ventana;
  final Map<String, List<DateTime>> _usos = {};

  /// Registra un uso de [clave] y dice si todavía está dentro del límite.
  bool permitir(String clave) {
    final ahora = DateTime.now();
    _usos.removeWhere((_, usos) {
      usos.removeWhere((uso) => ahora.difference(uso) >= ventana);
      return usos.isEmpty;
    });
    final usos = _usos.putIfAbsent(clave, () => []);
    if (usos.length >= maximo) {
      return false;
    }
    usos.add(ahora);
    return true;
  }
}

/// IP de quien llama. nginx la pone en `X-Real-IP`; sin proxy, la del socket.
String _ip(Request request) {
  final real = request.headers['x-real-ip']?.trim() ?? '';
  if (real.isNotEmpty) {
    return real;
  }
  final conexion = request.context['shelf.io.connection_info'];
  return conexion is HttpConnectionInfo ? conexion.remoteAddress.address : 'desconocida';
}

/// Origen público para los enlaces de los correos.
///
/// `URL_PUBLICA` si está definida; si no, el `Host` que reenvía nginx, con
/// https salvo en localhost (Coolify termina HTTPS delante de nginx).
String _urlPublica(Request request, ConfiguracionCorreo configuracion) {
  final fija = configuracion.urlPublica;
  if (fija.isNotEmpty) {
    return fija.endsWith('/') ? fija.substring(0, fija.length - 1) : fija;
  }
  final host = request.headers['host'] ?? request.requestedUri.authority;
  final local = host.startsWith('localhost') || host.startsWith('127.0.0.1');
  return '${local ? 'http' : 'https'}://$host';
}

/// Página HTML breve para quien abre el enlace del correo en el navegador.
Response _pagina(int estado, String titulo, String mensaje, String inicio) {
  const seguro = HtmlEscape();
  return _paginaHtml(estado, titulo, '''
<h1>${seguro.convert(titulo)}</h1><p>${seguro.convert(mensaje)}</p>
<a class="boton" href="${seguro.convert(inicio)}">Ir a Mercado Liebre</a>
''');
}

/// Esqueleto HTML con los estilos de la marca. [contenido] ya debe venir escapado.
///
/// `no-referrer`: el token de la URL no viaja a ningún otro sitio.
Response _paginaHtml(int estado, String titulo, String contenido) {
  const seguro = HtmlEscape();
  final cuerpo = '''
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>${seguro.convert(titulo)} · Mercado Liebre</title>
<style>
  body{margin:0;font-family:system-ui,sans-serif;background:#f5f5f5;color:#222;display:grid;place-items:center;min-height:100vh}
  main{background:#fff;max-width:420px;margin:16px;padding:32px;border-radius:12px;box-shadow:0 2px 12px #0002;text-align:center}
  h1{color:#d32f2f;font-size:1.4rem}
  a.boton,button{display:inline-block;margin-top:16px;background:#d32f2f;color:#fff;padding:10px 18px;border:0;border-radius:6px;text-decoration:none;font:inherit;cursor:pointer}
  form{text-align:left}
  label{display:block;margin:12px 0;font-weight:600}
  input{display:block;box-sizing:border-box;width:100%;margin-top:4px;padding:10px;border:1px solid #bbb;border-radius:6px;font:inherit}
  .error{background:#fde7e9;color:#8a1020;padding:10px;border-radius:6px}
  .nota{color:#666;font-size:.9rem}
</style></head>
<body><main>$contenido</main></body></html>
''';
  return Response(estado, body: cuerpo, headers: {'content-type': 'text/html; charset=utf-8'});
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
